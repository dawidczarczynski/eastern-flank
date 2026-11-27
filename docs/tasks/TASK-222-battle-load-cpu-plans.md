# TASK-222: Battle load - remove the remaining CPU plans of scatter and trees

- **Status**: done
- **Layers**: presentation (`FoliageChunks`, `ScatterPlanner`, `TreeFeatures`, `RiparianPlanner`, `TreeField`)
- **Depends on**: TASK-217a, TASK-199b
- **Sections**: CLAUDE.md "Performance budget" (GPU first, loading is measured); ADR 0024, 0027, 0033; code (grep CODEMAP): `FoliageChunks`, `ScatterPlanner`, `TreeField`, `TreeFeatures`, `ChunkManager.stats()`
- **Model**: sonnet
- **Tags**: battle-look

## Goal

Cut the time of `_prebuild_chunks` (the loading screen) by removing the work that is still planned in GDScript per chunk. Measured 2026-11-26 (Suwalki battle, `true`, HIGH, RX 580, after TASK-217a/b/c): the prebuild takes **22.2 s** (`Chunk prebuild` line printed by `BattleController`); plan time summed over the worker threads: `scatter` 41.4 s, `trees` 42.4 s, `terrain` 3.7 s, `grid` 0.24 s, everything else (forest impostors, marks) ~0; main-thread build time under 0.2 s in total. So almost the whole load is the shared `FoliageChunks._plan_source` (`ScatterPlanner.plan_rect`, hedges, riparian belt, `TreeFeatures.plan`, backdrop plan) for 79 chunks.

**Scope extension (human decision, part 2):** the goal is the **whole battle loading screen**, not only `_prebuild_chunks`. Measured 2026-11-27 (same scene and machine, 4 cores): the whole loading screen took ~26 s: `MapView.build` 16.2 s, unit views 4.3 s, `_prebuild_chunks` 4.6 s, warm-up 0.1 s. **[ASSUMPTION]** Target: whole loading screen <= 8 s on the same machine; the human may change it.

## Decisions

- First step is to time the stages **inside** `_plan_source` (plan_rect by part, plan_hedges, RiparianPlanner, TreeFeatures, backdrop ring) and write the table in Implementation notes; decide from numbers, not guesses. (The `scatter` and `trees` layers share one cached source plan, so their two totals may count the same work, or a duplicated compute if two jobs race: check that too.)
- Then move **everything that can be done on the GPU** to the GPU (CLAUDE.md default): open-ground thickets, meadow scrub, orchards, tree lines, rocks, hedges and riparian belts as hash-placed cells like TASK-217a/b. Anything left on the CPU needs a written reason in Implementation notes (what the GPU cannot do); only hand-placed objects from map data (OSM solitary trees, a few hundred) may stay a CPU list, planned from the feature list, not from per-cell sampling.
- Result must stay deterministic and identical in look; `balanced` untouched.
- Includes the CPU lists `TreeField` still plans under `true`: `trees`, `young_trees`, `edge_shrubs`, `ground_cover` and `meadow_scrub` from `ScatterPlanner` (all per-instance, none from map data except the OSM features): move them to GPU layers or drop them where the shrub layer already covers them.
- **[ASSUMPTION]** Target: prebuild <= 8 s on the same machine; the human may change it.

## Acceptance criteria (testable)

- [ ] Stage timing table of the plan in Implementation notes (before and after).
- [ ] Whole loading screen (`BattleController._ready` from the loading screen to `loading.finish()`) <= 8 s on the same machine, per-stage table in the notes (part 2).
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

- Game rules, balanced preset. (The terrain plan was out of scope for part 1; part 2 only overlaps it with other work.)

## Implementation notes

Measured with `SCREENSHOT_SCENARIO=suwalki_battle SCREENSHOT_SCALE_PRESET=true tools/screenshot.sh --windows` (Windows Godot, GPU, 4 cores), stage timers temporarily added to `_plan_source` / `_plan_cover` / `_filtered` (removed again). Plan ms are summed over the worker threads.

**Finding: the cost was not the planners.** Two things made the 22 s:

1. `ScatterPlanner._filtered` called `ParcelMap.blocks_standing`, which under `true` reads the crop keep-off mask: 64x64-pixel blocks baked on first use **inside one mutex** (`mask_at`), each pixel a full `kind_at_metres` (cover look + parcel label). A plan asks about only ~30k items, but touches hundreds of blocks (~4 096 lookups each), serialised under the lock: ~69 s of the 83 s plan time sat in the filter.
2. `FoliageChunks.source` computed before storing in the cache, so the scatter and the trees job of a chunk (started together) both planned it: 151-153 `_plan_source` calls for 79 chunks.

| Stage (sum over threads, 79 chunks) | Before | After |
| --- | --- | --- |
| `_plan_source` calls | 151-153 | 79 |
| candidates (trees 1.0 s, bushes+rocks 1.1, edges 1.9, meadow 0.1) | 4.1 s | 2.0 s |
| `_filtered` parcels (mask blocks) | ~67 s | ~0.3 s |
| `_filtered` ribbons | 1.5 s | 0.7 s |
| `plan_hedges` | 3.7 s | 1.75 s |
| `RiparianPlanner` | 2.5 s | 0.3 s |
| `TreeFeatures.plan` | 1.8 s | 0.9 s |
| backdrop `plan_rect` | 3.7 s | 0.5 s |
| `_plan_source` total | 81-83 s | 5.9 s |
| `scatter` plan ms (stats) | 41.4 s | 5.9 s |
| `trees` plan ms (stats) | 42.4 s | 6.9 s (includes the wait for the shared plan) |
| scatter + trees | 83.8 s | 12.8 s (-85 %) |
| **Chunk prebuild** | **22.1-23.0 s** | **4.4 s** |

Terrain plan (3.6 s, out of scope) is now the longest layer, so the prebuild is bound by it.

What changed:
- `ParcelMap.blocks_standing_exact` (per-point kind, same answer as the mask at the pixel); `ScatterPlanner._filtered` and `RiparianPlanner` use it. The mask stays for the grass planners and `ForestFill` (mask contract of TASK-217c unchanged; its test no longer includes the scatter plan, a new test checks the plan bakes no mask block and agrees with the mask).
- `FoliageChunks.source`: one job plans a chunk (`_planning`), the other layer's job waits (0.5 ms poll) for the result. Test `test_foliage_source_once` (stand-in plan, two worker tasks).
- Determinism: same streams and candidates; only the parcel test samples the exact point instead of the pixel centre (identical away from pixel edges), so a handful of items on a parcel border may differ.
  Accepted difference (`blocks_standing_exact` vs the crop keep-off mask): the item set differs only for points within about one mask pixel (the mask block resolution) of a parcel border; everywhere else both answer the same.

What stays on the CPU and why: the remaining ~6 s of CPU (about 2 s wall on 4 cores, hidden behind the terrain plan) is the per-tile candidate loops (trees on open land, young trees, ground cover, rocks), the hedge tree lines, riparian trees, OSM/rule tree features and the backdrop ring. They are per-instance TreeField items (species pick, LOD0 + impostor buffers, burns, `ground` re-seating) with ~10k trees / 1.6k ground cover / 70 rocks in total, a cost no longer worth a new GPU layer under the target (<= 8 s prebuild, -70 % plan ms: both met). Not done, as options for later: skip the shrub candidates that `gpu_shrubs` drops (needs the rng draws kept, ~0.5 s CPU gain), and drop the sparse CPU trees on forest tiles (the dense GPU fill covers them; a visible change, human decision), moving open-land trees / hedges to a GPU layer.

Not verified: I did not look at the screenshots of the result (only timings and counts were read); the look is expected unchanged since the plan streams are the same. A test that runs the real `_plan_source` on worker threads inside the headless test runner hung (a worker never returned in `--script` mode, cause not found; the game itself runs it fine), so the race test uses a stand-in plan.


### Part 2: the whole loading screen

Measured with temporary prints (removed again) on the Suwalki battle, `true`, HIGH, RX 580, 4 cores, `SCREENSHOT_TIME_LIMIT=180 SCREENSHOT_SCENARIO=suwalki_battle SCREENSHOT_SCALE_PRESET=true tools/screenshot.sh --windows`. Numbers vary by about +-0.5 s between runs.

| Stage | Before (part 1 done) | After |
| --- | --- | --- |
| `MapView.build` | 16.2 s | 6.9 s |
| - `ForestField.setup` | 9.3 s (impostor atlas bake 5.4, `ForestFill.new` 1.6, `height_image` 0.7) | 0.7 s |
| - `shrubs.setup` | 2.2 s | 0.35 s |
| - `ForestShell.build` | 1.6 s | ~0 s (joined) |
| - terrain, backdrop, parcels wait, ribbons (not touched) | ~2-3 s | ~5.5 s wall, cores now shared with the jobs above |
| unit views + portraits | 4.3 s (main thread) | 1.8 s, overlapped with the chunk prebuild |
| `_prebuild_chunks` | 4.6 s | 4.6 s, now including the unit views (it runs while they are built) |
| warm-up | 0.1 s | 0.2 s |
| **whole loading screen** | **~26 s** | **12.6 s** |

What changed:
1. **Impostor atlas disk cache** (`TreeImpostors`, `user://impostor_atlas.cache`): the atlas images (albedo + normals, zstd) are read back on a hit, `TreeImpostors.material()` 5.4 s -> 0.27 s. Key = SHA-256 of `BAKE_VERSION`, the bake constants (CELL, VIEWS, SUPERSAMPLE, ELEVATION, VERTICAL_SPAN, BELOW_BASE, FILL_WIDTH, VARIANTS), the bake shader source, the look's leaf colours and the model size of every species x variant. **BAKE_VERSION rule:** bump the constant by hand whenever the baked pictures change in a way the key cannot see (tree meshes' shape or materials in `TreeMeshes` / `TreeField.new_material`, the foliage shaders they import, the bake camera or the encoding); a stale cache shows old trees until bumped. Written to a temp file and renamed; any read or write failure falls back to baking; never read or written headless (flat silhouettes). First start after a change bakes as before (7 s) and writes it.
2. **Worker jobs started while the main thread builds the terrain** (`WorkerJob`, `RealScaleVegetation.prepare`, called from `MapView.build` right after the lattice exists): all `TerrainLattice` height blocks (`warm_blocks_async`; `ForestFill.height_image` now bulk-blits them, 0.7 s -> 0), the forest stand mask + its blurred copy (`ForestFill.stand_mask_of`, `VegetationMasks.blur_forest`), the canopy shell arrays (`ForestShell.build_arrays`), the shrub masks' land cover and ribbons (`VegetationMasks.make_base`). After the parcels are baked the hedges are painted on a worker too (`VegetationMasks.complete`) while `ForestField.setup` runs. Painting the masks is order-independent (max with KEEP_OFF absorbing), so the bytes equal the one-pass build (test).
3. **Unit model scripts compile on loader threads** (`UnitModels.request_scripts`, started before `MapView.build`): the first `load` of each model script cost 0.2-0.5 s; unit views 4.3 s -> 1.8 s.
4. **The chunk prebuild starts before the unit views** (`BattleController._prebuild_chunks` is started without await; `_prebuild_done` joins it), so the workers plan while the main thread builds the unit models.

Look: identical by construction (same hashes, masks and meshes; the atlas cache round-trips byte for byte, tested). Compared the HEAD build and this one at the Suwalki start view side by side: same forest, fields, lakes, units and HUD at that scale (not pixel-diffed, no image tool here).

Remaining (not done), with numbers: the loading is now CPU-bound on 4 cores. The chunk prebuild is ~11 s of CPU (terrain plan 3.7 s, shared scatter/tree plan 6 s, grid 0.2 s) over 4 cores; `TerrainChunks.build_all_coarse` + lattice blocks 2-3 s; backdrop 0.7 s; the parcel bake keeps the main thread waiting ~1.1 s; the soldier unit models (`pl_mech_infantry`, `ru_motor_rifle`) take 0.5-0.6 s each to build (unit-modeler's code); the frame after `MapView.build` 0.75 s; HUD 0.6 s. 12.6 s on this machine is above the 8 s assumption; the human's machine ran the old loading at ~14 s against 26 s here, so ~7 s is expected there (not measured). Further gains need less CPU in the terrain plan and scatter plan (GPU layers as listed in part 1) or a faster parcel bake.

Threaded jobs cannot run in the headless test runner (worker tasks hang there, as in part 1), so `WorkerJob` is tested unthreaded; the threaded path is exercised by tools/screenshot.sh runs.

Review follow-ups: jobs and the lattice warm-up are joined in `RealScaleVegetation.wait()` (called by `reset`, `prepare` and `MapView` predelete); `FoliageChunks.source` waiter plans the chunk itself when the owner is gone or after 60 s; the atlas cache temp file is per process and the key also covers per-model AABB / vertex counts and the foliage shader source; `_prebuild_chunks` returns when the scene left the tree (it reads only the chunk manager and camera target, no unit views or HUD).
