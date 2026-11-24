# TASK-218a: Road furniture by road class (1/2) – guardrails, noise screens, signs, lights, crossings

- **Status**: blocked
- **Layers**: data (`data/` resource with the per-class rule table) + presentation (new `RoadFurniturePlanner` + `RoadFurniture` drawer; edge lines / zebra markings in `FeatureRibbonPlanner` / `road.gdshader`)
- **Depends on**: TASK-202 (road class + surface per tile, widths, junctions); soft: TASK-198 (settlement surroundings), TASK-216
- **Sections**: ARCHITECTURE "Terrain rendering" (road ribbon bullet), "Two layers"; code (grep CODEMAP): `FeatureRibbonPlanner`, `FeatureRibbons`, `bridge_sites.gd`, `ScatterPlanner` / `scatter_chunks.gd` (MultiMesh chunking pattern), `MapScale`, `road.gdshader`
- **Model**: sonnet
- **Tags**: battle-look

## Goal

Roads carry the furniture their class implies: expressways have guardrails and noise screens, main roads have signs, towns have street lights and zebra crossings, junctions have give-way signs. Everything comes from **rules per road class** (TASK-202 class + existing settlement / building data), **not** from OSM nodes or tags. `true` preset only; `balanced` / default unchanged. Roundabouts, traffic lights and overpasses are TASK-218b.

## Decisions / assumptions

- **[ASSUMPTION]** No importer change. Inputs: road class and surface (TASK-202), ribbon centre lines from `FeatureRibbonPlanner`, settlement / building hexes, terrain slope. Placement is deterministic (hash of tile coordinate + kind; no `GameState.rng`).
- **[ASSUMPTION]** Rule table lives in a `data/` Resource (`RoadFurnitureRules`): per class and kind -> spacing, side offset from the carriageway edge, context (`open` / `settlement`). TASK-218b adds its own rows to the same resource. Starting values:

| Kind | Class 1 (motorway/trunk) | Class 2 (primary) | Class 3 (secondary/tertiary) | Class 4 (residential) | Class 5-6 |
|---|---|---|---|---|---|
| Guardrail (W-beam, 0.8 m) | both sides, always | on embankments / bends / by bridges | by bridges only | – | – |
| Median barrier (concrete, 0.9 m) | when another class-1 ribbon is < 30 m away | – | – | – | – |
| Noise screen (3.5 m, panels) | where a building is < 80 m from the edge, over its length + 20 m | – | – | – | – |
| Road signs (speed limit, warning, direction) | every ~400 m, speed sign after each junction | every ~250 m | settlement entry/exit + bends | settlement entry (name plate) | – |
| Junction signs (give-way / stop) | – | minor road at a T-junction with it | minor road at a T-junction | give-way at junctions with a higher class | – |
| Street lights (8 m pole, 40 m spacing) | at junctions only | in settlements | in settlements | in settlements | – |
| Delineator posts (0.1 m, 50 m spacing) | – | open land | open land | – | – |
| Zebra crossing + sign | – | in settlements, at settlement entry | in settlements near a junction | near a junction in settlements | – |
| Edge lines (solid) | yes | yes | yes | – | – |

- **[ASSUMPTION]** "Settlement" = the tile or a neighbour is a built-up hex (reuse the village / building test).
- **[ASSUMPTION]** Signs: flat plates with pictograms from one small atlas (speed limits 30/50/70/90/120, give-way, stop, pedestrian crossing, warning triangle, town name plate); no readable text beyond numbers.
- Performance: furniture scales with road length, not map area, so CPU planning is allowed but stays < 20 ms per chunk (TASK-217 rule). One MultiMesh per kind per chunk, shared meshes (< 300 triangles), visibility range per kind (signs / lights 250 m, barriers 400 m, screens 600 m), no per-instance lights.

## Acceptance criteria (testable)

- [ ] `RoadFurnitureRules` resource loads; every kind above has per-class spacing and offset; changing a value changes planner output (test); no numbers hard-coded in the planner.
- [ ] Straight class-1 fixture, 1 km, open land: guardrail on both sides over the full length, gaps only at junction / bridge sites; signs ~ every 400 m; no street lights; no zebra crossing.
- [ ] Class-1 fixture with a building 50 m from the edge: noise screen over the building's span + 20 m, only on that side; building at 120 m: none.
- [ ] Class-4 settlement road with a T-junction to class 3: give-way sign on the class-4 arm only, lights every 40 m ± 1 m on one side, one zebra crossing near the junction; the same road in open land has none of these.
- [ ] Furniture is outside the carriageway + verge of every ribbon (fixture with parallel and crossing roads), not on water, not inside buildings, not on slopes steeper than 35 %.
- [ ] Determinism: same map twice -> identical output; instance counts per kind appear in `ChunkManager.stats()`.
- [ ] `balanced` preset: no furniture, planner output for a road fixture identical to before (test); maps without class data (style 0) get none.
- [ ] Budget on `true` at Suwałki: planning < 20 ms per chunk, ≤ 8 extra draw calls per chunk view, frame time within 0.3 ms of before, 60 FPS kept.
- [ ] Screenshots (Read; `tools/screenshot.sh` at camera distance 0.4 / 1.2 / 5) of: expressway with guardrails and noise screen next to a village, a village road with lights + zebra, a T-junction with a give-way sign; compared with the look reference (TASK-190); deviations stated.

## Playtest (for the human)

1. `tools/run.sh --scenario=suwalki_battle` on the `true` scale; follow the expressway: guardrails both sides, signs, noise screens beside villages.
2. Go through a village: street lights, a zebra crossing near the junction, give-way signs on side roads; open-land roads have only signs and posts.
3. Switch to the default scale: roads look exactly as before.
4. FPS at the busiest village (HIGH quality): 60.

## Player manual

docs/MANUAL.md "Roads and rivers": on the true-size scale roads carry class-based furniture (guardrails, noise screens, signs, lights, crossings); purely visual.

## GDD

No rule changes – GDD untouched.

## Out of scope

- Roundabouts, traffic lights, overpasses (TASK-218b); importing real signs / lights / barriers from OSM.
- Vehicles and traffic; other street furniture (bus stops, benches), tunnels, toll gates, petrol stations; movement / cover effects of barriers.

## Implementation notes

_Filled in by the agent when done._
