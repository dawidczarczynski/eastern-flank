"""Real field parcel boundaries of tactical maps (TASK-215a, ADR 0032). Python 3.8, stdlib only.

Source: OpenStreetMap. The parcels are the `landuse=farmland|meadow|orchard` areas of the map's land-cover extract
(the `osm_<bbox>.json` the importer already reads), split by the ways that cut fields apart in the landscape
(`splitter_kind`): roads and tracks (`SPLIT_HIGHWAYS`), hedges and tree rows, fences and walls. The splitters come
from their own Overpass answer (`parcel_query`, cached as `<cache>/osm/pc1_<s>_<w>_<n>_<e>.json` for the same bbox
as the land-cover extract; the tactical query has no hedges, fences or service roads) plus the roads and tracks of
the land-cover extract. The game never goes online; only the processed polygons are committed.

Split (`split_area`): a planar graph of the area's rings (outer and inner, filled even-odd) and the pieces of the
splitter lines inside the area. A splitter is cut where it meets the rings; a piece between two such points (or a
line end) is kept when some point of it lies more than `TOUCH_M` inside the area, so a hedge drawn along the field
edge, or zigzagging across it, never cuts a sliver off. Kept pieces are noded where they cross each other, pieces
with a free end (a track ending in the field) are pruned, and the bounded faces inside the area are the parcels;
an inner ring that ends up inside a parcel stays its hole.

Each parcel ring is simplified (Douglas-Peucker, `SIMPLIFY_M`) and rounded to whole metres relative to the map origin
(x east, z south of tile (0, 0)'s centre). Faces smaller than `MIN_PARCEL_M2` or thinner than `MIN_WIDTH_M` (twice
the area over the perimeter: the strip between a track and a hedge drawn side by side) are dropped. Every edge gets
a kind (`edge_kind`): `hedge` or `track` when at least half of it runs within `EDGE_KIND_M` of, and roughly
parallel to, a splitter of that kind, else `plain` (fences and walls cut, but count as plain edges).

Big parcels (> `LARGE_PARCEL_HA`) are kept as they are; subdividing them is the renderer's fallback (TASK-215b).
"""
from __future__ import annotations

import base64
import math
from pathlib import Path
from typing import Callable, Dict, List, Optional, Sequence, Tuple

Point = Tuple[float, float]
Ring = List[Point]

PARCEL_QUERY_VERSION = "pc1"  # part of the cache file name: a changed query must not reuse old answers
PARCEL_LANDUSE = ("farmland", "meadow", "orchard")  # code = index (ImportedMap.parcel_landuse)
EDGE_KINDS = ("plain", "track", "hedge")  # code = index (ImportedMap.PARCEL_EDGE_*)
SPLIT_HIGHWAYS = ("track", "service", "unclassified", "residential", "tertiary", "secondary", "primary", "trunk",
                  "motorway")  # fmt: skip
HEDGE_TAGS = (("barrier", "hedge"), ("natural", "tree_row"))
PLAIN_TAGS = (("barrier", "fence"), ("barrier", "wall"))
TOUCH_M = 3.0  # a splitter piece that never gets farther than this inside the area only touches its edge
EDGE_KIND_M = 8.0  # an edge within this distance of a splitter (tracks are mapped on their centreline) runs along it
EDGE_PARALLEL_DEG = 25.0
EDGE_SAMPLE_M = 10.0
SIMPLIFY_M = 1.0
MIN_PARCEL_M2 = 200.0
MIN_WIDTH_M = 5.0
LARGE_PARCEL_HA = 15.0  # [ASSUMPTION] TASK-215b subdivides bigger parcels; only reported here
_TOL = 1.0e-6  # metres: intersection tolerance
_SNAP = 1000.0  # node key grid: 1 mm
_GRID = 50.0  # spatial index cell, metres


# ---------------------------------------------------------------------------------------------------------------
# OSM input.


def parcel_query(south: float, west: float, north: float, east: float) -> str:
    """Overpass query of the parcel splitters of a tactical map's bbox (the land-cover extract's bbox)."""
    bbox = "%.5f,%.5f,%.5f,%.5f" % (south, west, north, east)
    return "\n".join([
        "[out:json][timeout:180];",
        "(",
        '  way["highway"~"^(%s)$"](%s);' % ("|".join(SPLIT_HIGHWAYS), bbox),
        '  way["barrier"~"^(hedge|fence|wall)$"](%s);' % bbox,
        '  way["natural"="tree_row"](%s);' % bbox,
        ");",
        "(._;>;);",
        "out body;",
    ])  # fmt: skip


def parcel_osm_path(cache: Path, south: float, west: float, north: float, east: float, offline: bool,
                    fetch: Optional[Callable[[Path, str], None]] = None) -> Path:  # fmt: skip
    """The cached splitter answer of the bbox; downloaded with `fetch(path, query)` unless `offline`."""
    path = cache / "osm" / ("%s_%.5f_%.5f_%.5f_%.5f.json" % (PARCEL_QUERY_VERSION, south, west, north, east))
    if not path.exists():
        if offline or fetch is None:
            raise SystemExit("missing parcel splitters %s (run without --offline to download them)" % path)
        path.parent.mkdir(parents=True, exist_ok=True)
        fetch(path, parcel_query(south, west, north, east))
    return path


def splitter_kind(tags: Dict[str, str]) -> Optional[str]:
    """Edge kind ("track", "hedge", "plain") of a way that splits fields, or None."""
    if tags.get("area") == "yes":
        return None
    if tags.get("highway") in SPLIT_HIGHWAYS:
        return "track"
    if any(tags.get(k) == v for k, v in HEDGE_TAGS):
        return "hedge"
    if any(tags.get(k) == v for k, v in PLAIN_TAGS):
        return "plain"
    return None


def osm_splitters(answers: Sequence[dict], project: Callable[[float, float], Point]) -> List[Tuple[str, List[Point]]]:
    """(kind, points) of every splitter way of the Overpass answers (a way in several answers counts once), sorted by
    way id; `project(lat, lon)` gives the local metres."""
    nodes: Dict[int, Tuple[float, float]] = {}
    ways: Dict[int, dict] = {}
    for osm in answers:
        for el in osm.get("elements", []):
            if el.get("type") == "node":
                nodes[el["id"]] = (el["lat"], el["lon"])
            elif el.get("type") == "way":
                ways[el["id"]] = el
    lines = []
    for way_id in sorted(ways):
        way = ways[way_id]
        kind = splitter_kind(way.get("tags", {}))
        points = [project(*nodes[n]) for n in way.get("nodes", []) if n in nodes]
        if kind and len(points) >= 2:
            lines.append((kind, points))
    return lines


# ---------------------------------------------------------------------------------------------------------------
# Geometry.


def _key(p: Point) -> Tuple[int, int]:
    return (int(round(p[0] * _SNAP)), int(round(p[1] * _SNAP)))


def _signed_area(ring: Sequence[Point]) -> float:
    return 0.5 * sum(ring[k - 1][0] * ring[k][1] - ring[k][0] * ring[k - 1][1] for k in range(len(ring)))


def _inside(rings: Sequence[Sequence[Point]], x: float, y: float) -> bool:
    """Even-odd point in rings."""
    inside = False
    for ring in rings:
        n = len(ring)
        for k in range(n):
            (ax, ay), (bx, by) = ring[k - 1], ring[k]
            if (ay > y) != (by > y) and x < ax + (y - ay) * (bx - ax) / (by - ay):
                inside = not inside
    return inside


def _segment_distance(p: Point, a: Point, b: Point) -> float:
    dx, dy = b[0] - a[0], b[1] - a[1]
    length2 = dx * dx + dy * dy
    t = 0.0 if length2 == 0.0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / length2))
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy)


def _intersections(p: Point, p2: Point, q: Point, q2: Point) -> List[Tuple[float, float, Point]]:
    """(t along p-p2, u along q-q2, point) where the two segments meet; collinear overlaps give their end points."""
    rx, ry = p2[0] - p[0], p2[1] - p[1]
    sx, sy = q2[0] - q[0], q2[1] - q[1]
    rr, ss = rx * rx + ry * ry, sx * sx + sy * sy
    if rr == 0.0 or ss == 0.0:
        return []
    lr, ls = math.sqrt(rr), math.sqrt(ss)
    qpx, qpy = q[0] - p[0], q[1] - p[1]
    denom = rx * sy - ry * sx
    if abs(denom) > 1.0e-9 * lr * ls:
        t = (qpx * sy - qpy * sx) / denom
        u = (qpx * ry - qpy * rx) / denom
        tt, tu = _TOL / lr, _TOL / ls
        if not (-tt <= t <= 1.0 + tt and -tu <= u <= 1.0 + tu):
            return []
        t, u = min(1.0, max(0.0, t)), min(1.0, max(0.0, u))
        if u <= tu:
            return [(t, 0.0, q)]
        if u >= 1.0 - tu:
            return [(t, 1.0, q2)]
        if t <= tt:
            return [(0.0, u, p)]
        if t >= 1.0 - tt:
            return [(1.0, u, p2)]
        return [(t, u, (q[0] + u * sx, q[1] + u * sy))]
    if abs(qpx * ry - qpy * rx) / lr > _TOL:
        return []
    found = []
    for u, point in ((0.0, q), (1.0, q2)):
        t = ((point[0] - p[0]) * rx + (point[1] - p[1]) * ry) / rr
        if -_TOL / lr <= t <= 1.0 + _TOL / lr:
            found.append((min(1.0, max(0.0, t)), u, point))
    for t, point in ((0.0, p), (1.0, p2)):
        u = ((point[0] - q[0]) * sx + (point[1] - q[1]) * sy) / ss
        if -_TOL / ls <= u <= 1.0 + _TOL / ls:
            found.append((t, min(1.0, max(0.0, u)), point))
    return found


class _SegmentGrid:
    """Segments bucketed by the `_GRID` cells their bounding box (plus `pad`) touches."""

    def __init__(self, segments: Sequence[tuple], pad: float = 0.0) -> None:
        self.segments = list(segments)
        self.cells: Dict[Tuple[int, int], List[int]] = {}
        for index, segment in enumerate(self.segments):
            a, b = segment[0], segment[1]
            for cell in self._cells(min(a[0], b[0]) - pad, min(a[1], b[1]) - pad, max(a[0], b[0]) + pad,
                                    max(a[1], b[1]) + pad):  # fmt: skip
                self.cells.setdefault(cell, []).append(index)

    @staticmethod
    def _cells(x0: float, y0: float, x1: float, y1: float) -> List[Tuple[int, int]]:
        i0, j0, i1, j1 = int(math.floor(x0 / _GRID)), int(math.floor(y0 / _GRID)), int(math.floor(x1 / _GRID)), int(
            math.floor(y1 / _GRID))
        return [(i, j) for i in range(i0, i1 + 1) for j in range(j0, j1 + 1)]

    def near(self, x0: float, y0: float, x1: float, y1: float) -> List[int]:
        """Indices (sorted) of the segments whose padded box shares a cell with the box."""
        found = set()
        for cell in self._cells(x0, y0, x1, y1):
            found.update(self.cells.get(cell, ()))
        return sorted(found)


def _clean_ring(ring: Sequence[Point]) -> Ring:
    points = [tuple(p) for p in ring]
    if len(points) > 1 and _key(points[0]) == _key(points[-1]):
        points.pop()
    cleaned: Ring = []
    for p in points:
        if not cleaned or _key(cleaned[-1]) != _key(p):
            cleaned.append(p)
    if len(cleaned) > 1 and _key(cleaned[0]) == _key(cleaned[-1]):
        cleaned.pop()
    return cleaned


def _runs(line: Sequence[Point], ring_grid: _SegmentGrid, rings: Sequence[Ring]) -> List[List[Point]]:
    """The pieces of one splitter line inside the area: cut at the rings, kept when they reach `TOUCH_M` inside."""
    seq: List[Tuple[Point, bool]] = []

    def push(point: Point, boundary: bool) -> None:
        if seq and _key(seq[-1][0]) == _key(point):
            seq[-1] = (seq[-1][0], seq[-1][1] or boundary)
        else:
            seq.append((point, boundary))

    for j in range(len(line) - 1):
        a, b = line[j], line[j + 1]
        push(a, False)
        cuts = []
        for index in ring_grid.near(min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])):
            q, q2 = ring_grid.segments[index][:2]
            cuts += [(t, point) for t, _, point in _intersections(a, b, q, q2)]
        for _, point in sorted(cuts, key=lambda c: (c[0], c[1])):
            push(point, True)
        push(b, False)
    runs, current = [], [seq[0][0]] if seq else []
    for point, boundary in seq[1:]:
        current.append(point)
        if boundary:
            runs.append(current)
            current = [point]
    if len(current) >= 2:
        runs.append(current)
    return [run for run in runs if len(run) >= 2 and _reaches_inside(run, ring_grid, rings)]


def _reaches_inside(run: Sequence[Point], ring_grid: _SegmentGrid, rings: Sequence[Ring]) -> bool:
    for k in range(len(run) - 1):
        (ax, ay), (bx, by) = run[k], run[k + 1]
        n = max(1, int(math.ceil(math.hypot(bx - ax, by - ay) / EDGE_SAMPLE_M)))
        for i in range(n + (1 if k == len(run) - 2 else 0)):
            f = (i + 0.5) / n if i < n else 1.0
            p = (ax + f * (bx - ax), ay + f * (by - ay))
            near = ring_grid.near(p[0] - TOUCH_M, p[1] - TOUCH_M, p[0] + TOUCH_M, p[1] + TOUCH_M)
            if all(_segment_distance(p, *ring_grid.segments[s][:2]) > TOUCH_M for s in near):
                return _inside(rings, p[0], p[1])
    return False


def split_area(rings: Sequence[Sequence[Point]], lines: Sequence[Sequence[Point]]) -> List[List[Ring]]:
    """The faces of one area (rings filled even-odd) cut by the splitter lines: [outer ring (counter-clockwise),
    holes (clockwise)...] per face, in the input's metres."""
    rings = [r for r in (_clean_ring(r) for r in rings) if len(r) >= 3]
    ring_segments = [(r[k], r[(k + 1) % len(r)], ri, k) for ri, r in enumerate(rings) for k in range(len(r))]
    ring_grid = _SegmentGrid(ring_segments)
    runs: List[List[Point]] = []
    for line in lines:
        runs += _runs(line, ring_grid, rings)
    ends = {_key(p) for run in runs for p in (run[0], run[-1])}
    # ring cuts at the kept pieces' ends
    ring_cuts: Dict[int, List[Tuple[float, Point]]] = {}
    for run in runs:
        for p in (run[0], run[-1]):
            for index in ring_grid.near(p[0] - _TOL, p[1] - _TOL, p[0] + _TOL, p[1] + _TOL):
                a, b = ring_grid.segments[index][:2]
                if _segment_distance(p, a, b) <= _TOL * 10.0 and _key(p) in ends:
                    dx, dy = b[0] - a[0], b[1] - a[1]
                    t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy)
                    ring_cuts.setdefault(index, []).append((t, p))
    # the kept pieces noded where they cross each other
    run_segments = [(run[k], run[k + 1], r, k) for r, run in enumerate(runs) for k in range(len(run) - 1)]
    run_grid = _SegmentGrid(run_segments)
    run_cuts: Dict[int, List[Tuple[float, Point]]] = {}
    for i, (a, b, _, _) in enumerate(run_segments):
        for j in run_grid.near(min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])):
            if j <= i:
                continue
            c, d = run_segments[j][:2]
            for t, u, point in _intersections(a, b, c, d):
                run_cuts.setdefault(i, []).append((t, point))
                run_cuts.setdefault(j, []).append((u, point))
    nodes: Dict[Tuple[int, int], Point] = {}
    adjacency: Dict[Tuple[int, int], set] = {}

    def chain(a: Point, b: Point, cuts: List[Tuple[float, Point]]) -> None:
        points = [a] + [p for _, p in sorted(cuts, key=lambda c: (c[0], c[1]))] + [b]
        for k in range(len(points) - 1):
            ka, kb = _key(points[k]), _key(points[k + 1])
            if ka == kb:
                continue
            nodes.setdefault(ka, points[k])
            nodes.setdefault(kb, points[k + 1])
            adjacency.setdefault(ka, set()).add(kb)
            adjacency.setdefault(kb, set()).add(ka)

    for index, (a, b, _, _) in enumerate(ring_segments):
        chain(a, b, ring_cuts.get(index, []))
    for index, (a, b, _, _) in enumerate(run_segments):
        chain(a, b, run_cuts.get(index, []))
    _prune(adjacency)
    return _faces(nodes, adjacency, rings)


def _prune(adjacency: Dict[Tuple[int, int], set]) -> None:
    """Removes dangling edges (a piece ending inside the area) until every node has two edges or more."""
    stack = sorted(k for k, n in adjacency.items() if len(n) < 2)
    while stack:
        key = stack.pop()
        neighbours = adjacency.pop(key, None)
        if neighbours is None:
            continue
        for other in neighbours:
            adjacency[other].discard(key)
            if len(adjacency[other]) < 2:
                stack.append(other)


def _faces(nodes: Dict[Tuple[int, int], Point], adjacency: Dict[Tuple[int, int], set],
           rings: Sequence[Ring]) -> List[List[Ring]]:  # fmt: skip
    order: Dict[Tuple[int, int], List[Tuple[int, int]]] = {}
    for key in sorted(adjacency):
        x, y = nodes[key]
        order[key] = sorted(adjacency[key], key=lambda n: (math.atan2(nodes[n][1] - y, nodes[n][0] - x), n))
    component: Dict[Tuple[int, int], Tuple[int, int]] = {}

    def root(k: Tuple[int, int]) -> Tuple[int, int]:
        while component.get(k, k) != k:
            k = component[k]
        return k

    for key in sorted(adjacency):
        for other in adjacency[key]:
            a, b = root(key), root(other)
            if a != b:
                component[max(a, b)] = min(a, b)
    seen = set()
    cycles: List[Tuple[float, List[Point], Tuple[int, int]]] = []
    for start in sorted(order):
        for first in order[start]:
            if (start, first) in seen:
                continue
            keys, u, v = [], start, first
            while (u, v) not in seen:
                seen.add((u, v))
                keys.append(u)
                around = order[v]
                u, v = v, around[(around.index(u) - 1) % len(around)]
            points = [nodes[k] for k in keys]
            cycles.append((_signed_area(points), points, root(start)))
    bounded = [(area, pts, comp) for area, pts, comp in cycles if area > 0.0]
    kept = [_face_inside(pts, rings) for _, pts, _ in bounded]
    faces: List[List[Ring]] = [[pts] for _, pts, _ in bounded]
    for area, pts, comp in cycles:
        if area >= 0.0:
            continue
        best = None
        for index, (b_area, b_pts, b_comp) in enumerate(bounded):
            if b_comp != comp and (best is None or b_area < bounded[best][0]) and _inside([b_pts], *pts[0]):
                best = index
        if best is not None:
            faces[best].append(pts)
    return [face for face, keep in zip(faces, kept) if keep]


def _face_inside(points: Sequence[Point], rings: Sequence[Ring]) -> bool:
    """True when the face (counter-clockwise, interior on the left) lies inside the area: a point just left of its
    longest edge."""
    best, at = -1.0, 0
    for k in range(len(points)):
        a, b = points[k], points[(k + 1) % len(points)]
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        if length > best:
            best, at = length, k
    a, b = points[at], points[(at + 1) % len(points)]
    off = min(0.01, best * 0.1) / best
    mx, my = (a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0
    return _inside(rings, mx - (b[1] - a[1]) * off, my + (b[0] - a[0]) * off)


def _simplify_ring(ring: Sequence[Point], tolerance: float) -> Ring:
    """Douglas-Peucker of a closed ring, anchored on the vertex farthest from the ring's mean point (a true corner)."""
    n = len(ring)
    if n <= 3:
        return list(ring)
    mx, my = sum(p[0] for p in ring) / n, sum(p[1] for p in ring) / n
    start = max(range(n), key=lambda k: ((ring[k][0] - mx) ** 2 + (ring[k][1] - my) ** 2, -k))
    points = [ring[(start + k) % n] for k in range(n)] + [ring[start]]
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        lo, hi = stack.pop()
        best, at = -1.0, lo
        for i in range(lo + 1, hi):
            d = _segment_distance(points[i], points[lo], points[hi])
            if d > best:
                best, at = d, i
        if best > tolerance:
            keep[at] = True
            stack += [(lo, at), (at, hi)]
    return [p for p, k in zip(points[:-1], keep[:-1]) if k]


def _round_ring(ring: Sequence[Point]) -> List[Tuple[int, int]]:
    """Whole metres, x east and z south; consecutive duplicates removed."""
    out: List[Tuple[int, int]] = []
    for x, y in ring:
        p = (int(math.floor(x + 0.5)), int(math.floor(-y + 0.5)))
        if not out or out[-1] != p:
            out.append(p)
    while len(out) > 1 and out[0] == out[-1]:
        out.pop()
    return out


def _start_at_min(ring: List[Tuple[int, int]]) -> List[Tuple[int, int]]:
    k = min(range(len(ring)), key=lambda i: (ring[i][1], ring[i][0]))
    return ring[k:] + ring[:k]


def edge_kind(a: Point, b: Point, grid: _SegmentGrid) -> str:
    """"hedge" / "track" when at least half of the edge a-b (local metres) runs within `EDGE_KIND_M` of a roughly
    parallel splitter of that kind (the nearest one per sample), else "plain"."""
    length = math.hypot(b[0] - a[0], b[1] - a[1])
    if length == 0.0:
        return "plain"
    ux, uy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
    cos_min = math.cos(math.radians(EDGE_PARALLEL_DEG))
    n = max(1, int(math.ceil(length / EDGE_SAMPLE_M)))
    votes = {"track": 0, "hedge": 0}
    for i in range(n):
        f = (i + 0.5) / n
        p = (a[0] + f * (b[0] - a[0]), a[1] + f * (b[1] - a[1]))
        best, kind = EDGE_KIND_M, None
        for index in grid.near(p[0], p[1], p[0], p[1]):
            c, d, k = grid.segments[index]
            seg = math.hypot(d[0] - c[0], d[1] - c[1])
            if seg == 0.0 or abs((d[0] - c[0]) * ux + (d[1] - c[1]) * uy) / seg < cos_min:
                continue
            dist = _segment_distance(p, c, d)
            if dist <= best and (kind is None or dist < best or EDGE_KINDS.index(k) > EDGE_KINDS.index(kind)):
                best, kind = dist, k
        if kind is not None:
            votes[kind] += 1
    for kind in ("hedge", "track"):
        other = "track" if kind == "hedge" else "hedge"
        if 2 * votes[kind] >= n and votes[kind] >= votes[other]:
            return kind
    return "plain"


def build_parcels(areas: Sequence[Tuple[str, Sequence[Sequence[Point]]]],
                  splitters: Sequence[Tuple[str, Sequence[Point]]]) -> List[dict]:  # fmt: skip
    """Parcels of the areas ((landuse, rings) in local metres, x east, y north) cut by the splitters ((kind, points)):
    {"landuse", "rings": [outer, holes...] as (x, z) whole metres with z south, "kinds": edge kinds per ring (edge k
    runs from vertex k to the next)}, sorted by landuse, then the outer ring (deterministic whatever the input order).
    The outer ring is counter-clockwise seen from above with north up, holes the other way round."""
    lines = [(kind, [tuple(p) for p in pts]) for kind, pts in splitters]
    split_grid = _SegmentGrid([(pts[k], pts[k + 1], i) for i, (_, pts) in enumerate(lines) for k in range(len(pts) - 1)])
    kind_grid = _SegmentGrid([(pts[k], pts[k + 1], kind) for kind, pts in lines if kind != "plain"
                              for k in range(len(pts) - 1)], EDGE_KIND_M)  # fmt: skip
    parcels = []
    for landuse, rings in areas:
        xs = [p[0] for r in rings for p in r]
        ys = [p[1] for r in rings for p in r]
        near = sorted({split_grid.segments[s][2] for s in split_grid.near(min(xs), min(ys), max(xs), max(ys))})
        for face in split_area(rings, [lines[i][1] for i in near]):
            parcel = _finish(landuse, face, kind_grid)
            if parcel is not None:
                parcels.append(parcel)
    parcels.sort(key=lambda p: (PARCEL_LANDUSE.index(p["landuse"]), p["rings"]))
    return parcels


def _finish(landuse: str, face: List[Ring], kind_grid: _SegmentGrid) -> Optional[dict]:
    rings = []
    for index, ring in enumerate(face):
        rounded = _round_ring(_simplify_ring(ring, SIMPLIFY_M))
        if len(rounded) < 3 or _signed_area(rounded) == 0.0:
            if index == 0:
                return None
            continue
        # (x, z south): counter-clockwise north up is a negative shoelace sum
        if (_signed_area(rounded) < 0.0) != (index == 0):
            rounded.reverse()
        rings.append(_start_at_min(rounded))
    rings[1:] = sorted(rings[1:])
    area = abs(_signed_area(rings[0])) - sum(abs(_signed_area(r)) for r in rings[1:])
    perimeter = sum(math.hypot(r[k][0] - r[k - 1][0], r[k][1] - r[k - 1][1]) for r in rings for k in range(len(r)))
    if area < MIN_PARCEL_M2 or 2.0 * area / perimeter < MIN_WIDTH_M:
        return None
    kinds = [[edge_kind((r[k][0], -r[k][1]), (r[(k + 1) % len(r)][0], -r[(k + 1) % len(r)][1]), kind_grid)
              for k in range(len(r))] for r in rings]  # fmt: skip
    return {"landuse": landuse, "rings": rings, "kinds": kinds, "area": area}


# ---------------------------------------------------------------------------------------------------------------
# Output and statistics.


def parcel_fields(parcels: Sequence[dict]) -> List[str]:
    """The `parcel_*` lines of an ImportedMap (see its doc comment)."""
    rings = [len(p["rings"]) for p in parcels]
    sizes = [len(r) for p in parcels for r in p["rings"]]
    points = [str(v) for p in parcels for r in p["rings"] for xz in r for v in xz]
    kinds = bytes(EDGE_KINDS.index(k) for p in parcels for ks in p["kinds"] for k in ks)
    landuse = bytes(PARCEL_LANDUSE.index(p["landuse"]) for p in parcels)
    return [
        'parcel_landuse_codes = PackedByteArray("%s")' % base64.b64encode(landuse).decode("ascii"),
        "parcel_rings = PackedInt32Array(%s)" % ", ".join(str(n) for n in rings),
        "parcel_ring_sizes = PackedInt32Array(%s)" % ", ".join(str(n) for n in sizes),
        "parcel_points = PackedInt32Array(%s)" % ", ".join(points),
        'parcel_edge_codes = PackedByteArray("%s")' % base64.b64encode(kinds).decode("ascii"),
    ]


def _percentile(values: Sequence[float], p: float) -> float:
    if not values:
        return 0.0
    s = sorted(values)
    return s[min(len(s) - 1, int(round(p * (len(s) - 1))))]


def parcel_stats(parcels: Sequence[dict]) -> str:
    """One line of statistics for the import log and the ADR."""
    ha = [p["area"] / 10000.0 for p in parcels]
    by_use = {u: sum(1 for p in parcels if p["landuse"] == u) for u in PARCEL_LANDUSE}
    edges = [k for p in parcels for ks in p["kinds"] for k in ks]
    return ("Parcels: %d (%s); median %.2f ha, p10 %.2f, p90 %.2f, %d over %.0f ha; %d edges: %s" % (
        len(parcels), ", ".join("%s %d" % kv for kv in by_use.items()), _percentile(ha, 0.5), _percentile(ha, 0.1),
        _percentile(ha, 0.9), sum(1 for h in ha if h > LARGE_PARCEL_HA), LARGE_PARCEL_HA, len(edges),
        ", ".join("%s %d" % (k, edges.count(k)) for k in EDGE_KINDS)))  # fmt: skip
