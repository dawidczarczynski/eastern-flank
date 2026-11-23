# TASK-199a: Real tree features (A): OSM import of trees, tree rows, orchards and farmyards

- **Status**: done
- **Layers**: tools (`tools/import_map.py`, new `tools/import_map_trees.py`), core data (`ImportedMap`, loaders only – no rendering)
- **Depends on**: TASK-215a (done; same importer pattern)
- **Sections**: ADR 0032 (parcel import, the pattern), ADR 0018, ADR 0031; ARCHITECTURE "Trees", "Terrain rendering"; docs/tasks/TASK-215a-parcel-boundaries-data.md (read its notes)
- **Model**: opus (byte-identical import, cache reuse, compact format)
- **Tags**: battle-look

## Goal

Every real-geography tactical map carries the real single trees, tree rows, orchard polygons and farmyard polygons from OSM, loadable in code, so TASK-199b can draw them. No visual change in this task.

## Decisions (2026-11-23)

- Hedges are NOT part of this task: TASK-215b already draws them from `ParcelMap.hedge_lines`; 199 adds only the other features.
- Source: OSM `natural=tree` points, `natural=tree_row` lines, `landuse=orchard` and `landuse=farmyard` polygons. Overpass answers use the existing cache (`~/.cache/eastern-flank/maps/osm`); the game never goes online; processed data is committed.
- Opt-in flag `--trees` (like `--parcels`); without it the output is byte-identical to before. **[ASSUMPTION]** a separate cache file `tr1_<bbox>.json`; the `tree_row` ways already fetched by the parcel query are reused only if that is simpler and keeps the parcel output byte-identical, otherwise fetched again.
- Format: whole metres relative to the map origin, compact. **[ASSUMPTION]** size cap <= 100 KB of added `.tres` per tactical map (record the real size; adjust only with a note).
- Core stays pure: plain arrays in `ImportedMap`, no `Node`, no rendering.
- A short ADR 0033 (or an addendum to 0032) only if a real decision arises (e.g. points dropped inside forest); otherwise notes only.

## Acceptance criteria (testable)

- [ ] `tools/import_map.py --trees` writes the four feature kinds for a tactical map; without the flag the output is byte-identical to before (all existing goldens unchanged).
- [ ] Re-importing the same fixture twice gives byte-identical output (Python test in `tools/test_import_map.py`, fixture in `tools/import_map_fixtures/`).
- [ ] Fixture test: 5 `natural=tree` points inside the bbox yield 5 points in whole metres; a point outside the bbox is dropped.
- [ ] Fixture test: a `natural=tree_row` way of 100 m keeps its vertices (simplified <= 1 m tolerance) and its length is within 1 % of the original.
- [ ] Fixture test: a `landuse=orchard` polygon and a `landuse=farmyard` polygon (one with a hole) keep outer ring and hole; areas within 1 % of the original; each polygon is stored once.
- [ ] Duplicate points closer than 1 m are merged (fixture with 2 points 0.5 m apart gives 1).
- [ ] `data/maps/CREDITS` names OSM / ODbL for the new layer; added size <= 100 KB per tactical map.
- [ ] `ImportedMap` exposes `has_tree_features()`, `tree_point_count()`, `tree_point(i)`, `tree_row_count()`, `tree_row_polyline(i)`, `orchard_count()`, `orchard_polygon(i)`, `farmyard_count()`, `farmyard_polygon(i)`; tested headless on a golden `tests/fixtures/maps/` file (counts and the first vertex of each kind).
- [ ] A map without the layer (old `sample_map.tres`) loads as before: `has_tree_features()` is false and all counts are 0; `problem()` rejects mismatched array sizes (test).
- [ ] `data/maps/suwalki.tres` re-imported with `--trees`: hex data, colour layer and parcel lines byte-identical to before; only tree-feature lines added.
- [ ] Stats recorded in the implementation notes: point count, tree-row count and total length (km), orchard count and area (ha), farmyard count and area (ha), plus the share of points inside forest hexes.

## Playtest (for the human)

1. Run `tools/import_map.py` for Suwałki with `--trees` (needs the cache or network once); check the counts in the notes look plausible against the satellite view.
2. Start the game: nothing changes visually.

## Player manual

None (data only).

## Out of scope

- Drawing and rule-based fill (TASK-199b); hedges on parcel edges (TASK-215b); settlement plots / buildings (TASK-198, TASK-195); forest interior (TASK-135); operational maps.

## Implementation notes

- Importer: `tools/import_map_trees.py` (query, cache `tr1_<bbox>.json`, point merge, row simplification, ring grouping into outer + holes, dedupe, `.tres` fields, stats), wired into `tools/import_map.py` as `--trees` / `--tree-osm` (tactical only; `map_trees`, `tree_stats`). The `[ASSUMPTION]` holds: one separate Overpass answer with all four kinds (the parcel answer's `tree_row` ways are not reused, so the parcel output stays untouched). Without the flag the output is unchanged (all existing goldens byte-identical after `--make-fixtures`).
- Processing: trees closer than 1 m (`MERGE_M`, in float metres before rounding) are merged; only trees inside the hexes' bounding rectangle are kept. Rows: Douglas-Peucker 1 m, kept whole when their box reaches the map. Orchards / farmyards: OSM areas (closed ways + multipolygons) grouped even-odd into outer + holes, simplified 1 m, outer counter-clockwise north up and holes reversed (as the parcels), kept whole when they reach the map; a way tagged like the multipolygon it is the outer of is stored once (the copy with the most holes wins). All lists are sorted, so the output does not depend on the element order.
- Storage (`ImportedMap`, after the parcel fields): `tree_points` (x, z pairs), `tree_row_sizes` + `tree_row_points`, `orchard_rings` / `orchard_ring_sizes` / `orchard_points` and the same for `farmyard_*`; whole metres east / south of tile (0, 0)'s centre. All nine lines are written with `--trees`, even when empty. Loaders as specified plus `problem()` checks (`_trees_problem`, `_area_problem`); `has_tree_features()` is true when any of the four kinds is non-empty.
- Tests: `TreeFeaturesTest` / `TreeMapTest` in `tools/test_import_map.py` (fixture `tools/import_map_fixtures/sample_tree_osm.json`: 5 trees + a twin 0.5 m away + one off the map, a ~100 m bowed tree row, an orchard way, a farmyard multipolygon with a hole whose outer way is tagged too; golden `tests/fixtures/maps/sample_tree_map.tres`, made by `--make-fixtures`); GDScript `tests/unit/test_imported_map_trees.gd`.
- Suwałki re-imported (`--colour --parcels --trees`, then the same with `--offline`: byte-identical): only the 9 tree-feature lines added after `parcel_edge_codes`; every other line identical. CREDITS updated.
- Stats (Suwałki, OSM of 2026-11-23): **15 single trees** (the whole answer has 15), **20.0 %** (3) on forest hexes; **36 tree rows, 3.26 km** (48 in the answer incl. the 500 m margin); **0 orchards, 0 ha** (none mapped in the bbox); **117 farmyards, 63.34 ha** (160 in the answer; the area counts the whole polygons, some reach past the map edge); **added .tres size 10.3 KB** (220 652 → 231 199 bytes), well under the 100 KB cap. OSM single trees are very sparse here, so TASK-199b will rely mostly on rule-based fill; no ADR needed (no new decision beyond the pattern of ADR 0032).
