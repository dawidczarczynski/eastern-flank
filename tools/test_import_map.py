"""Tests for tools/import_map.py. Run: python3 -m unittest discover -s tools -p 'test_import_map.py'

The fixtures in tools/import_map_fixtures/ are SYNTHETIC (a made-up hill, lake, forest and village near Szurpily),
written by `python3 tools/test_import_map.py --make-fixtures`; the importer turns them into the committed sample
map tests/fixtures/maps/sample_map.tres that the GDScript tests load. After an intended importer change, re-run
`--make-fixtures` and commit both.
"""
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
    """Synthetic Overpass answer: lake, forest multipolygon with a clearing, village, fields, wetland, a road."""
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
    return {"version": 0.6, "generator": "synthetic fixture (tools/test_import_map.py)", "elements": elements}


def make_fixtures() -> None:
    FIXTURES.mkdir(parents=True, exist_ok=True)
    rows = [[synthetic_height(DEM_LAT0 - j * DEM_DLAT, DEM_LON0 + i * DEM_DLON) for i in range(DEM_COLS)] for j in range(DEM_ROWS)]
    write_geotiff(DEM_FIXTURE, rows, DEM_LAT0, DEM_LON0, DEM_DLAT, DEM_DLON)
    OSM_FIXTURE.write_text(json.dumps(fixture_osm(), indent=1, sort_keys=True) + "\n", encoding="utf-8")
    import_map.run(SAMPLE_ARGS + ["--offline", "--dem=%s" % DEM_FIXTURE, "--osm=%s" % OSM_FIXTURE, "--out=%s" % SAMPLE_MAP])


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
        for t in "PFHW":
            self.assertIn(t, flat, "the sample has every terrain type")
        self.assertEqual(terrain[4][0], "W", "the lake in the south-west")
        self.assertEqual(terrain[0][0], "F", "the forest in the north-west")
        self.assertIn("U", "".join(cover), "the village")
        self.assertIn("A", "".join(cover), "the fields")
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


if __name__ == "__main__":
    if "--make-fixtures" in sys.argv:
        make_fixtures()
    else:
        unittest.main()
