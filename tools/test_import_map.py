"""Tests for tools/import_map.py. Run: python3 -m unittest discover -s tools -p 'test_import_map.py'

The fixtures in tools/import_map_fixtures/ are SYNTHETIC (a made-up hill, lake, forest and village near Szurpily),
written by `python3 tools/test_import_map.py --make-fixtures`; the importer turns them into the committed sample
map tests/fixtures/maps/sample_map.tres that the GDScript tests load. After an intended importer change, re-run
`--make-fixtures` and commit both.

The operational fixtures (TASK-092a) are SYNTHETIC too: a made-up coast, lake, forest, town and wetland around
54.5 N 22.5 E, where four 0.5-degree OSM tiles meet. `fixture_op_elements` is the whole area; `fake_overpass` cuts
it into tiles the way the Overpass API answers a bbox query (whole ways and relations that touch the bbox), and
`--make-fixtures` writes the 0.5-degree tiles into tools/import_map_fixtures/op_cache/osm/, the DEM into
op_dem.tif and the golden map tests/fixtures/maps/sample_op_map.tres.
"""
import base64
import json
import math
import shutil
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import import_map  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
FIXTURES = Path(__file__).resolve().parent / "import_map_fixtures"
DEM_FIXTURE = FIXTURES / "sample_dem.tif"
OSM_FIXTURE = FIXTURES / "sample_osm.json"
SAMPLE_MAP = REPO / "tests" / "fixtures" / "maps" / "sample_map.tres"
SAMPLE_ARGS = ["--center=54.2,22.9", "--size=6x5", "--hex=250", "--name=sample_map", "--display-name=Sample (synthetic)"]
OP_CACHE = FIXTURES / "op_cache"
OP_DEM_FIXTURE = FIXTURES / "op_dem.tif"
SAMPLE_OP_MAP = REPO / "tests" / "fixtures" / "maps" / "sample_op_map.tres"
OP_SEED = "54.52,22.44"  # in the sea north-west of the synthetic coast
OP_COUNTRIES = "PL:54.47,22.47,LT:54.52,22.57"  # west and east of the synthetic border
OP_ARGS = ["--profile=operational", "--center=54.5,22.5", "--size=10x8", "--hex=1000", "--name=sample_op_map",
           "--display-name=Operational sample (synthetic)", "--sea-seed=%s" % OP_SEED,
           "--countries=%s" % OP_COUNTRIES]  # fmt: skip
# Synthetic operational DEM grid (pixel-is-point), ~110 x 100 m pixels.
OP_DEM_LAT0, OP_DEM_LON0 = 54.55, 22.38
OP_DEM_DLAT, OP_DEM_DLON = 0.001, 0.0015
OP_DEM_ROWS, OP_DEM_COLS = 101, 161

# Synthetic DEM grid: pixel centres (pixel-is-point) from (DEM_LAT0, DEM_LON0) going south / east.
DEM_LAT0, DEM_LON0 = 54.21, 22.88
DEM_DLAT, DEM_DLON = 0.0005, 0.001
DEM_ROWS, DEM_COLS = 41, 41


def synthetic_height(lat: float, lon: float) -> float:
    """A hill in the north-east, a bowl in the south-west (under the lake), a gentle slope; like the Copernicus
    DSM it includes a 15 m forest canopy (over the forest of `fixture_osm`, not its clearing)."""
    in_forest = 54.2000 < lat < 54.2055 and 22.8860 < lon < 22.9010
    in_clearing = 54.2015 < lat < 54.2040 and 22.8925 < lon < 22.8965
    canopy = 15.0 if in_forest and not in_clearing else 0.0
    hill = 60.0 * math.exp(-(((lat - 54.203) / 0.0015) ** 2 + ((lon - 22.909) / 0.0025) ** 2))
    bowl = 8.0 * math.exp(-(((lat - 54.197) / 0.002) ** 2 + ((lon - 22.892) / 0.003) ** 2))
    return 150.0 + (lat - 54.19) * 400.0 + hill - bowl + canopy


def write_geotiff(path: Path, rows: list, lat0: float, lon0: float, dlat: float, dlon: float,
                  tile: int = 16, predictor: int = 3) -> None:  # fmt: skip
    """Tiled, deflated float32 GeoTIFF (little endian, pixel-is-point) like the Copernicus COGs."""
    height, width = len(rows), len(rows[0])
    across, down = -(-width // tile), -(-height // tile)
    blocks = []
    for bj in range(down):
        for bi in range(across):
            values = []
            for j in range(bj * tile, bj * tile + tile):
                for i in range(bi * tile, bi * tile + tile):
                    values.append(rows[j][i] if j < height and i < width else 0.0)
            raw = bytearray()
            for r in range(tile):
                row = values[r * tile : (r + 1) * tile]
                if predictor == 3:
                    be = struct.pack(">%df" % tile, *row)
                    planes = bytearray(be[k::4][i] for k in range(4) for i in range(tile))
                    raw.extend(bytes((planes[i] - (planes[i - 1] if i else 0)) & 0xFF for i in range(len(planes))))
                else:
                    raw.extend(struct.pack("<%df" % tile, *row))
            blocks.append(zlib.compress(bytes(raw), 9))
    entries = []  # (tag, type, values)
    entries += [(256, 3, [width]), (257, 3, [height]), (258, 3, [32]), (259, 3, [8]), (262, 3, [1])]
    entries += [(277, 3, [1]), (284, 3, [1]), (317, 3, [predictor]), (322, 3, [tile]), (323, 3, [tile])]
    entries += [(324, 4, None), (325, 4, [len(b) for b in blocks]), (339, 3, [3])]
    entries += [(33550, 12, [dlon, dlat, 0.0]), (33922, 12, [0.0, 0.0, 0.0, lon0, lat0, 0.0])]
    entries += [(34735, 3, [1, 1, 0, 3, 1024, 0, 1, 2, 1025, 0, 1, 2, 2048, 0, 1, 4326])]
    codes = {3: "H", 4: "I", 12: "d"}
    data_start = 8 + 2 + 12 * len(entries) + 4  # header + IFD; out-of-line values follow, then the blocks
    counts = {tag: (len(blocks) if values is None else len(values)) for tag, _, values in entries}
    sizes = [struct.calcsize(codes[typ]) * counts[tag] for tag, typ, _ in entries]
    offsets = []
    pos = data_start + sum(s for s in sizes if s > 4)
    for b in blocks:
        offsets.append(pos)
        pos += len(b)
    extra = bytearray()
    ifd = bytearray(struct.pack("<H", len(entries)))
    for tag, typ, values in entries:
        values = offsets if values is None else values
        packed = struct.pack("<%d%s" % (len(values), codes[typ]), *values)
        if len(packed) <= 4:
            ifd += struct.pack("<HHI", tag, typ, len(values)) + packed.ljust(4, b"\0")
        else:
            ifd += struct.pack("<HHII", tag, typ, len(values), data_start + len(extra))
            extra += packed
    ifd += struct.pack("<I", 0)
    with open(path, "wb") as f:
        f.write(b"II" + struct.pack("<HI", 42, 8) + bytes(ifd) + bytes(extra) + b"".join(blocks))


def fixture_osm() -> dict:
    """Synthetic Overpass answer: lake, forest multipolygon with a clearing, village, fields, wetland, a road, a
    river crossing it, plus a track and an unnamed stream that are not rule roads / rivers."""
    elements = []
    next_node = [1000]

    def ring(points: list) -> list:
        ids = []
        for lat, lon in points:
            next_node[0] += 1
            elements.append({"type": "node", "id": next_node[0], "lat": lat, "lon": lon})
            ids.append(next_node[0])
        return ids

    def box(s: float, w: float, n: float, e: float) -> list:
        ids = ring([(s, w), (s, e), (n, e), (n, w)])
        return ids + [ids[0]]

    elements.append({"type": "way", "id": 1, "nodes": box(54.1950, 22.8875, 54.1985, 22.8960), "tags": {"natural": "water"}})
    outer = ring([(54.2000, 22.8860), (54.2000, 22.9010), (54.2055, 22.9010), (54.2055, 22.8860)])
    elements.append({"type": "way", "id": 2, "nodes": outer[:3]})
    elements.append({"type": "way", "id": 3, "nodes": [outer[0]] + list(reversed(outer[2:]))})
    elements.append({"type": "way", "id": 4, "nodes": box(54.2015, 22.8925, 54.2040, 22.8965)})
    elements.append({"type": "relation", "id": 5, "tags": {"type": "multipolygon", "landuse": "forest"},
                     "members": [{"type": "way", "ref": 2, "role": "outer"}, {"type": "way", "ref": 3, "role": "outer"},
                                 {"type": "way", "ref": 4, "role": "inner"}]})  # fmt: skip
    elements.append({"type": "way", "id": 6, "nodes": box(54.1950, 22.9000, 54.1985, 22.9070), "tags": {"landuse": "residential"}})
    elements.append({"type": "way", "id": 7, "nodes": box(54.1945, 22.9070, 54.2000, 22.9140), "tags": {"landuse": "farmland"}})
    elements.append({"type": "way", "id": 8, "nodes": box(54.1950, 22.8960, 54.1975, 22.9000), "tags": {"natural": "wetland"}})
    elements.append({"type": "way", "id": 9, "nodes": ring([(54.1990, 22.8860), (54.1990, 22.9140)]), "tags": {"highway": "secondary"}})
    elements.append({"type": "way", "id": 10, "nodes": ring([(54.2060, 22.9035), (54.2000, 22.9040), (54.1940, 22.9030)]),
                     "tags": {"waterway": "river", "name": "Rzeka (synthetic)"}})  # fmt: skip
    elements.append({"type": "way", "id": 11, "nodes": ring([(54.2050, 22.8870), (54.1960, 22.8870)]), "tags": {"waterway": "stream"}})
    elements.append({"type": "way", "id": 12, "nodes": ring([(54.2045, 22.9100), (54.1950, 22.9120)]), "tags": {"highway": "track"}})
    return {"version": 0.6, "generator": "synthetic fixture (tools/test_import_map.py)", "elements": elements}


def synthetic_op_height(lat: float, lon: float) -> float:
    """A gentle slope up to the south-east, a steep hill (relief > 60 m within a 1 km hex) north of the forest."""
    hill = 160.0 * math.exp(-(((lat - 54.515) / 0.004) ** 2 + ((lon - 22.505) / 0.007) ** 2))
    return 5.0 + (54.55 - lat) * 200.0 + (lon - 22.38) * 50.0 + hill


def fixture_op_elements() -> dict:
    """The whole synthetic operational area (one Overpass-like answer, before tiling)."""
    elements = []
    next_node = [5000]

    def line(points: list) -> list:
        ids = []
        for lat, lon in points:
            next_node[0] += 1
            elements.append({"type": "node", "id": next_node[0], "lat": lat, "lon": lon})
            ids.append(next_node[0])
        return ids

    def box(s: float, w: float, n: float, e: float) -> list:
        ids = line([(s, w), (s, e), (n, e), (n, w)])
        return ids + [ids[0]]

    def way(way_id: int, nodes: list, tags: dict = None) -> None:
        element = {"type": "way", "id": way_id, "nodes": nodes}
        if tags:
            element["tags"] = tags
        elements.append(element)

    # The coast: land on the left (OSM rule), so walking south-west the sea lies to the north-west.
    way(100, line([(54.545, 22.52), (54.515, 22.47), (54.495, 22.40)]), {"natural": "coastline"})
    way(101, box(54.470, 22.550, 54.480, 22.575), {"natural": "water"})
    way(102, box(54.525, 22.400, 54.545, 22.440), {"natural": "water", "water": "lagoon"})  # a lagoon in the sea
    outer = line([(54.471, 22.43), (54.471, 22.53), (54.492, 22.53), (54.492, 22.43)])
    way(111, outer[:3])
    way(112, [outer[0]] + list(reversed(outer[2:])))
    way(113, box(54.478, 22.46, 54.485, 22.48))
    elements.append({"type": "relation", "id": 110, "tags": {"type": "multipolygon", "landuse": "forest"},
                     "members": [{"type": "way", "ref": 111, "role": "outer"}, {"type": "way", "ref": 112, "role": "outer"},
                                 {"type": "way", "ref": 113, "role": "inner"}]})  # fmt: skip
    way(120, box(54.494, 22.535, 54.512, 22.565), {"landuse": "residential"})
    way(121, box(54.500, 22.540, 54.504, 22.550), {"landuse": "industrial"})
    way(122, box(54.505, 22.566, 54.530, 22.580), {"landuse": "military"})  # not urban at the operational scale
    way(130, box(54.468, 22.500, 54.476, 22.540), {"natural": "wetland"})
    way(131, box(54.500, 22.420, 54.530, 22.460), {"landuse": "farmland"})  # plains, never fields
    way(140, line([(54.488, 22.40), (54.4885, 22.50), (54.489, 22.60)]), {"highway": "primary", "ref": "S61"})
    way(141, line([(54.530, 22.450), (54.470, 22.455)]), {"highway": "tertiary"})
    way(150, line([(54.540, 22.545), (54.500, 22.520), (54.460, 22.515)]), {"waterway": "river", "name": "Rzeka"})
    way(151, line([(54.520, 22.570), (54.470, 22.585)]), {"waterway": "stream", "name": "Struga"})
    # The border: its southern half is tagged (what the land-cover tiles cache), the northern half is an untagged
    # member of the country relation (found only by the borders-only query). Poland lies west of it, Lithuania east.
    border = line([(54.400, 22.525), (54.500, 22.535)])
    way(160, border, {"boundary": "administrative", "admin_level": "2"})
    way(161, [border[-1]] + line([(54.600, 22.600)]))
    elements.append({"type": "relation", "id": 170, "tags": {"type": "boundary", "boundary": "administrative",
                                                              "admin_level": "2"},
                     "members": [{"type": "way", "ref": 160, "role": "outer"}, {"type": "way", "ref": 161, "role": "outer"}]})  # fmt: skip
    return {"version": 0.6, "generator": "synthetic fixture (tools/test_import_map.py)", "elements": elements}


def _segment_touches(a: tuple, b: tuple, s: float, w: float, n: float, e: float) -> bool:
    """Whether the segment a-b (lat, lon) touches the bbox (Liang-Barsky clipping)."""
    t0, t1 = 0.0, 1.0
    dlat, dlon = b[0] - a[0], b[1] - a[1]
    for p, q in ((-dlon, a[1] - w), (dlon, e - a[1]), (-dlat, a[0] - s), (dlat, n - a[0])):
        if p == 0.0:
            if q < 0.0:
                return False
            continue
        t = q / p
        if p < 0.0:
            t0 = max(t0, t)
        else:
            t1 = min(t1, t)
        if t0 > t1:
            return False
    return True


def fake_overpass(whole: dict, s: float, w: float, n: float, e: float) -> dict:
    """What Overpass answers for the bbox with `(._;>;); out body;`: every way that touches it and every relation
    with such a member way, complete (all member ways, all their nodes), nodes then ways then relations by id."""
    nodes = {el["id"]: el for el in whole["elements"] if el["type"] == "node"}
    ways = {el["id"]: el for el in whole["elements"] if el["type"] == "way"}
    relations = [el for el in whole["elements"] if el["type"] == "relation"]
    picked = set()
    for way_id, way in ways.items():
        pts = [(nodes[k]["lat"], nodes[k]["lon"]) for k in way["nodes"]]
        if any(_segment_touches(a, b, s, w, n, e) for a, b in zip(pts, pts[1:])):
            picked.add(way_id)
    rels = [r for r in relations if any(m["ref"] in picked for m in r["members"] if m["type"] == "way")]
    for rel in rels:
        picked.update(m["ref"] for m in rel["members"] if m["type"] == "way" and m["ref"] in ways)
    node_ids = sorted({k for way_id in picked for k in ways[way_id]["nodes"]})
    elements = [nodes[k] for k in node_ids] + [ways[k] for k in sorted(picked)] + sorted(rels, key=lambda r: r["id"])
    return {"version": 0.6, "generator": whole["generator"], "elements": elements}


def fake_border_overpass(whole: dict, s: float, w: float, n: float, e: float) -> dict:
    """What Overpass answers for `border_query`: the ways of the country relations that touch the bbox (untagged
    members included) and their nodes, no relations."""
    nodes = {el["id"]: el for el in whole["elements"] if el["type"] == "node"}
    ways = {el["id"]: el for el in whole["elements"] if el["type"] == "way"}
    picked = set()
    for rel in (el for el in whole["elements"] if el["type"] == "relation"):
        tags = rel.get("tags", {})
        if tags.get("boundary") != "administrative" or tags.get("admin_level") != "2":
            continue
        for member in rel["members"]:
            pts = [(nodes[k]["lat"], nodes[k]["lon"]) for k in ways[member["ref"]]["nodes"]]
            if any(_segment_touches(a, b, s, w, n, e) for a, b in zip(pts, pts[1:])):
                picked.add(member["ref"])
    node_ids = sorted({k for way_id in picked for k in ways[way_id]["nodes"]})
    elements = [nodes[k] for k in node_ids] + [ways[k] for k in sorted(picked)]
    return {"version": 0.6, "generator": whole["generator"], "elements": elements}


def write_op_cache(cache: Path, deg: float) -> None:
    """The synthetic operational area cut into `deg` tiles in `cache`/osm, named like the importer's tiles."""
    whole = fixture_op_elements()
    (cache / "osm").mkdir(parents=True, exist_ok=True)
    for lat, lon in import_map.osm_tiles(54.40, 22.30, 54.60, 22.70, deg):
        answer = fake_overpass(whole, lat, lon, lat + deg, lon + deg)
        path = import_map.osm_tile_path(cache, lat, lon, deg)
        path.write_text(json.dumps(answer, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        borders = fake_border_overpass(whole, lat, lon, lat + deg, lon + deg)
        path = import_map.border_tile_path(cache, lat, lon, deg)
        path.write_text(json.dumps(borders, indent=1, sort_keys=True) + "\n", encoding="utf-8")


COUNTRY_CASES = ("straight", "diagonal", "lake", "gap", "ring")
COUNTRY_SEEDS = "PL:54.50,22.44,LT:54.50,22.56"  # west and east of the synthetic borders (lon 22.44 / 22.56)


def fixture_country_osm(case: str) -> dict:
    """A tiny Overpass-like answer of border ways (tagged, as TASK-092a caches them) for one TASK-113 case on the
    10 x 8 hex operational sample at 54.5 N 22.5 E; the DEM and the sea are not needed."""
    elements = []
    next_node = [9000]

    def way(way_id: int, points: list, tags: dict = None) -> None:
        ids = []
        for lat, lon in points:
            next_node[0] += 1
            elements.append({"type": "node", "id": next_node[0], "lat": lat, "lon": lon})
            ids.append(next_node[0])
        if points[0] == points[-1]:
            ids[-1] = ids[0]  # a closed ring shares its first node
        elements.append({"type": "way", "id": way_id, "nodes": ids, "tags": tags or {}})

    border = {"boundary": "administrative", "admin_level": "2"}
    if case == "straight":
        way(1, [(54.40, 22.50), (54.60, 22.50)], border)
    elif case == "diagonal":
        way(1, [(54.40, 22.40), (54.60, 22.60)], border)
    elif case == "lake":
        way(1, [(54.40, 22.50), (54.60, 22.50)], border)
        way(2, [(54.485, 22.46), (54.485, 22.54), (54.515, 22.54), (54.515, 22.46), (54.485, 22.46)],
            {"natural": "water"})  # fmt: skip
    elif case == "gap":
        way(1, [(54.40, 22.50), (54.49, 22.50)], border)
        way(2, [(54.51, 22.50), (54.60, 22.50)], border)  # 2.2 km gap in the line
    elif case == "ring":  # a closed border around a land area without a seed
        way(1, [(54.40, 22.50), (54.60, 22.50)], border)
        way(2, [(54.48, 22.52), (54.48, 22.55), (54.52, 22.55), (54.52, 22.52), (54.48, 22.52)], border)
    return {"version": 0.6, "generator": "synthetic fixture (tools/test_import_map.py)", "elements": elements}


def make_fixtures() -> None:
    FIXTURES.mkdir(parents=True, exist_ok=True)
    rows = [[synthetic_height(DEM_LAT0 - j * DEM_DLAT, DEM_LON0 + i * DEM_DLON) for i in range(DEM_COLS)] for j in range(DEM_ROWS)]
    write_geotiff(DEM_FIXTURE, rows, DEM_LAT0, DEM_LON0, DEM_DLAT, DEM_DLON)
    OSM_FIXTURE.write_text(json.dumps(fixture_osm(), indent=1, sort_keys=True) + "\n", encoding="utf-8")
    import_map.run(SAMPLE_ARGS + ["--offline", "--dem=%s" % DEM_FIXTURE, "--osm=%s" % OSM_FIXTURE, "--out=%s" % SAMPLE_MAP])
    op_rows = [[synthetic_op_height(OP_DEM_LAT0 - j * OP_DEM_DLAT, OP_DEM_LON0 + i * OP_DEM_DLON)
                for i in range(OP_DEM_COLS)] for j in range(OP_DEM_ROWS)]  # fmt: skip
    write_geotiff(OP_DEM_FIXTURE, op_rows, OP_DEM_LAT0, OP_DEM_LON0, OP_DEM_DLAT, OP_DEM_DLON, tile=64)
    shutil.rmtree(OP_CACHE, ignore_errors=True)
    write_op_cache(OP_CACHE, import_map.OSM_TILE_DEG)
    import_map.run(OP_ARGS + ["--offline", "--cache=%s" % OP_CACHE, "--dem=%s" % OP_DEM_FIXTURE, "--out=%s" % SAMPLE_OP_MAP])
    for case in COUNTRY_CASES:
        (FIXTURES / ("country_%s.json" % case)).write_text(json.dumps(fixture_country_osm(case), indent=1, sort_keys=True) + "\n",
                                                           encoding="utf-8")  # fmt: skip


def _arrays(text: str) -> dict:
    result = {}
    for line in text.splitlines():
        if " = Packed" in line:
            key, value = line.split(" = ", 1)
            result[key] = value[value.index("(") + 1 : -1]
    return result


class ProjectionTest(unittest.TestCase):
    def test_zone_of_the_suwalki_gap_is_34(self) -> None:
        self.assertEqual(import_map.utm_zone(22.93), 34)
        self.assertEqual(import_map.utm_zone(24.0), 35)

    def test_central_meridian_maps_to_false_easting(self) -> None:
        e, n = import_map.to_utm(54.0, 21.0, 34)
        self.assertAlmostEqual(e, 500000.0, places=6)
        # Northing = 0.9996 x the WGS84 meridian arc from the equator, integrated numerically (Simpson).
        a, f = 6378137.0, 1 / 298.257223563
        e2 = f * (2 - f)
        steps = 2000
        h = math.radians(54.0) / steps
        radius = [a * (1 - e2) / (1 - e2 * math.sin(k * h) ** 2) ** 1.5 for k in range(steps + 1)]
        arc = h / 3 * (radius[0] + radius[-1] + 4 * sum(radius[1:-1:2]) + 2 * sum(radius[2:-1:2]))
        self.assertAlmostEqual(n, 0.9996 * arc, delta=0.01)

    def test_roundtrip_is_within_a_centimetre(self) -> None:
        for lat, lon in [(54.2, 22.9), (54.0, 18.5), (55.9, 23.9), (50.1, 21.0)]:
            e, n = import_map.to_utm(lat, lon, 34)
            back = import_map.from_utm(e, n, 34)
            self.assertAlmostEqual(back[0], lat, places=7)
            self.assertAlmostEqual(back[1], lon, places=7)

    def test_scale_factor_off_the_central_meridian(self) -> None:
        # Point scale k = 0.9996 * (1 + x^2 / (2 R^2)) for a short east-west step 123 km east of the meridian.
        lat = 54.2
        e1, n1 = import_map.to_utm(lat, 22.9, 34)
        e2, n2 = import_map.to_utm(lat, 22.9001, 34)
        a, f = 6378137.0, 1 / 298.257223563
        e2_ = f * (2 - f)
        nu = a / math.sqrt(1 - e2_ * math.sin(math.radians(lat)) ** 2)
        ground = nu * math.cos(math.radians(lat)) * math.radians(0.0001)
        k = math.hypot(e2 - e1, n2 - n1) / ground
        x = e1 - 500000.0
        self.assertAlmostEqual(k, 0.9996 * (1 + x * x / (2 * 6371000.0**2)), delta=2e-5)


class HexLayoutTest(unittest.TestCase):
    def test_tile_centres_round_trip(self) -> None:
        layout = import_map.HexLayout.centred(7, 6, 250.0, 600000.0, 6000000.0)
        for row in range(6):
            for col in range(7):
                e, n = layout.centre(col, row)
                self.assertEqual(layout.tile_at(e, n), (col, row))
                self.assertEqual(layout.tile_at(e + 100.0, n), (col, row), "within the inradius 125 m")
        self.assertIsNone(layout.tile_at(layout.origin_e - 200.0, layout.origin_n))

    def test_neighbouring_centres_are_the_spacing_apart(self) -> None:
        layout = import_map.HexLayout(4, 4, 250.0, 0.0, 0.0)
        a = layout.centre(1, 1)
        for b in (layout.centre(2, 1), layout.centre(1, 2), layout.centre(2, 2), layout.centre(1, 0)):
            self.assertAlmostEqual(math.hypot(b[0] - a[0], b[1] - a[1]), 250.0, places=6)
        self.assertLess(layout.centre(0, 1)[1], layout.centre(0, 0)[1], "row 1 is south of row 0")

    def test_centred_layout_is_centred(self) -> None:
        layout = import_map.HexLayout.centred(30, 24, 250.0, 620000.0, 6010000.0)
        min_e, min_n, max_e, max_n = layout.bounds()
        self.assertAlmostEqual((min_e + max_e) / 2, 620000.0, delta=1.0)
        self.assertAlmostEqual((min_n + max_n) / 2, 6010000.0, delta=1.0)
        self.assertAlmostEqual(max_e - min_e, 30.5 * 250.0, delta=1.0)


class GeoTiffTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())

    def tearDown(self) -> None:
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_reads_tiled_deflate_float_predictor(self) -> None:
        rows = [[100.0 + j * 1.5 - i * 0.25 for i in range(37)] for j in range(21)]
        for predictor in (1, 3):
            path = self.dir / ("p%d.tif" % predictor)
            write_geotiff(path, rows, 54.0, 22.0, 0.001, 0.002, tile=16, predictor=predictor)
            tif = import_map.GeoTiff(path)
            self.assertEqual((tif.width, tif.height), (37, 21))
            for j, i in [(0, 0), (20, 36), (16, 16), (5, 30)]:
                self.assertAlmostEqual(tif.pixel(i, j), rows[j][i], places=4)
            # Pixel-is-point: pixel (i, j) is centred on (lat0 - j*dlat, lon0 + i*dlon); bilinear between them.
            self.assertAlmostEqual(tif.sample(54.0 - 0.0035, 22.0 + 0.003), 100.0 + 3.5 * 1.5 - 1.5 * 0.25, places=4)

    def test_committed_dem_fixture_matches_the_synthetic_function(self) -> None:
        tif = import_map.GeoTiff(DEM_FIXTURE)
        for j, i in [(0, 0), (12, 30), (40, 40)]:
            expected = synthetic_height(DEM_LAT0 - j * DEM_DLAT, DEM_LON0 + i * DEM_DLON)
            self.assertAlmostEqual(tif.pixel(i, j), expected, places=3)

    def test_copernicus_tile_names(self) -> None:
        self.assertEqual(import_map.copernicus_tile_name(54, 22), "Copernicus_DSM_COG_10_N54_00_E022_00_DEM")
        self.assertEqual(import_map.copernicus_tile_name(-1, -3), "Copernicus_DSM_COG_10_S01_00_W003_00_DEM")


class OsmTest(unittest.TestCase):
    def test_tag_classes(self) -> None:
        self.assertEqual(import_map.cover_class({"natural": "water"}), "W")
        self.assertEqual(import_map.cover_class({"water": "pond"}), "W")
        self.assertEqual(import_map.cover_class({"landuse": "forest"}), "F")
        self.assertEqual(import_map.cover_class({"natural": "wood"}), "F")
        self.assertEqual(import_map.cover_class({"landuse": "farmyard"}), "U")
        self.assertEqual(import_map.cover_class({"landuse": "farmland"}), "A")
        self.assertEqual(import_map.cover_class({"natural": "wetland"}), "M")
        self.assertEqual(import_map.cover_class({"landuse": "meadow"}), "G")
        self.assertIsNone(import_map.cover_class({"highway": "primary"}))
        self.assertIsNone(import_map.cover_class({"building": "yes"}))

    def test_multipolygon_rings_are_assembled_and_sorted_by_priority(self) -> None:
        areas = import_map.osm_areas(fixture_osm())
        self.assertEqual([a[0] for a in areas], ["A", "U", "F", "M", "W"])
        forest = areas[2][1]
        self.assertEqual(len(forest), 2, "outer ring joined from two ways + the inner ring")
        self.assertTrue(all(r[0] == r[-1] for r in forest))

    def test_open_ring_is_dropped(self) -> None:
        self.assertEqual(import_map._assemble_rings([[1, 2, 3], [3, 4]]), [])
        self.assertEqual(import_map._assemble_rings([[1, 2, 3], [1, 4, 3]]), [[1, 2, 3, 4, 1]])

    def test_scanline_fill_even_odd(self) -> None:
        grid = [bytearray(10) for _ in range(10)]
        outer = [(0.0, 0.0), (9.0, 0.0), (9.0, 9.0), (0.0, 9.0), (0.0, 0.0)]
        hole = [(3.0, 3.0), (6.0, 3.0), (6.0, 6.0), (3.0, 6.0), (3.0, 3.0)]
        import_map._scanline_fill(grid, 1, [outer, hole], 0.0, 0.0, 1.0)
        self.assertEqual(grid[1][1], 1)
        self.assertEqual(grid[4][4], 0, "inside the hole")
        self.assertEqual(grid[8][8], 1)


def _counts(**shares: int) -> list:
    """Point counts per COVER_CLASSES index; keyword = class char (`unmapped` for '.'), 70 points in total."""
    counts = [0] * len(import_map.COVER_CLASSES)
    for key, value in shares.items():
        counts[import_map.COVER_CLASSES.index("." if key == "unmapped" else key)] = value
    counts[0] += 70 - sum(counts)
    return counts


class ClassifyTest(unittest.TestCase):
    def test_urban_from_a_fifth_of_the_hex(self) -> None:
        self.assertEqual(import_map.classify(_counts(U=14, A=35), 0.0), "urban", "20 % urban + 50 % fields")
        self.assertEqual(import_map.classify(_counts(U=13, A=35), 0.0), "fields", "19 % urban + 50 % fields")

    def test_forest_and_water_dominance_come_first(self) -> None:
        self.assertEqual(import_map.classify(_counts(F=42, U=21), 0.0), "forest", "60 % forest + 30 % urban")
        self.assertEqual(import_map.classify(_counts(W=40, M=30), 0.0), "water")

    def test_marsh_from_a_quarter_of_the_hex(self) -> None:
        self.assertEqual(import_map.classify(_counts(M=18), 0.0), "marsh", "25 %")
        self.assertEqual(import_map.classify(_counts(M=17, A=40), 0.0), "fields", "24 %")
        self.assertEqual(import_map.classify(_counts(M=18), 20.0), "marsh", "marshes are flat; before hills")

    def test_urban_before_hills_and_hills_before_fields(self) -> None:
        self.assertEqual(import_map.classify(_counts(U=14, A=40), 20.0), "urban")
        self.assertEqual(import_map.classify(_counts(A=50), 20.0), "hills", "a ploughed hill is a hill")
        self.assertEqual(import_map.classify(_counts(A=50), 14.9), "fields")

    def test_unmapped_or_grass_flat_is_plains(self) -> None:
        self.assertEqual(import_map.classify(_counts(), 0.0), "plains")
        self.assertEqual(import_map.classify(_counts(G=40, A=20), 0.0), "plains")

    def test_shares_are_options(self) -> None:
        self.assertEqual(import_map.classify(_counts(U=10), 0.0, urban_share=0.1), "urban")
        self.assertEqual(import_map.classify(_counts(M=10), 0.0, marsh_share=0.1), "marsh")


class LineKindTest(unittest.TestCase):
    def test_rule_roads(self) -> None:
        for value in import_map.ROAD_HIGHWAYS + ("primary_link", "tertiary_link"):
            self.assertEqual(import_map.line_kind({"highway": value}), import_map.ROAD, value)
        for value in ("track", "path", "footway", "service", "cycleway"):
            self.assertIsNone(import_map.line_kind({"highway": value}), value)

    def test_rivers_canals_and_named_streams(self) -> None:
        self.assertEqual(import_map.line_kind({"waterway": "river"}), import_map.RIVER)
        self.assertEqual(import_map.line_kind({"waterway": "canal"}), import_map.RIVER)
        self.assertEqual(import_map.line_kind({"waterway": "stream", "name": "Szeszupa"}), import_map.RIVER)
        self.assertIsNone(import_map.line_kind({"waterway": "stream"}))
        self.assertIsNone(import_map.line_kind({"waterway": "ditch", "name": "Rów"}))
        self.assertIsNone(import_map.line_kind({"waterway": "drain"}))
        self.assertIsNone(import_map.line_kind({"waterway": "riverbank"}), "areas are water already")

    def test_lines_are_sorted_by_kind_and_id(self) -> None:
        lines = import_map.osm_lines(fixture_osm())
        self.assertEqual([kind for kind, _ in lines], [import_map.RIVER, import_map.ROAD])


class LineLinksTest(unittest.TestCase):
    def setUp(self) -> None:
        self.layout = import_map.HexLayout(6, 6, 250.0, 600000.0, 6000000.0)

    def _masks(self, points: list, water: tuple = ()) -> dict:
        return import_map.store_links(self.layout, import_map.line_links(self.layout, points), list(water))

    def _neighbour(self, col: int, row: int, direction: int) -> tuple:
        q, r = self.layout.axial(col, row)
        dq, dr = import_map.HEX_DIRECTIONS[direction]
        return self.layout.offset(q + dq, r + dr)

    def test_straight_road_through_three_tiles_links_both_sides(self) -> None:
        masks = self._masks([self.layout.centre(1, 2), self.layout.centre(3, 2)])
        self.assertEqual(masks, {(1, 2): 1 << 0, (2, 2): (1 << 0) | (1 << 3), (3, 2): 1 << 3})

    def test_bit_index_follows_the_hex_directions(self) -> None:
        for direction in range(6):
            other = self._neighbour(2, 2, direction)
            masks = self._masks([self.layout.centre(2, 2), self.layout.centre(*other)])
            self.assertEqual(masks[(2, 2)], 1 << direction, "direction %d" % direction)
            self.assertEqual(masks[other], 1 << ((direction + 3) % 6), "direction %d, other side" % direction)

    def test_directions_match_the_compass(self) -> None:
        e0, n0 = self.layout.centre(2, 2)
        east = self._neighbour(2, 2, 0)
        north_east = self._neighbour(2, 2, 1)
        south_east = self._neighbour(2, 2, 5)
        self.assertGreater(self.layout.centre(*east)[0], e0)
        self.assertAlmostEqual(self.layout.centre(*east)[1], n0)
        self.assertGreater(self.layout.centre(*north_east)[1], n0, "direction 1 is north (-r)")
        self.assertLess(self.layout.centre(*south_east)[1], n0, "direction 5 is south (+r)")

    def _corner_line(self, depth: float) -> tuple:
        """A line from tile A (2, 2) to its east neighbour B that bends `depth` metres into the north-east
        neighbour C past the corner the three share."""
        a, b, c = (2, 2), self._neighbour(2, 2, 0), self._neighbour(2, 2, 1)
        ea, na = self.layout.centre(*a)
        m = self.layout.metres_per_unit
        corner = (ea + m * math.sqrt(3.0) / 2.0, na + m / 2.0)
        return a, b, c, [self.layout.centre(*a), (corner[0], corner[1] + depth), self.layout.centre(*b)]

    def test_a_clipped_corner_makes_no_link(self) -> None:
        a, b, c, line = self._corner_line(10.0)
        masks = self._masks(line)
        self.assertNotIn(c, masks)
        self.assertEqual(masks[a], 1 << 0)
        self.assertEqual(masks[b], 1 << 3)

    def test_a_longer_stretch_through_the_corner_links_it(self) -> None:
        a, b, c, line = self._corner_line(60.0)
        masks = self._masks(line)
        self.assertIn(c, masks)
        self.assertEqual(masks[a], 1 << 1, "A -> C")
        self.assertEqual(masks[c], (1 << 4) | (1 << 5), "C -> A and C -> B")

    def test_the_clip_threshold_is_forty_metres(self) -> None:
        layout = self.layout
        c = self._neighbour(2, 2, 1)
        for depth, linked in ((10.0, False), (60.0, True)):
            runs = []
            for e, n, along in import_map._densify(self._corner_line(depth)[3], import_map.LINE_STEP_M):
                tile = layout.offset(*layout.axial_at(e, n))
                if runs and runs[-1][0] == tile:
                    runs[-1][2] = along
                else:
                    runs.append([tile, along, along])
            inside = sum(r[2] - r[1] for r in runs if r[0] == c)
            self.assertEqual(inside >= import_map.CLIP_M, linked, "%s m in the corner" % inside)

    def test_a_line_leaving_the_map_sets_the_bit_on_the_edge_tile_only(self) -> None:
        e, n = self.layout.centre(5, 2)
        masks = self._masks([(e, n), (e + 500.0, n)])
        self.assertEqual(masks, {(5, 2): 1 << 0})

    def test_a_line_into_water_sets_the_bit_on_the_land_side_only(self) -> None:
        masks = self._masks([self.layout.centre(1, 2), self.layout.centre(3, 2)], water=((3, 2),))
        self.assertEqual(masks, {(1, 2): 1 << 0, (2, 2): (1 << 0) | (1 << 3)})

    def test_link_chars_are_64_unique(self) -> None:
        self.assertEqual(len(import_map.LINK_CHARS), 64)
        self.assertEqual(len(set(import_map.LINK_CHARS)), 64)
        self.assertEqual(import_map.LINK_CHARS[0], ".")
        self.assertEqual(import_map.LINK_CHARS[63], "@")


class ImportTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())

    def tearDown(self) -> None:
        shutil.rmtree(self.dir, ignore_errors=True)

    def _import(self, name: str) -> str:
        out = self.dir / name
        import_map.run(SAMPLE_ARGS + ["--offline", "--dem=%s" % DEM_FIXTURE, "--osm=%s" % OSM_FIXTURE, "--out=%s" % out])
        return out.read_bytes().decode("utf-8")

    def test_output_is_byte_identical_and_matches_the_committed_sample_map(self) -> None:
        first = self._import("a.tres")
        self.assertEqual(first, self._import("b.tres"))
        self.assertEqual(first, SAMPLE_MAP.read_text(encoding="utf-8"), "re-run tools/test_import_map.py --make-fixtures")

    def test_committed_osm_fixture_is_current(self) -> None:
        self.assertEqual(json.loads(OSM_FIXTURE.read_text(encoding="utf-8")), json.loads(json.dumps(fixture_osm())))

    def test_sample_map_classification(self) -> None:
        arrays = _arrays(self._import("c.tres"))
        terrain = [r.strip('"') for r in arrays["terrain_rows"].split(", ")]
        cover = [r.strip('"') for r in arrays["cover_rows"].split(", ")]
        self.assertEqual(len(terrain), 5)
        self.assertTrue(all(len(r) == 6 for r in terrain + cover))
        flat = "".join(terrain)
        for t in "PFHWAUM":
            self.assertIn(t, flat, "the sample has every terrain type")
        self.assertEqual(terrain[4][0], "W", "the lake in the south-west")
        self.assertEqual(terrain[0][0], "F", "the forest in the north-west")
        self.assertIn("U", "".join(cover), "the village")
        self.assertIn("A", "".join(cover), "the fields")
        roads = [r.strip('"') for r in arrays["road_rows"].split(", ")]
        rivers = [r.strip('"') for r in arrays["river_rows"].split(", ")]
        self.assertTrue(all(len(r) == 6 for r in roads + rivers) and len(roads) == len(rivers) == 5)
        self.assertNotEqual("".join(roads).strip("."), "", "the secondary road")
        self.assertNotEqual("".join(rivers).strip("."), "", "the river")
        for t, road, river in zip(flat, "".join(roads), "".join(rivers)):
            if t == "W":
                self.assertEqual(road + river, "..", "no links on water")
        elevation = [float(v) for v in arrays["elevation"].split(", ")]
        metres = [float(v) for v in arrays["elevation_m"].split(", ")]
        for t, e in zip(flat, elevation):
            if t == "W":
                self.assertEqual(e, import_map.WATER_ELEVATION)
            else:
                self.assertGreaterEqual(e, import_map.LAND_MIN)
                self.assertLessEqual(e, import_map.TOP_ELEVATION)
        land = [m for t, m in zip(flat, metres) if t != "W"]
        self.assertEqual(min(e for t, e in zip(flat, elevation) if t != "W"), import_map.LAND_MIN)
        self.assertGreater(max(land) - min(land), 30.0, "the hill")

    def test_offline_without_cache_fails(self) -> None:
        with self.assertRaises(SystemExit):
            import_map.run(["--center=54.2,22.9", "--size=2x2", "--name=x", "--out=%s" % (self.dir / "x.tres"),
                            "--offline", "--cache=%s" % (self.dir / "empty")])  # fmt: skip

    def test_cache_files_are_found_by_name(self) -> None:
        cache = self.dir / "cache"
        (cache / "dem").mkdir(parents=True)
        shutil.copy(DEM_FIXTURE, cache / "dem" / ("%s.tif" % import_map.copernicus_tile_name(54, 22)))
        layout = import_map.HexLayout.centred(6, 5, 250.0, *import_map.to_utm(54.2, 22.9, 34))
        min_e, min_n, max_e, max_n = layout.bounds(import_map.OSM_MARGIN_M)
        corners = [import_map.from_utm(e, n, 34) for e in (min_e, max_e) for n in (min_n, max_n)]
        bbox = [round(min(c[0] for c in corners), 5), round(min(c[1] for c in corners), 5),
                round(max(c[0] for c in corners), 5), round(max(c[1] for c in corners), 5)]  # fmt: skip
        (cache / "osm").mkdir()
        shutil.copy(OSM_FIXTURE, cache / "osm" / ("osm_%.5f_%.5f_%.5f_%.5f.json" % tuple(bbox)))
        out = self.dir / "cached.tres"
        args = SAMPLE_ARGS + ["--offline", "--cache=%s" % cache, "--out=%s" % out]
        import_map.run(args)
        self.assertEqual(out.read_text(encoding="utf-8"), SAMPLE_MAP.read_text(encoding="utf-8"))


def _op_counts(**shares: int) -> list:
    """Point counts per COVER_CLASSES index out of 100 (`unmapped` for '.')."""
    counts = [0] * len(import_map.COVER_CLASSES)
    for key, value in shares.items():
        counts[import_map.COVER_CLASSES.index("." if key == "unmapped" else key)] = value
    counts[0] += 100 - sum(counts)
    return counts


class OperationalClassifyTest(unittest.TestCase):
    def _classify(self, relief: float = 0.0, **shares: int) -> str:
        return import_map.classify_operational(_op_counts(**shares), relief)

    def test_water_from_half_the_hex_comes_first(self) -> None:
        self.assertEqual(self._classify(W=50, F=50), "water")
        self.assertEqual(self._classify(W=49, F=51), "forest")

    def test_urban_before_forest(self) -> None:
        self.assertEqual(self._classify(U=15, F=60), "urban")
        self.assertEqual(self._classify(U=14, F=60), "forest")

    def test_marsh_after_forest(self) -> None:
        self.assertEqual(self._classify(F=49, M=26), "marsh")
        self.assertEqual(self._classify(F=50, M=26), "forest")

    def test_hills_from_sixty_metres_of_relief(self) -> None:
        """The GDD's starting value 60 m (the spec's boundary test), passed explicitly since the tuning."""
        counts = _op_counts(F=49)
        self.assertEqual(import_map.classify_operational(counts, 60.0, hills_relief=60.0), "hills")
        self.assertEqual(import_map.classify_operational(counts, 59.9, hills_relief=60.0), "plains")

    def test_hills_from_the_tuned_relief_by_default(self) -> None:
        """Tuned on the real theatre import (TASK-092a): 35 m gives 8.8 % of the land as hills, 60 m only 0.5 %."""
        self.assertEqual(self._classify(35.0, F=49), "hills")
        self.assertEqual(self._classify(34.9, F=49), "plains")

    def test_farmland_is_plains_never_fields(self) -> None:
        self.assertEqual(self._classify(A=100), "plains")
        self.assertEqual(self._classify(G=60, A=40), "plains")

    def test_thresholds_are_parameters(self) -> None:
        counts = _op_counts(W=30, U=10, F=30, M=10)
        self.assertEqual(import_map.classify_operational(counts, 0.0, water_share=0.3), "water")
        self.assertEqual(import_map.classify_operational(counts, 0.0, urban_share=0.1), "urban")
        self.assertEqual(import_map.classify_operational(counts, 0.0, forest_share=0.3), "forest")
        self.assertEqual(import_map.classify_operational(counts, 0.0, marsh_share=0.1), "marsh")
        self.assertEqual(import_map.classify_operational(counts, 30.0, hills_relief=30.0), "hills")

    def test_military_areas_are_not_urban_at_the_operational_scale(self) -> None:
        table = import_map.OPERATIONAL.tag_classes
        self.assertIsNone(import_map.cover_class({"landuse": "military"}, table))
        self.assertIsNone(import_map.cover_class({"landuse": "farmland"}, table))
        self.assertEqual(import_map.cover_class({"landuse": "residential"}, table), "U")
        self.assertEqual(import_map.cover_class({"natural": "wood"}, table), "F")
        self.assertEqual(import_map.cover_class({"water": "lagoon"}, table), "W")


class ProfileTest(unittest.TestCase):
    def test_profiles(self) -> None:
        op, tac = import_map.OPERATIONAL, import_map.TACTICAL
        self.assertEqual((op.hex_m, op.sample_m, op.dem), (5000.0, 250.0, "glo90"))
        self.assertEqual((tac.hex_m, tac.sample_m, tac.dem), (250.0, 25.0, "glo30"))
        settings = import_map.Settings(op)
        self.assertEqual((settings.water_share, settings.urban_share, settings.forest_share), (0.50, 0.15, 0.50))
        self.assertEqual((settings.marsh_share, settings.hills_relief, settings.sample_m), (0.25, 35.0, 250.0))
        self.assertEqual(import_map.Settings(op, sample_m=100.0).sample_m, 100.0)

    def test_operational_roads_and_rivers(self) -> None:
        op = import_map.OPERATIONAL
        for value in ("motorway", "trunk", "primary", "secondary", "motorway_link", "secondary_link"):
            self.assertEqual(import_map.line_kind({"highway": value}, op), import_map.ROAD, value)
        for value in ("tertiary", "tertiary_link", "unclassified", "residential", "track"):
            self.assertIsNone(import_map.line_kind({"highway": value}, op), value)
        self.assertEqual(import_map.line_kind({"waterway": "river"}, op), import_map.RIVER)
        self.assertEqual(import_map.line_kind({"waterway": "canal"}, op), import_map.RIVER)
        self.assertIsNone(import_map.line_kind({"waterway": "stream", "name": "Szeszupa"}, op))

    def test_operational_query_asks_only_for_what_the_profile_reads(self) -> None:
        query = import_map.operational_query(54.0, 22.0, 54.5, 22.5)
        self.assertIn("(54.00000,22.00000,54.50000,22.50000)", query)
        for wanted in ('"natural"="coastline"', '"boundary"="administrative"]["admin_level"="2"', "wetland", "wood",
                       "forest", "residential", "farmyard", "(motorway|trunk|primary|secondary)(_link)?", "river|canal"):
            self.assertIn(wanted, query)
        for unwanted in ("farmland", "meadow", "tertiary", "stream", "military", "track"):
            self.assertNotIn(unwanted, query)

    def test_clip_length_scales_with_the_hex(self) -> None:
        self.assertEqual(import_map.clip_length(import_map.HexLayout(2, 2, 250.0, 0.0, 0.0)), 40.0)
        self.assertEqual(import_map.clip_length(import_map.HexLayout(2, 2, 5000.0, 0.0, 0.0)), 800.0)


class OperationalLinksTest(unittest.TestCase):
    """The corner clip at 5 km hexes: a stretch through the corner hex shorter than 800 m makes no link."""

    def setUp(self) -> None:
        self.layout = import_map.HexLayout(6, 6, 5000.0, 600000.0, 6000000.0)

    def _neighbour(self, col: int, row: int, direction: int) -> tuple:
        q, r = self.layout.axial(col, row)
        dq, dr = import_map.HEX_DIRECTIONS[direction]
        return self.layout.offset(q + dq, r + dr)

    def _line(self, depth: float) -> list:
        """Tile (2, 2) to its east neighbour, bending `depth` metres past their shared corner with the north-east
        neighbour."""
        ea, na = self.layout.centre(2, 2)
        m = self.layout.metres_per_unit
        corner = (ea + m * math.sqrt(3.0) / 2.0, na + m / 2.0)
        return [self.layout.centre(2, 2), (corner[0], corner[1] + depth), self.layout.centre(*self._neighbour(2, 2, 0))]

    def _inside(self, depth: float) -> float:
        """Length of the line inside the north-east neighbour (densified every metre)."""
        c = self._neighbour(2, 2, 1)
        pts = import_map._densify(self._line(depth), 1.0)
        inside = 0.0
        for (e1, n1, a1), (e2, n2, a2) in zip(pts, pts[1:]):
            if self.layout.tile_at((e1 + e2) / 2, (n1 + n2) / 2) == c:
                inside += a2 - a1
        return inside

    def _depth_for(self, length: float) -> float:
        lo, hi = 0.0, 2000.0
        for _ in range(40):
            mid = (lo + hi) / 2
            lo, hi = (mid, hi) if self._inside(mid) < length else (lo, mid)
        return (lo + hi) / 2

    def test_700_m_through_a_corner_makes_no_link_900_m_does(self) -> None:
        c = self._neighbour(2, 2, 1)
        for length, linked in ((700.0, False), (900.0, True)):
            depth = self._depth_for(length)
            self.assertAlmostEqual(self._inside(depth), length, delta=2.0)
            links = import_map.line_links(self.layout, self._line(depth), import_map.OPERATIONAL.line_step_m)
            masks = import_map.store_links(self.layout, links, [])
            self.assertEqual(c in masks, linked, "%.0f m in the corner" % length)


class Glo90Test(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())

    def tearDown(self) -> None:
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_tile_names(self) -> None:
        self.assertEqual(import_map.copernicus_tile_name(54, 22, "glo90"), "Copernicus_DSM_COG_30_N54_00_E022_00_DEM")
        self.assertEqual(import_map.copernicus_tile_name(54, 22, "glo30"), "Copernicus_DSM_COG_10_N54_00_E022_00_DEM")
        self.assertIn("copernicus-dem-90m", import_map.DEM_URLS["glo90"])

    def test_reads_a_glo90_sized_tile_from_the_cache(self) -> None:
        """A synthetic tile of GLO-90's size at 50-60 N (800 x 1200 pixels of 4.5" x 3"), next to a GLO-30-sized
        neighbour piece: the reader handles both widths."""
        dlon, dlat = 4.5 / 3600.0, 3.0 / 3600.0
        rows = [[float(j) + i / 1000.0 for i in range(800)] for j in range(1200)]
        name = import_map.copernicus_tile_name(54, 22, "glo90")
        (self.dir / "dem").mkdir()
        write_geotiff(self.dir / "dem" / (name + ".tif"), rows, 55.0, 22.0, dlat, dlon, tile=400, predictor=1)
        paths = import_map.dem_paths(self.dir, 54.2, 22.1, 54.3, 22.2, True, "glo90")
        self.assertEqual([p.name for p in paths], [name + ".tif"])
        dem = import_map.Dem(paths)
        tile = dem.tiles[0]
        self.assertEqual((tile.width, tile.height), (800, 1200))
        self.assertAlmostEqual(tile.pixel(799, 1199), 1199.799, places=3)
        self.assertAlmostEqual(dem.sample(55.0 - 600 * dlat, 22.0 + 400 * dlon), 600.4, places=3)
        self.assertAlmostEqual(dem.sample(55.0 - 600.5 * dlat, 22.0 + 400.5 * dlon), 600.9005, places=3)
        with self.assertRaises(SystemExit):
            import_map.dem_paths(self.dir, 54.2, 22.1, 54.3, 22.2, True, "glo30")


class OsmTilesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())
        self._download = import_map._download
        self._pause = import_map.RETRY_PAUSE_S
        import_map.RETRY_PAUSE_S = 0.0
        self.calls = []

    def tearDown(self) -> None:
        import_map._download = self._download
        import_map.RETRY_PAUSE_S = self._pause
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_tiles_are_aligned_to_the_grid(self) -> None:
        tiles = import_map.osm_tiles(52.94, 20.27, 55.47, 25.53, 0.5)
        self.assertEqual(tiles[0], (52.5, 20.0))
        self.assertEqual(tiles[-1], (55.0, 25.5))
        self.assertEqual(len(tiles), 6 * 12)
        self.assertEqual(import_map.osm_tiles(54.1, 22.1, 54.4, 22.4, 0.5), [(54.0, 22.0)])
        self.assertEqual(import_map.osm_tiles(54.0, 22.0, 54.5, 22.5, 0.5), [(54.0, 22.0)], "edges on the grid")
        self.assertEqual(len(import_map.osm_tiles(54.4, 22.4, 54.6, 22.6, 0.25)), 4)

    def _fake_download(self, failures: int = 0) -> None:
        def download(url: str, target: Path, data: bytes = None) -> None:
            self.calls.append(target.name)
            if self.calls.count(target.name) <= failures:
                raise OSError("HTTP Error 429: Too Many Requests")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('{"version": 0.6, "elements": []}\n', encoding="utf-8")

        import_map._download = download

    def test_offline_with_a_complete_cache_never_downloads(self) -> None:
        write_op_cache(self.dir, 0.5)
        self._fake_download()
        paths = import_map.osm_tile_paths(self.dir, 54.45, 22.40, 54.55, 22.60, True, 0.5)
        self.assertEqual(len(paths), 4)
        self.assertEqual(self.calls, [])

    def test_a_missing_tile_fails_offline_naming_the_tile(self) -> None:
        write_op_cache(self.dir, 0.5)
        import_map.osm_tile_path(self.dir, 54.5, 22.5, 0.5).unlink()
        with self.assertRaises(SystemExit) as raised:
            import_map.osm_tile_paths(self.dir, 54.45, 22.40, 54.55, 22.60, True, 0.5)
        self.assertIn("54.5000 N 22.5000 E", str(raised.exception))

    def test_failed_tiles_are_retried_and_finished_ones_never_fetched_again(self) -> None:
        write_op_cache(self.dir, 0.5)
        for lat, lon in ((54.0, 22.5), (54.5, 22.0)):
            import_map.osm_tile_path(self.dir, lat, lon, 0.5).unlink()
        self._fake_download(failures=2)
        import_map.osm_tile_paths(self.dir, 54.45, 22.40, 54.55, 22.60, False, 0.5)
        self.assertEqual(len(self.calls), 6, "two missing tiles, each failing twice before it works")
        self.assertEqual(len(set(self.calls)), 2)
        self.calls.clear()
        import_map.osm_tile_paths(self.dir, 54.45, 22.40, 54.55, 22.60, False, 0.5)
        self.assertEqual(self.calls, [], "all tiles cached now")

    def test_a_tile_failing_every_retry_stops_the_run(self) -> None:
        self._fake_download(failures=99)
        with self.assertRaises(SystemExit):
            import_map.osm_tile_paths(self.dir, 54.1, 22.1, 54.2, 22.2, False, 0.5)
        self.assertEqual(len(self.calls), 1 + import_map.DOWNLOAD_RETRIES)
        self.assertEqual(list((self.dir / "osm").glob("*.json")) if (self.dir / "osm").exists() else [], [])

    def test_an_overpass_runtime_error_is_not_cached(self) -> None:
        path = self.dir / "answer.json"
        path.write_text('{"version": 0.6, "elements": [], "remark": "runtime error: Query timed out"}', encoding="utf-8")
        with self.assertRaises(ValueError):
            import_map._check_overpass_answer(path)
        path.write_text("<html>429 Too Many Requests</html>", encoding="utf-8")
        with self.assertRaises(ValueError):
            import_map._check_overpass_answer(path)
        path.write_text('{"version": 0.6, "elements": []}\n', encoding="utf-8")
        import_map._check_overpass_answer(path)


class SeaFillTest(unittest.TestCase):
    """A coast running south-west on a 10 x 10 lattice of 1 m: land on its left (south-east), sea on its right."""

    COAST = [[(9.6, 9.4), (5.0, 5.2), (0.2, 3.7)]]

    def _cover(self) -> list:
        return [bytearray(10) for _ in range(10)]

    def test_seed_side_becomes_water_land_side_does_not(self) -> None:
        cover = self._cover()
        reached = import_map.fill_sea(cover, self.COAST, [(1.0, 8.0)], 0.0, 0.0, 1.0)
        water = import_map.COVER_CLASSES.index("W")
        self.assertGreater(reached, 10)
        self.assertEqual(cover[8][1], water)
        self.assertEqual(cover[9][0], water, "north-west corner")
        self.assertEqual(cover[0][9], 0, "south-east corner is land")
        self.assertEqual(cover[2][5], 0)
        self.assertEqual(sum(row.count(water) for row in cover), reached)

    def test_a_seed_on_land_is_an_error(self) -> None:
        with self.assertRaises(ValueError):
            import_map.fill_sea(self._cover(), self.COAST, [(8.0, 1.0)], 0.0, 0.0, 1.0)

    def test_a_seed_off_the_lattice_or_without_a_coast_is_an_error(self) -> None:
        with self.assertRaises(ValueError):
            import_map.fill_sea(self._cover(), self.COAST, [(-5.0, 8.0)], 0.0, 0.0, 1.0)
        with self.assertRaises(ValueError):
            import_map.fill_sea(self._cover(), [], [(1.0, 8.0)], 0.0, 0.0, 1.0)

    def test_a_diagonal_coast_does_not_leak(self) -> None:
        cover = self._cover()
        import_map.fill_sea(cover, [[(10.0, 10.0), (-1.0, -1.0)]], [(1.0, 8.0)], 0.0, 0.0, 1.0)
        self.assertEqual(cover[1][8], 0, "south-east of the diagonal stays land")

    def test_existing_water_is_kept(self) -> None:
        cover = self._cover()
        water = import_map.COVER_CLASSES.index("W")
        cover[0][9] = water  # a lake on land
        import_map.fill_sea(cover, self.COAST, [(1.0, 8.0)], 0.0, 0.0, 1.0)
        self.assertEqual(cover[0][9], water)


class OperationalImportTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())

    def tearDown(self) -> None:
        shutil.rmtree(self.dir, ignore_errors=True)

    def _import(self, name: str, cache: Path = OP_CACHE, extra: tuple = ()) -> str:
        out = self.dir / name
        import_map.run(OP_ARGS + ["--offline", "--cache=%s" % cache, "--dem=%s" % OP_DEM_FIXTURE, "--out=%s" % out]
                       + list(extra))  # fmt: skip
        return out.read_text(encoding="utf-8")

    def test_output_is_byte_identical_and_matches_the_committed_sample(self) -> None:
        first = self._import("a.tres")
        self.assertEqual(first, self._import("b.tres"))
        self.assertEqual(first, SAMPLE_OP_MAP.read_text(encoding="utf-8"), "re-run tools/test_import_map.py --make-fixtures")

    def test_committed_tiles_are_current(self) -> None:
        cache = self.dir / "cache"
        write_op_cache(cache, import_map.OSM_TILE_DEG)
        committed = sorted(p.name for p in (OP_CACHE / "osm").glob("*.json"))
        self.assertEqual(committed, sorted(p.name for p in (cache / "osm").glob("*.json")))
        self.assertEqual(len(committed), 8, "the sample lies where four tiles meet: land cover and borders each")
        for name in committed:
            self.assertEqual((OP_CACHE / "osm" / name).read_text(encoding="utf-8"),
                             (cache / "osm" / name).read_text(encoding="utf-8"), name)  # fmt: skip

    def test_one_tile_or_four_tiles_give_the_same_map(self) -> None:
        one = self.dir / "one"
        write_op_cache(one, 1.0)
        self.assertEqual(len(list((one / "osm").glob("*.json"))), 2, "land cover and borders")
        self.assertEqual(self._import("one.tres", one, ("--tile-deg=1.0",)), self._import("four.tres"))

    def test_sample_classification(self) -> None:
        text = self._import("c.tres")
        self.assertIn('hex_spacing_m = 1000.0', text)
        self.assertIn("GLO-90", text)
        arrays = _arrays(text)
        terrain = [r.strip('"') for r in arrays["terrain_rows"].split(", ")]
        roads = [r.strip('"') for r in arrays["road_rows"].split(", ")]
        rivers = [r.strip('"') for r in arrays["river_rows"].split(", ")]
        self.assertEqual(len(terrain), 8)
        self.assertTrue(all(len(r) == 10 for r in terrain + roads + rivers))
        flat = "".join(terrain)
        for t in "PFHWUM":
            self.assertIn(t, flat, "the operational sample has terrain %s" % t)
        self.assertNotIn("A", flat, "no fields at the operational scale")
        self.assertEqual(terrain[0][0], "W", "the sea in the north-west corner")
        self.assertNotEqual(terrain[7][9], "W")
        self.assertEqual(len([r for r in roads if r.strip(".")]), 1, "the primary road only (no tertiary)")
        self.assertNotEqual("".join(rivers).strip("."), "", "the river")
        stream_col = [r[9] for r in rivers]
        self.assertEqual(stream_col, ["."] * 8, "the named stream in the east makes no river")

    def test_without_the_seed_there_is_no_sea(self) -> None:
        out = self.dir / "dry.tres"
        args = [a for a in OP_ARGS if not a.startswith("--sea-seed")]
        import_map.run(args + ["--offline", "--cache=%s" % OP_CACHE, "--dem=%s" % OP_DEM_FIXTURE, "--out=%s" % out])
        dry = _arrays(out.read_text(encoding="utf-8"))["terrain_rows"]
        wet = _arrays(SAMPLE_OP_MAP.read_text(encoding="utf-8"))["terrain_rows"]
        self.assertLess(dry.count("W"), wet.count("W") - 3, "the default theatre seeds lie off this map")
        self.assertGreater(dry.count("W"), 0, "the lake and the lagoon polygon stay water")

    def test_a_seed_on_land_stops_the_import(self) -> None:
        with self.assertRaises(ValueError):
            self._import("land.tres", extra=("--sea-seed=54.48,22.55",))


class BorderBarrierTest(unittest.TestCase):
    """Supercover of border lines on a 10 x 10 lattice of 1 m (cell (i, j) is the square around point (i, j))."""

    def _cells(self, line: list) -> set:
        barrier = import_map.border_barrier(10, 10, [line], 0.0, 0.0, 1.0)
        return {(k % 10, k // 10) for k in range(100) if barrier[k]}

    def test_a_straight_line_marks_its_column(self) -> None:
        self.assertEqual(self._cells([(4.0, -2.0), (4.0, 12.0)]), {(4, j) for j in range(10)})

    def test_a_diagonal_line_is_a_4_connected_chain(self) -> None:
        cells = self._cells([(0.0, 0.0), (9.0, 9.0)])
        self.assertTrue({(i, i) for i in range(10)} <= cells)
        self.assertTrue({(i + 1, i) for i in range(9)} <= cells or {(i, i + 1) for i in range(9)} <= cells,
                        "a pass through the cell corners marks the cells beside them")  # fmt: skip
        # no 8-connected leak: a fill from the north-west corner never reaches the south-east corner
        barrier = import_map.border_barrier(10, 10, [[(0.0, 9.0), (9.0, 0.0)]], 0.0, 0.0, 1.0)
        owner = import_map.fill_countries(10, 10, barrier, [("PL", 0.0, 0.0)], 0.0, 0.0, 1.0)
        self.assertEqual(owner[9 * 10 + 9], import_map.NO_COUNTRY)
        self.assertEqual(owner[0], 0)

    def test_a_shallow_slanted_line_leaves_no_hole(self) -> None:
        barrier = import_map.border_barrier(10, 10, [[(0.2, 0.1), (9.7, 4.3)]], 0.0, 0.0, 1.0)
        owner = import_map.fill_countries(10, 10, barrier, [("PL", 0.0, 9.0)], 0.0, 0.0, 1.0)
        self.assertEqual(owner[3], import_map.NO_COUNTRY, "south of the line is the far side")

    def test_segments_outside_the_lattice_are_ignored(self) -> None:
        self.assertEqual(self._cells([(-5.0, -5.0), (-5.0, 50.0)]), set())


class BorderPolylinesTest(unittest.TestCase):
    """The real border lines for drawing (TASK-113): clipped, chained, simplified, in world units."""

    def setUp(self) -> None:
        self.layout = import_map.HexLayout(10, 8, 5000.0, 500000.0, 6000000.0)  # 1 unit = 2886.75 m
        self.m = self.layout.metres_per_unit

    def _en(self, x: float, z: float) -> tuple:
        return (self.layout.origin_e + x * self.m, self.layout.origin_n - z * self.m)

    def _lines(self, ways: dict, tolerance: float = 0.1) -> list:
        projected = {k: [self._en(*p) for p in v] for k, v in ways.items()}
        return import_map.border_polylines(self.layout, projected, tolerance)

    def test_world_units_x_east_z_south(self) -> None:
        (line,) = self._lines({1: [(0.0, 0.0), (3.0, 2.0)]})
        self.assertAlmostEqual(line[0][0], 0.0)
        self.assertAlmostEqual(line[0][1], 0.0)
        self.assertAlmostEqual(line[-1][0], 3.0)
        self.assertAlmostEqual(line[-1][1], 2.0)

    def test_ways_meeting_end_to_end_become_one_line_whatever_their_order_or_direction(self) -> None:
        a, b, c = [(0.0, 0.0), (2.0, 1.0)], [(5.0, 3.0), (2.0, 1.0)], [(5.0, 3.0), (6.0, 6.0)]
        for ways in ({1: a, 2: b, 3: c}, {3: c, 2: b, 1: a}, {1: c, 2: a, 3: b}):
            lines = self._lines(ways)
            self.assertEqual(len(lines), 1, ways)
            self.assertEqual([tuple(round(v, 6) for v in p) for p in lines[0]],
                             [(0.0, 0.0), (2.0, 1.0), (5.0, 3.0), (6.0, 6.0)])  # fmt: skip

    def test_a_junction_of_three_ways_is_not_chained(self) -> None:
        lines = self._lines({1: [(0.0, 0.0), (2.0, 2.0)], 2: [(2.0, 2.0), (4.0, 0.0)], 3: [(2.0, 2.0), (2.0, 5.0)]})
        self.assertEqual(len(lines), 3)

    def test_clipped_to_the_map_rectangle(self) -> None:
        min_e, min_n, max_e, max_n = self.layout.bounds()
        x_max = (max_e - self.layout.origin_e) / self.m
        (line,) = self._lines({1: [(-50.0, 2.0), (50.0, 2.0)]})
        self.assertEqual(len(line), 2)
        self.assertLess(line[0][0], 0.0)
        self.assertGreater(line[0][0], -2.0)
        self.assertAlmostEqual(line[-1][0], x_max)
        self.assertEqual(self._lines({1: [(-50.0, -50.0), (-40.0, -40.0)]}), [], "wholly outside: nothing")

    def test_a_line_leaving_and_re_entering_gives_two_lines(self) -> None:
        lines = self._lines({1: [(1.0, 1.0), (1.0, -50.0), (4.0, -50.0), (4.0, 2.0)]})
        self.assertEqual(len(lines), 2)

    def test_simplified_below_a_tenth_of_a_hex_and_kept_above(self) -> None:
        wobble = [(float(i), 0.04 * (i % 2)) for i in range(8)]
        (line,) = self._lines({1: wobble})
        self.assertEqual(len(line), 2, "wobble of 0.04 hex goes")
        bend = [(0.0, 0.0), (3.0, 0.5), (6.0, 0.0)]
        (line,) = self._lines({1: bend})
        self.assertEqual(len(line), 3, "a bend of 0.5 hex stays")

    def test_a_closed_ring_stays_closed(self) -> None:
        ring = [(2.0, 2.0), (5.0, 2.0), (5.0, 5.0), (2.0, 5.0), (2.0, 2.0)]
        (line,) = self._lines({1: ring})
        self.assertEqual(line[0], line[-1])
        self.assertEqual(len(line), 5)

    def test_deterministic_and_sorted_by_first_point(self) -> None:
        ways = {7: [(6.0, 1.0), (7.0, 4.0)], 3: [(1.0, 1.0), (2.0, 5.0)]}
        lines = self._lines(ways)
        self.assertEqual(lines, self._lines(dict(reversed(list(ways.items())))))
        self.assertEqual([round(line[0][0]) for line in lines], [1, 6])

    def test_the_tres_has_border_lines_in_world_units_and_tactical_has_none(self) -> None:
        text = SAMPLE_OP_MAP.read_text(encoding="utf-8")
        self.assertIn("\nborder_lines = Array[PackedVector2Array]([PackedVector2Array(", text)
        self.assertLess(text.index("country_rows ="), text.index("border_lines ="))
        self.assertLess(text.index("border_lines ="), text.index("elevation_m ="))
        self.assertNotIn("border_lines", SAMPLE_MAP.read_text(encoding="utf-8"))


class FillCountriesTest(unittest.TestCase):
    def _fill(self, line: list, seeds: list) -> bytearray:
        barrier = import_map.border_barrier(10, 10, [line], 0.0, 0.0, 1.0)
        return import_map.fill_countries(10, 10, barrier, seeds, 0.0, 0.0, 1.0)

    def test_each_side_gets_its_seed_and_the_border_points_the_majority(self) -> None:
        owner = self._fill([(4.0, -1.0), (4.0, 11.0)], [("PL", 1.0, 5.0), ("LT", 8.0, 5.0)])
        row = list(owner[50:60])
        self.assertEqual(row[:4], [0] * 4)
        self.assertEqual(row[5:], [1] * 5)
        self.assertEqual(row[4], 0, "a border point with 1 west and 1 east neighbour (+ 2 on the line): tie -> first")

    def test_a_border_point_follows_the_majority_of_its_neighbours(self) -> None:
        barrier = bytearray(9)
        barrier[4] = 1  # centre of a 3 x 3 lattice, an island of border
        owner = import_map.fill_countries(3, 3, barrier, [("PL", 0.0, 0.0)], 0.0, 0.0, 1.0)
        self.assertEqual(owner[4], 0, "all 4 neighbours belong to PL")
        owner = import_map.fill_countries(3, 3, bytearray([0, 0, 0, 0, 0, 0, 0, 0, 0]), [("PL", 0.0, 0.0)], 0.0, 0.0, 1.0)
        self.assertEqual(set(owner), {0})
        barrier = bytearray([0, 1, 0, 1, 1, 1, 0, 1, 0])  # four corners cut off by a cross; the centre has no voters
        owner = import_map.fill_countries(3, 3, barrier, [("PL", 0.0, 0.0)], 0.0, 0.0, 1.0)
        self.assertEqual(owner[4], import_map.NO_COUNTRY, "no neighbour owns a country: none")
        barrier = bytearray([0, 0, 0, 1, 1, 1, 0, 0, 0])
        owner = import_map.fill_countries(3, 3, barrier, [("PL", 0.0, 0.0), ("LT", 0.0, 2.0)], 0.0, 0.0, 1.0)
        self.assertEqual(list(owner), [0, 0, 0, 0, 0, 0, 1, 1, 1], "the middle row has 1 vote each way: the first wins")
        owner = import_map.fill_countries(3, 3, barrier, [("LT", 0.0, 2.0), ("PL", 0.0, 0.0)], 0.0, 0.0, 1.0)
        self.assertEqual(list(owner), [1, 1, 1, 0, 0, 0, 0, 0, 0], "ties follow the --countries order")

    def test_a_gap_in_the_border_names_both_countries(self) -> None:
        with self.assertRaises(ValueError) as raised:
            self._fill([(4.0, -1.0), (4.0, 3.0)], [("PL", 1.0, 5.0), ("LT", 8.0, 5.0)])
        self.assertIn("two seeds in one region", str(raised.exception))
        self.assertIn("PL", str(raised.exception))
        self.assertIn("LT", str(raised.exception))

    def test_a_seed_on_the_border_or_off_the_map_is_an_error(self) -> None:
        with self.assertRaises(ValueError):
            self._fill([(4.0, -1.0), (4.0, 11.0)], [("PL", 4.0, 5.0)])
        with self.assertRaises(ValueError):
            self._fill([(4.0, -1.0), (4.0, 11.0)], [("PL", 40.0, 5.0)])

    def test_hex_country_is_the_most_land_points_ties_first(self) -> None:
        self.assertEqual(import_map.hex_country([3, 5, 1]), 1)
        self.assertEqual(import_map.hex_country([4, 4]), 0)
        self.assertEqual(import_map.hex_country([0, 0]), import_map.NO_COUNTRY)
        self.assertEqual(import_map.hex_country([]), import_map.NO_COUNTRY)


class CountriesOptionTest(unittest.TestCase):
    def test_parse(self) -> None:
        self.assertEqual(import_map.parse_countries(["PL:54.1,22.9,LT:54.9,23.9"]), [("PL", 54.1, 22.9), ("LT", 54.9, 23.9)])
        self.assertEqual(import_map.parse_countries(["PL:54.1,22.9", "LT:54.9,23.9"]), [("PL", 54.1, 22.9), ("LT", 54.9, 23.9)])

    def test_bad_input(self) -> None:
        for bad in (["PL:54.1"], ["PL54.1,22.9"], ["pl:54.1,22.9"], ["POL:54.1,22.9"], ["PL:a,b"],
                    ["PL:1,2", "PL:3,4"]):  # fmt: skip
            with self.assertRaises(ValueError, msg=str(bad)):
                import_map.parse_countries(bad)

    def test_the_operational_defaults(self) -> None:
        self.assertEqual([c[0] for c in import_map.OP_COUNTRIES], ["PL", "LT", "BY", "RU"])
        self.assertEqual(import_map.OP_COUNTRIES[3], ("RU", 54.71, 20.51))

    def test_tactical_with_countries_is_refused(self) -> None:
        with self.assertRaises(SystemExit):
            import_map.run(SAMPLE_ARGS + ["--offline", "--countries=PL:54.2,22.9", "--out=/nonexistent/x.tres"])

    def test_tactical_output_has_no_countries(self) -> None:
        self.assertNotIn("countries", SAMPLE_MAP.read_text(encoding="utf-8"))


class BorderTilesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())
        self._download = import_map._download
        self._pause = import_map.RETRY_PAUSE_S
        import_map.RETRY_PAUSE_S = 0.0
        self.calls = []

    def tearDown(self) -> None:
        import_map._download = self._download
        import_map.RETRY_PAUSE_S = self._pause
        shutil.rmtree(self.dir, ignore_errors=True)

    def _fake_download(self) -> None:
        def download(url: str, target: Path, data: bytes = None) -> None:
            self.calls.append((target.name, data))
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('{"version": 0.6, "elements": []}\n', encoding="utf-8")

        import_map._download = download

    def test_the_border_query_asks_for_country_relation_member_ways_only(self) -> None:
        query = import_map.border_query(54.0, 22.5, 54.5, 23.0)
        self.assertIn('rel["boundary"="administrative"]["admin_level"="2"](54.00000,22.50000,54.50000,23.00000)', query)
        self.assertIn("way(r)(54.00000,22.50000,54.50000,23.00000)", query)
        self.assertNotIn("landuse", query)
        self.assertNotIn("natural", query)

    def test_border_tiles_sit_next_to_the_land_cover_tiles_with_their_own_version(self) -> None:
        write_op_cache(self.dir, 0.5)
        self.assertEqual(import_map.border_tile_path(self.dir, 54.5, 22.5, 0.5).name, "bd1_54.5000_22.5000_0.5000.json")
        self.assertTrue(import_map.border_tile_path(self.dir, 54.5, 22.5, 0.5).exists())
        self.assertNotEqual(import_map.border_tile_path(self.dir, 54.5, 22.5, 0.5), import_map.osm_tile_path(self.dir, 54.5, 22.5, 0.5))

    def test_offline_with_a_complete_cache_never_downloads(self) -> None:
        write_op_cache(self.dir, 0.5)
        self._fake_download()
        paths = import_map.border_tile_paths(self.dir, 54.45, 22.40, 54.55, 22.60, True, 0.5)
        self.assertEqual(len(paths), 4)
        self.assertEqual(self.calls, [])

    def test_a_missing_border_tile_fails_offline_naming_the_tile(self) -> None:
        write_op_cache(self.dir, 0.5)
        import_map.border_tile_path(self.dir, 54.5, 22.5, 0.5).unlink()
        with self.assertRaises(SystemExit) as raised:
            import_map.border_tile_paths(self.dir, 54.45, 22.40, 54.55, 22.60, True, 0.5)
        self.assertIn("54.5000 N 22.5000 E", str(raised.exception))
        self.assertIn("border", str(raised.exception))
        self.assertIn("bd1_54.5000_22.5000_0.5000.json", str(raised.exception))

    def test_only_the_missing_border_tiles_are_downloaded_never_land_cover(self) -> None:
        write_op_cache(self.dir, 0.5)
        import_map.border_tile_path(self.dir, 54.0, 22.0, 0.5).unlink()
        land_before = {p.name: p.read_text(encoding="utf-8") for p in (self.dir / "osm").glob("op1_*.json")}
        self._fake_download()
        import_map.osm_tile_paths(self.dir, 54.45, 22.40, 54.55, 22.60, False, 0.5)
        import_map.border_tile_paths(self.dir, 54.45, 22.40, 54.55, 22.60, False, 0.5)
        self.assertEqual([name for name, _ in self.calls], ["bd1_54.0000_22.0000_0.5000.json.check"])
        self.assertIn(b"admin_level", self.calls[0][1])
        land_after = {p.name: p.read_text(encoding="utf-8") for p in (self.dir / "osm").glob("op1_*.json")}
        self.assertEqual(land_before, land_after)

    def test_borders_only_ways_count_whatever_their_tags(self) -> None:
        answer = {"elements": [{"type": "node", "id": 1, "lat": 54.0, "lon": 22.0}, {"type": "node", "id": 2, "lat": 54.1, "lon": 22.1},
                               {"type": "way", "id": 7, "nodes": [1, 2]},
                               {"type": "way", "id": 8, "nodes": [1, 2], "tags": {"highway": "primary"}}]}  # fmt: skip
        self.assertEqual(list(import_map.osm_borders(answer)), [])
        self.assertEqual(sorted(import_map.osm_borders(answer, True)), [7, 8])
        answer["elements"][2]["tags"] = {"boundary": "administrative", "admin_level": "2"}
        self.assertEqual(list(import_map.osm_borders(answer)), [7])


class CountryImportTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())

    def tearDown(self) -> None:
        shutil.rmtree(self.dir, ignore_errors=True)

    def _args(self, osm: Path = None) -> list:
        args = [a for a in OP_ARGS if not a.startswith(("--sea-seed", "--countries"))]
        return args + ["--offline", "--dem=%s" % OP_DEM_FIXTURE, "--out=%s" % (self.dir / "c.tres"),
                       "--osm=%s" % (osm or OP_CACHE)]  # fmt: skip

    def _case(self, case: str, seeds: str = COUNTRY_SEEDS) -> dict:
        import_map.run(self._args(FIXTURES / ("country_%s.json" % case)) + ["--countries=%s" % seeds])
        return _arrays((self.dir / "c.tres").read_text(encoding="utf-8"))

    @staticmethod
    def _rows(arrays: dict, key: str) -> list:
        return [r.strip('"') for r in arrays[key].split(", ")]

    def test_committed_country_fixtures_are_current(self) -> None:
        for case in COUNTRY_CASES:
            text = (FIXTURES / ("country_%s.json" % case)).read_text(encoding="utf-8")
            self.assertEqual(text, json.dumps(fixture_country_osm(case), indent=1, sort_keys=True) + "\n", case)

    def test_a_straight_border_each_side_one_country(self) -> None:
        arrays = self._case("straight")
        self.assertEqual(arrays["countries"], '"PL", "LT"')
        rows = self._rows(arrays, "country_rows")
        self.assertEqual(len(rows), 8)
        for row in rows:
            self.assertTrue(all(len(r) == 10 for r in rows))
            self.assertEqual(row[0], "0", row)
            self.assertEqual(row[-1], "1", row)
            self.assertEqual(row.strip("01"), "", "land everywhere (no sea, no lake): " + row)
            self.assertEqual(row, "0" * row.count("0") + "1" * row.count("1"), "one border crossing per row: " + row)

    def test_a_diagonal_border_does_not_leak(self) -> None:
        rows = self._rows(self._case("diagonal"), "country_rows")
        flat = "".join(rows)
        self.assertGreater(flat.count("0"), 10)
        self.assertGreater(flat.count("1"), 10)
        # PL (seed west, 54.50 N 22.44 E) lies north-west of the line, LT south-east: row 0 is the north row
        self.assertEqual(rows[0][0], "0")
        self.assertEqual(rows[-1][-1], "1")
        for row in rows:
            self.assertEqual(row, "0" * row.count("0") + "1" * row.count("1"), row)

    def test_a_lake_across_the_border_has_no_country_and_the_shores_keep_theirs(self) -> None:
        arrays = self._case("lake")
        terrain = self._rows(arrays, "terrain_rows")
        rows = self._rows(arrays, "country_rows")
        lake = [(r, c) for r in range(8) for c in range(10) if terrain[r][c] == "W"]
        self.assertGreaterEqual(len(lake), 4)
        for r, c in lake:
            self.assertEqual(rows[r][c], ".", "a water hex has no country")
        for r in {r for r, _ in lake}:
            cols = [c for rr, c in lake if rr == r]
            self.assertEqual(rows[r][min(cols) - 1], "0", "west shore")
            self.assertEqual(rows[r][max(cols) + 1], "1", "east shore")
        self.assertEqual(sum(row.count(".") for row in rows), len(lake))

    def test_a_gap_in_the_border_is_an_error(self) -> None:
        with self.assertRaises(ValueError) as raised:
            self._case("gap")
        self.assertIn("two seeds in one region", str(raised.exception))

    def test_a_land_area_closed_off_without_a_seed_is_an_error_listing_hexes(self) -> None:
        with self.assertRaises(ValueError) as raised:
            self._case("ring")
        self.assertIn("no country", str(raised.exception))
        self.assertRegex(str(raised.exception), r"first: \d+,\d+")

    def test_seeds_off_the_map_or_on_the_line_stop_the_import(self) -> None:
        with self.assertRaises(ValueError):
            self._case("straight", "PL:54.50,22.44,LT:54.50,23.90")
        with self.assertRaises(ValueError):
            self._case("straight", "PL:54.50,22.50,LT:54.50,22.56")

    def test_countries_without_any_border_way_is_an_error(self) -> None:
        with self.assertRaises(ValueError):
            import_map.run(self._args(OSM_FIXTURE) + ["--countries=%s" % COUNTRY_SEEDS])

    def test_the_committed_sample_needs_the_border_tiles_for_a_complete_border(self) -> None:
        cache = self.dir / "cache"
        write_op_cache(cache, 0.5)
        args = [a for a in OP_ARGS if not a.startswith("--out")] + ["--offline", "--cache=%s" % cache,
                                                                    "--dem=%s" % OP_DEM_FIXTURE, "--out=%s" % (self.dir / "o.tres")]  # fmt: skip
        import_map.run(args)
        self.assertEqual((self.dir / "o.tres").read_text(encoding="utf-8"), SAMPLE_OP_MAP.read_text(encoding="utf-8"))
        for tile in (cache / "osm").glob("bd1_*.json"):  # only the tagged half of the border (in the land tiles) is left
            tile.write_text('{"version": 0.6, "elements": []}\n', encoding="utf-8")
        with self.assertRaises(ValueError) as raised:
            import_map.run(args)
        self.assertIn("two seeds in one region", str(raised.exception))
        for tile in (cache / "osm").glob("bd1_*.json"):
            tile.unlink()
        with self.assertRaises(SystemExit) as missing:
            import_map.run(args)
        self.assertIn("border tile", str(missing.exception))

    def test_borders_in_both_files_are_merged_without_duplicates(self) -> None:
        cache = self.dir / "cache"
        write_op_cache(cache, 0.5)
        shutil.copy(import_map.border_tile_path(cache, 54.0, 22.5, 0.5), import_map.border_tile_path(cache, 54.0, 22.0, 0.5))
        args = [a for a in OP_ARGS if not a.startswith("--out")] + ["--offline", "--cache=%s" % cache,
                                                                    "--dem=%s" % OP_DEM_FIXTURE, "--out=%s" % (self.dir / "d.tres")]  # fmt: skip
        import_map.run(args)  # way 160 now comes from three files (one land-cover tile, two border tiles)
        self.assertEqual((self.dir / "d.tres").read_text(encoding="utf-8"), SAMPLE_OP_MAP.read_text(encoding="utf-8"))

    def test_the_sample_has_two_countries_and_none_on_water(self) -> None:
        arrays = _arrays(SAMPLE_OP_MAP.read_text(encoding="utf-8"))
        self.assertEqual(arrays["countries"], '"PL", "LT"')
        terrain = "".join(self._rows(arrays, "terrain_rows"))
        countries = "".join(self._rows(arrays, "country_rows"))
        self.assertEqual(len(terrain), len(countries))
        for t, c in zip(terrain, countries):
            self.assertEqual(t == "W", c == ".", "%s %s" % (t, c))
        self.assertIn("0", countries)
        self.assertIn("1", countries)


def read_png_gray(data: bytes) -> tuple:
    """(width, height, pixels) of a non-interlaced grayscale PNG of bit depth 1 (expanded to 0 / 255) or 8."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat, header = 8, b"", None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        kind, body = data[pos + 4 : pos + 8], data[pos + 8 : pos + 8 + length]
        assert struct.unpack(">I", data[pos + 8 + length : pos + 12 + length])[0] == zlib.crc32(kind + body) & 0xFFFFFFFF
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    width, height, depth, color, _, _, interlace = header
    assert color == 0 and interlace == 0 and depth in (1, 8)
    raw = zlib.decompress(idat)
    row_bytes = (width + 7) // 8 if depth == 1 else width
    prior = bytearray(row_bytes)
    pixels = bytearray()
    for r in range(height):
        kind = raw[r * (row_bytes + 1)]
        line = bytearray(raw[r * (row_bytes + 1) + 1 : (r + 1) * (row_bytes + 1)])
        for k in range(row_bytes):
            a = line[k - 1] if k else 0
            b = prior[k]
            c = prior[k - 1] if k else 0
            predictor = (0, a, b, (a + b) >> 1, import_map._paeth(a, b, c))[kind]
            line[k] = (line[k] + predictor) & 0xFF
        if depth == 1:
            pixels.extend(255 if line[c >> 3] & (0x80 >> (c & 7)) else 0 for c in range(width))
        else:
            pixels.extend(line)
        prior = line
    return width, height, bytes(pixels)


def _fields(text: str) -> dict:
    """Plain `key = value` lines of a .tres (the value text as written)."""
    result = {}
    for line in text.splitlines():
        if " = " in line and not line.startswith("["):
            key, value = line.split(" = ", 1)
            result[key] = value
    return result


class TerrainLayers:
    """The graphic layers of an imported .tres (TASK-126), decoded, with lookups by WGS84 point."""

    def __init__(self, text: str) -> None:
        fields = _fields(text)
        self.width = int(fields["layer_width"])
        self.height = int(fields["layer_height"])
        self.pixel_m = float(fields["layer_pixel_m"])
        self.origin_e = float(fields["layer_origin_easting"])
        self.origin_n = float(fields["layer_origin_northing"])
        self.relief_step = int(fields["layer_relief_step"])
        self.size = {"water": (self.width, self.height), "cover": (self.width, self.height),
                     "relief": ((self.width - 1) // self.relief_step + 1, (self.height - 1) // self.relief_step + 1)}  # fmt: skip
        self.png = {}
        self.pixels = {}
        for kind in ("water", "cover", "relief"):
            value = fields["layer_%s_png" % kind]
            self.png[kind] = base64.b64decode(value[value.index('"') + 1 : value.rindex('"')])
            w, h, self.pixels[kind] = read_png_gray(self.png[kind])
            assert (w, h) == self.size[kind], (kind, w, h)
        self.layout = import_map.HexLayout(int(fields["width"]), int(fields["height"]), float(fields["hex_spacing_m"]),
                                           float(fields["origin_easting"]), float(fields["origin_northing"]))  # fmt: skip
        self.terrain = "".join(r.strip('"') for r in _arrays(text)["terrain_rows"].split(", "))

    def pixel(self, lat: float, lon: float, kind: str = "water") -> tuple:
        e, n = import_map.to_utm(lat, lon, 34)
        size = self.pixel_m * (self.relief_step if kind == "relief" else 1)
        return int(round((e - self.origin_e) / size)), int(round((self.origin_n - n) / size))

    def at(self, kind: str, lat: float, lon: float) -> int:
        i, j = self.pixel(lat, lon, kind)
        width, height = self.size[kind]
        assert 0 <= i < width and 0 <= j < height, (lat, lon)
        return self.pixels[kind][j * width + i]

    def hex_terrain(self, lat: float, lon: float) -> str:
        col, row = self.layout.tile_at(*import_map.to_utm(lat, lon, 34))
        return self.terrain[row * self.layout.width + col]


class HillshadeTest(unittest.TestCase):
    def test_flat_ground_is_constant(self) -> None:
        shade = import_map.hillshade([120.0] * 30, 6, 5, 250.0)
        self.assertEqual(set(shade), {import_map.RELIEF_FLAT})
        self.assertEqual(import_map.RELIEF_FLAT, 180)

    def test_a_slope_facing_the_north_west_is_brighter_than_one_facing_the_south_east(self) -> None:
        cols, rows = 7, 7
        # rising towards the south-east = facing the north-west, and the reverse
        facing_nw = [10.0 * (c + r) for r in range(rows) for c in range(cols)]
        facing_se = [-v for v in facing_nw]
        nw = import_map.hillshade(facing_nw, cols, rows, 250.0)[3 * cols + 3]
        se = import_map.hillshade(facing_se, cols, rows, 250.0)[3 * cols + 3]
        self.assertGreater(nw, import_map.RELIEF_FLAT)
        self.assertLess(se, import_map.RELIEF_FLAT)

    def test_exaggeration_strengthens_the_shading(self) -> None:
        heights = [5.0 * c for r in range(3) for c in range(3)]  # rising east: facing west, half lit
        mild = import_map.hillshade(heights, 3, 3, 250.0, z=1.0)[4]
        strong = import_map.hillshade(heights, 3, 3, 250.0, z=8.0)[4]
        self.assertLess(abs(mild - import_map.RELIEF_FLAT), abs(strong - import_map.RELIEF_FLAT))


class DownsampleTest(unittest.TestCase):
    def test_constant_stays_constant_and_size_keeps_both_edges(self) -> None:
        values, cols, rows = import_map.downsample([7.0] * (9 * 5), 9, 5, 2)
        self.assertEqual((cols, rows), (5, 3))
        self.assertEqual(values, [7.0] * 15)

    def test_a_ramp_keeps_its_values_on_the_kept_points(self) -> None:
        ramp = [float(c) for r in range(5) for c in range(9)]
        values, cols, _ = import_map.downsample(ramp, 9, 5, 2)
        self.assertEqual(values[1:4], [2.0, 4.0, 6.0], "tent filter centred on the kept points")

    def test_a_spike_is_spread_not_dropped(self) -> None:
        spike = [0.0] * 25
        spike[1 * 5 + 1] = 16.0  # between kept points (0 and 2)
        values, _, _ = import_map.downsample(spike, 5, 5, 2)
        self.assertGreater(values[0], 0.0)
        self.assertEqual(import_map.downsample(spike, 5, 5, 1)[0], spike)


class PngTest(unittest.TestCase):
    def test_eight_bit_round_trip(self) -> None:
        pixels = bytes((7 * i + (i // 13) * 31) & 0xFF for i in range(13 * 9))
        self.assertEqual(read_png_gray(import_map.png_gray(13, 9, pixels)), (13, 9, pixels))

    def test_one_bit_round_trip_expands_to_white(self) -> None:
        pixels = bytes(1 if (i * 7) % 5 < 2 else 0 for i in range(11 * 4))
        width, height, decoded = read_png_gray(import_map.png_gray(11, 4, pixels, 1))
        self.assertEqual((width, height), (11, 4))
        self.assertEqual(decoded, bytes(255 if p else 0 for p in pixels))

    def test_unfiltered_round_trip(self) -> None:
        pixels = bytes((i * 3) % 7 for i in range(10 * 6))
        self.assertEqual(read_png_gray(import_map.png_gray(10, 6, pixels, 8, False)), (10, 6, pixels))

    def test_the_same_pixels_give_the_same_bytes(self) -> None:
        pixels = bytes(range(256)) * 4
        self.assertEqual(import_map.png_gray(64, 16, pixels), import_map.png_gray(64, 16, bytes(pixels)))


class OperationalLayersTest(unittest.TestCase):
    """Graphic layers of the synthetic operational sample (10 x 8 hexes of 1 km, 250 m pixels; TASK-126)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.text = SAMPLE_OP_MAP.read_text(encoding="utf-8")
        cls.layers = TerrainLayers(cls.text)

    def test_the_layers_cover_the_map_at_250_m(self) -> None:
        layers = self.layers
        self.assertEqual(layers.pixel_m, 250.0)
        min_e, min_n, max_e, max_n = layers.layout.bounds()
        self.assertEqual(layers.width, int((max_e - min_e) // 250.0) + 1)
        self.assertEqual(layers.height, int((max_n - min_n) // 250.0) + 1)
        self.assertAlmostEqual(layers.origin_e, min_e, places=2)
        self.assertAlmostEqual(layers.origin_n, min_n + (layers.height - 1) * 250.0, places=2)
        self.assertEqual(layers.relief_step, 2, "the relief has 500 m pixels")

    def test_two_imports_give_identical_layer_bytes(self) -> None:
        tmp = Path(tempfile.mkdtemp())
        try:
            texts = []
            for name in ("a.tres", "b.tres"):
                import_map.run(OP_ARGS + ["--offline", "--cache=%s" % OP_CACHE, "--dem=%s" % OP_DEM_FIXTURE,
                                          "--out=%s" % (tmp / name)])  # fmt: skip
                texts.append(TerrainLayers((tmp / name).read_text(encoding="utf-8")).png)
            self.assertEqual(texts[0], texts[1])
            self.assertEqual(texts[0], self.layers.png, "re-run tools/test_import_map.py --make-fixtures")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_lake_pixels_are_water(self) -> None:
        self.assertEqual(self.layers.at("water", 54.475, 22.5625), 255)
        self.assertEqual(self.layers.at("cover", 54.475, 22.5625), import_map.COVER_CLASSES.index("W"))

    def test_the_coast_separates_sea_and_land(self) -> None:
        # the coast segment (54.515, 22.47) - (54.495, 22.40); the sea lies to its north-west
        self.assertEqual(self.layers.at("water", 54.5085, 22.4300), 255, "~450 m off the coast")
        self.assertEqual(self.layers.at("water", 54.5020, 22.4400), 0, "~350 m inland")
        self.assertEqual(self.layers.at("water", 54.4900, 22.4500), 0, "inland")

    def test_forest_inside_its_polygon_not_in_the_clearing_or_outside(self) -> None:
        forest = import_map.COVER_CLASSES.index("F")
        self.assertEqual(self.layers.at("cover", 54.4880, 22.5000), forest)
        self.assertNotEqual(self.layers.at("cover", 54.4815, 22.4700), forest, "the clearing (inner ring)")
        self.assertNotEqual(self.layers.at("cover", 54.4950, 22.4500), forest, "north of the forest")

    def test_town_is_urban_and_military_is_not(self) -> None:
        urban = import_map.COVER_CLASSES.index("U")
        self.assertEqual(self.layers.at("cover", 54.5070, 22.5550), urban)
        self.assertNotEqual(self.layers.at("cover", 54.5200, 22.5730), urban, "military areas are not drawn urban")

    def test_wetland_is_marsh(self) -> None:
        self.assertEqual(self.layers.at("cover", 54.4700, 22.5200), import_map.COVER_CLASSES.index("M"))

    def test_the_north_west_flank_of_the_hill_is_brighter_than_the_south_east_flank(self) -> None:
        nw = self.layers.at("relief", 54.5180, 22.4990)
        se = self.layers.at("relief", 54.5120, 22.5110)
        self.assertGreater(nw, import_map.RELIEF_FLAT + 10)
        self.assertLess(se, import_map.RELIEF_FLAT - 10)

    def test_the_sea_is_flat(self) -> None:
        sea = self.layers.at("relief", 54.5300, 22.4300)  # inside the lagoon polygon, DEM slope only
        self.assertLess(abs(sea - import_map.RELIEF_FLAT), 10)

    def test_the_hex_values_do_not_depend_on_the_layers(self) -> None:
        tmp = Path(tempfile.mkdtemp())
        try:
            layout = self.layers.layout
            settings = import_map.Settings(import_map.OPERATIONAL, sea_seeds=[tuple(map(float, OP_SEED.split(",")))],
                                           countries=import_map.parse_countries([OP_COUNTRIES]))  # fmt: skip
            tiles = sorted((OP_CACHE / "osm").glob("op1_*.json"))
            borders = sorted((OP_CACHE / "osm").glob("bd1_*.json"))
            dem = import_map.Dem([OP_DEM_FIXTURE])
            with_layers = import_map.build_map(layout, 34, dem, tiles, settings, borders)
            settings.layers = False
            without = import_map.build_map(layout, 34, dem, tiles, settings, borders)
            self.assertIsNone(without["layers"])
            self.assertIsNotNone(with_layers["layers"])
            self.assertEqual(with_layers["tiles"], without["tiles"])
            bbox = (0.0, 0.0, 0.0, 0.0)
            import_map.write_tres(tmp / "w.tres", "m", "m", layout, 34, with_layers, bbox)
            import_map.write_tres(tmp / "o.tres", "m", "m", layout, 34, without, bbox)
            layered = (tmp / "w.tres").read_text(encoding="utf-8").splitlines()
            plain = (tmp / "o.tres").read_text(encoding="utf-8").splitlines()
            self.assertEqual([line for line in layered if not line.startswith("layer_")], plain)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_a_pond_smaller_than_its_hex_stays_water(self) -> None:
        layout = self.layers.layout
        pond = {"elements": [{"type": "node", "id": k + 1, "lat": lat, "lon": lon} for k, (lat, lon) in enumerate(
            [(54.4800, 22.4800), (54.4800, 22.4924), (54.4841, 22.4924), (54.4841, 22.4800)])]
            + [{"type": "way", "id": 1, "nodes": [1, 2, 3, 4, 1], "tags": {"natural": "water"}}]}  # fmt: skip
        result = import_map.build_map(layout, 34, import_map.Dem([OP_DEM_FIXTURE]), pond,
                                      import_map.Settings(import_map.OPERATIONAL))  # fmt: skip
        self.assertNotIn("water", {t["terrain"] for t in result["tiles"].values()}, "800 x 450 m: no hex is water")
        layers = result["layers"]
        water = [k for k, v in enumerate(layers["water"]) if v]
        columns = {k % layers["width"] for k in water}
        rows = {k // layers["width"] for k in water}
        self.assertGreaterEqual(len(columns), 3, "at least 3 px wide")
        self.assertGreaterEqual(len(rows), 1)

    def test_tactical_maps_have_no_layers(self) -> None:
        self.assertNotIn("layer_", SAMPLE_MAP.read_text(encoding="utf-8"))


if __name__ == "__main__":
    if "--make-fixtures" in sys.argv:
        make_fixtures()
    else:
        unittest.main()
