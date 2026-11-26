# TASK-222: Battle load - remove the remaining CPU plans of scatter and trees

- **Status**: ready
- **Layers**: presentation (`FoliageChunks`, `ScatterPlanner`, `TreeFeatures`, `RiparianPlanner`, `TreeField`)
- **Depends on**: TASK-217a, TASK-199b
- **Sections**: CLAUDE.md "Performance budget" (GPU first, loading is measured); ADR 0024, 0027, 0033; code (grep CODEMAP): `FoliageChunks`, `ScatterPlanner`, `TreeField`, `TreeFeatures`, `ChunkManager.stats()`
- **Model**: sonnet
- **Tags**: battle-look

## Goal

Cut the time of `_prebuild_chunks` (the loading screen) by removing the work that is still planned in GDScript per chunk. Measured 2026-11-26 (Suwalki battle, `true`, HIGH, RX 580, after TASK-217a/b/c): the prebuild takes **22.2 s** (`Chunk prebuild` line printed by `BattleController`); plan time summed over the worker threads: `scatter` 41.4 s, `trees` 42.4 s, `terrain` 3.7 s, `grid` 0.24 s, everything else (forest impostors, marks) ~0; main-thread build time under 0.2 s in total. So almost the whole load is the shared `FoliageChunks._plan_source` (`ScatterPlanner.plan_rect`, hedges, riparian belt, `TreeFeatures.plan`, backdrop plan) for 79 chunks.

## Decisions

- First step is to time the stages **inside** `_plan_source` (plan_rect by part, plan_hedges, RiparianPlanner, TreeFeatures, backdrop ring) and write the table in Implementation notes; decide from numbers, not guesses. (The `scatter` and `trees` layers share one cached source plan, so their two totals may count the same work, or a duplicated compute if two jobs race: check that too.)
- Then move **everything that can be done on the GPU** to the GPU (CLAUDE.md default): open-ground thickets, meadow scrub, orchards, tree lines, rocks, hedges and riparian belts as hash-placed cells like TASK-217a/b. Anything left on the CPU needs a written reason in Implementation notes (what the GPU cannot do); only hand-placed objects from map data (OSM solitary trees, a few hundred) may stay a CPU list, planned from the feature list, not from per-cell sampling.
- Result must stay deterministic and identical in look; `balanced` untouched.
- Includes the CPU lists `TreeField` still plans under `true`: `trees`, `young_trees`, `edge_shrubs`, `ground_cover` and `meadow_scrub` from `ScatterPlanner` (all per-instance, none from map data except the OSM features): move them to GPU layers or drop them where the shrub layer already covers them.
- **[ASSUMPTION]** Target: prebuild <= 8 s on the same machine; the human may change it.

## Acceptance criteria (testable)

- [ ] Stage timing table of the plan in Implementation notes (before and after).
- [ ] `Chunk prebuild` after the change <= target (measured with `SCREENSHOT_SCENARIO=suwalki_battle SCREENSHOT_SCALE_PRESET=true tools/screenshot.sh --windows`), written in the notes.
- [ ] `scatter` + `trees` plan ms in `ChunkManager.stats()` under `true` fall by >= 70 %.
- [ ] Existing planner tests green; any moved rule has a GDScript reference twin test.
- [ ] `tools/check.sh --full` passes.

## Playtest (for the human)

1. Loading screen is clearly shorter than before; the battlefield looks the same (compare with `docs/images/gameplay.png`).
2. Pan and jump the camera: no new popping of trees / bushes / rocks.

## Player manual / GDD

None.

## Out of scope

- Terrain plan (3.7 s), game rules, balanced preset.

## Implementation notes

(empty)
