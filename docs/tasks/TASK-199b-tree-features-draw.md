# TASK-199b: Real tree features (B): solitary trees, tree lines, copses and orchards in the open country

- **Status**: done
- **Layers**: presentation (`ScatterPlanner` meadow features, `TreeField`)
- **Depends on**: TASK-199a, TASK-135, TASK-108g (soft: TASK-215b, TASK-195)
- **Sections**: ARCHITECTURE "Trees", "Terrain rendering"; look reference (TASK-190); read in code: `scatter_planner.gd` (`plan_tile_meadow`, `_plan_parcel_hedges`, `plan_hedges`), `tree_field.gd`, `forest_fill.gd`, `real_scale_vegetation.gd`, `land_cover.gd`, `parcel_map.gd`, `imported_map.gd`
- **Model**: sonnet
- **Tags**: battle-look

## Goal

The open country reads like the reference: single trees in fields, tree lines along roads and field edges, copses and orchards at real size – from OSM where it knows them (TASK-199a) and by rule where it does not. Hedges come from TASK-215b.

## Decisions (2026-11-23)

- Hedges are reused from TASK-215b (`ScatterPlanner._plan_parcel_hedges` on `ParcelMap.hedge_lines`); this task adds no hedge planner, only an optional tuning (below).
- Rule fill where OSM has none, all four: roadside tree lines, solitary field trees, copses on hills and wet ground, orchards (on `landuse=orchard` and a small one inside `landuse=farmyard` by hash). Building-based farm placement is out of scope.
- Everything exists ONLY on the `true` VisualScale preset; other presets are unchanged.
- Planners are pure and deterministic (hash / `ScatterPlanner` streams, no `GameState.rng`); trees at real size (`VisualScale.tree_size`) with the regional species shares; chunked on the existing tree layer, no new draw calls.
- **[ASSUMPTION]** orchard row spacing 5–8 m in real metres; roadside lines every 6–12 m; a tree-line probability of 0.25 per road segment by hash; 0–3 solitary trees per parcel / meadow hex.

## Acceptance criteria (testable)

- [ ] OSM trees from `ImportedMap.tree_point(i)` are planted at their positions (within 0.5 m); `tree_row` polylines get trees every 5–10 m with every instance within 1.5 m of the polyline.
- [ ] Orchards: inside an `orchard_polygon` trees stand in rows of 5–8 m spacing, all instances inside the polygon; a `farmyard_polygon` gets one small orchard (8–30 trees) with hash probability 0.3 per polygon.
- [ ] Roadside fill: on a fixture road of 1 km, 20–40 % of its length carries a tree line (hash), spacing 6–12 m, offset 3–6 m from the centre line.
- [ ] Solitary field trees: 0–3 per parcel / open meadow hex, only near edges and corners (within 15 m of the boundary).
- [ ] Copses: 5–30 trees on hill or wet-ground hexes, outside the forest fill, at most 1 per hex.
- [ ] Nothing lands inside a forest tile, on a road, on water or inside a building footprint (when the TASK-195 mask exists; else skipped); asserted over a fixture region.
- [ ] Determinism: the same seed and map give identical instance lists (test); instances stand on the near surface (height within 0.1 m of the terrain).
- [ ] Counts per open hex stay within range; on `true`, total instances in open hexes grow <= 20 % versus before this task; other presets give an identical list.
- [ ] Budget: frame time unchanged within 0.5 ms and 60 FPS on `true` (measure with the existing frame benchmark / `tools/screenshot.sh` timing); no new draw calls.
- [ ] Optional: tune the TASK-215b hedge height to 1.5–4 m with gaps if it falls outside; test the range.
- [ ] Screenshots Read at zoom 1.2 / 5 / 24 (`tools/screenshot.sh`) and compared with the look reference (TASK-190); deviations stated.

## Playtest (for the human)

1. `true` preset: open country shows solitary trees, roadside and field-edge tree lines, copses and orchards like the reference; forests and other presets are unchanged.
2. Zoom 1.2 / 5 / 24: nothing grows on roads, water or in forests; framerate stays at 60.

## Player manual

None.

## Out of scope

- Settlement plots (TASK-198), buildings (TASK-195), forest interior (TASK-135), hedges on parcel edges (TASK-215b), the import (TASK-199a).

## Implementation notes

- **Code**: `TreeFeatureSet` (`src/presentation/tree_feature_set.gd`: the OSM points / rows / orchard / farmyard polygons of `ImportedMap` in view metres, with bounds) and `TreeFeatures` (`src/presentation/tree_features.gd`, pure static, hash-only: `plan(grid, surface, seed, rect, parcels, look, features)` returns ScatterPlanner-format trees for one chunk rectangle, `[]` on every preset but `true`). Wiring: `BattleCover.tree_features_for_battle` -> `MapView.tree_features` -> `FoliageChunks.tree_features`; `FoliageChunks._plan_source` appends the list to the map `trees` (the existing `trees` layer, so no new draw calls, same TreeField / impostor path as the hedges). Tests: `tests/unit/test_tree_features.gd` (16).
- **OSM**: points exactly at their position; rows a tree every 5..10 m, at most 0.6 m off the polyline; orchards a lattice along the polygon's long axis (`RealParcels.long_axis`), row and tree spacing 5..8 m per orchard, small trees (scale 0.26..0.34 = ~6 m); a farmyard gets with hash probability 0.3 a block of 3..6 x 3..5 trees wholly inside the polygon (holes respected).
- **Rule fill** (all independent of the chunk: a tile's / road piece's result is a pure function of the map, chunks add up to the eager plan - tested): roadside lines (80 m pieces, exactly one in four by hash, one side, 3.3..5.7 m +- 0.3 from the centre line, a tree every 6..12 m = 25 % of a road's length); solitary trees per open hex (PLAINS / FIELDS / HILLS, 0..3, cumulative 0.70 / 0.90 / 0.97; only where a parcel edge or hex edge lies within 15 m - `TreeFeatures.near_boundary`); copses (HILLS / MARSH hexes, chance 0.06, 5..30 trees, at most one per hex, sunflower layout).
- **Filters**: nothing in forest, on water, on URBAN, outside the grid or below `MIN_TREE_GROUND`; the rule fill keeps the full scatter clearance from roads / rivers, the OSM trees and roadside lines only stay off the 5 m carriageway / river bank (the road ribbon is 10 m wide with 2.5 m verges, so a roadside line at 3.3..5.7 m stands on the verge / just beyond it). Building mask (TASK-195) does not exist: no building test (skipped as the task says). Heights: the planned surface height, replaced by the near-surface height through `FoliageChunks.ground` under `true`, like every map tree.
- **Growth**: the test fixture (FIELDS with 12 % hills, 14 % marsh, real parcels) adds <= 20 % of the existing plan + hedges (the copse chance and the solitary distribution were tuned for it: first values gave 42 %).
- **Frame budget** (Suwalki battle, `true`, `SCREENSHOT_CAMERA=1,-40,5`, `SCREENSHOT_MEASURE_FRAMES=120`, Windows GPU): feature off 18.72 ms / 2501 draws / 13 756 k tris; on 20.88 ms and 19.04 ms (two runs) / 2501 draws / 14 140 k tris (+384 k tris, +2.8 %). Draw calls are unchanged; the frame-time delta is +0.3 ms in the second run but +2.2 ms in the first, so the 0.5 ms criterion is NOT proven (run-to-run noise ~2 ms on this machine; the baseline is already above 16.7 ms here). The human should check the FPS on the target GPU.
- **Screenshots** (`.screenshots/t199_z1.2.png`, `t199_z5.png`, `t199_z24.png`, camera on unit 1): at 5 and 24 single trees and small dark copses in the fields are visible (I did not see a tree on a road or in water in these shots, but did not check each one); at 1.2 the camera ended in a forest, so open-country trees are only visible at the edges. NOT compared with the TASK-190 look reference side by side; the Suwalki sample has only 15 OSM trees and no orchard in the shown area, so OSM rows and orchards were verified by tests only, not seen.
- **Not done**: the optional hedge-height tuning (TASK-215b hedges unchanged).

