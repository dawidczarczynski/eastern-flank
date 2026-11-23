# TASK-199b: Real tree features (B): solitary trees, tree lines, copses and orchards in the open country

- **Status**: ready
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

_Filled in by the agent when done._
