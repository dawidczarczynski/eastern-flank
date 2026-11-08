#!/usr/bin/env python3
"""Tactical and operational hex maps from real geography (TASK-087, TASK-092a, ADR 0018). Python 3.8, stdlib only.

Usage:
  tools/import_map.py [<min_lon,min_lat,max_lon,max_lat>] [--profile=tactical|operational] [--center=<lat,lon>]
                      [--size=30x24] [--hex=250] [--sample=25] [--tile-deg=0.5] [--sea-seed=<lat,lon> ...]
                      --name=<id> --out=data/maps/<id>.tres [--display-name=<text>]
                      [--cache=~/.cache/eastern-flank/maps] [--offline] [--dem=<file.tif> ...] [--osm=<file.json>]
                      [--countries=<ISO>:<lat,lon>[,<ISO>:<lat,lon>...]]

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
Per hex (`classify`, TASK-108 / ADR 0019): the dominant group of its points (water / forest / open, ties prefer open,
then forest) makes WATER or FOREST; an open hex is URBAN when built-up cover reaches `--urban-share` of its points,
MARSH when wetland reaches `--marsh-share`, HILLS when its relief (90th - 10th percentile of its heights) reaches
`--hills-relief` metres, FIELDS when farmland is its largest open cover class, else PLAINS.
Roads and rivers (`line_links`): rule road ways (`ROAD_HIGHWAYS`) and river ways (`RIVER_WATERWAYS`, named streams)
are densified every `LINE_STEP_M` metres and turned into links between consecutive hexes (a 6-bit mask per hex, bit i
towards the neighbour in `HEX_DIRECTIONS[i]`); a stretch shorter than `CLIP_M` that only clips a hex corner between
two neighbouring hexes is skipped. Links are stored on both land hexes, on the land side only towards water or off
the map, never on water (`store_links`).
The hex elevation is the mean DEM height of its open points (a DSM: forest canopy and buildings are skipped when
at least a quarter of the hex is open; a hex that is mostly forest takes the mean minus `--canopy`). Game
elevation: land = land_min + (metres - lowest land hex) x vertical scale (`--exaggeration` x true scale, reduced
so the highest hex stays at `TOP_ELEVATION`), water = `WATER_ELEVATION` (the game has one water plane at 0).

Profiles (`--profile`, TASK-092a, ADR 0018 "Operational maps"): `tactical` (default) is everything above;
`operational` is for the 5 km theatre map: hex 5000 m, lattice 250 m (`--sample`), Copernicus GLO-90 tiles
(`<cache>/dem/Copernicus_DSM_COG_30_N<lat>_00_E<lon>_00_DEM.tif`; `--dem=glo30|glo90` picks the cached DEM),
`classify_operational` (water / urban / forest / marsh shares, hills by relief, else plains - never fields), only
major roads (`OP_ROAD_HIGHWAYS`) and rivers / canals, the corner clip scaled with the hex (`clip_length`). Its OSM
input is fetched in `--tile-deg` tiles on a grid aligned to multiples of the tile size (`osm_tile_paths`, each
tile its own cache file `<cache>/osm/op1_<lat>_<lon>_<deg>.json`, retried and resumable); tiles are read one at a
time and areas / lines that appear in several tiles give the same result again (highest class per point, link
masks OR-ed). OSM has no sea polygons: `natural=coastline` ways are rasterised as a barrier and the sea is filled
from `--sea-seed` points (`fill_sea`; the theatre's defaults `OP_SEA_SEEDS` apply when they lie on the map).

Countries (TASK-113, operational only; ADR 0018 "Countries"): `--countries=PL:54.10,22.93,LT:54.90,23.90,...` gives each
country an ISO code and a seed point inside it (the operational defaults `OP_COUNTRIES` apply when they lie on the map).
The country-border ways are rasterised as barrier points on the lattice (`border_barrier`, supercover: every lattice
cell a segment crosses), a 4-connected flood fill from each seed owns its region (`fill_countries`; two seeds in one
region = a gap in the border line = error), barrier points take the majority of their 4 neighbours (ties: the first
country), and a hex takes the country with the most land points (`hex_country`; water hexes none). The border ways
come from the tagged `admin_level=2` ways of the land-cover tiles plus the borders-only tiles
`<cache>/osm/bd1_<lat>_<lon>_<deg>.json` (`border_query`: the member ways of the country relations touching the tile;
fetched like the land-cover tiles, `--offline` fails naming a missing tile). Written as `countries` and `country_rows`.
The borders are also written as lines for drawing (`border_lines`, `border_polylines`): the ways clipped to the map, chained
and Douglas-Peucker simplified (0.1 hex), in world units (x east, z south, hex size 1) - never snapped to hexes.

Graphic layers (TASK-126, operational only; GDD "Operational map", map principle): the drawn staff map is not made
of hexes, so the importer also writes three images of the whole lattice (one pixel per lattice point, `--sample`
= 250 m, row 0 north): `water` (1-bit: the water class of the lattice - lakes, reservoirs, riverbanks and the sea
fill), `cover` (8-bit: the lattice's COVER_CLASSES index, `LAYER_COVER_*`) and `relief` (8-bit hillshade of the
DEM heights at the lattice points, forest canopy removed, on every `--relief-step`-th point = 500 m (tent filtered,
`downsample`), sun from the north-west at 45 degrees, `--relief-z` vertical exaggeration; flat ground =
`RELIEF_FLAT`). They are stored as grayscale PNGs (deterministic: water and
cover unfiltered, relief with a fixed adaptive filter rule, zlib level 9), base64 `PackedByteArray`s in the `.tres` (`layer_*` fields). The rules grid
is computed exactly as without them (`Settings.layers`).

Tactical layer (`--profile=layer`, TASK-094b; ADR 0018 "Tactical layer"): the tactical terrain of a whole theatre for
contact battles, from the operational inputs (op1 OSM tiles, GLO-90, sea fill): 250 m hexes, a 50 m cover lattice
(`_scanline_fill_fast`), per hex the cover classes of the `_hex_pattern` points and the DEM at the centre and six
points `LAYER_DEM_RADIUS_M` around it, the tactical `classify` (hills from `LAYER_HILLS_RELIEF`); never fields (no
farmland in the inputs). Written into the folder `--out` as `layer.tres` (TacticalLayer) and one zlib-compressed
`chunk_<cx>_<cy>.tres` (TacticalChunk) per `LAYER_CHUNK` square (`write_layer`).

Output: a Godot text resource of class ImportedMap (src/core/data/imported_map.gd). The same inputs give a
byte-identical file: elements are processed in sorted order and every number is written with fixed decimals.
"""
from __future__ import annotations

import argparse
import base64
import json
import math
import os
import struct
import sys
import urllib.parse
import urllib.request
import time
import zlib
from array import array
from collections import deque
from itertools import accumulate
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

DEFAULT_CACHE = Path(os.path.expanduser("~/.cache/eastern-flank/maps"))
DEM_URL = "https://copernicus-dem-30m.s3.amazonaws.com/{name}/{name}.tif"
DEM_URLS = {"glo30": DEM_URL, "glo90": "https://copernicus-dem-90m.s3.amazonaws.com/{name}/{name}.tif"}
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
SOURCES_GLO90 = SOURCES.replace("GLO-30 DEM", "GLO-90 DEM").replace("WorldDEM-30", "WorldDEM-90")

# Cover classes in priority order (a later class wins where polygons overlap) and their map characters.
# Terrain (`classify`): W -> WATER, F -> FOREST by dominance; in an open hex U -> URBAN and M -> MARSH by share,
# then HILLS by relief, A -> FIELDS when it is the largest open class, else PLAINS.
COVER_CLASSES = ".GAUFMW"  # . unmapped, G grass/meadow/scrub, A fields, U urban, F forest, M marsh, W water
OPEN, FOREST, WATER = "open", "forest", "water"
TERRAIN_CHARS = {"plains": "P", "forest": "F", "hills": "H", "water": "W", "fields": "A", "urban": "U", "marsh": "M"}
URBAN_SHARE = 0.20  # a village core (~1 ha) of the 5.4 ha hex
MARSH_SHARE = 0.25

# Roads and rivers (TASK-108). Links per hex side: bit i of a hex's mask = a link towards the neighbour
# axial + HEX_DIRECTIONS[i] (the order of Hex.DIRECTIONS in the game).
HEX_DIRECTIONS = ((1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1))
LINK_CHARS = ".123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ#@"  # LINK_CHARS[mask], ImportedMap
ROAD_HIGHWAYS = ("motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential")
RIVER_WATERWAYS = ("river", "canal")  # plus `stream` with a name; ditches, drains and unnamed streams are ignored
LINE_STEP_M = 10.0  # densification of road / river lines
CLIP_M = 40.0  # a shorter stretch through a hex between two neighbouring hexes is a clipped corner
ROAD, RIVER = "road", "river"

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

# Operational profile (TASK-092a, GDD "Operational map"): 5 km hexes read only major features. Urban areas without
# the large military training grounds (mostly forest and heath, they would make whole 5 km hexes urban); fields and
# grass are not told apart at this scale, so they are not downloaded (unmapped = plains).
OP_URBAN_LANDUSE = ("residential", "commercial", "industrial", "retail", "farmyard", "garages", "construction",
                    "railway")  # fmt: skip
_OP_TAG_CLASSES: List[Tuple[str, Dict[str, str]]] = [
    ("natural", {"water": "W", "bay": "W", "wetland": "M", "wood": "F"}),
    ("waterway", {"riverbank": "W", "dock": "W"}),
    ("water", {"*": "W"}),
    ("landuse", dict([("reservoir", "W"), ("basin", "W"), ("forest", "F")] + [(v, "U") for v in OP_URBAN_LANDUSE])),
]
OP_ROAD_HIGHWAYS = ("motorway", "trunk", "primary", "secondary")
OP_SEA_SEEDS = ((55.30, 20.60), (55.10, 21.05))  # the open Baltic west of the Curonian Spit; the Curonian Lagoon
OP_QUERY_VERSION = "op1"  # part of the tile file names: a changed query must not reuse old tiles
BORDER_QUERY_VERSION = "bd1"  # borders-only tile files (TASK-113), next to the `op1` land-cover tiles
OP_COUNTRIES = (("PL", 54.10, 22.93), ("LT", 54.90, 23.90), ("BY", 53.68, 23.83), ("RU", 54.71, 20.51))
# Suwalki, Kaunas, Grodno, Kaliningrad: the operational defaults of `--countries` (skipped when off the map)
NO_COUNTRY = 255
OSM_TILE_DEG = 0.5
DOWNLOAD_RETRIES = 3
RETRY_PAUSE_S = 60.0
# GDD "Operational map" thresholds (shares of a hex's sample points, relief in metres).
OP_WATER_SHARE = 0.50
OP_URBAN_SHARE = 0.15
OP_FOREST_SHARE = 0.50
OP_MARSH_SHARE = 0.25
OP_HILLS_RELIEF = 35.0  # GDD start 60 m gave 0.5 % hills on the real theatre; tuned (TASK-092a)
# Graphic layers (TASK-126): hillshade light and vertical exaggeration (the theatre's slopes over 250 m pixels are
# a few percent, true scale would leave the shading almost flat).
RELIEF_AZIMUTH = 315.0  # degrees clockwise from north: the sun in the north-west (cartographic convention)
RELIEF_ALTITUDE = 45.0
RELIEF_Z = 4.0
RELIEF_STEP = 2  # relief pixel = 2 x 2 lattice points (500 m): a 250 m hillshade made the theatre file load 0.2 s slower
RELIEF_FLAT = int(255.0 * math.sin(math.radians(RELIEF_ALTITUDE)) + 0.5)  # 180: the hillshade of flat ground


LAYER_SAMPLE_M = 50.0  # tactical layer (TASK-094b): cover lattice of the whole theatre at 250 m hexes
LAYER_LINE_STEP_M = 20.0
LAYER_CHUNK = 128  # hexes per chunk side (even, so every chunk starts on an even row)
LAYER_DEM_RADIUS_M = 110.0  # the six DEM points around a hex centre (GLO-90 pixels are ~90 m)
LAYER_HILLS_RELIEF = 10.0  # GLO-90 at 7 points: 10 m gives 142 hills on the suwalki.tres area (GLO-30, 15 m: 129)
LAYER_ELEVATION_OFFSET_M = 100.0  # stored height = round((metres + offset) / step), uint16
LAYER_ELEVATION_STEP_M = 0.1
LAYER_TERRAIN_CODES = {"plains": 0, "forest": 1, "hills": 2, "water": 3, "fields": 4, "urban": 5,
                       "marsh": 6}  # Terrain.Type  # fmt: skip


class Profile:
    """What a map scale reads: hex and lattice spacing, DEM, classifier, tag table, line classes, OSM tiling."""

    def __init__(self, name: str, hex_m: float, sample_m: float, dem: str, tag_classes: list,
                 road_highways: Tuple[str, ...], named_streams: bool, line_step_m: float, tiled: bool) -> None:  # fmt: skip
        self.name = name
        self.hex_m = hex_m
        self.sample_m = sample_m
        self.dem = dem
        self.tag_classes = tag_classes
        self.road_highways = road_highways
        self.named_streams = named_streams
        self.line_step_m = line_step_m
        self.tiled = tiled


PROFILES = {
    "tactical": Profile("tactical", 250.0, SAMPLE_M, "glo30", _TAG_CLASSES, ROAD_HIGHWAYS, True, LINE_STEP_M, False),
    "operational": Profile("operational", 5000.0, 250.0, "glo90", _OP_TAG_CLASSES, OP_ROAD_HIGHWAYS, False, 50.0, True),
}
PROFILES["layer"] = Profile("layer", 250.0, LAYER_SAMPLE_M, "glo90", _OP_TAG_CLASSES, OP_ROAD_HIGHWAYS, False,
                            LAYER_LINE_STEP_M, True)  # fmt: skip
TACTICAL = PROFILES["tactical"]
OPERATIONAL = PROFILES["operational"]
LAYER = PROFILES["layer"]


class Settings:
    """Everything `build_map` needs besides the layout and the inputs (the CLI options, resolved per profile)."""

    def __init__(self, profile: Profile = TACTICAL, sample_m: Optional[float] = None,
                 hills_relief: Optional[float] = None, canopy: float = 15.0, exaggeration: float = 1.5, water_share: float = OP_WATER_SHARE,
                 urban_share: Optional[float] = None, forest_share: float = OP_FOREST_SHARE,
                 marsh_share: float = MARSH_SHARE, sea_seeds: Sequence[Tuple[float, float]] = (),
                 default_seeds: Sequence[Tuple[float, float]] = (),
                 countries: Sequence[Tuple[str, float, float]] = (),
                 default_countries: Sequence[Tuple[str, float, float]] = (),
                 layers: Optional[bool] = None, relief_z: float = RELIEF_Z,
                 relief_step: int = RELIEF_STEP) -> None:  # fmt: skip
        operational = profile is OPERATIONAL
        self.profile = profile
        self.sample_m = sample_m if sample_m is not None else profile.sample_m
        default_relief = OP_HILLS_RELIEF if operational else LAYER_HILLS_RELIEF if profile.name == "layer" else 15.0
        self.hills_relief = hills_relief if hills_relief is not None else default_relief
        self.canopy = canopy
        self.exaggeration = exaggeration
        self.water_share = water_share
        self.urban_share = urban_share if urban_share is not None else (OP_URBAN_SHARE if operational else URBAN_SHARE)
        self.forest_share = forest_share
        self.marsh_share = marsh_share
        self.sea_seeds = list(sea_seeds)  # explicit: each must lie on the map's lattice, on the sea side
        self.default_seeds = list(default_seeds)  # the profile's: skipped when off the lattice
        self.countries = list(countries)  # (ISO code, lat, lon of a seed point): explicit, each must lie on the map
        self.default_countries = list(default_countries)  # the profile's: skipped when off the map
        self.layers = operational if layers is None else layers  # graphic layers (TASK-126): operational maps
        self.relief_z = relief_z
        self.relief_step = relief_step


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
        self._cache: Dict[int, Sequence[float]] = {}

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

    def _block(self, index: int) -> Sequence[float]:
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
        # Compact storage, the same values: float32 samples stay float32, integers fit a double exactly.
        self._cache[index] = array("f" if self._sample == "f" else "d", values)
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
        self._candidates: Dict[Tuple[int, int], List[GeoTiff]] = {}

    def _cell(self, lat: float, lon: float) -> List[GeoTiff]:
        """The tiles (in order) that may contain a point of the 1-degree cell of (lat, lon)."""
        key = (int(math.floor(lat)), int(math.floor(lon)))
        found = self._candidates.get(key)
        if found is None:
            found = []
            for t in self.tiles:
                west, east = t.lon0 - t.dx, t.lon0 + t.width * t.dx
                north, south = t.lat0 + t.dy, t.lat0 - t.height * t.dy
                if west <= key[1] + 1 and east >= key[1] and south <= key[0] + 1 and north >= key[0]:
                    found.append(t)
            self._candidates[key] = found
        return found

    def sample(self, lat: float, lon: float) -> float:
        for tile in self._cell(lat, lon):
            if tile.contains(lat, lon):
                return tile.sample(lat, lon)
        raise ValueError("no DEM tile covers %.5f, %.5f" % (lat, lon))


def copernicus_tile_name(lat: int, lon: int, dem: str = "glo30") -> str:
    """Copernicus COG tile name; GLO-30 tiles are `_10_` (1 arc second), GLO-90 tiles `_30_` (3 arc seconds)."""
    ns = "N" if lat >= 0 else "S"
    ew = "E" if lon >= 0 else "W"
    res = {"glo30": "10", "glo90": "30"}[dem]
    return "Copernicus_DSM_COG_%s_%s%02d_00_%s%03d_00_DEM" % (res, ns, abs(lat), ew, abs(lon))


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


def border_query(south: float, west: float, north: float, east: float) -> str:
    """Overpass query of one borders-only tile (TASK-113): the member ways of the country-border relations
    (`boundary=administrative`, `admin_level=2`) that touch the bbox, with their nodes. Most of the Poland - Russia and
    Lithuania - Russia borders are untagged members of these relations, so the tagged `admin_level=2` ways of the land-cover
    tiles miss them. Whole ways come back (no clipping), but only ways touching the bbox, never whole countries."""
    bbox = "%.5f,%.5f,%.5f,%.5f" % (south, west, north, east)
    return "\n".join([
        "[out:json][timeout:900];",
        'rel["boundary"="administrative"]["admin_level"="2"](%s);' % bbox,
        "way(r)(%s);" % bbox,
        "(._;>;);",
        "out body;",
    ])  # fmt: skip


def operational_query(south: float, west: float, north: float, east: float) -> str:
    """Overpass query of one operational tile: only what the operational profile reads (forest, water, wetland,
    urban land use, major roads, rivers and canals) plus the coastline (sea fill) and the country borders
    (`admin_level=2` ways, read by TASK-113)."""
    bbox = "%.5f,%.5f,%.5f,%.5f" % (south, west, north, east)
    landuse = "|".join(["forest", "reservoir", "basin"] + list(OP_URBAN_LANDUSE))
    return "\n".join([
        "[out:json][timeout:900];",
        "(",
        '  wr["natural"~"^(water|bay|wetland|wood)$"](%s);' % bbox,
        '  wr["landuse"~"^(%s)$"](%s);' % (landuse, bbox),
        '  wr["water"](%s);' % bbox,
        '  wr["waterway"~"^(riverbank|dock)$"](%s);' % bbox,
        '  way["highway"~"^(%s)(_link)?$"](%s);' % ("|".join(OP_ROAD_HIGHWAYS), bbox),
        '  way["waterway"~"^(river|canal)$"](%s);' % bbox,
        '  way["natural"="coastline"](%s);' % bbox,
        '  way["boundary"="administrative"]["admin_level"="2"](%s);' % bbox,
        ");",
        "(._;>;);",
        "out body;",
    ])  # fmt: skip


def cover_class(tags: Dict[str, str], table: Optional[list] = None) -> Optional[str]:
    """Cover class character of an OSM area's tags, or None when the area does not set the cover."""
    for key, values in _TAG_CLASSES if table is None else table:
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


def osm_areas(osm: dict, table: Optional[list] = None) -> List[Tuple[str, List[List[Tuple[float, float]]]]]:
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
        cls = cover_class(way.get("tags", {}), table)
        refs = way.get("nodes", [])
        if cls and len(refs) >= 4 and refs[0] == refs[-1]:
            rings = rings_of([refs])
            if rings:
                areas.append((COVER_CLASSES.index(cls), 0, way_id, cls, rings))
    for rel in sorted(relations, key=lambda r: r["id"]):
        tags = rel.get("tags", {})
        cls = cover_class(tags, table)
        if not cls or tags.get("type") not in ("multipolygon", "boundary"):
            continue
        members = [ways[m["ref"]]["nodes"] for m in rel.get("members", []) if m.get("type") == "way" and m.get("ref") in ways]
        rings = rings_of(_assemble_rings(members))
        if rings:
            areas.append((COVER_CLASSES.index(cls), 1, rel["id"], cls, rings))
    areas.sort(key=lambda a: a[:3])
    return [(a[3], a[4]) for a in areas]


def line_kind(tags: Dict[str, str], profile: Optional[Profile] = None) -> Optional[str]:
    """ROAD, RIVER or None for an OSM way's tags (rule roads and rivers only, TASK-108; the operational profile
    reads only major roads and no streams, TASK-092a)."""
    profile = profile or TACTICAL
    if tags.get("area") == "yes":
        return None
    highway = tags.get("highway", "")
    roads = profile.road_highways
    if highway in roads or (highway.endswith("_link") and highway[: -len("_link")] in roads):
        return ROAD
    waterway = tags.get("waterway", "")
    if waterway in RIVER_WATERWAYS or (profile.named_streams and waterway == "stream" and tags.get("name")):
        return RIVER
    return None


def osm_coastlines(osm: dict) -> List[Tuple[int, List[Tuple[float, float]]]]:
    """(way id, [(lat, lon), ...]) of every `natural=coastline` way, sorted by id (land on the left, OSM rule)."""
    nodes: Dict[int, Tuple[float, float]] = {}
    ways = []
    for el in osm.get("elements", []):
        if el.get("type") == "node":
            nodes[el["id"]] = (el["lat"], el["lon"])
        elif el.get("type") == "way" and el.get("tags", {}).get("natural") == "coastline":
            ways.append(el)
    lines = []
    for way in sorted(ways, key=lambda w: w["id"]):
        points = [nodes[n] for n in way.get("nodes", []) if n in nodes]
        if len(points) >= 2:
            lines.append((way["id"], points))
    return lines


def osm_borders(osm: dict, all_ways: bool = False) -> Dict[int, List[Tuple[float, float]]]:
    """Way id -> [(lat, lon), ...] of the country-border ways of an Overpass answer: the ways tagged
    `boundary=administrative` + `admin_level=2`, or - in a borders-only tile (`all_ways`) - every way."""
    nodes: Dict[int, Tuple[float, float]] = {}
    ways = []
    for el in osm.get("elements", []):
        if el.get("type") == "node":
            nodes[el["id"]] = (el["lat"], el["lon"])
        elif el.get("type") == "way":
            tags = el.get("tags", {})
            if all_ways or (tags.get("boundary") == "administrative" and tags.get("admin_level") == "2"):
                ways.append(el)
    lines = {}
    for way in ways:
        points = [nodes[n] for n in way.get("nodes", []) if n in nodes]
        if len(points) >= 2:
            lines[way["id"]] = points
    return lines


def osm_lines(osm: dict, profile: Optional[Profile] = None) -> List[Tuple[str, List[Tuple[float, float]]]]:
    """(ROAD or RIVER, [(lat, lon), ...]) of every road and river way, sorted by (kind, way id)."""
    nodes: Dict[int, Tuple[float, float]] = {}
    ways = []
    for el in osm.get("elements", []):
        if el.get("type") == "node":
            nodes[el["id"]] = (el["lat"], el["lon"])
        elif el.get("type") == "way":
            ways.append(el)
    lines = []
    for way in ways:
        kind = line_kind(way.get("tags", {}), profile)
        points = [nodes[n] for n in way.get("nodes", []) if n in nodes]
        if kind and len(points) >= 2:
            lines.append((kind, way["id"], points))
    lines.sort(key=lambda line: line[:2])
    return [(kind, points) for kind, _, points in lines]


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

    @staticmethod
    def offset(q: int, r: int) -> Tuple[int, int]:
        return q + (r // 2), r

    def axial_at(self, e: float, n: float) -> Tuple[int, int]:
        """Axial (q, r) of the hex containing the point, also off the map (Hex.from_world rounding)."""
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
        return int(q), int(r)

    def on_map(self, col: int, row: int) -> bool:
        return 0 <= col < self.width and 0 <= row < self.height

    def tile_at(self, e: float, n: float) -> Optional[Tuple[int, int]]:
        """(col, row) of the hex containing the point, None off the map."""
        col, row = self.offset(*self.axial_at(e, n))
        return (col, row) if self.on_map(col, row) else None

    def bounds(self, margin: float = 0.0) -> Tuple[float, float, float, float]:
        """(min_e, min_n, max_e, max_n) of the map's hexes plus `margin` metres."""
        m = self.metres_per_unit
        half_w = SQRT3 / 2.0 * m
        xs = [self.centre(c, r)[0] for r in range(min(2, self.height)) for c in (0, self.width - 1)]
        return (min(xs) - half_w - margin, self.origin_n - 1.5 * (self.height - 1) * m - m - margin,
                max(xs) + half_w + margin, self.origin_n + m + margin)  # fmt: skip


def _scanline_fill(grid: List[bytearray], value: int, rings: List[List[Tuple[float, float]]],
                   min_e: float, min_n: float, step: float) -> None:  # fmt: skip
    """Raises lattice points (row j at N = min_n + j*step, column i at E = min_e + i*step) inside the rings
    (even-odd) to `value`: a point keeps the highest class of all areas covering it, whatever the order the areas
    come in (idempotent, so areas that appear in several OSM tiles may be filled again)."""
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
                if row[i] < value:
                    row[i] = value


def _percentile(sorted_values: List[float], p: float) -> float:
    k = (len(sorted_values) - 1) * p
    f = int(math.floor(k))
    c = min(f + 1, len(sorted_values) - 1)
    return sorted_values[f] + (sorted_values[c] - sorted_values[f]) * (k - f)


def classify(counts: Sequence[int], relief: float, hills_relief: float = 15.0, urban_share: float = URBAN_SHARE,
             marsh_share: float = MARSH_SHARE) -> str:  # fmt: skip
    """Terrain of a hex from its points per COVER_CLASSES index and its relief in metres (first match
    wins): water / forest by dominance, then urban share, marsh share, hills by relief, fields when farmland is
    the largest open class, else plains."""
    total = sum(counts)
    group = dominant_group(counts)
    if group == WATER:
        return "water"
    if group == FOREST:
        return "forest"
    if counts[COVER_CLASSES.index("U")] >= urban_share * total - 1e-9:
        return "urban"
    if counts[COVER_CLASSES.index("M")] >= marsh_share * total - 1e-9:
        return "marsh"
    if relief >= hills_relief:
        return "hills"
    if dominant_open_class(counts) == "A":
        return "fields"
    return "plains"


def classify_operational(counts: Sequence[int], relief: float, water_share: float = OP_WATER_SHARE,
                         urban_share: float = OP_URBAN_SHARE, forest_share: float = OP_FOREST_SHARE,
                         marsh_share: float = OP_MARSH_SHARE, hills_relief: float = OP_HILLS_RELIEF) -> str:  # fmt: skip
    """Terrain of a 5 km hex (GDD "Operational map", first match wins): water share -> water, urban share ->
    urban, forest share -> forest, marsh share -> marsh, relief -> hills, else plains (never fields)."""
    total = sum(counts)

    def reaches(cls: str, share: float) -> bool:
        return counts[COVER_CLASSES.index(cls)] >= share * total - 1e-9

    if reaches("W", water_share):
        return "water"
    if reaches("U", urban_share):
        return "urban"
    if reaches("F", forest_share):
        return "forest"
    if reaches("M", marsh_share):
        return "marsh"
    if relief >= hills_relief:
        return "hills"
    return "plains"


def dominant_group(counts: Sequence[int]) -> str:
    """WATER, FOREST or OPEN: the group with the most points; ties prefer open, then forest."""
    forest_i, water_i = COVER_CLASSES.index("F"), COVER_CLASSES.index("W")
    groups = {WATER: counts[water_i], FOREST: counts[forest_i]}
    groups[OPEN] = sum(counts) - groups[WATER] - groups[FOREST]
    return max((OPEN, FOREST, WATER), key=lambda g: groups[g])  # max keeps the first on ties


def dominant_open_class(counts: Sequence[int]) -> str:
    """The open cover class (not forest or water) with the most points; ties prefer the later class."""
    forest_i, water_i = COVER_CLASSES.index("F"), COVER_CLASSES.index("W")
    open_classes = [k for k in range(len(COVER_CLASSES)) if k not in (forest_i, water_i)]
    return COVER_CLASSES[max(reversed(open_classes), key=lambda k: counts[k])]


def _densify(points: Sequence[Tuple[float, float]], step: float) -> List[Tuple[float, float, float]]:
    """(e, n, distance along the line) every `step` metres or less, the vertices included."""
    out = [(points[0][0], points[0][1], 0.0)]
    along = 0.0
    for (e1, n1), (e2, n2) in zip(points, points[1:]):
        length = math.hypot(e2 - e1, n2 - n1)
        if length == 0.0:
            continue
        parts = max(1, int(math.ceil(length / step - 1e-9)))
        for k in range(1, parts + 1):
            t = k / parts
            out.append((e1 + (e2 - e1) * t, n1 + (n2 - n1) * t, along + length * t))
        along += length
    return out


def _hex_distance(a: Tuple[int, int], b: Tuple[int, int]) -> int:
    dq, dr = a[0] - b[0], a[1] - b[1]
    return (abs(dq) + abs(dr) + abs(dq + dr)) // 2


def clip_length(layout: HexLayout) -> float:
    """Corner-clip length of the layout: CLIP_M at the 250 m tactical hex, scaled with the hex (800 m at 5 km)."""
    return CLIP_M * layout.spacing / 250.0


def line_links(layout: HexLayout, points: Sequence[Tuple[float, float]],
               step: float = LINE_STEP_M) -> List[Tuple[Tuple[int, int], Tuple[int, int]]]:  # fmt: skip
    """Links (axial a, axial b) between consecutive hexes along a projected polyline (also off the map), after
    dropping stretches shorter than `clip_length` that clip a hex corner between two neighbouring hexes (or leave
    and re-enter the same hex). The line is densified every `step` metres."""
    clip = clip_length(layout)
    samples = _densify(points, step)
    runs: List[list] = []  # [axial, distance where the line enters, distance where it leaves]
    for e, n, along in samples:
        tile = layout.axial_at(e, n)
        if runs and runs[-1][0] == tile:
            runs[-1][2] = along
        else:
            if runs:
                runs[-1][2] = along
            runs.append([tile, along, along])
    changed = True
    while changed:
        changed = False
        for i in range(1, len(runs) - 1):
            prev, run, nxt = runs[i - 1], runs[i], runs[i + 1]
            if run[2] - run[1] < clip and _hex_distance(prev[0], nxt[0]) <= 1:
                del runs[i]
                if prev[0] == nxt[0]:
                    prev[2] = nxt[2]
                    del runs[i]
                changed = True
                break
    links = []
    for a, b in zip(runs, runs[1:]):
        if _hex_distance(a[0], b[0]) == 1:
            links.append((a[0], b[0]))
    return links


def store_links(layout: HexLayout, links: Sequence[Tuple[Tuple[int, int], Tuple[int, int]]],
                water: Sequence[Tuple[int, int]]) -> Dict[Tuple[int, int], int]:  # fmt: skip
    """(col, row) -> link mask of the map's land hexes: each link (axial a, b) sets the bit towards the other
    hex on both ends; water hexes and hexes off the map keep none (so land -> water / off-map links stay on the
    land side only)."""
    water_set = set(water)
    masks: Dict[Tuple[int, int], int] = {}
    for a, b in links:
        for src, dst in ((a, b), (b, a)):
            tile = layout.offset(*src)
            if not layout.on_map(*tile) or tile in water_set:
                continue
            bit = HEX_DIRECTIONS.index((dst[0] - src[0], dst[1] - src[1]))
            masks[tile] = masks.get(tile, 0) | (1 << bit)
    return masks


def _coast_barrier(rows: int, cols: int, coastlines: Sequence[Sequence[Tuple[float, float]]],
                   min_e: float, min_n: float, step: float) -> bytearray:  # fmt: skip
    """Lattice points (row-major, 1 = barrier) on the projected coastlines: each segment is walked every quarter
    step and the nearest lattice point marked, so the marks form an 8-connected chain no 4-connected fill crosses."""
    barrier = bytearray(rows * cols)
    for line in coastlines:
        for (e1, n1), (e2, n2) in zip(line, line[1:]):
            parts = max(1, int(math.ceil(math.hypot(e2 - e1, n2 - n1) / (step / 4.0))))
            for k in range(parts + 1):
                t = k / parts
                i = int(round((e1 + (e2 - e1) * t - min_e) / step))
                j = int(round((n1 + (n2 - n1) * t - min_n) / step))
                if 0 <= i < cols and 0 <= j < rows:
                    barrier[j * cols + i] = 1
    return barrier


def sea_side(coastlines: Sequence[Sequence[Tuple[float, float]]], e: float, n: float) -> bool:
    """True when the projected point lies on the sea side (right, OSM: land is on the left) of the nearest
    coastline segment."""
    best = None
    for line in coastlines:
        for (e1, n1), (e2, n2) in zip(line, line[1:]):
            de, dn = e2 - e1, n2 - n1
            length2 = de * de + dn * dn
            t = 0.0 if length2 == 0.0 else min(1.0, max(0.0, ((e - e1) * de + (n - n1) * dn) / length2))
            dist = math.hypot(e - (e1 + de * t), n - (n1 + dn * t))
            if best is None or dist < best[0]:
                best = (dist, de * (n - n1) - dn * (e - e1))
    return best is not None and best[1] < 0.0  # cross product < 0: the point is right of the segment


def fill_sea(cover: List[bytearray], coastlines: Sequence[Sequence[Tuple[float, float]]],
             seeds: Sequence[Tuple[float, float]], min_e: float, min_n: float, step: float) -> int:  # fmt: skip
    """Marks as water every lattice point 4-connected to a projected seed point without crossing a coastline
    (OSM has no sea polygons). A seed off the lattice, on land or on the coastline is an error. Returns the number
    of points reached."""
    rows = len(cover)
    cols = len(cover[0]) if rows else 0
    barrier = _coast_barrier(rows, cols, coastlines, min_e, min_n, step)
    water = COVER_CLASSES.index("W")
    seen = bytearray(rows * cols)
    reached = 0
    for e, n in seeds:
        i = int(round((e - min_e) / step))
        j = int(round((n - min_n) / step))
        if not (0 <= i < cols and 0 <= j < rows):
            raise ValueError("sea seed E %.0f N %.0f is off the map" % (e, n))
        if not coastlines or barrier[j * cols + i] or not sea_side(coastlines, e, n):
            raise ValueError("sea seed E %.0f N %.0f is not on the sea side of a coastline" % (e, n))
        queue = deque([j * cols + i])
        seen[j * cols + i] = 1
        while queue:
            k = queue.popleft()
            cover[k // cols][k % cols] = water
            reached += 1
            ki, kj = k % cols, k // cols
            for nk, ok in ((k - 1, ki > 0), (k + 1, ki < cols - 1), (k - cols, kj > 0), (k + cols, kj < rows - 1)):
                if ok and not seen[nk] and not barrier[nk]:
                    seen[nk] = 1
                    queue.append(nk)
    return reached


def border_barrier(rows: int, cols: int, lines: Sequence[Sequence[Tuple[float, float]]],
                   min_e: float, min_n: float, step: float) -> bytearray:  # fmt: skip
    """Lattice points (row-major, 1 = barrier) that projected border lines pass through. Supercover: every lattice
    cell (the `step` square around a point) a segment crosses is marked, so the barrier is a 4-connected chain and
    neither a 4- nor an 8-connected fill leaks through a diagonal border; a segment through exactly a cell corner
    marks both cells that touch it."""
    barrier = bytearray(rows * cols)

    def mark(i: int, j: int) -> None:
        if 0 <= i < cols and 0 <= j < rows:
            barrier[j * cols + i] = 1

    for line in lines:
        for (e1, n1), (e2, n2) in zip(line, line[1:]):
            x1, y1 = (e1 - min_e) / step + 0.5, (n1 - min_n) / step + 0.5  # cell (i, j) is [i, i+1) x [j, j+1)
            x2, y2 = (e2 - min_e) / step + 0.5, (n2 - min_n) / step + 0.5
            if (max(x1, x2) < 0 or min(x1, x2) > cols or max(y1, y2) < 0 or min(y1, y2) > rows):
                continue
            i, j = int(math.floor(x1)), int(math.floor(y1))
            end_i, end_j = int(math.floor(x2)), int(math.floor(y2))
            dx, dy = x2 - x1, y2 - y1
            sx = 1 if dx > 0 else -1
            sy = 1 if dy > 0 else -1
            inf = float("inf")
            t_x = ((i + (1 if dx > 0 else 0)) - x1) / dx if dx != 0 else inf
            t_y = ((j + (1 if dy > 0 else 0)) - y1) / dy if dy != 0 else inf
            d_x = abs(1.0 / dx) if dx != 0 else inf
            d_y = abs(1.0 / dy) if dy != 0 else inf
            mark(i, j)
            for _ in range(abs(end_i - i) + abs(end_j - j) + 2):
                if (i, j) == (end_i, end_j):
                    break
                if abs(t_x - t_y) < 1e-12:  # through a cell corner: both cells beside it are touched
                    mark(i + sx, j)
                    mark(i, j + sy)
                    i += sx
                    j += sy
                    t_x += d_x
                    t_y += d_y
                elif t_x < t_y:
                    i += sx
                    t_x += d_x
                else:
                    j += sy
                    t_y += d_y
                mark(i, j)
    return barrier


BORDER_TOLERANCE = 0.1  # Douglas-Peucker tolerance of the drawn border lines, in hex units (world units)


def _clip_runs(line: Sequence[Tuple[float, float]], rect: Tuple[float, float, float, float]) -> List[list]:
    """The parts of a polyline inside the rectangle (min_x, min_y, max_x, max_y), Liang-Barsky per segment; a run
    continues across segments that stay inside and ends where the line leaves."""
    runs: List[list] = []
    run: list = []
    for (x1, y1), (x2, y2) in zip(line, line[1:]):
        t0, t1 = 0.0, 1.0
        dx, dy = x2 - x1, y2 - y1
        inside = True
        for p, q in ((-dx, x1 - rect[0]), (dx, rect[2] - x1), (-dy, y1 - rect[1]), (dy, rect[3] - y1)):
            if p == 0:
                if q < 0:
                    inside = False
                    break
            elif p < 0:
                t0 = max(t0, q / p)
            else:
                t1 = min(t1, q / p)
        if not inside or t0 >= t1:
            if len(run) >= 2:
                runs.append(run)
            run = []
            continue
        a = (x1, y1) if t0 == 0.0 else (x1 + t0 * dx, y1 + t0 * dy)
        b = (x2, y2) if t1 == 1.0 else (x1 + t1 * dx, y1 + t1 * dy)
        if t0 > 0.0 and len(run) >= 2:
            runs.append(run)
            run = []
        if not run:
            run = [a]
        run.append(b)
        if t1 < 1.0:
            runs.append(run)
            run = []
    if len(run) >= 2:
        runs.append(run)
    return runs


def simplify_line(points: Sequence[Tuple[float, float]], tolerance: float) -> List[Tuple[float, float]]:
    """Douglas-Peucker; the end points stay (a closed ring keeps its first point as the last)."""
    if len(points) < 3:
        return list(points)
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        lo, hi = stack.pop()
        (ax, ay), (bx, by) = points[lo], points[hi]
        length = math.hypot(bx - ax, by - ay)
        best, at = -1.0, lo
        for i in range(lo + 1, hi):
            px, py = points[i]
            if length == 0.0:
                d = math.hypot(px - ax, py - ay)
            else:
                d = abs((bx - ax) * (ay - py) - (ax - px) * (by - ay)) / length
            if d > best:
                best, at = d, i
        if best > tolerance:
            keep[at] = True
            stack += [(lo, at), (at, hi)]
    return [p for p, k in zip(points, keep) if k]


def border_polylines(layout: "HexLayout", lines: Dict[int, List[Tuple[float, float]]],
                     tolerance: float = BORDER_TOLERANCE) -> List[List[Tuple[float, float]]]:  # fmt: skip
    """The real country borders for drawing (TASK-113): projected border ways (way id -> [(E, N), ...]) clipped to the
    map's rectangle, chained end to end where exactly two ways meet, converted to world units (x east, z south, hex
    size 1, world (0, 0) = the centre of tile (0, 0)) and simplified (`tolerance` in hex units). Deterministic: ways
    in id order, each line starts at its smaller end point (x, then z), lines sorted by their first point."""
    m = layout.metres_per_unit
    min_e, min_n, max_e, max_n = layout.bounds()
    rect = ((min_e - layout.origin_e) / m, (layout.origin_n - max_n) / m,
            (max_e - layout.origin_e) / m, (layout.origin_n - min_n) / m)  # fmt: skip
    pieces: List[list] = []
    for way_id in sorted(lines):
        world = [((e - layout.origin_e) / m, (layout.origin_n - n) / m) for e, n in lines[way_id]]
        pieces += _clip_runs(world, rect)
    ends: Dict[Tuple[float, float], list] = {}
    for index, piece in enumerate(pieces):
        ends.setdefault(piece[0], []).append(index)
        ends.setdefault(piece[-1], []).append(index)
    used = [False] * len(pieces)

    def extend(chain: list) -> None:
        while chain[0] != chain[-1] or len(chain) < 3:
            owners = ends.get(chain[-1], [])
            if len(owners) != 2:
                return
            nxt = [i for i in owners if not used[i]]
            if not nxt:
                return
            used[nxt[0]] = True
            piece = pieces[nxt[0]]
            chain.extend((piece if piece[0] == chain[-1] else piece[::-1])[1:])

    result = []
    for index, piece in enumerate(pieces):
        if used[index]:
            continue
        used[index] = True
        chain = list(piece)
        extend(chain)
        if chain[0] != chain[-1]:
            chain.reverse()
            extend(chain)
        if chain[-1] < chain[0] and chain[0] != chain[-1]:
            chain.reverse()
        simple = simplify_line(chain, tolerance)
        if len(simple) >= 2:
            result.append(simple)
    result.sort(key=lambda line: (line[0], len(line)))
    return result


def fill_countries(rows: int, cols: int, barrier: bytearray, seeds: Sequence[Tuple[str, float, float]],
                   min_e: float, min_n: float, step: float) -> bytearray:  # fmt: skip
    """Country index (position in `seeds`, NO_COUNTRY = none) of every lattice point. `seeds` are (ISO code, easting,
    northing). A 4-connected flood fill from each seed over the non-barrier points owns its region; a barrier point
    then takes the country of the majority of its 4 neighbours (ties: the first country; none when no neighbour has
    one). A seed off the map or on a barrier point is an error, and so are two seeds in one region (a gap in the
    border line)."""
    owner = bytearray([NO_COUNTRY]) * (rows * cols)
    for index, (iso, e, n) in enumerate(seeds):
        i = int(round((e - min_e) / step))
        j = int(round((n - min_n) / step))
        if not (0 <= i < cols and 0 <= j < rows):
            raise ValueError("country %s: the seed point is off the map" % iso)
        start = j * cols + i
        if barrier[start]:
            raise ValueError("country %s: the seed point lies on the border line" % iso)
        if owner[start] != NO_COUNTRY:
            raise ValueError("countries %s and %s: two seeds in one region (a gap in the border line?)"
                             % (seeds[owner[start]][0], iso))  # fmt: skip
        owner[start] = index
        queue = deque([start])
        while queue:
            k = queue.popleft()
            ki, kj = k % cols, k // cols
            for nk, ok in ((k - 1, ki > 0), (k + 1, ki < cols - 1), (k - cols, kj > 0), (k + cols, kj < rows - 1)):
                if ok and not barrier[nk] and owner[nk] == NO_COUNTRY:
                    owner[nk] = index
                    queue.append(nk)
    settled = bytes(owner)  # barrier points read the fill, not each other
    for k in range(rows * cols):
        if not barrier[k]:
            continue
        ki, kj = k % cols, k // cols
        votes: Dict[int, int] = {}
        for nk, ok in ((k - 1, ki > 0), (k + 1, ki < cols - 1), (k - cols, kj > 0), (k + cols, kj < rows - 1)):
            if ok and settled[nk] != NO_COUNTRY:
                votes[settled[nk]] = votes.get(settled[nk], 0) + 1
        if votes:
            owner[k] = max(sorted(votes), key=lambda c: votes[c])  # first of the best: sorted, max keeps the first
    return owner


def hex_country(land_by_country: Sequence[int]) -> int:
    """Country index with the most land sample points of a hex (ties: the first), NO_COUNTRY without any."""
    best = NO_COUNTRY
    for index, count in enumerate(land_by_country):
        if count > 0 and (best == NO_COUNTRY or count > land_by_country[best]):
            best = index
    return best


# ---------------------------------------------------------------------------------------------------------------
# Graphic layers (TASK-126).

LAYER_WATER, LAYER_COVER, LAYER_RELIEF = "water", "cover", "relief"


def hillshade(heights: Sequence[float], cols: int, rows: int, cell_m: float, z: float = RELIEF_Z,
              azimuth: float = RELIEF_AZIMUTH, altitude: float = RELIEF_ALTITUDE) -> bytearray:  # fmt: skip
    """8-bit hillshade of a height grid (row-major, row 0 north, `cell_m` apart): Horn's 3 x 3 gradient (edge
    cells repeat the border), heights times `z`, Lambert shading towards the sun at `azimuth` (clockwise from
    north) and `altitude` degrees; flat ground is 255 * sin(altitude), facing away from the sun steeply is 0."""
    az, alt = math.radians(azimuth), math.radians(altitude)
    lx, ly, lz = math.cos(alt) * math.sin(az), math.cos(alt) * math.cos(az), math.sin(alt)  # x east, y north
    scale = z / (8.0 * cell_m)
    out = bytearray(cols * rows)
    for r in range(rows):
        north = heights[max(r - 1, 0) * cols : max(r - 1, 0) * cols + cols]
        mid = heights[r * cols : r * cols + cols]
        south = heights[min(r + 1, rows - 1) * cols : min(r + 1, rows - 1) * cols + cols]
        base = r * cols
        for c in range(cols):
            w, e = max(c - 1, 0), min(c + 1, cols - 1)
            a, b, cc = north[w], north[c], north[e]
            d, f = mid[w], mid[e]
            g, h, i = south[w], south[c], south[e]
            dx = ((cc + 2.0 * f + i) - (a + 2.0 * d + g)) * scale  # rise per metre towards the east
            dy = ((a + 2.0 * b + cc) - (g + 2.0 * h + i)) * scale  # rise per metre towards the north
            shade = (lz - dx * lx - dy * ly) / math.sqrt(dx * dx + dy * dy + 1.0)
            out[base + c] = 0 if shade <= 0.0 else min(255, int(255.0 * shade + 0.5))
    return out


def _png_filter_rows(width_bytes: int, height: int, data: bytes, adaptive: bool) -> bytes:
    """PNG scanlines (bpp 1): unfiltered, or (`adaptive`) each with the filter of the smallest sum of |signed
    bytes| (the usual heuristic; ties take the lower filter type), so the bytes depend only on the image."""
    out = bytearray()
    prior = bytes(width_bytes)
    for r in range(height):
        row = data[r * width_bytes : (r + 1) * width_bytes]
        if not adaptive:
            out.append(0)
            out.extend(row)
            continue
        left = b"\0" + row[:-1]
        up_left = b"\0" + prior[:-1]
        candidates = [
            bytes(row),
            bytes((x - a) & 0xFF for x, a in zip(row, left)),
            bytes((x - b) & 0xFF for x, b in zip(row, prior)),
            bytes((x - ((a + b) >> 1)) & 0xFF for x, a, b in zip(row, left, prior)),
            bytes((x - _paeth(a, b, c)) & 0xFF for x, a, b, c in zip(row, left, prior, up_left)),
        ]
        costs = [sum(v if v < 128 else 256 - v for v in cand) for cand in candidates]
        best = costs.index(min(costs))
        out.append(best)
        out.extend(candidates[best])
        prior = row
    return bytes(out)


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def png_gray(width: int, height: int, pixels: bytes, bit_depth: int = 8, filtered: bool = True) -> bytes:
    """Grayscale PNG of `pixels` (row-major, one byte per pixel). `bit_depth` 1 stores nonzero as white (decoders
    expand it to 0 / 255), 8 stores the bytes. `filtered` = adaptive PNG filters (smooth images such as the
    relief); class images (water, cover) compress better unfiltered (theatre cover: 219 KB instead of 341 KB)."""
    if bit_depth == 1:
        width_bytes = (width + 7) // 8
        packed = bytearray(width_bytes * height)
        for r in range(height):
            row = pixels[r * width : (r + 1) * width]
            for c in range(width):
                if row[c]:
                    packed[r * width_bytes + (c >> 3)] |= 0x80 >> (c & 7)
        data, row_bytes = bytes(packed), width_bytes
    elif bit_depth == 8:
        data, row_bytes = bytes(pixels), width
    else:
        raise ValueError("bit depth %d" % bit_depth)

    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, bit_depth, 0, 0, 0, 0)
    idat = zlib.compress(_png_filter_rows(row_bytes, height, data, filtered), 9)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


def downsample(values: Sequence[float], cols: int, rows: int, step: int) -> Tuple[List[float], int, int]:
    """Every `step`-th point of a row-major grid in both directions (from point 0), each the tent-weighted mean
    (weight step - |offset| per axis, edges clamped) of the points around it, so a coarser grid keeps its pixel
    centres on grid points without aliasing. Returns (values, cols, rows) of the coarse grid."""
    if step <= 1:
        return list(values), cols, rows
    out_cols, out_rows = (cols - 1) // step + 1, (rows - 1) // step + 1
    offsets = [(d, step - abs(d)) for d in range(1 - step, step)]
    across: List[float] = []  # pass 1: along the rows, at every row
    for r in range(rows):
        row = values[r * cols : (r + 1) * cols]
        for i in range(out_cols):
            c = i * step
            total = weight = 0.0
            for d, w in offsets:
                total += row[min(max(c + d, 0), cols - 1)] * w
                weight += w
            across.append(total / weight)
    out: List[float] = []
    for j in range(out_rows):
        r = j * step
        for i in range(out_cols):
            total = weight = 0.0
            for d, w in offsets:
                total += across[min(max(r + d, 0), rows - 1) * out_cols + i] * w
                weight += w
            out.append(total / weight)
    return out, out_cols, out_rows


def graphic_layers(cover: List[bytearray], heights: Sequence[float], min_e: float, min_n: float, step: float,
                   canopy: float = 0.0, relief_z: float = RELIEF_Z, relief_step: int = RELIEF_STEP) -> dict:  # fmt: skip
    """The three layers of the lattice as raw bytes (row-major, row 0 = the northernmost lattice row): `water`
    (1 / 0) and `cover` (COVER_CLASSES index) one pixel per lattice point, `relief` the hillshade of `heights` (the
    row-major lattice heights, south row first like `cover`, minus `canopy` on forest points - the DEM is a surface
    model) on every `relief_step`-th lattice point (`downsample`; relief pixel (i, j) lies on lattice pixel
    (i * relief_step, j * relief_step)). `origin_e` / `origin_n` are the projected metres of the centre of pixel
    (0, 0), the north-west one, of all three."""
    rows = len(cover)
    cols = len(cover[0]) if rows else 0
    water_class, forest_class = COVER_CLASSES.index("W"), COVER_CLASSES.index("F")
    cover_px = bytearray()
    ground: List[float] = []
    for r in range(rows):
        j = rows - 1 - r
        line = cover[j]
        cover_px.extend(line)
        base = j * cols
        ground.extend(heights[base + i] - (canopy if line[i] == forest_class else 0.0) for i in range(cols))
    water_px = bytearray(1 if v == water_class else 0 for v in cover_px)
    coarse, relief_cols, relief_rows = downsample(ground, cols, rows, relief_step)
    return {"width": cols, "height": rows, "pixel_m": step, "origin_e": min_e, "origin_n": min_n + (rows - 1) * step,
            "relief_step": relief_step, "relief_width": relief_cols, "relief_height": relief_rows,
            LAYER_WATER: water_px, LAYER_COVER: cover_px,
            LAYER_RELIEF: hillshade(coarse, relief_cols, relief_rows, step * relief_step, relief_z)}  # fmt: skip


def _load_osm(source: object) -> dict:
    if isinstance(source, dict):
        return source
    with open(str(source), encoding="utf-8") as f:
        return json.load(f)


def build_map(layout: HexLayout, zone: int, dem: Dem, osm: object, settings: Optional[Settings] = None,
              borders: object = None) -> dict:  # fmt: skip
    """Per-hex terrain, cover and elevation of the layout (see the module docstring). `osm` is one Overpass
    answer (dict or path) or a list of them (OSM tiles, loaded one at a time; areas and lines that appear in several
    tiles give the same result again, `_scanline_fill` and link masks are idempotent). `borders` is a list of
    borders-only answers (TASK-113) whose ways all count as country borders, added to the tagged border ways of `osm`."""
    settings = settings or Settings()
    profile = settings.profile
    step = settings.sample_m
    operational = profile is OPERATIONAL
    min_e, min_n, max_e, max_n = layout.bounds()
    cols = int(math.floor((max_e - min_e) / step)) + 1
    rows = int(math.floor((max_n - min_n) / step)) + 1
    cover = [bytearray(cols) for _ in range(rows)]
    links: Dict[str, set] = {ROAD: set(), RIVER: set()}
    coastlines: Dict[int, List[Tuple[float, float]]] = {}
    sources = osm if isinstance(osm, list) else [osm]
    country_seeds = [(iso, *to_utm(lat, lon, zone)) for iso, lat, lon in settings.countries]
    for iso, lat, lon in settings.default_countries:
        e, n = to_utm(lat, lon, zone)
        if min_e <= e <= max_e and min_n <= n <= max_n:
            country_seeds.append((iso, e, n))
    if len(country_seeds) > 10:
        raise ValueError("at most 10 countries (one digit each in country_rows)")
    border_lines: Dict[int, List[Tuple[float, float]]] = {}
    for index, source in enumerate(sources):
        if len(sources) > 1:
            print("OSM tile %d/%d %s" % (index + 1, len(sources), getattr(source, "name", "")), file=sys.stderr)
        data = _load_osm(source)
        for cls, rings in osm_areas(data, profile.tag_classes):
            projected = [[to_utm(lat, lon, zone) for lat, lon in ring] for ring in rings]
            _scanline_fill(cover, COVER_CLASSES.index(cls), projected, min_e, min_n, step)
        for kind, line in osm_lines(data, profile):
            links[kind].update(line_links(layout, [to_utm(lat, lon, zone) for lat, lon in line], profile.line_step_m))
        if operational:
            for way_id, line in osm_coastlines(data):
                coastlines[way_id] = [to_utm(lat, lon, zone) for lat, lon in line]
        if country_seeds:
            for way_id, line in osm_borders(data).items():
                border_lines[way_id] = [to_utm(lat, lon, zone) for lat, lon in line]
        del data
    for source in (borders if country_seeds and borders else []):
        for way_id, line in osm_borders(_load_osm(source), True).items():
            border_lines[way_id] = [to_utm(lat, lon, zone) for lat, lon in line]
    seeds = [to_utm(lat, lon, zone) for lat, lon in settings.sea_seeds]
    for lat, lon in settings.default_seeds:
        e, n = to_utm(lat, lon, zone)
        if min_e <= e <= max_e and min_n <= n <= max_n:
            seeds.append((e, n))
    sea_points = 0
    if seeds:
        sea_points = fill_sea(cover, [coastlines[k] for k in sorted(coastlines)], seeds, min_e, min_n, step)
    owner = bytearray()
    drawn: List[List[Tuple[float, float]]] = []
    if country_seeds:
        if not border_lines:
            raise ValueError("countries given but no border ways found (borders-only tiles missing?)")
        barrier = border_barrier(rows, cols, [border_lines[k] for k in sorted(border_lines)], min_e, min_n, step)
        owner = fill_countries(rows, cols, barrier, country_seeds, min_e, min_n, step)
        del barrier
        drawn = border_polylines(layout, border_lines)
    water_class = COVER_CLASSES.index("W")
    land_by_country: Dict[Tuple[int, int], List[int]] = {}
    samples: Dict[Tuple[int, int], List[Tuple[float, int]]] = {}
    heights = array("d", bytes(8 * rows * cols)) if settings.layers else None  # every lattice point (TASK-126)
    last_height = 0.0
    for j in range(rows):
        n = min_n + j * step
        cover_row = cover[j]
        for i in range(cols):
            e = min_e + i * step
            tile = layout.tile_at(e, n)
            if tile is None:
                if heights is not None:  # off the hexes (the jagged map edge): only drawn
                    lat, lon = from_utm(e, n, zone)
                    try:
                        last_height = dem.sample(lat, lon)
                    except ValueError:
                        pass  # no DEM there: repeat the last height
                    heights[j * cols + i] = last_height
                continue
            lat, lon = from_utm(e, n, zone)
            height = dem.sample(lat, lon)
            samples.setdefault(tile, []).append((height, cover_row[i]))
            if heights is not None:
                heights[j * cols + i] = last_height = height
            if country_seeds and cover_row[i] != water_class:
                index = owner[j * cols + i]
                if index != NO_COUNTRY:
                    land_by_country.setdefault(tile, [0] * len(country_seeds))[index] += 1
    tiles = {}
    for row in range(layout.height):
        for col in range(layout.width):
            points = samples.get((col, row), [])
            if not points:
                raise ValueError("hex %d,%d has no sample points (hex smaller than the lattice step?)" % (col, row))
            counts = [0] * len(COVER_CLASSES)
            for _, c in points:
                counts[c] += 1
            open_heights = sorted(h for h, c in points if COVER_CLASSES[c] not in "FUW")
            all_heights = sorted(h for h, _ in points)
            group = dominant_group(counts)
            if len(open_heights) >= len(points) / 4.0:
                mean = sum(open_heights) / len(open_heights)
                relief = _percentile(open_heights, 0.9) - _percentile(open_heights, 0.1)
            else:
                mean = sum(all_heights) / len(all_heights) - (settings.canopy if group == FOREST else 0.0)
                relief = _percentile(all_heights, 0.9) - _percentile(all_heights, 0.1)
            if operational:
                terrain = classify_operational(counts, relief, settings.water_share, settings.urban_share,
                                               settings.forest_share, settings.marsh_share, settings.hills_relief)  # fmt: skip
            else:
                terrain = classify(counts, relief, settings.hills_relief, settings.urban_share, settings.marsh_share)
            cover_char = "W" if group == WATER else "F" if group == FOREST else dominant_open_class(counts)
            tiles[(col, row)] = {"terrain": terrain, "cover": cover_char, "metres": round(mean, 1),
                                 "relief": round(relief, 1)}  # fmt: skip
    del samples
    unassigned = []
    for (col, row), t in sorted(tiles.items(), key=lambda item: (item[0][1], item[0][0])):
        t["country"] = hex_country(land_by_country.get((col, row), [])) if t["terrain"] != "water" else NO_COUNTRY
        if country_seeds and t["terrain"] != "water" and t["country"] == NO_COUNTRY:
            unassigned.append("%d,%d" % (col, row))
    if unassigned:
        raise ValueError("%d land hexes have no country (a leak in the border line or a missing seed); first: %s"
                         % (len(unassigned), "; ".join(unassigned[:5])))  # fmt: skip
    water = [tile for tile, t in tiles.items() if t["terrain"] == "water"]
    masks = {kind: store_links(layout, sorted(links[kind]), water) for kind in (ROAD, RIVER)}
    for tile, t in tiles.items():
        t["road"] = masks[ROAD].get(tile, 0)
        t["river"] = masks[RIVER].get(tile, 0)
    land = [t["metres"] for t in tiles.values() if t["terrain"] != "water"]
    low = min(land) if land else 0.0
    high = max(land) if land else 0.0
    scale = settings.exaggeration / layout.metres_per_unit
    if high > low:
        scale = min(scale, (TOP_ELEVATION - LAND_MIN) / (high - low))
    for t in tiles.values():
        if t["terrain"] == "water":
            t["elevation"] = WATER_ELEVATION
        else:
            t["elevation"] = LAND_MIN + (t["metres"] - low) * scale
    layers = None
    if heights is not None:
        layers = graphic_layers(cover, heights, min_e, min_n, step, settings.canopy, settings.relief_z,
                                settings.relief_step)  # fmt: skip
    return {"tiles": tiles, "reference_m": low, "vertical_scale": scale, "sea_points": sea_points,
            "countries": [iso for iso, _, _ in country_seeds], "border_lines": drawn, "layers": layers}  # fmt: skip


# ---------------------------------------------------------------------------------------------------------------
# Tactical layer of a whole theatre (TASK-094b, ADR 0018 "Tactical layer"): 250 m hexes everywhere, in chunks.


_RAISE_TABLES = [bytes(max(v, k) for k in range(256)) for v in range(256)]


def _scanline_fill_fast(grid: List[bytearray], value: int, rings: List[List[Tuple[float, float]]],
                        min_e: float, min_n: float, step: float) -> None:  # fmt: skip
    """`_scanline_fill` with edges bucketed by lattice row and spans raised by slice translation: the same points
    (half-open edge rule, even-odd), fast enough for a theatre-wide 50 m lattice."""
    rows = len(grid)
    cols = len(grid[0]) if rows else 0
    starts: Dict[int, list] = {}
    for ring in rings:
        for k in range(len(ring) - 1):
            (e1, n1), (e2, n2) = ring[k], ring[k + 1]
            if n1 == n2:
                continue
            lo, hi = (n1, n2) if n1 < n2 else (n2, n1)
            j0 = max(0, int(math.ceil((lo - min_n) / step)))
            j1 = min(rows - 1, int(math.ceil((hi - min_n) / step)) - 1)  # n < hi: the half-open rule
            if j0 <= j1:
                starts.setdefault(j0, []).append((j1, e1, n1, (e2 - e1) / (n2 - n1)))
    if not starts:
        return
    table = _RAISE_TABLES[value]
    active: list = []
    for j in range(min(starts), rows):
        if j in starts:
            active.extend(starts.pop(j))
        if not active:
            if not starts:
                break
            continue
        n = min_n + j * step
        xs = []
        keep = []
        for edge in active:
            j1, e1, n1, slope = edge
            xs.append(e1 + (n - n1) * slope)
            if j1 > j:
                keep.append(edge)
        active = keep
        xs.sort()
        row = grid[j]
        for k in range(0, len(xs) - 1, 2):
            i0 = max(0, int(math.ceil((xs[k] - min_e) / step)))
            i1 = min(cols - 1, int(math.floor((xs[k + 1] - min_e) / step)))
            if i0 <= i1:
                row[i0 : i1 + 1] = row[i0 : i1 + 1].translate(table)


def _hex_pattern(spacing: float, step: float) -> List[Tuple[float, float]]:
    """Offsets (east, north metres) of a triangular lattice of `step` inside a pointy-top hex of `spacing`
    (flat-to-flat east-west), the centre included: the cover sample points of one tactical-layer hex."""
    half_w = spacing / 2.0 - 1e-6
    radius = spacing / SQRT3 - 1e-6
    dz = step * SQRT3 / 2.0
    points = []
    reach = int(radius / dz) + 1
    for j in range(-reach, reach + 1):
        n = j * dz
        shift = 0.5 if j % 2 else 0.0
        for i in range(-reach - 1, reach + 2):
            e = (i + shift) * step
            if abs(e) < half_w and abs(n) < radius - abs(e) / SQRT3:
                points.append((e, n))
    return points


def build_layer(layout: HexLayout, zone: int, dem: Dem, osm: object, settings: Settings) -> dict:
    """Per-hex terrain, road / river links and DEM height (metres) of a theatre-wide tactical layout, as flat
    row-major arrays (`terrain` LAYER_TERRAIN_CODES, `road`, `river` link masks, `metres`). Same inputs as the
    operational profile (OSM tiles loaded one at a time, the sea filled from the coastline); per hex the cover
    classes of `_hex_pattern` points of the `settings.sample_m` lattice and the DEM at the centre and six points
    LAYER_DEM_RADIUS_M around it give `classify` (the tactical rules) and the height (open points, or all minus
    the canopy for a forest hex). Nothing per lattice point is kept besides the cover lattice."""
    step = settings.sample_m
    min_e, min_n, max_e, max_n = layout.bounds()
    cols = int(math.floor((max_e - min_e) / step)) + 1
    rows = int(math.floor((max_n - min_n) / step)) + 1
    cover = [bytearray(cols) for _ in range(rows)]
    links: Dict[str, set] = {ROAD: set(), RIVER: set()}
    coastlines: Dict[int, List[Tuple[float, float]]] = {}
    sources = osm if isinstance(osm, list) else [osm]
    for index, source in enumerate(sources):
        if len(sources) > 1:
            print("OSM tile %d/%d %s" % (index + 1, len(sources), getattr(source, "name", "")), file=sys.stderr)
        data = _load_osm(source)
        for cls, rings in osm_areas(data, settings.profile.tag_classes):
            projected = [[to_utm(lat, lon, zone) for lat, lon in ring] for ring in rings]
            _scanline_fill_fast(cover, COVER_CLASSES.index(cls), projected, min_e, min_n, step)
        for kind, line in osm_lines(data, settings.profile):
            projected_line = [to_utm(lat, lon, zone) for lat, lon in line]
            links[kind].update(line_links(layout, projected_line, settings.profile.line_step_m))
        for way_id, line in osm_coastlines(data):
            coastlines[way_id] = [to_utm(lat, lon, zone) for lat, lon in line]
        del data
    seeds = [to_utm(lat, lon, zone) for lat, lon in settings.sea_seeds]
    for lat, lon in settings.default_seeds:
        e, n = to_utm(lat, lon, zone)
        if min_e <= e <= max_e and min_n <= n <= max_n:
            seeds.append((e, n))
    sea_points = 0
    if seeds:
        sea_points = fill_sea(cover, [coastlines[k] for k in sorted(coastlines)], seeds, min_e, min_n, step)
    width, height = layout.width, layout.height
    pattern = [((de / step), (dn / step)) for de, dn in _hex_pattern(layout.spacing, step)]
    ring = [(0.0, 0.0)] + [(LAYER_DEM_RADIUS_M * math.cos(math.radians(30 + 60 * k)),
                            LAYER_DEM_RADIUS_M * math.sin(math.radians(30 + 60 * k))) for k in range(6)]  # fmt: skip
    terrain = bytearray(width * height)
    metres = array("f", bytes(4 * width * height))
    reliefs = array("f", bytes(4 * width * height))  # open hexes' relief, for tuning --hills-relief
    closed = {COVER_CLASSES.index(c) for c in "FUW"}
    n_classes = len(COVER_CLASSES)
    for row in range(height):
        if row % 128 == 0:
            print("layer row %d/%d" % (row, height), file=sys.stderr)
        for col in range(width):
            e, n = layout.centre(col, row)
            fi = (e - min_e) / step + 0.5
            fj = (n - min_n) / step + 0.5
            counts = [0] * n_classes
            for di, dj in pattern:
                counts[cover[int(fj + dj)][int(fi + di)]] += 1
            lat, lon = from_utm(e, n, zone)
            lat_e, lon_e = from_utm(e + 100.0, n, zone)
            lat_n, lon_n = from_utm(e, n + 100.0, zone)
            open_heights = []
            all_heights = []
            for de, dn in ring:
                h = dem.sample(lat + ((lat_e - lat) * de + (lat_n - lat) * dn) / 100.0,
                               lon + ((lon_e - lon) * de + (lon_n - lon) * dn) / 100.0)  # fmt: skip
                all_heights.append(h)
                if cover[int(fj + dn / step)][int(fi + de / step)] not in closed:
                    open_heights.append(h)
            group = dominant_group(counts)
            if len(open_heights) >= len(ring) / 4.0:
                open_heights.sort()
                mean = sum(open_heights) / len(open_heights)
                relief = _percentile(open_heights, 0.9) - _percentile(open_heights, 0.1)
            else:
                all_heights.sort()
                mean = sum(all_heights) / len(all_heights) - (settings.canopy if group == FOREST else 0.0)
                relief = _percentile(all_heights, 0.9) - _percentile(all_heights, 0.1)
            kind = classify(counts, relief, settings.hills_relief, settings.urban_share, settings.marsh_share)
            terrain[row * width + col] = LAYER_TERRAIN_CODES[kind]
            metres[row * width + col] = mean
            reliefs[row * width + col] = relief
    del cover
    masks = {}
    water = LAYER_TERRAIN_CODES["water"]
    for kind in (ROAD, RIVER):
        mask = bytearray(width * height)
        for a, b in sorted(links[kind]):
            for src, dst in ((a, b), (b, a)):
                col, row = layout.offset(*src)
                if not layout.on_map(col, row) or terrain[row * width + col] == water:
                    continue
                mask[row * width + col] |= 1 << HEX_DIRECTIONS.index((dst[0] - src[0], dst[1] - src[1]))
        masks[kind] = mask
    return {"terrain": terrain, "road": masks[ROAD], "river": masks[RIVER], "metres": metres, "relief": reliefs,
            "sea_points": sea_points}  # fmt: skip


def layer_chunk_bytes(result: dict, width: int, x0: int, y0: int, w: int, h: int) -> bytes:
    """One chunk (columns x0 .. x0 + w - 1, rows y0 .. y0 + h - 1), zlib level 9 of the planes: terrain codes,
    road masks, river masks, then the heights as uint16 (LAYER_ELEVATION_OFFSET_M / _STEP_M) low bytes, high
    bytes; each plane row-major, row 0 north (TacticalChunk)."""
    terrain, road, river = bytearray(), bytearray(), bytearray()
    low, high = bytearray(), bytearray()
    for row in range(y0, y0 + h):
        a, b = row * width + x0, row * width + x0 + w
        terrain += result["terrain"][a:b]
        road += result["road"][a:b]
        river += result["river"][a:b]
        for m in result["metres"][a:b]:
            v = min(65535, max(0, int(round((m + LAYER_ELEVATION_OFFSET_M) / LAYER_ELEVATION_STEP_M))))
            low.append(v & 0xFF)
            high.append(v >> 8)
    return zlib.compress(bytes(terrain + road + river + low + high), 9)


def write_layer(out_dir: Path, name: str, display_name: str, layout: HexLayout, zone: int, result: dict,
                bbox: Tuple[float, float, float, float], settings: Settings, sources: str) -> int:  # fmt: skip
    """`<out_dir>/layer.tres` (TacticalLayer) and one `chunk_<cx>_<cy>.tres` (TacticalChunk) per LAYER_CHUNK square;
    old chunk files are removed first. Returns the total size in bytes."""
    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("chunk_*.tres"):
        old.unlink()
    lines = [
        '[gd_resource type="Resource" script_class="TacticalLayer" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="res://src/core/data/tactical_layer.gd" id="1_layer"]',
        "",
        "[resource]",
        'script = ExtResource("1_layer")',
        "id = &%s" % _string(name),
        "display_name = %s" % _string(display_name),
        "width = %d" % layout.width,
        "height = %d" % layout.height,
        "chunk_size = %d" % LAYER_CHUNK,
        "hex_spacing_m = %s" % _f(layout.spacing, 1),
        "crs = %s" % _string("EPSG:%d" % (32600 + zone)),
        "origin_easting = %s" % _f(layout.origin_e, 1),
        "origin_northing = %s" % _f(layout.origin_n, 1),
        "bbox_wgs84 = PackedFloat64Array(%s)" % ", ".join(_f(v, 5) for v in bbox),
        "elevation_offset_m = %s" % _f(LAYER_ELEVATION_OFFSET_M, 1),
        "elevation_step_m = %s" % _f(LAYER_ELEVATION_STEP_M, 2),
        "land_min = %s" % _f(LAND_MIN, 3),
        "top_elevation = %s" % _f(TOP_ELEVATION, 3),
        "water_elevation = %s" % _f(WATER_ELEVATION, 3),
        "exaggeration = %s" % _f(settings.exaggeration, 3),
        "sources = %s" % _string(sources),
        "",
    ]
    index = out_dir / "layer.tres"
    with open(index, "w", encoding="utf-8", newline="\n") as out:
        out.write("\n".join(lines))
    total = index.stat().st_size
    for cy in range(0, layout.height, LAYER_CHUNK):
        for cx in range(0, layout.width, LAYER_CHUNK):
            w = min(LAYER_CHUNK, layout.width - cx)
            h = min(LAYER_CHUNK, layout.height - cy)
            data = layer_chunk_bytes(result, layout.width, cx, cy, w, h)
            chunk = [
                '[gd_resource type="Resource" script_class="TacticalChunk" load_steps=2 format=3]',
                "",
                '[ext_resource type="Script" path="res://src/core/data/tactical_chunk.gd" id="1_chunk"]',
                "",
                "[resource]",
                'script = ExtResource("1_chunk")',
                "column = %d" % cx,
                "row = %d" % cy,
                "width = %d" % w,
                "height = %d" % h,
                'data = PackedByteArray("%s")' % base64.b64encode(data).decode("ascii"),
                "",
            ]
            path = out_dir / ("chunk_%d_%d.tres" % (cx // LAYER_CHUNK, cy // LAYER_CHUNK))
            with open(path, "w", encoding="utf-8", newline="\n") as out:
                out.write("\n".join(chunk))
            total += path.stat().st_size
    return total


# ---------------------------------------------------------------------------------------------------------------
# Output.


def _f(value: float, decimals: int) -> str:
    text = "%.*f" % (decimals, value)
    return "0." + "0" * decimals if text.startswith("-") and float(text) == 0.0 else text


def _string(text: str) -> str:
    return '"%s"' % text.replace("\\", "\\\\").replace('"', '\\"')


def write_tres(path: Path, name: str, display_name: str, layout: HexLayout, zone: int, result: dict,
               bbox: Tuple[float, float, float, float], sources: str = SOURCES) -> None:  # fmt: skip
    tiles = result["tiles"]
    terrain_rows, cover_rows, road_rows, river_rows, metres, elevation = [], [], [], [], [], []
    for row in range(layout.height):
        terrain_rows.append("".join(TERRAIN_CHARS[tiles[(c, row)]["terrain"]] for c in range(layout.width)))
        cover_rows.append("".join(tiles[(c, row)]["cover"] for c in range(layout.width)))
        road_rows.append("".join(LINK_CHARS[tiles[(c, row)].get("road", 0)] for c in range(layout.width)))
        river_rows.append("".join(LINK_CHARS[tiles[(c, row)].get("river", 0)] for c in range(layout.width)))
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
        "road_rows = PackedStringArray(%s)" % ", ".join(_string(r) for r in road_rows),
        "river_rows = PackedStringArray(%s)" % ", ".join(_string(r) for r in river_rows),
        "elevation_m = PackedFloat32Array(%s)" % ", ".join(metres),
        "elevation = PackedFloat32Array(%s)" % ", ".join(elevation),
        "sources = %s" % _string(sources),
        "",
    ]
    if result.get("countries"):
        country_rows = ["".join("." if tiles[(c, row)]["country"] == NO_COUNTRY else str(tiles[(c, row)]["country"])
                                for c in range(layout.width)) for row in range(layout.height)]  # fmt: skip
        at = lines.index("elevation_m = PackedFloat32Array(%s)" % ", ".join(metres))
        lines[at:at] = [
            "countries = PackedStringArray(%s)" % ", ".join(_string(c) for c in result["countries"]),
            "country_rows = PackedStringArray(%s)" % ", ".join(_string(r) for r in country_rows),
        ]
        if result.get("border_lines"):
            lines[at + 2:at + 2] = ["border_lines = Array[PackedVector2Array]([%s])" % ", ".join(
                "PackedVector2Array(%s)" % ", ".join("%s, %s" % (_f(x, 3), _f(z, 3)) for x, z in line)
                for line in result["border_lines"])]  # fmt: skip
    layers = result.get("layers")
    if layers:
        at = lines.index("sources = %s" % _string(sources)) + 1
        width, height = layers["width"], layers["height"]
        lines[at:at] = [
            "layer_width = %d" % width,
            "layer_height = %d" % height,
            "layer_pixel_m = %s" % _f(layers["pixel_m"], 3),
            "layer_origin_easting = %s" % _f(layers["origin_e"], 3),
            "layer_origin_northing = %s" % _f(layers["origin_n"], 3),
            "layer_relief_step = %d" % layers["relief_step"],
        ] + [
            "layer_%s_png = PackedByteArray(\"%s\")" % (kind, base64.b64encode(png).decode("ascii")) for kind, png in (
                (LAYER_WATER, png_gray(width, height, layers[LAYER_WATER], 1, False)),
                (LAYER_COVER, png_gray(width, height, layers[LAYER_COVER], 8, False)),
                (LAYER_RELIEF, png_gray(layers["relief_width"], layers["relief_height"], layers[LAYER_RELIEF])))
        ]  # fmt: skip
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
    with urllib.request.urlopen(request, timeout=1000) as response, open(tmp, "wb") as out:
        while True:
            chunk = response.read(1 << 20)
            if not chunk:
                break
            out.write(chunk)
    tmp.replace(target)


def dem_paths(cache: Path, south: float, west: float, north: float, east: float, offline: bool,
              dem: str = "glo30") -> List[Path]:  # fmt: skip
    paths = []
    for lat in range(int(math.floor(south)), int(math.floor(north)) + 1):
        for lon in range(int(math.floor(west)), int(math.floor(east)) + 1):
            name = copernicus_tile_name(lat, lon, dem)
            path = cache / "dem" / (name + ".tif")
            if not path.exists():
                if offline:
                    raise SystemExit("missing DEM tile %s (run without --offline to download it)" % path)
                _download(DEM_URLS[dem].format(name=name), path)
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


def osm_tiles(south: float, west: float, north: float, east: float, deg: float) -> List[Tuple[float, float]]:
    """South-west corners (lat, lon) of the `deg` x `deg` tiles, on a grid aligned to multiples of `deg`, that
    cover the bbox; sorted south to north, then west to east."""
    def index(value: float) -> int:
        return int(math.floor(value / deg + 1e-9))

    return [(round(i * deg, 6), round(k * deg, 6)) for i in range(index(south), index(north - 1e-9) + 1)
            for k in range(index(west), index(east - 1e-9) + 1)]  # fmt: skip


def osm_tile_path(cache: Path, lat: float, lon: float, deg: float) -> Path:
    return cache / "osm" / ("%s_%.4f_%.4f_%.4f.json" % (OP_QUERY_VERSION, lat, lon, deg))


def _check_overpass_answer(path: Path) -> None:
    """Raises when a downloaded Overpass answer is not complete JSON (an error page, or a 200 answer whose
    `remark` reports a runtime error such as a timeout - its data would be cut off)."""
    with open(path, "rb") as f:
        head = f.read(64).lstrip()
        f.seek(0, os.SEEK_END)
        f.seek(max(0, f.tell() - 4096))
        tail = f.read()
    if not head.startswith(b"{") or not tail.rstrip().endswith(b"}"):
        raise ValueError("not an Overpass JSON answer: %r" % head[:40])
    if b'"remark"' in tail and b"error" in tail:
        remark = tail[tail.index(b'"remark"') :][:300].decode("utf-8", "replace")
        raise ValueError("Overpass reported an error: %s" % remark)


def _fetch_tile(path: Path, lat: float, lon: float, deg: float) -> None:
    _fetch_answer(path, operational_query(lat, lon, lat + deg, lon + deg))


def _fetch_answer(path: Path, query: str) -> None:
    tmp = path.with_name(path.name + ".check")
    _download(OVERPASS_URL, tmp, urllib.parse.urlencode({"data": query}).encode("utf-8"))
    try:
        _check_overpass_answer(tmp)
    except ValueError:
        tmp.unlink()
        raise
    tmp.replace(path)


def border_tile_path(cache: Path, lat: float, lon: float, deg: float) -> Path:
    return cache / "osm" / ("%s_%.4f_%.4f_%.4f.json" % (BORDER_QUERY_VERSION, lat, lon, deg))


def _fetch_border_tile(path: Path, lat: float, lon: float, deg: float) -> None:
    _fetch_answer(path, border_query(lat, lon, lat + deg, lon + deg))


def _cached_tiles(cache: Path, south: float, west: float, north: float, east: float, offline: bool, deg: float,
                  path_of, fetch, what: str) -> List[Path]:  # fmt: skip
    """The cached tile files of the bbox, downloading missing ones one by one (each retried DOWNLOAD_RETRIES times
    after a pause that doubles each time); finished tiles are never fetched again, so a failed run continues where it stopped."""
    paths = []
    tiles = osm_tiles(south, west, north, east, deg)
    for lat, lon in tiles:
        path = path_of(cache, lat, lon, deg)
        if not path.exists():
            name = "%s tile %.4f N %.4f E (%.4f deg) %s" % (what, lat, lon, deg, path)
            if offline:
                raise SystemExit("missing %s (run without --offline to download it)" % name)
            for attempt in range(DOWNLOAD_RETRIES + 1):
                try:
                    started = time.time()
                    fetch(path, lat, lon, deg)
                    print("  %d/%d: %.1f MB in %.0f s" % (len(paths) + 1, len(tiles), path.stat().st_size / 1e6,
                          time.time() - started), file=sys.stderr)  # fmt: skip
                    break
                except (OSError, ValueError) as error:
                    if attempt == DOWNLOAD_RETRIES:
                        raise SystemExit("%s failed %d times: %s (re-run to continue)" % (name, attempt + 1, error))
                    pause = RETRY_PAUSE_S * 2**attempt  # 60, 120, 240 s: the public server's 502 / 429 last minutes
                    print("%s failed (%s), retrying in %.0f s" % (name, error, pause), file=sys.stderr)
                    time.sleep(pause)
        paths.append(path)
    return paths


def osm_tile_paths(cache: Path, south: float, west: float, north: float, east: float, offline: bool,
                   deg: float = OSM_TILE_DEG) -> List[Path]:  # fmt: skip
    """The cached land-cover OSM tiles of the bbox (see `_cached_tiles`)."""
    return _cached_tiles(cache, south, west, north, east, offline, deg, osm_tile_path, _fetch_tile, "OSM")


def border_tile_paths(cache: Path, south: float, west: float, north: float, east: float, offline: bool,
                      deg: float = OSM_TILE_DEG) -> List[Path]:  # fmt: skip
    """The cached borders-only tiles of the bbox (TASK-113), same tiling as `osm_tile_paths`; the land-cover tiles
    are never touched."""
    return _cached_tiles(cache, south, west, north, east, offline, deg, border_tile_path, _fetch_border_tile,
                         "OSM border")  # fmt: skip


def parse_countries(values: Sequence[str]) -> List[Tuple[str, float, float]]:
    """`ISO:lat,lon[,ISO:lat,lon...]` (the option is repeatable) -> [(ISO, lat, lon)] in the given order."""
    result = []
    for value in values:
        tokens = [t.strip() for t in value.split(",") if t.strip()]
        k = 0
        while k < len(tokens):
            if ":" not in tokens[k] or k + 1 >= len(tokens):
                raise ValueError("--countries expects ISO:lat,lon, got %r" % value)
            iso, lat = tokens[k].split(":", 1)
            try:
                result.append((iso, float(lat), float(tokens[k + 1])))
            except ValueError:
                raise ValueError("--countries expects ISO:lat,lon, got %r" % value)
            k += 2
    for iso, _, _ in result:
        if len(iso) != 2 or not iso.isalpha() or not iso.isupper():
            raise ValueError("country code %r is not two upper-case letters" % iso)
    if len({iso for iso, _, _ in result}) != len(result):
        raise ValueError("duplicate country code in --countries")
    return result


def _countries_on_map(countries: Sequence[Tuple[str, float, float]], layout: HexLayout, zone: int) -> bool:
    min_e, min_n, max_e, max_n = layout.bounds()
    for _, lat, lon in countries:
        e, n = to_utm(lat, lon, zone)
        if min_e <= e <= max_e and min_n <= n <= max_n:
            return True
    return False


def _pair(text: str, sep: str, kind: type) -> Tuple:
    parts = text.split(sep)
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("expected two values separated by '%s': %s" % (sep, text))
    return kind(parts[0]), kind(parts[1])


def run(argv: Sequence[str]) -> Path:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("bbox", nargs="?", help="min_lon,min_lat,max_lon,max_lat (WGS84 degrees)")
    parser.add_argument("--profile", choices=sorted(PROFILES), default="tactical",
                        help="map scale: tactical (250 m hexes) or operational (5 km hexes, TASK-092a)")  # fmt: skip
    parser.add_argument("--center", help="lat,lon of the map centre (default: the bbox centre)")
    parser.add_argument("--size", help="columns x rows, e.g. 30x24 (default: from the bbox extent)")
    parser.add_argument("--hex", type=float, help="metres between neighbouring hex centres (250 / 5000)")
    parser.add_argument("--sample", type=float, help="metres between lattice sample points (25 / 250)")
    parser.add_argument("--name", required=True, help="map id (data/maps/<id>.tres)")
    parser.add_argument("--display-name", default="", help="name shown to the player (default: the id)")
    parser.add_argument("--out", required=True)
    parser.add_argument("--cache", default=str(DEFAULT_CACHE))
    parser.add_argument("--offline", action="store_true", help="never download; fail on a missing cache file")
    parser.add_argument("--dem", action="append", default=[],
                        help="glo30 / glo90 (the cached Copernicus DEM, default per profile), or a DEM GeoTIFF "
                             "instead of the cache (repeatable)")  # fmt: skip
    parser.add_argument("--osm", help="Overpass JSON instead of the cache")
    parser.add_argument("--tile-deg", type=float, default=OSM_TILE_DEG, help="OSM tile size in degrees (operational)")
    parser.add_argument("--sea-seed", action="append", default=[],
                        help="lat,lon of a sea point; the sea is filled from it up to the coastline (repeatable; "
                             "operational default: %s)" % "; ".join("%.2f,%.2f" % s for s in OP_SEA_SEEDS))  # fmt: skip
    parser.add_argument("--hills-relief", type=float, help="metres of in-hex relief that make HILLS (15 / 35)")
    parser.add_argument("--canopy", type=float, default=15.0, help="metres a mostly forested hex's DSM is lowered")
    parser.add_argument("--exaggeration", type=float, default=1.5, help="vertical exaggeration of the 3D relief")
    parser.add_argument("--urban-share", type=float, help="built-up share of a hex for URBAN (0.20 / 0.15)")
    parser.add_argument("--marsh-share", type=float, default=MARSH_SHARE, help="wetland share of a hex for MARSH")
    parser.add_argument("--water-share", type=float, default=OP_WATER_SHARE, help="water share for WATER (operational)")
    parser.add_argument("--forest-share", type=float, default=OP_FOREST_SHARE,
                        help="forest share for FOREST (operational)")  # fmt: skip
    parser.add_argument("--countries", action="append", default=[],
                        help="ISO:lat,lon[,ISO:lat,lon...] - the countries to assign to the hexes, each with a seed "
                             "point inside it (repeatable; operational default: %s; tactical maps have none)"
                             % ",".join("%s:%.2f,%.2f" % c for c in OP_COUNTRIES))  # fmt: skip
    parser.add_argument("--relief-z", type=float, default=RELIEF_Z,
                        help="vertical exaggeration of the relief layer's hillshade (operational, TASK-126)")  # fmt: skip
    parser.add_argument("--relief-step", type=int, default=RELIEF_STEP,
                        help="lattice points per relief pixel (operational, TASK-126; 2 = 500 m)")  # fmt: skip
    args = parser.parse_args(argv)
    profile = PROFILES[args.profile]
    try:
        countries = parse_countries(args.countries)
    except ValueError as error:
        parser.error(str(error))
    if countries and profile is not OPERATIONAL:
        parser.error("--countries needs --profile=operational")
    hex_m = args.hex if args.hex is not None else profile.hex_m
    dem_kind = profile.dem
    dem_files = []
    for value in args.dem:
        if value in DEM_URLS:
            dem_kind = value
        else:
            dem_files.append(Path(value))
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
        width = max(1, int(round((e_e - w_e) / hex_m)))
        height = max(1, int(round((n_n - s_n) / (hex_m * SQRT3 / 2.0))))
    else:
        parser.error("give --size with --center")
    if width < 1 or height < 1:
        parser.error("size must be positive")
    layout = HexLayout.centred(width, height, hex_m, centre_e, centre_n)
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
    started = time.time()
    dem_files = dem_files or dem_paths(cache, south, west, north, east, args.offline, dem_kind)
    osm: object
    if args.osm:
        osm = Path(args.osm)
    elif profile.tiled:
        osm = osm_tile_paths(cache, south, west, north, east, args.offline, args.tile_deg)
    else:
        osm = osm_path(cache, south, west, north, east, args.offline)
    border_files = None
    if profile.tiled and not args.osm and (countries or (profile is OPERATIONAL and _countries_on_map(
            OP_COUNTRIES, layout, zone))):  # fmt: skip
        border_files = border_tile_paths(cache, south, west, north, east, args.offline, args.tile_deg)
    downloaded = time.time()
    settings = Settings(profile, args.sample, args.hills_relief, args.canopy, args.exaggeration, args.water_share,
                        args.urban_share, args.forest_share, args.marsh_share,
                        [_pair(s, ",", float) for s in args.sea_seed],
                        OP_SEA_SEEDS if profile in (OPERATIONAL, LAYER) and not args.sea_seed else (),
                        countries, OP_COUNTRIES if profile is OPERATIONAL and not countries else (),
                        relief_z=args.relief_z, relief_step=args.relief_step)  # fmt: skip
    out = Path(args.out)
    sources = SOURCES_GLO90 if dem_kind == "glo90" else SOURCES
    if profile is LAYER:
        layer = build_layer(layout, zone, Dem(dem_files), osm, settings)
        size = write_layer(out, args.name, args.display_name or args.name, layout, zone, layer, map_bbox, settings,
                           sources)  # fmt: skip
        counts = [layer["terrain"].count(code) for code in range(len(LAYER_TERRAIN_CODES))]
        print("Wrote %s: %dx%d hexes of %.0f m in chunks of %d, %s; %d hexes with roads, %d river hexes; %.2f MB; "
              "%d sea points; inputs %.0f s, import %.0f s" % (out, width, height, hex_m, LAYER_CHUNK, ", ".join(
                  "%s %d" % (k, counts[v]) for k, v in sorted(LAYER_TERRAIN_CODES.items())),
                  sum(1 for m in layer["road"] if m), sum(1 for m in layer["river"] if m), size / 1e6,
                  layer["sea_points"], downloaded - started, time.time() - downloaded))  # fmt: skip
        return out
    result = build_map(layout, zone, Dem(dem_files), osm, settings, border_files)
    write_tres(out, args.name, args.display_name or args.name, layout, zone, result, map_bbox, sources)
    counts: Dict[str, int] = {}
    for t in result["tiles"].values():
        counts[t["terrain"]] = counts.get(t["terrain"], 0) + 1
    roads = sum(1 for t in result["tiles"].values() if t["road"])
    rivers = sum(1 for t in result["tiles"].values() if t["river"])
    print("Wrote %s: %dx%d hexes of %.0f m, %s; %d hexes with roads, %d river hexes" % (out, width, height,
          hex_m, ", ".join("%s %d" % (k, counts[k]) for k in sorted(counts)), roads, rivers))  # fmt: skip
    if result["countries"]:
        owned = [sum(1 for t in result["tiles"].values() if t["country"] == k) for k in range(len(result["countries"]))]
        print("Countries: %s" % ", ".join("%s %d" % (iso, n) for iso, n in zip(result["countries"], owned)))
    if result.get("layers"):
        layers = result["layers"]
        print("Graphic layers: %dx%d px of %.0f m, water %d px; file %.2f MB" % (layers["width"], layers["height"],
              layers["pixel_m"], sum(layers[LAYER_WATER]), out.stat().st_size / 1e6))  # fmt: skip
    if profile is OPERATIONAL:
        print("Operational import: %d sea points filled; inputs %.0f s, import %.0f s" % (result["sea_points"],
              downloaded - started, time.time() - downloaded))  # fmt: skip
    return out


if __name__ == "__main__":
    run(sys.argv[1:])
