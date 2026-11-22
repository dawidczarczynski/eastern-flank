# TASK-192a: Satellite colour layer (A): research, import and loaders

- **Status**: done
- **Layers**: tools (`tools/import_map.py`), core data (`ImportedMap`, `TacticalLayer`, loaders only – no rendering)
- **Depends on**: TASK-190, TASK-108g (the 16 m land-cover raster)
- **Sections**: ARCHITECTURE "Terrain rendering" and its real-scale vegetation / land-cover paragraphs; ADR 0018, 0026, 0028
- **Model**: opus (data pipeline, licence, byte-identical re-import)
- **Tags**: battle-look

## Goal

Every real-geography tactical map and the theatre's tactical layer carry a compressed sRGB colour layer made from Sentinel-2 imagery, loadable and samplable in code, so TASK-192b can paint the far terrain and forests from it. No visual change in this task.

## Decisions (2026-11-22)

- Coverage: tactical maps (`ImportedMap`, e.g. `data/maps/suwalki.tres`) and the tactical layer of the theatre (`TacticalLayer` / chunks, where the 16 m LandCover raster exists, ADR 0028). Operational (5 km hex) maps are untouched.
- Raw Sentinel-2 scenes stay in the local cache (`~/.cache/eastern-flank/maps`, like DEM/OSM, outside git); the game never goes online.
- The processed compressed sRGB layer IS committed (the game works after a clone); re-import is byte-identical.
- Resolution, compression and total size cap are fixed by the ADR (research) and recorded here. Initial budget to propose: <= 10 m/pixel for tactical maps, coarser for the theatre layer; total added size under `data/maps` recorded and justified (current `data/maps` is 30 MB).
- Core stays pure: the layer is a resource/image loaded by `ImportedMap` / `TacticalLayer`; no `Node`, no rendering here.

## Acceptance criteria (testable)

- [ ] New `docs/adr/0031-satellite-colour-layer.md` (0030 is the highest existing) records: source and licence of a cloud-free summer mosaic (Copernicus Sentinel-2 L2A 10 m, free/open with attribution, or e.g. EOX s2cloudless – licence checked per year), offline-repeatable download into the cache, L2A -> sRGB correction, haze and seasonal look, chosen resolution/compression, per-map and total size.
- [ ] `tools/import_map.py` writes the colour layer for a tactical map at <= 10 m per pixel; the file size per map is within the ADR budget.
- [ ] Re-importing the same fixture twice gives byte-identical layer files (Python test in `tools/test_import_map.py`, fixture in `tools/import_map_fixtures/`).
- [ ] The same fixture test checks the layer's pixel size equals ceil(map extent in m / resolution) and that a known fixture pixel keeps its expected sRGB value after correction.
- [ ] The importer writes the theatre tactical layer's colour layer (coarser, ADR value) and per-chunk windows if the loader needs them; chunk windows tile without gaps (test: the window edge pixels equal the neighbour's).
- [ ] `data/maps/CREDITS` names the imagery source, licence and attribution text required by the ADR.
- [ ] `ImportedMap` and `TacticalLayer` load the layer; `sample(x_m, z_m)` returns the expected colour at 3 fixture points (centre, corner, a point outside -> clamped to the edge colour), tested headless in `tests/unit/`.
- [ ] A map without the layer loads as before: `has_colour_layer()` is false and `sample()` is never needed (test with an existing older map).
- [ ] Total added size of committed layers is recorded in the ADR and Implementation notes.

## Playtest (for the human)

1. Run `tools/import_map.py` for Suwałki (needs the local cache / network once); check the layer file opens as a plausible summer picture of the area.
2. Start the game: nothing changes visually.

## Player manual

None (data only).

## Out of scope

- Any shader or rendering use of the layer (TASK-192b); operational maps; buildings/roads from imagery; seasons / weather.

## Implementation notes

- **Source / licence** (ADR 0031): Copernicus Sentinel-2 L2A (collection `sentinel-2-c1-l2a`, AWS COGs via Earth Search STAC), our own composite; free, full and open, attribution "Contains modified Copernicus Sentinel data <year>" (data/maps/CREDITS, each layer's `colour_sources`). EOX s2cloudless rejected: 2018+ are CC BY-NC-SA (only 2016 is CC BY), and it is JPEG web-map tiles a stdlib importer cannot decode.
- **Importer**: `tools/import_map.py --colour` (opt-in; without it the output is byte-identical to before), the colour code in `tools/import_map_colour.py` (projected COG reader with overviews, STAC search + scene manifest `~/.cache/eastern-flank/maps/s2/s2v1_<bbox>.json`, band prefix download by HTTP range, SCL-masked best-pixel composite, L2A -> sRGB LUT `2.6 x reflectance` + sRGB + soft shoulder, integer baseline-JPEG encoder). A scene must add >= 2 % of the pixels to be used for clear ground (one date fewer: SCL marks stray bright fields as cloud); leftover pixels come from scenes already used.
- **Resolution / storage**: tactical maps 10 m, one JPEG (q85) in `ImportedMap.colour_jpg`; tactical layer 40 m (the bands' 40 m overview), geometry in `layer.tres`, one JPEG window per chunk (`TacticalChunk.colour_*`), windows one pixel wider east / south so a bilinear sample needs one window.
- **Loaders** (pure core): `ColourRaster` (`src/core/data/colour_raster.gd`), `ImportedMap.has_colour_layer()` / `colour_raster()` / `sample(x_m, z_m)`, `TacticalLayer.has_colour_layer()` / `sample(x_m, z_m)` / `from_folder()` / `loaded_colour_windows()` (frame: metres east / south of tile (0, 0)'s centre; clamped to the edge; transparent black without a layer).
- **Tests**: Python `ColourTest`, `ColourMapTest`, `ColourLayerTest` in `tools/test_import_map.py` (byte-identical re-import, pixel count = ceil(extent / cell), the known centre pixel's sRGB, cloud / no-data filling, zone-35 reprojection, window edges shared); synthetic scenes in `tools/import_map_fixtures/s2/` (`--make-fixtures`), golden `tests/fixtures/maps/sample_colour_map.tres` and `tests/fixtures/maps/sample_layer/`. GDScript `tests/unit/test_colour_raster.gd` (3 fixture points incl. clamped outside, the old `sample_map.tres` / operational map without a layer, layer sampling across chunk windows).
- **Committed layers** (imported 2026-11-22, the hex data of both is byte-identical to before; only `colour_*` lines added): `data/maps/suwalki.tres` 10 m, 763 x 527 px, 80.7 KB JPEG (108 KB in the file) from one scene (S2B_T34UFF_20240824T094545_L2A); `data/maps/suwalki_tactical/` 40 m, 8566 x 6974 px in 121 windows, 14.7 MB JPEG (19.6 MB in the files) from 27 scenes. **Total added 19.7 MB** (`data/maps` 30.2 -> 49.9 MB), within the ADR budget (1 MB per tactical map, 20 MB theatre).
- **Known look issues for TASK-192b**: the theatre composite shows date / tile seams (tile-shaped blocks, a brighter hazy block in Belarus) and a few small clouds the SCL missed (east of the theatre); the Curonian Lagoon area is blocky. The first selection (best 6 per tile) left a 20 km swath gap; selecting per tile and relative orbit fixed it.
