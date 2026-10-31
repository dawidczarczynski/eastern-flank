# ADR 0018: Maps from real geography – sources, scales, projection, classification, offline import

- **Status**: accepted
- **Date**: 2026-10-31
- **Task**: TASK-087 (extends [ADR 0011](0011-third-party-assets.md))

## Context

The vision (GDD "Vision decisions") wants battles fought on the real terrain of the eastern flank: operational and tactical maps are generated from real map data, not from the noise generator (`MapGenerator`). Until now every map came from `TerrainField` noise; the core had no way to load a map, and `TerrainSurface` drew a hand-made grid without a field as flat tiles. TASK-087 step 1 asked the human to pick data sources, scales, a projection and the classification; step 2 builds the first importer and one real sample.

## Decision

The human's decisions (2026-10-31), with the options that were on the table:

### Sources and licences

| Option | Coverage | Licence | Decision |
|---|---|---|---|
| **Copernicus GLO-30 DEM** (30 m, DSM) | whole theatre (PL, LT, LV, EE, BY, UA, RU) | free with attribution | **elevation** |
| GUGiK NMT (Polish national DTM, 1 m / 5 m) | Poland only | free (Polish open-data terms) | not now – no Baltics/Belarus; may refine Polish maps later |
| **OpenStreetMap** via the Overpass API | whole theatre | ODbL 1.0 (attribution, share-alike of the derived database) | **land cover** (land use, natural areas, water; roads and waterways fetched for TASK-108) |

- The raw downloads go into a **cache outside git** (`~/.cache/eastern-flank/maps/`, `--cache=` overrides): the original Copernicus COG tiles (`dem/Copernicus_DSM_COG_10_N<lat>_00_E<lon>_00_DEM.tif`) and the raw Overpass JSON (`osm/osm_<s>_<w>_<n>_<e>.json`, the map's bbox + 500 m). Only the generated hex maps are committed (`data/maps/<id>.tres`). **The game never goes online.**
- Attribution lives in `data/maps/CREDITS` (both sources, the ODbL share-alike statement for the derived hex data, and per map: inputs, download date, rebuild command), in every map's `sources` field and in the README "Credits" section. `tests/unit/test_real_map_battle.gd` (`test_maps_are_credited`) fails when a map in `data/maps/` lacks the attribution or is not listed in CREDITS – the counterpart of ADR 0011's `test_third_party_assets.gd` (the credits.json manifest stays for `assets/third_party/`; map data is not an asset file there).

### Scales

| Option | Hex | Map | Size | Tiles (default map 12×10 = 120) |
|---|---|---|---|---|
| **A** | **250 m** (a company frontage) | **30×24** | **7.5 × 5.2 km** | **720** |
| B | 200 m | 24×20 | 4.8 × 3.5 km | 480 |
| C | 500 m (battalion) | 20×16 | 10 × 6.9 km | 320 |

**A** is the tactical scale. "250 m" is the distance between neighbouring hex centres (flat-to-flat), so one world unit (`TerrainField.HEX_SIZE` = 1, centre to corner) is 250 / √3 ≈ 144.3 m and rows are 216.5 m apart (24 rows ≈ 5.2 km, not 6 km). The operational hex will be about **5 km** (TASK-092, documented only): a battle map covers about 1.5 × 1 operational hexes – the contact hex and a half ring around it. Performance (TASK-072): 6× the tiles of the default battle; on the RX 580 the screenshot run cut grass density to 0.89 to stay in the instance budget, and an AI-vs-AI match (16 turns) takes ~5 s headless. A larger map needs TASK-072's work first.

### Projection

One local metric projection per theatre: **UTM** (transverse Mercator, WGS84), zone of the map centre – **34N (EPSG:32634) for the Suwałki Gap**. The importer projects with the Krüger series (stdlib, mm-level within a zone). The hex ↔ geography mapping is stored with the map: `crs`, `origin_easting` / `origin_northing` (centre of tile (0, 0), whole metres), `hex_spacing_m`; world x grows east, world z south (`ImportedMap.easting / northing / projected_to_tile`), and `bbox_wgs84` for reference.

### Classification

Each map is covered by a lattice of sample points every 25 m (~70 per hex). Each point gets the DEM height (bilinear between pixel centres) and an OSM cover class; areas are closed ways and multipolygon relations (rings assembled from all member ways, filled even-odd), and where areas overlap the higher class wins:

| Class | OSM tags | Terrain today | TASK-108 |
|---|---|---|---|
| `.` unmapped | – | PLAINS / HILLS | open ground (mostly fields in rural Poland) |
| `G` grass | `landuse=meadow/grass/village_green/recreation_ground/cemetery/brownfield/greenfield/quarry/landfill`, `natural=grassland/heath/scrub` | PLAINS / HILLS | open |
| `A` fields | `landuse=farmland/orchard/vineyard/allotments/plant_nursery/greenhouse_horticulture` | PLAINS / HILLS | **fields** |
| `U` urban | `landuse=residential/commercial/industrial/retail/farmyard/garages/construction/railway/military` | PLAINS / HILLS | **urban** (villages = farmyards + residential) |
| `F` forest | `landuse=forest`, `natural=wood` | FOREST | forest |
| `M` marsh | `natural=wetland` | PLAINS / HILLS | **marsh** |
| `W` water | `natural=water/bay`, `water=*`, `waterway=riverbank/dock`, `landuse=reservoir/basin` | WATER | water |

- **Dominant cover per hex**: the points of a hex are grouped into water / forest / open; the largest group wins (ties prefer open, then forest – passable ground over water). The map also stores the dominant fine class per hex (`cover_rows`) for TASK-108; no rule reads it yet.
- **Roads and rivers** (TASK-108): `highway=motorway … track` and `waterway=river/stream/canal` lines are already in the cached Overpass extract; v1 does not rasterise them. Wide rivers mapped as areas are water already.
- **Elevation per hex** = DEM mean. Copernicus is a surface model (trees, buildings), so the mean uses the hex's open points when at least a quarter of it is open; a mostly forested hex takes the mean minus a 15 m canopy (`--canopy`).
- **Hills from local relief**: an open hex whose relief (90th − 10th percentile of its heights) is ≥ **15 m** (`--hills-relief`) is HILLS (Suwałki sample: 131 of 720 hexes; 12 m gave 193, 18 m gave 82). Forest stays forest.
- **Game elevation**: one water plane at 0 in the game, so water hexes get −0.4; land = 0.12 (`land_min`) + (metres − lowest land hex) × vertical scale, the scale = 1.5× true scale (`--exaggeration`; 2× made the Suwałki lake shores ~1.1 units high cliffs, because Lake Szurpiły lies 36 m above the map's lowest land), reduced if the highest hex would exceed 2.2 (`hills_max`; the camera ray starts at 3.0). Lakes at different real heights all sit at the one water plane; their banks become slopes.

### Core

- `ImportedMap` (`src/core/data/imported_map.gd`, Resource): metadata above, `terrain_rows` (one character per tile: P/F/H/W), `cover_rows`, `elevation_m` (real metres), `elevation` (game units), `sources`. `ImportedMap.find(id)` loads `data/maps/<id>.tres`; `to_grid()` builds a `HexGrid` (offset layout like `MapGenerator`) or returns null for malformed data (`problem()`).
- `HexGrid.authored_elevation`: set by `to_grid()`. `TerrainSurface` with `field == null` then blends the three tile centres around a point (smoothstep-weighted barycentric: passes through every centre, flat around it, continuous across edges) instead of flat tiles; `MapGenerator.force_terrain` keeps a land tile's real elevation when it stays land (spawn tiles), only land ↔ water changes are clamped into the generator's bands. Hand-made grids and generated maps are unchanged.
- `BattleSetup.map_id` names either `generated_river` or an imported map; `Scenario.from_setup` loads it. `map_region` (a cut of a big map) stays for TASK-094.
- Sample: `data/maps/suwalki.tres` – real data, Suwałki Landscape Park around Szurpiły (54.235 N, 22.88 E), played by `Scenario.suwalki_battle` (`tools/run.sh --scenario=suwalki_battle`).

### Tool

`tools/import_map.py` – Python 3.8 stdlib only (own GeoTIFF reader for deflate + floating-point predictor tiles, own UTM projection, scanline polygon fill; no GDAL/numpy/shapely). Optional dependencies: none required; network only for the first download (urllib). Deterministic: elements are processed sorted by (class, type, id), every number is written with fixed decimals – the same cache gives a byte-identical `.tres` (tested on the committed synthetic fixtures `tools/import_map_fixtures/` → `tests/fixtures/maps/sample_map.tres`; the real Suwałki import was also re-run offline and compared). Python tests: `tools/test_import_map.py`, run by `tools/check.sh`.

## Consequences

- (+) Battles can be fought on real terrain; the importer runs offline from the cache, so maps are reproducible and reviewable as data (`terrain_rows` diff by row).
- (+) No new runtime dependency or network access in the game; the core stays pure (`ImportedMap` is a Resource, `to_grid()` pure).
- (+) TASK-108 finds fields / urban / marsh per hex already stored, roads and rivers in the cache.
- (−) ODbL share-alike: the derived hex data of every map is offered under the ODbL (stated in CREDITS); a re-download gets today's OSM, so a rebuilt map can differ from the committed one.
- (−) One water plane: lakes at different real heights are all drawn at 0, and land is mapped with one linear scale per map – a map with lakes high above its lowest ground gets steep banks (tune `--exaggeration`).
- (−) The DSM canopy correction is a heuristic; GUGiK's DTM would be exact for Poland.
- (−) Larger maps cost frame rate and AI time (TASK-072).
