# TASK-072b: Chunked lazy world – build and free terrain, scatter, trees, grass and marks around the camera

- **Status**: ready
- **Layers**: presentation (`MapView`, `TerrainGround`, `TreeField`, `GrassField` / `GrassPlanner`, `ScatterChunks` / `ScatterPlanner`, `BackdropMesh` / `BackdropCanopy`, ground marks), tools; no core rule change
- **Depends on**: TASK-072a
- **Sections**: GDD "Visual direction" (Performance); ADR 0021, ADR 0022, ADR 0023
- **Model**: opus (threads, determinism, timing between systems)

## Goal

A very large map (16x Suwałki, ~11 500 hexes) loads fast and runs at about today's Suwałki frame cost, because only chunks within metre-based rings around the camera exist.

## Decisions (2026-11-20)

1. Scope: a chunk manager builds/frees terrain, scatter, trees, grass and ground marks around the camera with metre-based distance rings. TASK-134 (terrain LOD, real-metre ground) and TASK-135 (impostors, canopy shells, real density) keep their scope and plug into the manager; 072b implements neither.
2. Target: a 16x map (11 520 hexes) must build and run.
3. Frame bar is map-size independent: cost depends on what the camera reaches, not on map size; no hitch above 33 ms while panning. Hard 60 FPS stays with TASK-134/135/138.
4. Load time and memory must not grow linearly with map area: only the initial visible area is built up front.
5. Determinism: scatter positions unchanged (same seed → same positions); chunk build order never changes results; no `GameState.rng` use.

## Assumptions

- **[ASSUMPTION]** Chunk size 8x8 world units, as `TreeField`; `TacticalLayer`/`TacticalChunk` (core) stay the source of theatre terrain and are only read.
- **[ASSUMPTION]** Ring radii are given in metres (`MapScale`, data-driven in a `.tres`): build ring 1.5x the draw reach, free ring +20 % beyond it (hysteresis against thrash).
- **[ASSUMPTION]** Planners (pure `RefCounted`) run on `WorkerThreadPool`; Nodes/MultiMeshes/RenderingServer calls only on the main thread (ADR 0022 rule 3).
- **[ASSUMPTION]** Far terrain stays a coarse single mesh / colour tint; terrain LOD itself is TASK-134.
- **[ASSUMPTION]** LOW quality keeps working (smaller rings). Placeholders `B_*` below are filled from TASK-072a's baseline and confirmed after it lands.

## Acceptance criteria (testable)

- [ ] A `ChunkManager` (presentation) holds a set of live chunks keyed by chunk coordinate; test: moving a synthetic camera builds exactly the chunks inside the build ring and frees those outside the free ring.
- [ ] Hysteresis: a camera oscillating ±10 % of a ring radius around the border builds/frees 0 chunks after the first pass (test).
- [ ] Terrain, scatter, trees, grass and ground marks register with the manager through one chunk interface (build(chunk), free(chunk)); TASK-134/135 can add layers without changing the manager (test with a stub layer).
- [ ] Scatter positions in a chunk are identical to the eager build for the same seed, regardless of build order (test: shuffled order, compare packed positions); no `GameState.rng` access.
- [ ] Threaded plans equal single-thread plans (test, as ADR 0022); the main thread spends ≤ 4 ms per frame on chunk finishing (budget enforced, queue carries over).
- [ ] 16x map: initial build ≤ 1.5 x baseline Suwałki build time [ASSUMPTION: B_build from 072a] and memory ≤ baseline Suwałki + 25 % [ASSUMPTION: B_mem].
- [ ] 16x map: build time and static memory at 16x ≤ 1.5 x those at 4x (not linear in area).
- [ ] 16x map frame time at distances 46 / 24 / 7 / 1.2 ≤ baseline Suwałki avg ms + 1.0 [ASSUMPTION: B_frame from 072a / ADR 0021 table].
- [ ] Pan sweep over the 16x map (10 s, as 072a): 0 frames > 33 ms [ASSUMPTION threshold, confirm after 072a].
- [ ] Zoomed fully out on the 16x map the whole map shows (coarse terrain + backdrop tint) with instance count ≤ Suwałki's overview count.
- [ ] Existing Suwałki map renders as before: same instance counts per layer within the draw reach; screenshot Read by the agent shows no missing chunk at the screen edge.
- [ ] LOW quality builds with smaller rings and passes the same chunk tests.
- [ ] `tools/check.sh --full` passes; benchmark table from 072a re-run and recorded in the notes.

## Playtest (for the human)

1. Load the 16x test map (`tools/bench_large_map.sh` scenario); the battle opens in about the time of Suwałki.
2. Pan quickly across the map: no hitches, no visible trees/grass popping in at the screen edge.
3. Zoom fully out and in: whole map visible and smooth.

## Player manual

None.

## Out of scope

- Terrain LOD and real-metre ground (TASK-134); impostors, canopy shells, real density (TASK-135); making the real-scale preset default (TASK-138).
- Units and game logic at scale (pathfinding, AI) – separate task if needed.

## Implementation notes

_Filled in by the agent when done._
