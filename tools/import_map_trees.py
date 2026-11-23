"""Real tree features of tactical maps (TASK-199a): single trees, tree rows, orchards and farmyards. Python 3.8,
stdlib only.

Source: OpenStreetMap, one Overpass answer per map (`tree_query`, cached as `<cache>/osm/tr1_<s>_<w>_<n>_<e>.json`
for the same bbox as the land-cover extract): `natural=tree` nodes, `natural=tree_row` ways and `landuse=orchard` /
`landuse=farmyard` areas (closed ways and multipolygon relations). The game never goes online; only the processed
features are committed. Hedges are not read here: the parcel edges carry them (TASK-215a / 215b).

Processing (`build_tree_features`), all in local metres (x east, y north of tile (0, 0)'s centre), written as whole
metres (x east, z south, the frame of `ImportedMap.sample`):
- trees: points closer than `MERGE_M` to an earlier one (sorted by position) are merged into it; only points
  inside the map's hexes (their bounding rectangle) are kept;
- tree rows: simplified (Douglas-Peucker, `SIMPLIFY_M`), kept whole when their bounding box reaches the map;
- orchards and farmyards: the rings of an area (filled even-odd) are grouped into polygons (outer ring + its holes),
  each ring simplified like the rows; the outer ring runs counter-clockwise seen from above with north up, holes the
  other way round; a polygon whose outer ring is already stored (a way tagged like the multipolygon it is the outer
  of) is stored once, with the most holes; kept whole when its bounding box reaches the map.
Everything is sorted by its coordinates, so the same answer gives the same output whatever the element order.
"""
from __future__ import annotations

import math
from pathlib import Path
from typing import Callable, Dict, List, Optional, Sequence, Tuple

import import_map_parcels as parcels

Point = Tuple[float, float]
IntPoint = Tuple[int, int]

TREE_QUERY_VERSION = "tr1"  # part of the cache file name: a changed query must not reuse old answers
AREA_KINDS = ("orchard", "farmyard")
SIMPLIFY_M = 1.0
MERGE_M = 1.0  # single trees closer than this are one tree (mapped twice)


# ---------------------------------------------------------------------------------------------------------------
# OSM input.


def tree_query(south: float, west: float, north: float, east: float) -> str:
    """Overpass query of the tree features of a tactical map's bbox (the land-cover extract's bbox)."""
    bbox = "%.5f,%.5f,%.5f,%.5f" % (south, west, north, east)
    return "\n".join([
        "[out:json][timeout:180];",
        "(",
        '  node["natural"="tree"](%s);' % bbox,
        '  way["natural"="tree_row"](%s);' % bbox,
        '  wr["landuse"~"^(orchard|farmyard)$"](%s);' % bbox,
        ");",
        "(._;>;);",
        "out body;",
    ])  # fmt: skip


def tree_osm_path(cache: Path, south: float, west: float, north: float, east: float, offline: bool,
                  fetch: Optional[Callable[[Path, str], None]] = None) -> Path:  # fmt: skip
    """The cached tree answer of the bbox; downloaded with `fetch(path, query)` unless `offline`."""
    path = cache / "osm" / ("%s_%.5f_%.5f_%.5f_%.5f.json" % (TREE_QUERY_VERSION, south, west, north, east))
    if not path.exists():
        if offline or fetch is None:
            raise SystemExit("missing tree features %s (run without --offline to download them)" % path)
        path.parent.mkdir(parents=True, exist_ok=True)
        fetch(path, tree_query(south, west, north, east))
    return path


def osm_tree_points(osm: dict, project: Callable[[float, float], Point]) -> List[Point]:
    """Local metres of every `natural=tree` node, sorted by node id; `project(lat, lon)` gives the metres."""
    found = [el for el in osm.get("elements", []) if el.get("type") == "node"
             and el.get("tags", {}).get("natural") == "tree"]  # fmt: skip
    return [project(el["lat"], el["lon"]) for el in sorted(found, key=lambda el: el["id"])]


def osm_tree_rows(osm: dict, project: Callable[[float, float], Point]) -> List[List[Point]]:
    """Local metres of every `natural=tree_row` way (not an area), sorted by way id."""
    nodes: Dict[int, Tuple[float, float]] = {}
    ways = []
    for el in osm.get("elements", []):
        if el.get("type") == "node":
            nodes[el["id"]] = (el["lat"], el["lon"])
        elif el.get("type") == "way":
            tags = el.get("tags", {})
            if tags.get("natural") == "tree_row" and tags.get("area") != "yes":
                ways.append(el)
    rows = []
    for way in sorted(ways, key=lambda w: w["id"]):
        points = [project(*nodes[n]) for n in way.get("nodes", []) if n in nodes]
        if len(points) >= 2:
            rows.append(points)
    return rows


# ---------------------------------------------------------------------------------------------------------------
# Geometry.


def merge_points(points: Sequence[Point], distance: float = MERGE_M) -> List[Point]:
    """The points without those closer than `distance` to an earlier kept one (in sorted order)."""
    cells: Dict[Tuple[int, int], List[Point]] = {}
    kept: List[Point] = []
    for p in sorted(tuple(p) for p in points):
        i, j = int(math.floor(p[0] / distance)), int(math.floor(p[1] / distance))
        near = [q for a in (i - 1, i, i + 1) for b in (j - 1, j, j + 1) for q in cells.get((a, b), ())]
        if any(math.hypot(p[0] - q[0], p[1] - q[1]) < distance for q in near):
            continue
        cells.setdefault((i, j), []).append(p)
        kept.append(p)
    return kept


def simplify_line(points: Sequence[Point], tolerance: float = SIMPLIFY_M) -> List[Point]:
    """Douglas-Peucker of an open line (both ends kept)."""
    if len(points) <= 2:
        return list(points)
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        lo, hi = stack.pop()
        best, at = -1.0, lo
        for i in range(lo + 1, hi):
            d = parcels._segment_distance(points[i], points[lo], points[hi])
            if d > best:
                best, at = d, i
        if best > tolerance:
            keep[at] = True
            stack += [(lo, at), (at, hi)]
    return [p for p, k in zip(points, keep) if k]


def _round_point(p: Point) -> IntPoint:
    """Whole metres, x east and z south."""
    return int(math.floor(p[0] + 0.5)), int(math.floor(-p[1] + 0.5))


def group_rings(rings: Sequence[Sequence[Point]]) -> List[List[List[Point]]]:
    """The rings of one area (filled even-odd) as polygons [outer, holes...]: a ring inside an odd number of the
    others is a hole of the smallest even one around it."""
    rings = [list(r) for r in rings if len(r) >= 3]
    depth = [sum(1 for k, other in enumerate(rings) if k != i and parcels._inside([other], *ring[0]))
             for i, ring in enumerate(rings)]  # fmt: skip
    outers = [i for i in range(len(rings)) if depth[i] % 2 == 0]
    polygons = {i: [rings[i]] for i in outers}
    for i in range(len(rings)):
        if depth[i] % 2 == 0:
            continue
        around = [o for o in outers if depth[o] == depth[i] - 1 and parcels._inside([rings[o]], *rings[i][0])]
        if around:
            best = min(around, key=lambda o: (abs(parcels._signed_area(rings[o])), o))
            polygons[best].append(rings[i])
    return [polygons[i] for i in outers]


def _finish_polygon(polygon: Sequence[Sequence[Point]]) -> Optional[List[List[IntPoint]]]:
    """Simplified whole-metre rings (outer counter-clockwise north up, holes the other way), or None."""
    rings: List[List[IntPoint]] = []
    for index, ring in enumerate(polygon):
        rounded = parcels._round_ring(parcels._simplify_ring(parcels._clean_ring(ring), SIMPLIFY_M))
        if len(rounded) < 3 or parcels._signed_area(rounded) == 0.0:
            if index == 0:
                return None
            continue
        # (x, z south): counter-clockwise north up is a negative shoelace sum
        if (parcels._signed_area(rounded) < 0.0) != (index == 0):
            rounded.reverse()
        rings.append(parcels._start_at_min(rounded))
    rings[1:] = sorted(rings[1:])
    return rings


def _finish_row(row: Sequence[Point]) -> Optional[List[IntPoint]]:
    out: List[IntPoint] = []
    for p in simplify_line(row):
        q = _round_point(p)
        if not out or out[-1] != q:
            out.append(q)
    if len(out) < 2:
        return None
    return out if out <= list(reversed(out)) else list(reversed(out))


def _reaches(points: Sequence[Point], rect: Tuple[float, float, float, float]) -> bool:
    x0, y0, x1, y1 = rect
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    return max(xs) >= x0 and min(xs) <= x1 and max(ys) >= y0 and min(ys) <= y1


def build_tree_features(points: Sequence[Point], rows: Sequence[Sequence[Point]],
                        areas: Sequence[Tuple[str, Sequence[Sequence[Point]]]],
                        rect: Tuple[float, float, float, float]) -> dict:  # fmt: skip
    """The tree features of a map (inputs in local metres, x east, y north; `rect` = (x0, y0, x1, y1) of the map's
    hexes): {"points": [(x, z)], "rows": [[(x, z)...]], "orchard": [[outer, holes...]], "farmyard": [...]} in whole
    metres with z south, each list sorted."""
    x0, y0, x1, y1 = rect
    inside = [p for p in merge_points(points) if x0 <= p[0] <= x1 and y0 <= p[1] <= y1]
    features: dict = {"points": sorted(set(_round_point(p) for p in inside), key=lambda p: (p[1], p[0]))}
    finished_rows = {tuple(r) for r in (_finish_row(row) for row in rows if _reaches(row, rect)) if r is not None}
    features["rows"] = [list(r) for r in sorted(finished_rows)]
    for kind in AREA_KINDS:
        by_outer: Dict[tuple, List[List[IntPoint]]] = {}
        for area_kind, rings in areas:
            if area_kind != kind:
                continue
            for polygon in group_rings(rings):
                if not _reaches(polygon[0], rect):
                    continue
                done = _finish_polygon(polygon)
                if done is None:
                    continue
                key = tuple(done[0])
                if key not in by_outer or (len(done), done) > (len(by_outer[key]), by_outer[key]):
                    by_outer[key] = done
        features[kind] = [by_outer[k] for k in sorted(by_outer)]
    return features


# ---------------------------------------------------------------------------------------------------------------
# Output and statistics.


def _ints(values: Sequence[int]) -> str:
    return ", ".join(str(v) for v in values)


def tree_fields(features: dict) -> List[str]:
    """The `tree_*`, `orchard_*` and `farmyard_*` lines of an ImportedMap (see its doc comment)."""
    lines = [
        "tree_points = PackedInt32Array(%s)" % _ints([v for p in features["points"] for v in p]),
        "tree_row_sizes = PackedInt32Array(%s)" % _ints([len(r) for r in features["rows"]]),
        "tree_row_points = PackedInt32Array(%s)" % _ints([v for r in features["rows"] for p in r for v in p]),
    ]
    for kind in AREA_KINDS:
        polygons = features[kind]
        lines += [
            "%s_rings = PackedInt32Array(%s)" % (kind, _ints([len(p) for p in polygons])),
            "%s_ring_sizes = PackedInt32Array(%s)" % (kind, _ints([len(r) for p in polygons for r in p])),
            "%s_points = PackedInt32Array(%s)" % (kind, _ints([v for p in polygons for r in p for xz in r for v in xz])),
        ]
    return lines


def polyline_length(points: Sequence[Tuple[float, float]]) -> float:
    return sum(math.hypot(points[k][0] - points[k - 1][0], points[k][1] - points[k - 1][1])
               for k in range(1, len(points)))  # fmt: skip


def polygon_area(polygon: Sequence[Sequence[Tuple[float, float]]]) -> float:
    """Square metres of the outer ring minus its holes."""
    return abs(parcels._signed_area(polygon[0])) - sum(abs(parcels._signed_area(r)) for r in polygon[1:])


def tree_stats(features: dict, in_forest: Callable[[int, int], bool]) -> str:
    """One line of statistics for the import log and the task notes; `in_forest(x, z)` tells a point on a forest
    hex."""
    points = features["points"]
    forest = sum(1 for x, z in points if in_forest(x, z))
    return ("Tree features: %d trees (%.1f %% on forest hexes); %d tree rows, %.2f km; %d orchards, %.2f ha; "
            "%d farmyards, %.2f ha" % (
                len(points), 100.0 * forest / len(points) if points else 0.0, len(features["rows"]),
                sum(polyline_length(r) for r in features["rows"]) / 1000.0, len(features["orchard"]),
                sum(polygon_area(p) for p in features["orchard"]) / 10000.0, len(features["farmyard"]),
                sum(polygon_area(p) for p in features["farmyard"]) / 10000.0))  # fmt: skip
