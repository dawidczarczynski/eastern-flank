#!/usr/bin/env python3
"""Tactical hex map from real geography (TASK-087, ADR 0018). Python 3.8, stdlib only.

Usage:
  tools/import_map.py [<min_lon,min_lat,max_lon,max_lat>] [--center=<lat,lon>] [--size=30x24] [--hex=250]
                      --name=<id> --out=data/maps/<id>.tres [--display-name=<text>]
                      [--cache=~/.cache/eastern-flank/maps] [--offline] [--dem=<file.tif> ...] [--osm=<file.json>]

The map is a rectangle of `--size` columns x rows of pointy-top hexes (offset layout, odd rows shifted east, like
MapGenerator) whose neighbouring centres are `--hex` metres apart, centred on `--center` (or the bbox centre; without
`--size` the bbox extent decides it). It lies in the UTM zone of its centre (34N for the Suwalki Gap).

Inputs (downloaded once into the cache, outside git; the game never goes online):
- Elevation: Copernicus GLO-30 DEM tiles, the original Cloud Optimized GeoTIFFs from the public AWS bucket, kept
  as `<cache>/dem/Copernicus_DSM_COG_10_N<lat>_00_E<lon>_00_DEM.tif` (any GeoTIFF in geographic WGS84 degrees with
  float32 / int16 samples, uncompressed or deflate, predictor 1-3, works when passed with `--dem`).
- Land cover: the raw OpenStreetMap answer of the Overpass API to `overpass_query(bbox)` (JSON, `out body` with
  all nodes), kept as `<cache>/osm/osm_<s>_<w>_<n>_<e>.json` (bbox of the map plus `OSM_MARGIN_M`).
Missing cache files are downloaded unless `--offline`; `--dem` / `--osm` read the given files instead of the
cache (tests use the committed fixtures in tools/import_map_fixtures/).

Method (ADR 0018): a lattice of sample points every `SAMPLE_M` metres covers the map; each point gets the DEM
height (bilinear) and an OSM cover class (polygons rasterised by scanline, higher `COVER_CLASSES` priority wins).
Per hex: the dominant group of its points (water / forest / open, ties prefer open, then forest) gives the terrain
type; an open hex whose relief (90th - 10th percentile of its heights) reaches `--hills-relief` metres is HILLS.
The hex elevation is the mean DEM height of its open points (a DSM: forest canopy and buildings are skipped when
at least a quarter of the hex is open; a hex that is mostly forest takes the mean minus `--canopy`). Game
elevation: land = land_min + (metres - lowest land hex) x vertical scale (`--exaggeration` x true scale, reduced
so the highest hex stays at `TOP_ELEVATION`), water = `WATER_ELEVATION` (the game has one water plane at 0).

Output: a Godot text resource of class ImportedMap (src/core/data/imported_map.gd). The same inputs give a
byte-identical file: elements are processed in sorted order and every number is written with fixed decimals.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys
import urllib.parse
import urllib.request
import zlib
from itertools import accumulate
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

DEFAULT_CACHE = Path(os.path.expanduser("~/.cache/eastern-flank/maps"))
DEM_URL = "https://copernicus-dem-30m.s3.amazonaws.com/{name}/{name}.tif"
OVERPASS_URL = "https://overpass-api.de/api/interpreter"
USER_AGENT = "eastern-flank-map-import/1 (offline game map builder; one-off download)"
SQRT3 = math.sqrt(3.0)
SAMPLE_M = 25.0  # lattice step of the sample points (the DEM has ~30 m pixels)
OSM_MARGIN_M = 500.0  # land cover fetched around the map, so polygons crossing the edge are complete
# Game elevation bands (data/map/terrain_generation.tres): land starts at land_min, the camera ray starts at 3.0.
LAND_MIN = 0.12
TOP_ELEVATION = 2.2
WATER_ELEVATION = -0.4
SOURCES = (
    "Elevation: Copernicus GLO-30 DEM, produced using Copernicus WorldDEM-30 (c) DLR e.V. 2010-2014 and "
    "(c) Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; "
    "all rights reserved. Land cover: (c) OpenStreetMap contributors, ODbL 1.0 (openstreetmap.org/copyright). "
    "See data/maps/CREDITS."
)

# Cover classes in priority order (a later class wins where polygons overlap) and their map characters.
# Terrain today: W -> WATER, F -> FOREST, the rest is open (PLAINS, or HILLS by relief). TASK-108 can give
# fields (A), urban (U) and marsh (M) their own rules from the `cover_rows` the map stores.
COVER_CLASSES = ".GAUFMW"  # . unmapped, G grass/meadow/scrub, A fields, U urban, F forest, M marsh, W water
OPEN, FOREST, WATER = "open", "forest", "water"
TERRAIN_CHARS = {"plains": "P", "forest": "F", "hills": "H", "water": "W"}

_TAG_CLASSES: List[Tuple[str, Dict[str, str]]] = [
    # (tag key, {value: class}); "*" matches any value. First match in this order wins for one element.
    ("natural", {"water": "W", "bay": "W", "wetland": "M", "wood": "F", "grassland": "G", "heath": "G", "scrub": "G"}),
    ("waterway", {"riverbank": "W", "dock": "W"}),
    ("water", {"*": "W"}),
    ("landuse", {
        "reservoir": "W", "basin": "W", "forest": "F",
        "residential": "U", "commercial": "U", "industrial": "U", "retail": "U", "farmyard": "U",
        "garages": "U", "construction": "U", "railway": "U", "military": "U",
        "farmland": "A", "orchard": "A", "vineyard": "A", "allotments": "A", "plant_nursery": "A",
        "greenhouse_horticulture": "A",
        "meadow": "G", "grass": "G", "village_green": "G", "recreation_ground": "G", "cemetery": "G",
        "brownfield": "G", "greenfield": "G", "quarry": "G", "landfill": "G",
    }),
]  # fmt: skip


# ---------------------------------------------------------------------------------------------------------------
# Projection: WGS84 <-> UTM (transverse Mercator, Krueger series to n^3; millimetre accuracy within a zone).

_A = 6378137.0
_F = 1.0 / 298.257223563
_N = _F / (2.0 - _F)
_RECT = _A / (1.0 + _N) * (1.0 + _N**2 / 4.0 + _N**4 / 64.0)
_ALPHA = (_N / 2 - 2 * _N**2 / 3 + 5 * _N**3 / 16, 13 * _N**2 / 48 - 3 * _N**3 / 5, 61 * _N**3 / 240)
_BETA = (_N / 2 - 2 * _N**2 / 3 + 37 * _N**3 / 96, _N**2 / 48 + _N**3 / 15, 17 * _N**3 / 480)
_DELTA = (2 * _N - 2 * _N**2 / 3 - 2 * _N**3, 7 * _N**2 / 3 - 8 * _N**3 / 5, 56 * _N**3 / 15)
_K0 = 0.9996
_E0 = 500000.0
_C = 2.0 * math.sqrt(_N) / (1.0 + _N)


def utm_zone(lon: float) -> int:
    return int(math.floor((lon + 180.0) / 6.0)) + 1


def _central_meridian(zone: int) -> float:
    return math.radians(zone * 6.0 - 183.0)


def to_utm(lat: float, lon: float, zone: int) -> Tuple[float, float]:
    """(easting, northing) in metres of a WGS84 point in UTM zone `zone`, northern hemisphere."""
    phi = math.radians(lat)
    dlam = math.radians(lon) - _central_meridian(zone)
    t = math.sinh(math.atanh(math.sin(phi)) - _C * math.atanh(_C * math.sin(phi)))
    xi_p = math.atan2(t, math.cos(dlam))
    eta_p = math.atanh(math.sin(dlam) / math.sqrt(1.0 + t * t))
    xi = xi_p
    eta = eta_p
    for j, a in enumerate(_ALPHA, 1):
        xi += a * math.sin(2 * j * xi_p) * math.cosh(2 * j * eta_p)
        eta += a * math.cos(2 * j * xi_p) * math.sinh(2 * j * eta_p)
    return _E0 + _K0 * _RECT * eta, _K0 * _RECT * xi


def from_utm(easting: float, northing: float, zone: int) -> Tuple[float, float]:
    """(lat, lon) in degrees of a UTM point (inverse of `to_utm`)."""
    xi = northing / (_K0 * _RECT)
    eta = (easting - _E0) / (_K0 * _RECT)
    xi_p = xi
    eta_p = eta
    for j, b in enumerate(_BETA, 1):
        xi_p -= b * math.sin(2 * j * xi) * math.cosh(2 * j * eta)
        eta_p -= b * math.cos(2 * j * xi) * math.sinh(2 * j * eta)
    chi = math.asin(math.sin(xi_p) / math.cosh(eta_p))
    phi = chi
    for j, d in enumerate(_DELTA, 1):
        phi += d * math.sin(2 * j * chi)
    lam = _central_meridian(zone) + math.atan2(math.sinh(eta_p), math.cos(xi_p))
    return math.degrees(phi), math.degrees(lam)


# ---------------------------------------------------------------------------------------------------------------
# GeoTIFF reader (the subset DEMs use): tiles or strips, no compression or deflate, predictor 1/2/3.

_TIFF_TYPES = {1: "B", 2: "s", 3: "H", 4: "I", 6: "b", 8: "h", 9: "i", 11: "f", 12: "d", 16: "Q"}


class GeoTiff:
    """One-band GeoTIFF in geographic degrees; decodes only the blocks that are sampled."""

    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        self._data = self.path.read_bytes()
        head = self._data[:2]
        if head not in (b"II", b"MM"):
            raise ValueError("%s: not a TIFF" % path)
        self._bo = "<" if head == b"II" else ">"
        (magic, ifd) = struct.unpack(self._bo + "HI", self._data[2:8])
        if magic != 42:
            raise ValueError("%s: BigTIFF / unknown TIFF variant" % path)
        tags = self._read_ifd(ifd)
        self.width = tags[256][0]
        self.height = tags[257][0]
        bits = tags.get(258, (1,))[0]
        fmt = tags.get(339, (1,))[0]
        self._compression = tags.get(259, (1,))[0]
        self._predictor = tags.get(317, (1,))[0]
        if tags.get(277, (1,))[0] != 1:
            raise ValueError("%s: only one-band rasters are supported" % path)
        if (fmt, bits) == (3, 32):
            self._sample = "f"
        elif (fmt, bits) in ((1, 16), (2, 16)):
            self._sample = "H" if fmt == 1 else "h"
        else:
            raise ValueError("%s: unsupported sample format %s/%s bits" % (path, fmt, bits))
        if self._compression not in (1, 8, 32946):
            raise ValueError("%s: unsupported compression %s" % (path, self._compression))
        if 322 in tags:
            self._block_w, self._block_h = tags[322][0], tags[323][0]
            self._offsets, self._counts = tags[324], tags[325]
        else:
            self._block_w, self._block_h = self.width, tags.get(278, (self.height,))[0]
            self._offsets, self._counts = tags[273], tags[279]
        self._blocks_across = -(-self.width // self._block_w)
        scale = tags[33550]
        tie = tags[33922]
        keys = tags.get(34735, ())
        pixel_is_point = any(keys[i] == 1025 and keys[i + 3] == 2 for i in range(4, len(keys), 4))
        half = 0.0 if pixel_is_point else 0.5
        self.dx, self.dy = scale[0], scale[1]
        # Degrees of the centre of pixel (0, 0).
        self.lon0 = tie[3] + (half - tie[0]) * self.dx
        self.lat0 = tie[4] - (half - tie[1]) * self.dy
        self._cache: Dict[int, List[float]] = {}

    def _read_ifd(self, offset: int) -> Dict[int, tuple]:
        bo = self._bo
        count = struct.unpack(bo + "H", self._data[offset : offset + 2])[0]
        tags: Dict[int, tuple] = {}
        for i in range(count):
            entry = self._data[offset + 2 + i * 12 : offset + 14 + i * 12]
            tag, typ, n = struct.unpack(bo + "HHI", entry[:8])
            code = _TIFF_TYPES.get(typ)
            if code is None:
                continue
            size = struct.calcsize(code) * n
            raw = entry[8 : 8 + size] if size <= 4 else self._data[struct.unpack(bo + "I", entry[8:12])[0] :][:size]
            tags[tag] = (raw,) if code == "s" else struct.unpack(bo + code * n, raw)
        return tags

    def _block(self, index: int) -> List[float]:
        if index in self._cache:
            return self._cache[index]
        raw = self._data[self._offsets[index] : self._offsets[index] + self._counts[index]]
        if self._compression != 1:
            raw = zlib.decompress(raw)
        size = struct.calcsize(self._sample)
        w = self._block_w
        rows = len(raw) // (w * size)
        if self._predictor == 3:  # floating point: per row, byte-wise differences of byte planes (MSB first)
            out = bytearray(rows * w * size)
            stride = w * size
            for r in range(rows):
                row = bytes(v & 0xFF for v in accumulate(raw[r * stride : (r + 1) * stride]))
                for p in range(size):
                    out[r * stride + p : (r + 1) * stride : size] = row[p * w : (p + 1) * w]
            values = list(struct.unpack(">%d%s" % (rows * w, self._sample), bytes(out)))
        else:
            values = list(struct.unpack("%s%d%s" % (self._bo, rows * w, self._sample), raw[: rows * w * size]))
            if self._predictor == 2:  # horizontal integer differences
                for r in range(rows):
                    for i in range(1, w):
                        values[r * w + i] += values[r * w + i - 1]
        self._cache[index] = values
        return values

    def pixel(self, i: int, j: int) -> float:
        i = min(max(i, 0), self.width - 1)
        j = min(max(j, 0), self.height - 1)
        bw, bh = self._block_w, self._block_h
        block = self._block((j // bh) * self._blocks_across + i // bw)
        return float(block[(j % bh) * bw + i % bw])

    def contains(self, lat: float, lon: float) -> bool:
        fi = (lon - self.lon0) / self.dx
        fj = (self.lat0 - lat) / self.dy
        return -0.5 <= fi <= self.width - 0.5 and -0.5 <= fj <= self.height - 0.5

    def sample(self, lat: float, lon: float) -> float:
        """Bilinear height between the four nearest pixel centres."""
        fi = (lon - self.lon0) / self.dx
        fj = (self.lat0 - lat) / self.dy
        i = int(math.floor(fi))
        j = int(math.floor(fj))
        u = fi - i
        v = fj - j
        top = self.pixel(i, j) * (1 - u) + self.pixel(i + 1, j) * u
        bottom = self.pixel(i, j + 1) * (1 - u) + self.pixel(i + 1, j + 1) * u
        return top * (1 - v) + bottom * v


class Dem:
    """Several DEM tiles; a point is read from the first tile (sorted by path) that contains it."""

    def __init__(self, paths: Sequence[Path]) -> None:
        self.tiles = [GeoTiff(p) for p in sorted(paths, key=lambda p: Path(p).name)]

    def sample(self, lat: float, lon: float) -> float:
        for tile in self.tiles:
            if tile.contains(lat, lon):
                return tile.sample(lat, lon)
        raise ValueError("no DEM tile covers %.5f, %.5f" % (lat, lon))


def copernicus_tile_name(lat: int, lon: int) -> str:
    ns = "N" if lat >= 0 else "S"
    ew = "E" if lon >= 0 else "W"
    return "Copernicus_DSM_COG_10_%s%02d_00_%s%03d_00_DEM" % (ns, abs(lat), ew, abs(lon))


# ---------------------------------------------------------------------------------------------------------------
# OpenStreetMap land cover.


def overpass_query(south: float, west: float, north: float, east: float) -> str:
    bbox = "%.5f,%.5f,%.5f,%.5f" % (south, west, north, east)
    return "\n".join([
        "[out:json][timeout:180];",
        "(",
        '  wr["natural"~"^(water|bay|wetland|wood|grassland|heath|scrub)$"](%s);' % bbox,
        '  wr["landuse"](%s);' % bbox,
        '  wr["water"](%s);' % bbox,
        '  wr["waterway"](%s);' % bbox,
        '  way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|track)$"](%s);' % bbox,
        ");",
        "(._;>;);",
        "out body;",
    ])  # fmt: skip


def cover_class(tags: Dict[str, str]) -> Optional[str]:
    """Cover class character of an OSM area's tags, or None when the area does not set the cover."""
    for key, values in _TAG_CLASSES:
        value = tags.get(key)
        if value is None:
            continue
        if value in values:
            return values[value]
        if "*" in values:
            return values["*"]
    return None


def _assemble_rings(ways: List[List[int]]) -> List[List[int]]:
    """Closed node rings from way node lists, joined end to end in list order; open leftovers are dropped."""
    unused = [w for w in ways if len(w) >= 2]
    rings = []
    while unused:
        ring = list(unused.pop(0))
        while ring[0] != ring[-1]:
            for k, way in enumerate(unused):
                if way[0] == ring[-1]:
                    ring.extend(way[1:])
                elif way[-1] == ring[-1]:
                    ring.extend(reversed(way[:-1]))
                else:
                    continue
                unused.pop(k)
                break
            else:
                break
        if ring[0] == ring[-1] and len(ring) >= 4:
            rings.append(ring)
    return rings


def osm_areas(osm: dict) -> List[Tuple[str, List[List[Tuple[float, float]]]]]:
    """(cover class, rings of (lat, lon)) of every land-cover area, sorted by priority, then element type and id.
    Closed ways are areas; multipolygon relations assemble all member ways into rings (filled even-odd)."""
    nodes: Dict[int, Tuple[float, float]] = {}
    ways: Dict[int, dict] = {}
    relations = []
    for el in osm.get("elements", []):
        if el.get("type") == "node":
            nodes[el["id"]] = (el["lat"], el["lon"])
        elif el.get("type") == "way":
            ways[el["id"]] = el
        elif el.get("type") == "relation":
            relations.append(el)
    areas = []

    def rings_of(node_rings: List[List[int]]) -> List[List[Tuple[float, float]]]:
        return [[nodes[n] for n in ring] for ring in node_rings if all(n in nodes for n in ring)]

    for way_id in sorted(ways):
        way = ways[way_id]
        cls = cover_class(way.get("tags", {}))
        refs = way.get("nodes", [])
        if cls and len(refs) >= 4 and refs[0] == refs[-1]:
            rings = rings_of([refs])
            if rings:
                areas.append((COVER_CLASSES.index(cls), 0, way_id, cls, rings))
    for rel in sorted(relations, key=lambda r: r["id"]):
        tags = rel.get("tags", {})
        cls = cover_class(tags)
        if not cls or tags.get("type") not in ("multipolygon", "boundary"):
            continue
        members = [ways[m["ref"]]["nodes"] for m in rel.get("members", []) if m.get("type") == "way" and m.get("ref") in ways]
        rings = rings_of(_assemble_rings(members))
        if rings:
            areas.append((COVER_CLASSES.index(cls), 1, rel["id"], cls, rings))
    areas.sort(key=lambda a: a[:3])
    return [(a[3], a[4]) for a in areas]


# ---------------------------------------------------------------------------------------------------------------
# Hex grid in projected metres.


class HexLayout:
    """Pointy-top hexes, offset layout (odd rows shifted east), `spacing` metres between neighbouring centres.
    Game world units (TerrainField.HEX_SIZE = 1, centre to corner) are `metres_per_unit` = spacing / sqrt(3);
    world x grows east, world z grows south: E = origin_e + x * m, N = origin_n - z * m."""

    def __init__(self, width: int, height: int, spacing: float, origin_e: float, origin_n: float) -> None:
        self.width = width
        self.height = height
        self.spacing = spacing
        self.metres_per_unit = spacing / SQRT3
        self.origin_e = origin_e
        self.origin_n = origin_n

    @staticmethod
    def centred(width: int, height: int, spacing: float, centre_e: float, centre_n: float) -> "HexLayout":
        m = spacing / SQRT3
        cx = SQRT3 * (width - 1) / 2.0 + (SQRT3 / 4.0 if height > 1 else 0.0)
        cz = 1.5 * (height - 1) / 2.0
        return HexLayout(width, height, spacing, round(centre_e - cx * m), round(centre_n + cz * m))

    @staticmethod
    def axial(col: int, row: int) -> Tuple[int, int]:
        return col - (row // 2), row

    def centre(self, col: int, row: int) -> Tuple[float, float]:
        q, r = self.axial(col, row)
        x = SQRT3 * (q + r / 2.0)
        z = 1.5 * r
        return self.origin_e + x * self.metres_per_unit, self.origin_n - z * self.metres_per_unit

    def tile_at(self, e: float, n: float) -> Optional[Tuple[int, int]]:
        """(col, row) of the hex containing the point, None off the map (Hex.from_world rounding)."""
        x = (e - self.origin_e) / self.metres_per_unit
        z = (self.origin_n - n) / self.metres_per_unit
        qf = SQRT3 / 3.0 * x - z / 3.0
        rf = 2.0 / 3.0 * z
        sf = -qf - rf
        q, r, s = round(qf), round(rf), round(sf)
        dq, dr, ds = abs(q - qf), abs(r - rf), abs(s - sf)
        if dq > dr and dq > ds:
            q = -r - s
        elif dr > ds:
            r = -q - s
        col = q + (r // 2)
        if 0 <= col < self.width and 0 <= r < self.height:
            return col, r
        return None

    def bounds(self, margin: float = 0.0) -> Tuple[float, float, float, float]:
        """(min_e, min_n, max_e, max_n) of the map's hexes plus `margin` metres."""
        m = self.metres_per_unit
        half_w = SQRT3 / 2.0 * m
        xs = [self.centre(c, r)[0] for r in range(min(2, self.height)) for c in (0, self.width - 1)]
        return (min(xs) - half_w - margin, self.origin_n - 1.5 * (self.height - 1) * m - m - margin,
                max(xs) + half_w + margin, self.origin_n + m + margin)  # fmt: skip


def _scanline_fill(grid: List[bytearray], value: int, rings: List[List[Tuple[float, float]]],
                   min_e: float, min_n: float, step: float) -> None:  # fmt: skip
    """Sets `value` on lattice points (row j at N = min_n + j*step, column i at E = min_e + i*step) inside the
    rings (even-odd)."""
    rows = len(grid)
    cols = len(grid[0]) if rows else 0
    edges = []
    lo, hi = float("inf"), float("-inf")
    for ring in rings:
        for k in range(len(ring) - 1):
            (e1, n1), (e2, n2) = ring[k], ring[k + 1]
            if n1 != n2:
                edges.append((e1, n1, e2, n2))
                lo, hi = min(lo, n1, n2), max(hi, n1, n2)
    if not edges:
        return
    j0 = max(0, int(math.ceil((lo - min_n) / step)))
    j1 = min(rows - 1, int(math.floor((hi - min_n) / step)))
    for j in range(j0, j1 + 1):
        n = min_n + j * step
        xs = []
        for e1, n1, e2, n2 in edges:
            if (n1 <= n < n2) or (n2 <= n < n1):
                xs.append(e1 + (n - n1) * (e2 - e1) / (n2 - n1))
        xs.sort()
        row = grid[j]
        for k in range(0, len(xs) - 1, 2):
            i0 = max(0, int(math.ceil((xs[k] - min_e) / step)))
            i1 = min(cols - 1, int(math.floor((xs[k + 1] - min_e) / step)))
            for i in range(i0, i1 + 1):
                row[i] = value


def _percentile(sorted_values: List[float], p: float) -> float:
    k = (len(sorted_values) - 1) * p
    f = int(math.floor(k))
    c = min(f + 1, len(sorted_values) - 1)
    return sorted_values[f] + (sorted_values[c] - sorted_values[f]) * (k - f)


def build_map(layout: HexLayout, zone: int, dem: Dem, osm: dict, hills_relief: float = 15.0,
              canopy: float = 15.0, exaggeration: float = 1.5) -> dict:  # fmt: skip
    """Per-hex terrain, cover and elevation of the layout (see the module docstring)."""
    min_e, min_n, max_e, max_n = layout.bounds()
    cols = int(math.floor((max_e - min_e) / SAMPLE_M)) + 1
    rows = int(math.floor((max_n - min_n) / SAMPLE_M)) + 1
    cover = [bytearray(cols) for _ in range(rows)]
    for cls, rings in osm_areas(osm):
        projected = [[to_utm(lat, lon, zone) for lat, lon in ring] for ring in rings]
        _scanline_fill(cover, COVER_CLASSES.index(cls), projected, min_e, min_n, SAMPLE_M)
    samples: Dict[Tuple[int, int], List[Tuple[float, int]]] = {}
    for j in range(rows):
        n = min_n + j * SAMPLE_M
        for i in range(cols):
            e = min_e + i * SAMPLE_M
            tile = layout.tile_at(e, n)
            if tile is None:
                continue
            lat, lon = from_utm(e, n, zone)
            samples.setdefault(tile, []).append((dem.sample(lat, lon), cover[j][i]))
    forest_i, water_i = COVER_CLASSES.index("F"), COVER_CLASSES.index("W")
    tiles = {}
    for row in range(layout.height):
        for col in range(layout.width):
            points = samples.get((col, row), [])
            if not points:
                raise ValueError("hex %d,%d has no sample points (hex smaller than SAMPLE_M?)" % (col, row))
            counts = [0] * len(COVER_CLASSES)
            for _, c in points:
                counts[c] += 1
            groups = {WATER: counts[water_i], FOREST: counts[forest_i]}
            groups[OPEN] = len(points) - groups[WATER] - groups[FOREST]
            group = max((OPEN, FOREST, WATER), key=lambda g: groups[g])  # max keeps the first on ties
            if group == WATER:
                cover_char = "W"
            elif group == FOREST:
                cover_char = "F"
            else:
                open_classes = [k for k in range(len(COVER_CLASSES)) if k not in (forest_i, water_i)]
                cover_char = COVER_CLASSES[max(reversed(open_classes), key=lambda k: counts[k])]
            open_heights = sorted(h for h, c in points if COVER_CLASSES[c] not in "FUW")
            all_heights = sorted(h for h, _ in points)
            if len(open_heights) >= len(points) / 4.0:
                mean = sum(open_heights) / len(open_heights)
                relief = _percentile(open_heights, 0.9) - _percentile(open_heights, 0.1)
            else:
                mean = sum(all_heights) / len(all_heights) - (canopy if group == FOREST else 0.0)
                relief = _percentile(all_heights, 0.9) - _percentile(all_heights, 0.1)
            if group == WATER:
                terrain = "water"
            elif group == FOREST:
                terrain = "forest"
            else:
                terrain = "hills" if relief >= hills_relief else "plains"
            tiles[(col, row)] = {"terrain": terrain, "cover": cover_char, "metres": round(mean, 1),
                                 "relief": round(relief, 1)}  # fmt: skip
    land = [t["metres"] for t in tiles.values() if t["terrain"] != "water"]
    low = min(land) if land else 0.0
    high = max(land) if land else 0.0
    scale = exaggeration / layout.metres_per_unit
    if high > low:
        scale = min(scale, (TOP_ELEVATION - LAND_MIN) / (high - low))
    for t in tiles.values():
        if t["terrain"] == "water":
            t["elevation"] = WATER_ELEVATION
        else:
            t["elevation"] = LAND_MIN + (t["metres"] - low) * scale
    return {"tiles": tiles, "reference_m": low, "vertical_scale": scale}


# ---------------------------------------------------------------------------------------------------------------
# Output.


def _f(value: float, decimals: int) -> str:
    text = "%.*f" % (decimals, value)
    return "0." + "0" * decimals if text.startswith("-") and float(text) == 0.0 else text


def _string(text: str) -> str:
    return '"%s"' % text.replace("\\", "\\\\").replace('"', '\\"')


def write_tres(path: Path, name: str, display_name: str, layout: HexLayout, zone: int, result: dict,
               bbox: Tuple[float, float, float, float]) -> None:  # fmt: skip
    tiles = result["tiles"]
    terrain_rows, cover_rows, metres, elevation = [], [], [], []
    for row in range(layout.height):
        terrain_rows.append("".join(TERRAIN_CHARS[tiles[(c, row)]["terrain"]] for c in range(layout.width)))
        cover_rows.append("".join(tiles[(c, row)]["cover"] for c in range(layout.width)))
        metres.append(", ".join(_f(tiles[(c, row)]["metres"], 1) for c in range(layout.width)))
        elevation.append(", ".join(_f(tiles[(c, row)]["elevation"], 3) for c in range(layout.width)))
    lines = [
        '[gd_resource type="Resource" script_class="ImportedMap" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="res://src/core/data/imported_map.gd" id="1_map"]',
        "",
        "[resource]",
        'script = ExtResource("1_map")',
        "id = &%s" % _string(name),
        "display_name = %s" % _string(display_name),
        "width = %d" % layout.width,
        "height = %d" % layout.height,
        "hex_spacing_m = %s" % _f(layout.spacing, 1),
        "crs = %s" % _string("EPSG:%d" % (32600 + zone)),
        "origin_easting = %s" % _f(layout.origin_e, 1),
        "origin_northing = %s" % _f(layout.origin_n, 1),
        "bbox_wgs84 = PackedFloat64Array(%s)" % ", ".join(_f(v, 5) for v in bbox),
        "reference_m = %s" % _f(result["reference_m"], 1),
        "vertical_scale = %s" % _f(result["vertical_scale"], 6),
        "terrain_rows = PackedStringArray(%s)" % ", ".join(_string(r) for r in terrain_rows),
        "cover_rows = PackedStringArray(%s)" % ", ".join(_string(r) for r in cover_rows),
        "elevation_m = PackedFloat32Array(%s)" % ", ".join(metres),
        "elevation = PackedFloat32Array(%s)" % ", ".join(elevation),
        "sources = %s" % _string(SOURCES),
        "",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as out:
        out.write("\n".join(lines))


# ---------------------------------------------------------------------------------------------------------------
# Inputs: cache and download.


def _download(url: str, target: Path, data: Optional[bytes] = None) -> None:
    request = urllib.request.Request(url, data=data, headers={"User-Agent": USER_AGENT})
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(target.suffix + ".part")
    print("Downloading %s -> %s" % (url, target), file=sys.stderr)
    with urllib.request.urlopen(request, timeout=600) as response, open(tmp, "wb") as out:
        while True:
            chunk = response.read(1 << 20)
            if not chunk:
                break
            out.write(chunk)
    tmp.replace(target)


def dem_paths(cache: Path, south: float, west: float, north: float, east: float, offline: bool) -> List[Path]:
    paths = []
    for lat in range(int(math.floor(south)), int(math.floor(north)) + 1):
        for lon in range(int(math.floor(west)), int(math.floor(east)) + 1):
            name = copernicus_tile_name(lat, lon)
            path = cache / "dem" / (name + ".tif")
            if not path.exists():
                if offline:
                    raise SystemExit("missing DEM tile %s (run without --offline to download it)" % path)
                _download(DEM_URL.format(name=name), path)
            paths.append(path)
    return paths


def osm_path(cache: Path, south: float, west: float, north: float, east: float, offline: bool) -> Path:
    path = cache / "osm" / ("osm_%.5f_%.5f_%.5f_%.5f.json" % (south, west, north, east))
    if not path.exists():
        if offline:
            raise SystemExit("missing OSM extract %s (run without --offline to download it)" % path)
        query = overpass_query(south, west, north, east)
        _download(OVERPASS_URL, path, urllib.parse.urlencode({"data": query}).encode("utf-8"))
    return path


def _pair(text: str, sep: str, kind: type) -> Tuple:
    parts = text.split(sep)
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("expected two values separated by '%s': %s" % (sep, text))
    return kind(parts[0]), kind(parts[1])


def run(argv: Sequence[str]) -> Path:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("bbox", nargs="?", help="min_lon,min_lat,max_lon,max_lat (WGS84 degrees)")
    parser.add_argument("--center", help="lat,lon of the map centre (default: the bbox centre)")
    parser.add_argument("--size", help="columns x rows, e.g. 30x24 (default: from the bbox extent)")
    parser.add_argument("--hex", type=float, default=250.0, help="metres between neighbouring hex centres")
    parser.add_argument("--name", required=True, help="map id (data/maps/<id>.tres)")
    parser.add_argument("--display-name", default="", help="name shown to the player (default: the id)")
    parser.add_argument("--out", required=True)
    parser.add_argument("--cache", default=str(DEFAULT_CACHE))
    parser.add_argument("--offline", action="store_true", help="never download; fail on a missing cache file")
    parser.add_argument("--dem", action="append", default=[], help="DEM GeoTIFF instead of the cache (repeatable)")
    parser.add_argument("--osm", help="Overpass JSON instead of the cache")
    parser.add_argument("--hills-relief", type=float, default=15.0, help="metres of in-hex relief that make HILLS")
    parser.add_argument("--canopy", type=float, default=15.0, help="metres a mostly forested hex's DSM is lowered")
    parser.add_argument("--exaggeration", type=float, default=1.5, help="vertical exaggeration of the 3D relief")
    args = parser.parse_args(argv)
    bbox = tuple(float(v) for v in args.bbox.split(",")) if args.bbox else None
    if bbox is not None and len(bbox) != 4:
        parser.error("bbox needs four numbers")
    if args.center:
        lat, lon = _pair(args.center, ",", float)
    elif bbox:
        lat, lon = (bbox[1] + bbox[3]) / 2.0, (bbox[0] + bbox[2]) / 2.0
    else:
        parser.error("give a bbox or --center")
    zone = utm_zone(lon)
    centre_e, centre_n = to_utm(lat, lon, zone)
    if args.size:
        width, height = _pair(args.size.lower(), "x", int)
    elif bbox:
        w_e, s_n = to_utm(bbox[1], bbox[0], zone)
        e_e, n_n = to_utm(bbox[3], bbox[2], zone)
        width = max(1, int(round((e_e - w_e) / args.hex)))
        height = max(1, int(round((n_n - s_n) / (args.hex * SQRT3 / 2.0))))
    else:
        parser.error("give --size with --center")
    if width < 1 or height < 1:
        parser.error("size must be positive")
    layout = HexLayout.centred(width, height, args.hex, centre_e, centre_n)
    min_e, min_n, max_e, max_n = layout.bounds()
    corners = [from_utm(e, n, zone) for e in (min_e, max_e) for n in (min_n, max_n)]
    map_bbox = (min(c[1] for c in corners), min(c[0] for c in corners),
                max(c[1] for c in corners), max(c[0] for c in corners))  # fmt: skip
    min_e, min_n, max_e, max_n = layout.bounds(OSM_MARGIN_M)
    corners = [from_utm(e, n, zone) for e in (min_e, max_e) for n in (min_n, max_n)]
    south = round(min(c[0] for c in corners), 5)
    west = round(min(c[1] for c in corners), 5)
    north = round(max(c[0] for c in corners), 5)
    east = round(max(c[1] for c in corners), 5)
    cache = Path(os.path.expanduser(args.cache))
    dem_files = [Path(p) for p in args.dem] or dem_paths(cache, south, west, north, east, args.offline)
    osm_file = Path(args.osm) if args.osm else osm_path(cache, south, west, north, east, args.offline)
    with open(osm_file, encoding="utf-8") as f:
        osm = json.load(f)
    result = build_map(layout, zone, Dem(dem_files), osm, args.hills_relief, args.canopy, args.exaggeration)
    out = Path(args.out)
    write_tres(out, args.name, args.display_name or args.name, layout, zone, result, map_bbox)
    counts: Dict[str, int] = {}
    for t in result["tiles"].values():
        counts[t["terrain"]] = counts.get(t["terrain"], 0) + 1
    print("Wrote %s: %dx%d hexes of %.0f m, %s" % (out, width, height, args.hex,
          ", ".join("%s %d" % (k, counts[k]) for k in sorted(counts))))  # fmt: skip
    return out


if __name__ == "__main__":
    run(sys.argv[1:])
