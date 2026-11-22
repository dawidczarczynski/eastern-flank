"""Satellite colour layer of tactical maps and the tactical layer (TASK-192a, ADR 0031). Python 3.8, stdlib only.

Source: Copernicus Sentinel-2 Level-2A (bottom-of-atmosphere reflectance, 10 m), the Cloud-Optimized GeoTIFFs of
the "Sentinel-2 Collection 1 Level-2A" on AWS, found through the Earth Search STAC API (`S2_STAC_URL`,
collection `S2_COLLECTION`). Free, full and open under the Copernicus Sentinel data terms (attribution
"Contains modified Copernicus Sentinel data <year>", see data/maps/CREDITS).

Offline-repeatable cache (`<cache>/s2/`, outside git, like the DEM and OSM inputs):
- `s2v1_<s>_<w>_<n>_<e>.json` - the scene manifest of an area: the summer scenes `s2_search` found (fixed seasons
  `S2_SEASONS`, scene cloud cover below `S2_MAX_CLOUD`, the `S2_SCENES_PER_ORBIT` least cloudy per MGRS tile and relative orbit), in
  priority order (`select_scenes`), with their band URLs and the reflectance scale / offset of the STAC metadata. Written once; later runs
  (and `--offline`) read it, so the same scenes are used again.
- `<scene id>/<band>_L<level>.tif` - a band file (B04 red, B03 green, B02 blue, SCL scene classification) cut
  after the data of overview `level` (COG overviews lie before the full resolution in the file: level 2 of a 10 m
  band, the 40 m overview, is ~5 MB of the ~80 MB file); level 0 is the whole file. A file of a finer level
  serves every coarser one.

Composite (`composite`): output pixels of `cell` metres in the map's UTM zone, row 0 north. Each band is read
at its coarsest overview not coarser than the cell (GDAL AVERAGE overviews; the SCL ones are MODE), nearest
pixel. Every pixel takes the first scene in manifest order whose SCL says clear ground (`S2_CLEAR`: dark
area, vegetation, not vegetated, water) - a scene that would add less than `S2_MIN_SHARE` of the pixels is
skipped there (one date fewer: SCL flags stray bright fields as cloud) -; a pixel no scene sees clear takes the first scene with any data, the
scenes already used first (so a few cloudy pixels do not download a scene's bands); a pixel without any data the
mean colour. A scene in another UTM zone is reprojected point by point.

L2A -> sRGB (`srgb_lut`): reflectance = DN * scale + offset (the STAC values: 1e-4 and -0.1 for Collection 1);
display value = sRGB transfer of `S2_GAIN` x reflectance with a soft shoulder above `S2_KNEE` (bright roofs and
sand do not clip hard), 8 bit. L2A is already corrected for haze, so none is added (aerial perspective is the
renderer's job).

Storage: baseline JPEG (`jpeg_rgb`: YCbCr 4:2:0, the Annex K tables at `quality`, integer DCT - the same input
gives the same bytes on every machine), Godot reads it with Image.load_jpg_from_buffer.
"""
from __future__ import annotations

import json
import math
import struct
import sys
import time
import urllib.request
import zlib
from array import array
from itertools import accumulate
from operator import add, itemgetter, mul
from pathlib import Path
from typing import Callable, Dict, List, Optional, Sequence, Tuple

S2_STAC_URL = "https://earth-search.aws.element84.com/v1/search"
S2_COLLECTION = "sentinel-2-c1-l2a"
S2_SEASONS = ("2024-06-01T00:00:00Z/2024-08-31T23:59:59Z", "2023-06-01T00:00:00Z/2023-08-31T23:59:59Z")
S2_MAX_CLOUD = 20.0  # per cent of the scene (eo:cloud_cover)
S2_SCENES_PER_ORBIT = 3  # per MGRS tile and relative orbit (a tile on a swath edge needs both orbits)
S2_MANIFEST_VERSION = "s2v2"  # part of the manifest file name: a changed search must not reuse an old manifest
S2_BANDS = (("red", "B04"), ("green", "B03"), ("blue", "B02"), ("scl", "SCL"))
S2_NATIVE_M = {"B04": 10.0, "B03": 10.0, "B02": 10.0, "SCL": 20.0}
S2_CLEAR = (2, 4, 5, 6)
S2_MIN_SHARE = 0.02  # of the pixels (at most S2_MIN_PIXELS): a scene adding less to the clear-ground pass is not used for it
S2_MIN_PIXELS = 250000  # SCL dark area, vegetation, not vegetated, water
S2_GAIN = 2.6
S2_KNEE = 0.80
COLOUR_QUALITY = 85
COLOUR_CELL_TACTICAL_M = 10.0
COLOUR_CELL_LAYER_M = 40.0
USER_AGENT = "eastern-flank-map-import/1 (offline game map builder; one-off download)"
HEAD_BYTES = 65536

# ---------------------------------------------------------------------------------------------------------------
# Projected Cloud-Optimized GeoTIFF bands (uint8 / uint16, deflate, predictor 1 / 2, overviews).


class CogBand:
    """One band of a projected COG (or a prefix of one, see the module docstring): every IFD is a level, level 0
    the full resolution, level k its k-th overview. Blocks are decoded on first use."""

    _TYPES = {1: "B", 2: "s", 3: "H", 4: "I", 12: "d", 16: "Q"}

    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        self._data = self.path.read_bytes()
        head = self._data[:2]
        if head not in (b"II", b"MM"):
            raise ValueError("%s: not a TIFF" % path)
        self._bo = "<" if head == b"II" else ">"
        self.levels = [tags for tags in _ifds(self._data, self._bo, self._TYPES)]
        if not self.levels:
            raise ValueError("%s: no image" % path)
        first = self.levels[0]
        scale, tie = first[33550], first[33922]
        self.full_width = first[256][0]
        self.x0 = tie[3] - tie[0] * scale[0]  # corner of pixel (0, 0) (pixel-is-area)
        self.y0 = tie[4] + tie[1] * scale[1]
        self.res0 = scale[0]
        keys = first.get(34735, ())
        self.epsg = 0
        for i in range(4, len(keys), 4):
            if keys[i] in (3072, 2048) and keys[i + 1] == 0:
                self.epsg = keys[i + 3] if keys[i] == 3072 else self.epsg
        self._blocks: Dict[Tuple[int, int], array] = {}

    def level_count(self) -> int:
        return len(self.levels)

    def resolution(self, level: int) -> float:
        return self.res0 * self.full_width / self.levels[level][256][0]

    def level_for(self, cell: float) -> int:
        """The coarsest level whose pixels are not coarser than `cell` (level 0 when even that is coarser)."""
        best = 0
        for k in range(len(self.levels)):
            if self.resolution(k) <= cell + 1e-6:
                best = k
        return best

    def size(self, level: int) -> Tuple[int, int]:
        tags = self.levels[level]
        return tags[256][0], tags[257][0]

    def block(self, level: int, index: int) -> array:
        key = (level, index)
        found = self._blocks.get(key)
        if found is not None:
            return found
        tags = self.levels[level]
        bw, bh = tags[322][0], tags[323][0]
        bits = tags.get(258, (8,))[0]
        code = "H" if bits == 16 else "B"
        offset, count = tags[324][index], tags[325][index]
        values = array(code)
        if count and offset + count <= len(self._data):
            raw = self._data[offset : offset + count]
            if tags.get(259, (1,))[0] in (8, 32946):
                raw = zlib.decompress(raw)
            values.frombytes(raw[: bw * bh * values.itemsize])
            if self._bo != ("<" if sys.byteorder == "little" else ">") and values.itemsize > 1:
                values.byteswap()
            if tags.get(317, (1,))[0] == 2:
                mask = (0xFFFF if bits == 16 else 0xFF).__and__
                rows = len(values) // bw
                out = array(code)
                for r in range(rows):
                    out.extend(map(mask, accumulate(values[r * bw : (r + 1) * bw])))
                values = out
        elif count:
            raise ValueError("%s: level %d is not in this file (a coarser prefix?)" % (self.path, level))
        if len(values) < bw * bh:
            values.extend([0] * (bw * bh - len(values)))
        self._blocks[key] = values
        return values

    def drop(self) -> None:
        self._blocks.clear()

    def row(self, level: int, j: int, i0: int, i1: int) -> array:
        """Values of row `j` from column i0 to i1 - 1 (both inside the level)."""
        tags = self.levels[level]
        width = tags[256][0]
        bw, bh = tags[322][0], tags[323][0]
        across = -(-width // bw)
        out: Optional[array] = None
        r = j % bh
        for b in range(i0 // bw, (i1 - 1) // bw + 1):
            block = self.block(level, (j // bh) * across + b)
            a = max(i0, b * bw) - b * bw
            e = min(i1, (b + 1) * bw) - b * bw
            part = block[r * bw + a : r * bw + e]
            if out is None:
                out = part
            else:
                out.extend(part)
        return out if out is not None else array("H")

    def value(self, level: int, i: int, j: int) -> int:
        tags = self.levels[level]
        width, height = tags[256][0], tags[257][0]
        if not (0 <= i < width and 0 <= j < height):
            return 0
        bw, bh = tags[322][0], tags[323][0]
        across = -(-width // bw)
        return self.block(level, (j // bh) * across + i // bw)[(j % bh) * bw + i % bw]


def _ifds(data: bytes, bo: str, types: Dict[int, str]) -> List[Dict[int, tuple]]:
    """The tags of every IFD in the chain (raises IndexError / struct.error when `data` stops inside them)."""
    out = []
    offset = struct.unpack(bo + "I", data[4:8])[0]
    while offset:
        count = struct.unpack(bo + "H", data[offset : offset + 2])[0]
        tags: Dict[int, tuple] = {}
        for k in range(count):
            entry = data[offset + 2 + k * 12 : offset + 14 + k * 12]
            tag, typ, n = struct.unpack(bo + "HHI", entry[:8])
            code = types.get(typ)
            if code is None:
                continue
            size = struct.calcsize(code) * n
            if size <= 4:
                raw = entry[8 : 8 + size]
            else:
                start = struct.unpack(bo + "I", entry[8:12])[0]
                raw = data[start : start + size]
                if len(raw) < size:
                    raise IndexError("tag %d beyond the data" % tag)
            tags[tag] = (raw,) if code == "s" else struct.unpack(bo + code * n, raw)
        if 256 in tags and 322 in tags:
            out.append(tags)
        offset = struct.unpack(bo + "I", data[offset + 2 + count * 12 : offset + 6 + count * 12])[0]
    return out


# ---------------------------------------------------------------------------------------------------------------
# Scene search, manifest and band cache.


def manifest_path(cache: Path, south: float, west: float, north: float, east: float) -> Path:
    return cache / "s2" / ("%s_%.5f_%.5f_%.5f_%.5f.json" % (S2_MANIFEST_VERSION, south, west, north, east))


def _post_json(url: str, body: dict) -> dict:
    request = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"),
                                     headers={"User-Agent": USER_AGENT, "Content-Type": "application/json"})  # fmt: skip
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.loads(response.read().decode("utf-8"))


def select_scenes(features: Sequence[dict], zone: int) -> List[dict]:
    """Manifest entries of STAC items: per MGRS tile and relative orbit the S2_SCENES_PER_ORBIT least cloudy
    (then the least no-data, then the id; a tile on a swath edge is only half seen by each orbit, so both
    are kept), all in priority order: the map's UTM zone first, then cloud, no data and id. Cloud
    comes first because the no-data part of a scene (outside its swath) costs only its SCL download: the
    composite takes a scene's bands only where its SCL has clear ground."""
    by_tile: Dict[str, List[dict]] = {}
    for f in features:
        p = f["properties"]
        bands = {}
        for key, band in S2_BANDS:
            asset = f["assets"].get(key)
            if asset is None:
                break
            bands[band] = asset["href"]
        if len(bands) != len(S2_BANDS):
            continue
        raster = (f["assets"]["red"].get("raster:bands") or [{}])[0]
        entry = {"id": f["id"], "datetime": p.get("datetime", ""), "tile": p.get("grid:code", ""),
                 "epsg": int(p.get("proj:epsg", 0)), "cloud": round(float(p.get("eo:cloud_cover", 100.0)), 4),
                 "nodata": round(float(p.get("s2:nodata_pixel_percentage", 0.0)), 4),
                 "orbit": _relative_orbit(p.get("s2:product_uri", "")),
                 "scale": float(raster.get("scale", 0.0001)), "offset": float(raster.get("offset", -0.1)),
                 "bands": bands}  # fmt: skip
        by_tile.setdefault((entry["tile"], entry["orbit"]), []).append(entry)
    chosen = []
    for key in sorted(by_tile):
        scenes = sorted(by_tile[key], key=lambda s: (s["cloud"], s["nodata"], s["id"]))
        chosen += scenes[:S2_SCENES_PER_ORBIT]
    return sorted(chosen, key=lambda s: (s["epsg"] != 32600 + zone, s["cloud"], s["nodata"], s["id"]))


def _relative_orbit(product_uri: str) -> int:
    """The relative orbit of a product name (`..._N0510_R079_T34UFF_...` -> 79; 0 when there is none)."""
    for part in product_uri.split("_"):
        if len(part) == 4 and part[0] == "R" and part[1:].isdigit():
            return int(part[1:])
    return 0


def s2_search(south: float, west: float, north: float, east: float) -> List[dict]:
    """STAC items of the summer seasons over the bbox (network)."""
    features: List[dict] = []
    for season in S2_SEASONS:
        body: Optional[dict] = {"collections": [S2_COLLECTION], "bbox": [west, south, east, north],
                                "datetime": season, "query": {"eo:cloud_cover": {"lt": S2_MAX_CLOUD}},
                                "limit": 100}  # fmt: skip
        url = S2_STAC_URL
        while body is not None:
            page = _post_json(url, body)
            features += page.get("features", [])
            body = None
            for link in page.get("links", []):
                if link.get("rel") == "next" and link.get("body"):
                    url, body = link.get("href", url), link["body"]
            time.sleep(1.0)
    return features


def scene_manifest(cache: Path, south: float, west: float, north: float, east: float, zone: int,
                   offline: bool) -> Tuple[Path, List[dict]]:  # fmt: skip
    path = manifest_path(cache, south, west, north, east)
    if not path.exists():
        if offline:
            raise SystemExit("offline and the Sentinel-2 scene manifest is not in the cache: %s" % path)
        print("Searching Sentinel-2 scenes (%s) ..." % S2_COLLECTION, file=sys.stderr)
        scenes = select_scenes(s2_search(south, west, north, east), zone)
        if not scenes:
            raise SystemExit("no Sentinel-2 scene found for %.5f,%.5f,%.5f,%.5f" % (south, west, north, east))
        path.parent.mkdir(parents=True, exist_ok=True)
        manifest = {"collection": S2_COLLECTION, "seasons": list(S2_SEASONS), "max_cloud": S2_MAX_CLOUD,
                    "bbox": [south, west, north, east], "scenes": scenes}  # fmt: skip
        tmp = path.with_suffix(".part")
        tmp.write_text(json.dumps(manifest, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        tmp.replace(path)
    return path, json.loads(path.read_text(encoding="utf-8"))["scenes"]


def _range(url: str, first: int, last: Optional[int]) -> bytes:
    headers = {"User-Agent": USER_AGENT}
    if last is not None:
        headers["Range"] = "bytes=%d-%d" % (first, last)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=300) as response:
                return response.read()
        except OSError as error:
            if attempt == 2:
                raise
            print("download failed (%s), retrying" % error, file=sys.stderr)
            time.sleep(10.0)
    return b""


def fetch_band_prefix(url: str, target: Path, level: int) -> None:
    """Downloads the start of a COG up to the end of the data of `level` (the whole file for level 0)."""
    if level == 0:
        data = _range(url, 0, None)
    else:
        size = HEAD_BYTES
        while True:
            head = _range(url, 0, size - 1)
            bo = "<" if head[:2] == b"II" else ">"
            try:
                levels = _ifds(head, bo, CogBand._TYPES)
                break
            except (IndexError, struct.error):
                if len(head) < size:
                    raise
                size *= 4
        tags = levels[min(level, len(levels) - 1)]
        end = max(o + c for o, c in zip(tags[324], tags[325]))
        data = head if end <= len(head) else _range(url, 0, end - 1)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(".part")
    tmp.write_bytes(data)
    tmp.replace(target)


def band_file(root: Path, scene: dict, band: str, level: int, offline: bool) -> Path:
    """The cached file of `band` that holds `level` (a finer level's file serves too); downloaded unless
    `offline`."""
    folder = root / scene["id"]
    for k in range(level, -1, -1):
        path = folder / ("%s_L%d.tif" % (band, k))
        if path.exists():
            return path
    path = folder / ("%s_L%d.tif" % (band, level))
    if offline:
        raise SystemExit("offline and a Sentinel-2 band is not in the cache: %s" % path)
    print("Downloading %s %s (level %d)" % (scene["id"], band, level), file=sys.stderr)
    fetch_band_prefix(scene["bands"][band], path, level)
    return path


# ---------------------------------------------------------------------------------------------------------------
# L2A -> sRGB.


def srgb_value(reflectance: float) -> int:
    """8-bit display value of a surface reflectance (see the module docstring)."""
    x = max(0.0, S2_GAIN * reflectance)
    if x > S2_KNEE:  # soft shoulder: 1 is reached only at infinity
        x = S2_KNEE + (1.0 - S2_KNEE) * (1.0 - math.exp(-(x - S2_KNEE) / (1.0 - S2_KNEE)))
    s = 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1.0 / 2.4) - 0.055
    return min(255, max(0, int(math.floor(s * 255.0 + 0.5))))


def srgb_lut(scale: float, offset: float) -> bytes:
    """srgb_value of every uint16 DN (0 = no data -> 0)."""
    cache: Dict[int, int] = {}
    out = bytearray(65536)
    for dn in range(1, 65536):
        r = dn * scale + offset
        key = int(round(r * 1e5))
        v = cache.get(key)
        if v is None:
            v = srgb_value(key / 1e5)
            cache[key] = v
        out[dn] = v
    return bytes(out)


# ---------------------------------------------------------------------------------------------------------------
# Composite.


def composite(width: int, height: int, cell: float, west_e: float, north_n: float, zone: int, scenes: List[dict],
              root: Path, offline: bool, to_latlon: Callable, to_utm: Callable) -> Tuple[List[bytearray], List[str]]:  # fmt: skip
    """R, G, B planes (width x height bytes, row 0 north) of the area whose north-west corner is (west_e, north_n)
    in UTM `zone`, plus the ids of the scenes used (see the module docstring)."""
    n = width * height
    owner = bytearray(n)
    centres_e = [west_e + (i + 0.5) * cell for i in range(width)]
    centres_n = [north_n - (j + 0.5) * cell for j in range(height)]

    def sampler(band: CogBand, level: int) -> Callable[[int, bytes, int], list]:
        """(row j, the row's owners, an owner value) -> values (a list) of `band` at the row's pixel centres (0
        outside the band; a band in another UTM zone is read only where the owner is that value)."""
        res = band.resolution(level)
        w, h = band.size(level)
        if band.epsg == 32600 + zone:
            cols = [int(math.floor((e - band.x0) / res)) for e in centres_e]
            inside = [0 <= c < w for c in cols]
            if not any(inside):
                return lambda j, owners, value: [0] * width
            lo = min(c for c, ok in zip(cols, inside) if ok)
            hi = max(c for c, ok in zip(cols, inside) if ok) + 1
            # index into [0] + row(lo .. hi): outside columns read the leading 0
            pick = itemgetter(*[(c - lo + 1) if ok else 0 for c, ok in zip(cols, inside)])

            def read(j: int, owners: bytes, value: int) -> list:
                r = int(math.floor((band.y0 - centres_n[j]) / res))
                if not 0 <= r < h:
                    return [0] * width
                values = [0]
                values.extend(band.row(level, r, lo, hi).tolist())
                got = pick(values)
                return list(got) if width > 1 else [got]

            return read
        other = band.epsg - 32600
        # The band's footprint in the map's zone (its corners, 1 km of slack for the curved edges).
        corners = [to_utm(*to_latlon(band.x0 + a * w * res, band.y0 - b * h * res, other), zone)
                   for a in (0, 1) for b in (0, 1)]  # fmt: skip
        foot = (min(c[0] for c in corners) - 1000.0, min(c[1] for c in corners) - 1000.0,
                max(c[0] for c in corners) + 1000.0, max(c[1] for c in corners) + 1000.0)  # fmt: skip

        def read_other(j: int, owners: bytes, value: int) -> list:
            out = [0] * width
            n_j = centres_n[j]
            if not foot[1] <= n_j <= foot[3]:
                return out
            for i in _positions(owners, value):
                e = centres_e[i]
                if foot[0] <= e <= foot[2]:
                    e2, n2 = to_utm(*to_latlon(e, n_j, zone), other)
                    out[i] = band.value(level, int(math.floor((e2 - band.x0) / res)), int(math.floor((band.y0 - n2) / res)))
            return out

        return read_other

    # Pass 1: clear ground; pass 2: any data.
    clear_table = bytes(1 if k in S2_CLEAR else 0 for k in range(256))
    data_table = bytes(1 if 0 < k < 256 else 0 for k in range(256))
    free_table = bytes([1] + [0] * 255)
    order = list(range(min(255, len(scenes))))
    for table in (clear_table, data_table):
        if table is data_table:  # cloudy leftovers: from the scenes already used first (no extra band downloads)
            used_first = [k for k in order if owner.find(k + 1) >= 0]
            order = used_first + [k for k in order if k not in used_first]
        for index in order:
            scene = scenes[index]
            if owner.find(0) < 0:
                break
            scl = CogBand(_band(root, scene, "SCL", cell, offline))
            read = sampler(scl, scl.level_for(cell))
            takes = []
            count = 0
            for j in range(height):
                row = owner[j * width : (j + 1) * width]
                if row.find(0) < 0:
                    continue
                flags = bytes(read(j, row, 0)).translate(table)
                take = int.from_bytes(flags, "big") & int.from_bytes(bytes(row).translate(free_table), "big")
                if take:
                    takes.append((j, take))
                    count += bin(take).count("1")
            scl.drop()
            # A new scene must be worth its bands (and a date seam): a few stray pixels wait for pass 2.
            if table is clear_table and count < min(S2_MIN_SHARE * n, S2_MIN_PIXELS) and owner.find(index + 1) < 0:
                continue
            for j, take in takes:
                row = owner[j * width : (j + 1) * width]
                owner[j * width : (j + 1) * width] = (int.from_bytes(row, "big") + (index + 1) * take).to_bytes(
                    width, "big")  # fmt: skip
    planes = [bytearray(n), bytearray(n), bytearray(n)]
    used = []
    for index, scene in enumerate(scenes[:255]):
        code = index + 1
        if owner.find(code) < 0:
            continue
        used.append(scene["id"])
        lut = srgb_lut(scene["scale"], scene["offset"])
        select = bytes(255 if k == code else 0 for k in range(256))
        for plane, band_name in zip(planes, ("B04", "B03", "B02")):
            band = CogBand(_band(root, scene, band_name, cell, offline))
            read = sampler(band, band.level_for(cell))
            for j in range(height):
                row = owner[j * width : (j + 1) * width]
                if row.find(code) < 0:
                    continue
                mask = int.from_bytes(bytes(row).translate(select), "big")
                values = bytes(map(lut.__getitem__, read(j, row, code)))
                old = int.from_bytes(plane[j * width : (j + 1) * width], "big")
                new = (old & ~mask) | (int.from_bytes(values, "big") & mask)
                plane[j * width : (j + 1) * width] = new.to_bytes(width, "big")
            band.drop()
    missing = owner.count(0)
    if missing:
        have = n - missing
        means = [int(round(sum(p) / have)) if have else 128 for p in planes]
        for k in range(n):
            if owner[k] == 0:
                for p, m in zip(planes, means):
                    p[k] = m
        print("Colour layer: %d of %d pixels without Sentinel-2 data (mean colour)" % (missing, n), file=sys.stderr)
    return planes, used


def _positions(row: bytes, value: int) -> List[int]:
    """Indices of `value` in `row`."""
    out = []
    k = row.find(value)
    while k >= 0:
        out.append(k)
        k = row.find(value, k + 1)
    return out


def _band(root: Path, scene: dict, band: str, cell: float, offline: bool) -> Path:
    """The cached file of `band` at the level `cell` needs (the level is known from the band's native
    resolution: COG overviews halve it level by level)."""
    level = 0
    res = S2_NATIVE_M[band]
    while res * 2.0 <= cell + 1e-6:
        res *= 2.0
        level += 1
    return band_file(root, scene, band, level, offline)


def interleave(planes: Sequence[bytearray], width: int, i0: int, j0: int, w: int, h: int) -> bytes:
    """RGB bytes of the window (i0, j0, w, h) of the planes."""
    out = bytearray(3 * w * h)
    for j in range(h):
        a = (j0 + j) * width + i0
        base = 3 * w * j
        for k in range(3):
            out[base + k : base + 3 * w : 3] = planes[k][a : a + w]
    return bytes(out)


def windows(edges: Sequence[int], size: int) -> List[Tuple[int, int]]:
    """(first, count) of each window between consecutive `edges` (the first pixel of every window), each one
    pixel wider than its share (overlapping the next window's first pixel), the last one up to `size`."""
    out = []
    for k in range(len(edges)):
        a = edges[k]
        b = min(size, edges[k + 1] + 1) if k + 1 < len(edges) else size
        out.append((a, max(1, b - a)))
    return out


# ---------------------------------------------------------------------------------------------------------------
# Baseline JPEG encoder.

_ZIGZAG = (0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7,
           14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39,
           46, 53, 60, 61, 54, 47, 55, 62, 63)  # fmt: skip
_Q_LUMA = (16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57, 69, 56, 14, 17,
           22, 29, 51, 87, 80, 62, 18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92, 49, 64, 78,
           87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99)  # fmt: skip
_Q_CHROMA = (17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99, 24, 26, 56, 99, 99, 99, 99, 99, 47, 66,
             99, 99, 99, 99, 99, 99) + (99,) * 32  # fmt: skip
_DC_LUMA_BITS = (0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0)
_DC_CHROMA_BITS = (0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0)
_DC_VALUES = tuple(range(12))
_AC_LUMA_BITS = (0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7D)
_AC_LUMA_VALUES = bytes.fromhex(
    "01020300041105122131410613516107227114328191a1082342b1c11552d1f02433627282090a161718191a25262728292a3435363738"
    "393a434445464748494a535455565758595a636465666768696a737475767778797a838485868788898a92939495969798999aa2a3a4a5"
    "a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9fa")
_AC_CHROMA_BITS = (0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77)
_AC_CHROMA_VALUES = bytes.fromhex(
    "000102031104052131061241510761711322328108144291a1b1c109233352f0156272d10a162434e125f11718191a262728292a3536"
    "3738393a434445464748494a535455565758595a636465666768696a737475767778797a82838485868788898a92939495969798999aa2"
    "a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae2e3e4e5e6e7e8e9eaf2f3f4f5f6f7f8f9fa")
assert sum(_AC_LUMA_BITS) == len(_AC_LUMA_VALUES) == 162
assert sum(_AC_CHROMA_BITS) == len(_AC_CHROMA_VALUES) == 162

# DCT basis, 2^12 fixed point: C[u][x] = round(4096 * c(u) / 2 * cos((2x + 1) u pi / 16)), c(0) = 1 / sqrt 2.
_DCT = tuple(tuple(int(round(4096.0 * (math.sqrt(0.5) if u == 0 else 1.0) / 2.0 * math.cos((2 * x + 1) * u * math.pi / 16.0)))
                   for x in range(8)) for u in range(8))  # fmt: skip


def _huffman_codes(bits: Sequence[int], values: bytes) -> Dict[int, Tuple[int, int]]:
    codes: Dict[int, Tuple[int, int]] = {}
    code = 0
    k = 0
    for length in range(1, 17):
        for _ in range(bits[length - 1]):
            codes[values[k]] = (code, length)
            code += 1
            k += 1
        code <<= 1
    return codes


def _quant(base: Sequence[int], quality: int) -> List[int]:
    q = max(1, min(100, quality))
    scale = 5000 // q if q < 50 else 200 - 2 * q
    return [max(1, min(255, (b * scale + 50) // 100)) for b in base]


class _Bits:
    def __init__(self) -> None:
        self.out = bytearray()
        self.acc = 0
        self.n = 0

    def put(self, code: int, length: int) -> None:
        self.acc = (self.acc << length) | code
        self.n += length
        out = self.out
        while self.n >= 8:
            self.n -= 8
            byte = (self.acc >> self.n) & 0xFF
            out.append(byte)
            if byte == 0xFF:
                out.append(0)
        self.acc &= (1 << self.n) - 1

    def flush(self) -> None:
        if self.n:
            self.put((1 << (8 - self.n)) - 1, 8 - self.n)


def _encode_block(block: List[int], divisors: Sequence[int], prev_dc: int, dc: Dict, ac: Dict, bits: _Bits) -> int:
    """Forward DCT, quantisation and Huffman coding of one 8 x 8 block (level-shifted samples, row-major);
    returns its quantised DC."""
    rows = [[sum(map(mul, c, block[r * 8 : r * 8 + 8])) for c in _DCT] for r in range(8)]
    coef = [0] * 64
    for u in range(8):
        column = [rows[r][u] for r in range(8)]
        for v in range(8):
            coef[v * 8 + u] = sum(map(mul, _DCT[v], column))
    quantised = []
    for k in range(64):
        s = coef[_ZIGZAG[k]]
        d = divisors[k]
        quantised.append((s + (d >> 1)) // d if s >= 0 else -(((d >> 1) - s) // d))
    diff = quantised[0] - prev_dc
    size = abs(diff).bit_length()
    bits.put(*dc[size])
    if size:
        bits.put(diff if diff > 0 else diff + (1 << size) - 1, size)
    run = 0
    last = 63
    while last > 0 and quantised[last] == 0:
        last -= 1
    for k in range(1, last + 1):
        v = quantised[k]
        if v == 0:
            run += 1
            continue
        while run > 15:
            bits.put(*ac[0xF0])
            run -= 16
        size = abs(v).bit_length()
        bits.put(*ac[(run << 4) | size])
        bits.put(v if v > 0 else v + (1 << size) - 1, size)
        run = 0
    if last < 63:
        bits.put(*ac[0x00])
    return quantised[0]


def jpeg_rgb(width: int, height: int, rgb: bytes, quality: int = COLOUR_QUALITY) -> bytes:
    """Baseline JFIF of an RGB image (row-major, 3 bytes per pixel): YCbCr 4:2:0, Annex K tables scaled by
    `quality` (IJG formula), no restart markers. Deterministic: integer colour conversion and DCT."""
    pw, ph = -(-width // 16) * 16, -(-height // 16) * 16
    r, g, b = rgb[0::3], rgb[1::3], rgb[2::3]
    y = [(19595 * rr + 38470 * gg + 7471 * bb + 32768) >> 16 for rr, gg, bb in zip(r, g, b)]
    cb = [(-11059 * rr - 21709 * gg + 32768 * bb + 8421375) >> 16 for rr, gg, bb in zip(r, g, b)]
    cr = [(32768 * rr - 27439 * gg - 5329 * bb + 8421375) >> 16 for rr, gg, bb in zip(r, g, b)]

    def padded(plane: List[int]) -> List[List[int]]:
        rows = []
        for j in range(ph):
            row = plane[min(j, height - 1) * width : min(j, height - 1) * width + width]
            rows.append(row + [row[-1]] * (pw - width))
        return rows

    ys = padded(y)
    chroma = []
    for plane in (cb, cr):
        full = padded(plane)
        half = []
        for j in range(0, ph, 2):
            a, c = full[j], full[j + 1]
            half.append([(a[i] + a[i + 1] + c[i] + c[i + 1] + 2) >> 2 for i in range(0, pw, 2)])
        chroma.append(half)
    q_luma, q_chroma = _quant(_Q_LUMA, quality), _quant(_Q_CHROMA, quality)
    div_luma = [q_luma[_ZIGZAG[k]] << 24 for k in range(64)]
    div_chroma = [q_chroma[_ZIGZAG[k]] << 24 for k in range(64)]
    dc_l, ac_l = _huffman_codes(_DC_LUMA_BITS, bytes(_DC_VALUES)), _huffman_codes(_AC_LUMA_BITS, _AC_LUMA_VALUES)
    dc_c, ac_c = _huffman_codes(_DC_CHROMA_BITS, bytes(_DC_VALUES)), _huffman_codes(_AC_CHROMA_BITS, _AC_CHROMA_VALUES)
    bits = _Bits()
    prev = [0, 0, 0]

    def block_of(plane: List[List[int]], x: int, yy: int) -> List[int]:
        out: List[int] = []
        for row in plane[yy : yy + 8]:
            out.extend(v - 128 for v in row[x : x + 8])
        return out

    for my in range(0, ph, 16):
        for mx in range(0, pw, 16):
            for dy in (0, 8):
                for dx in (0, 8):
                    prev[0] = _encode_block(block_of(ys, mx + dx, my + dy), div_luma, prev[0], dc_l, ac_l, bits)
            for k in (1, 2):
                prev[k] = _encode_block(block_of(chroma[k - 1], mx // 2, my // 2), div_chroma, prev[k], dc_c, ac_c, bits)
    bits.flush()

    def segment(marker: int, payload: bytes) -> bytes:
        return struct.pack(">BBH", 0xFF, marker, len(payload) + 2) + payload

    out = bytearray(b"\xff\xd8")
    out += segment(0xE0, b"JFIF\0" + struct.pack(">BBBHHBB", 1, 1, 0, 1, 1, 0, 0))
    out += segment(0xDB, b"\x00" + bytes(q_luma[_ZIGZAG[k]] for k in range(64))
                   + b"\x01" + bytes(q_chroma[_ZIGZAG[k]] for k in range(64)))  # fmt: skip
    out += segment(0xC0, struct.pack(">BHHB", 8, height, width, 3) + bytes([1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1]))
    for cls_id, bits_table, values in ((0x00, _DC_LUMA_BITS, bytes(_DC_VALUES)), (0x10, _AC_LUMA_BITS, _AC_LUMA_VALUES),
                                       (0x01, _DC_CHROMA_BITS, bytes(_DC_VALUES)),
                                       (0x11, _AC_CHROMA_BITS, _AC_CHROMA_VALUES)):  # fmt: skip
        out += segment(0xC4, bytes([cls_id]) + bytes(bits_table) + values)
    out += segment(0xDA, bytes([3, 1, 0x00, 2, 0x11, 3, 0x11, 0, 63, 0]))
    out += bits.out
    out += b"\xff\xd9"
    return bytes(out)
