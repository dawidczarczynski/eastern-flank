# TASK-215a: Real field parcel boundaries (A): research, import and loaders

- **Status**: done
- **Layers**: tools (`tools/import_map.py`), core data (`ImportedMap`, loaders only – no rendering)
- **Depends on**: TASK-200 (soft: TASK-192b)
- **Sections**: ADR 0018 (maps from real geography), ADR 0031 (satellite colour layer, as the pattern); ARCHITECTURE "Terrain rendering"; TASK-200
- **Model**: opus (research, licence, byte-identical import, polygon splitting)
- **Tags**: battle-look

## Goal

Every real-geography tactical map carries the real field parcel polygons (OSM farmland / meadow / orchard areas split by roads, tracks and hedgerows), loadable in code, so TASK-215b can draw straight, real-sized fields. No visual change in this task.

## Decisions (2026-11-23)

- Source: OSM first. Reuse the landuse fetch (`landuse=farmland|meadow|orchard` polygons) and split large polygons by `highway=track|service|unclassified|residential`, `barrier=hedge`, `natural=tree_row`, `barrier=fence|wall` and field-edge ways. OSM-split is the default unless the ADR research shows it is clearly unusable.
- The ADR compares it with Polish LPIS / EGiB open data and Sentinel-2 field-edge detection: coverage on the Suwałki theatre (also Lithuania, Belarus, Kaliningrad), licence / ODbL attribution, size per map, importer cost.
- Overpass data is cached like the other layers (`~/.cache/eastern-flank/maps/osm`); the game never goes online; the processed polygons are committed.
- Large polygons (> ~15 ha, **[ASSUMPTION]**, configurable constant) are NOT subdivided here; that is TASK-215b's fallback. This task stores the polygons as they are after the OSM split.
- Core stays pure: plain data in `ImportedMap`, no `Node`, no rendering.

## Acceptance criteria (testable)

- [x] New `docs/adr/0032-real-field-parcel-boundaries.md` compares OSM-split, LPIS / EGiB, Sentinel-2 edge detection (coverage per country, licence, size per map, importer cost) and records the decision; if OSM is rejected, it says why with numbers.
- [x] `tools/import_map.py` writes parcel polygons for a tactical map (opt-in flag like `--colour`; without it the output is byte-identical to before).
- [x] Re-importing the same fixture twice gives byte-identical output (Python test in `tools/test_import_map.py`, fixture in `tools/import_map_fixtures/`).
- [x] Fixture test: a 40 ha farmland polygon crossed by one track becomes 2 polygons whose areas sum to the original within 1 %; a polygon with a hole (e.g. a wood inside) keeps the hole out of the parcel.
- [x] Fixture test: a `barrier=hedge` way that only touches a polygon edge does not split it; one that crosses it fully does; each output polygon records its edge kinds (`hedge` / `track` / `plain`) per edge.
- [x] Compact format: vertices in whole metres relative to the map origin, <= 150 KB per tactical map (ADR may adjust, recorded); `data/maps/CREDITS` names OSM / ODbL attribution (and any other source the ADR picks).
- [x] `ImportedMap` exposes `has_parcels()`, `parcel_count()`, `parcel_polygon(i)`, `parcel_edge_kinds(i)`, `parcel_landuse(i)`; tested headless on a golden `tests/fixtures/maps/` file.
- [x] A map without parcels loads as before: `has_parcels()` is false (test with the old `sample_map.tres`).
- [x] Parcel size stats for the committed Suwałki map (count, median, p10, p90 in ha, share of farmland area covered by polygons) are recorded in the ADR and compared with the TASK-108f strips' stats.
- [x] `data/maps/suwalki.tres` re-imported with parcels: its hex data and colour layer are byte-identical to before; only parcel lines are added.

## Playtest (for the human)

1. Run `tools/import_map.py` for Suwałki with the parcel flag (needs the local cache / network once); open the debug dump or ADR figure and check the polygons look like the fields on the satellite view.
2. Start the game: nothing changes visually.

## Player manual

None (data only).

## Out of scope

- Baking, drawing, subdividing big polygons (TASK-215b); operational maps and the theatre tactical layer (follow-up if wanted); buildings, field roads as geometry (TASK-202).

## Implementation notes

- Importer: `tools/import_map_parcels.py` (query, cache `pc1_<bbox>.json`, planar split, edge kinds, `.tres` fields, stats), wired into `tools/import_map.py` as `--parcels` / `--parcel-osm` (tactical only; `map_parcels`). Without the flag the output is unchanged (all existing goldens byte-identical).
- Tests: `ParcelSplitTest` / `ParcelMapTest` in `tools/test_import_map.py` (fixture `tools/import_map_fixtures/sample_parcel_osm.json`, golden `tests/fixtures/maps/sample_parcel_map.tres`, made by `--make-fixtures`); GDScript `tests/unit/test_imported_map_parcels.gd`.
- Core: `ImportedMap` fields `parcel_landuse_codes`, `parcel_rings`, `parcel_ring_sizes`, `parcel_points`, `parcel_edge_codes` (the accessor names `parcel_landuse` / `parcel_edge_kinds` are methods, so the arrays carry `_codes`), accessors as specified, validation in `problem()`.
- Suwałki re-imported (`--colour --parcels`, then `--offline`): only 5 `parcel_*` lines added (78 KB); 282 parcels, median 1.70 ha, p10 0.38, p90 7.06; farmland covered 98.6 %, but only 28.6 % of the open land has OSM land use – TASK-215b needs its fallback beyond big polygons. ADR 0032 with figure `docs/adr/0032-suwalki-parcels.jpg`.
