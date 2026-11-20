# ADR 0024: Chunked lazy world – one chunk manager, metre rings, per-tile scatter seeds

- **Status**: accepted
- **Date**: 2026-11-20
- **Task**: TASK-072b (baseline TASK-072a)

## Context

TASK-072a measured the Suwałki map tiled to 4× and 16× its area: the build grew roughly linearly with the map (5.2 s → 14.4 s → 51.7 s), static memory 79 → 609 MB, and the frame time doubled at 16× because every tree, bush, grass chunk and the one terrain mesh existed for the whole map. Large theatre maps need the build and the frame cost to follow what the camera reaches, not the map area.

## Decision

1. **One chunk manager, one layer interface.** `ChunkManager` (presentation, `RefCounted`) keeps live chunks per `ChunkLayer`. A layer is three callables – `plan_chunk(chunk)` (pure, worker thread), `build_chunk(chunk, plan)` and `free_chunk(chunk)` (main thread) – plus chunk size, origin and area. Terrain, bushes / rocks, trees, grass, grid lines and ground marks are layers; TASK-134 (terrain LOD) and TASK-135 (impostors, canopy shells) add layers without touching the manager.
2. **Rings in metres, as data.** `ChunkRings` (`data/visuals/chunk_rings.tres`): draw reach per layer in metres around the camera target (through `MapScale`), build ring 1.5 × reach, free ring 1.2 × build ring, LOW × 0.66. Values: terrain, scatter, trees, grid, marks 4 040 m (28 units: from the centre of Suwałki the whole map lies inside, so the existing map looks as before), grass 1 925 m (the former 20-unit grass build radius).
3. **Threads plan, the main thread finishes within a budget.** Plans run in batches on the `WorkerThreadPool` (ADR 0022 rule 2: read shared state only, write an own slot; lazy caches are filled on the main thread first). Nodes, meshes and MultiMeshes are made on the main thread (ADR 0022 rule 3) within 4 ms a frame (frees take at most half of it: a camera jump leaves hundreds of chunks to free, ~0.4 ms each); the plans carry ready-made arrays (terrain mesh arrays with packed weights, MultiMesh buffers) so a build is a few hundred microseconds to ~2 ms. The queue carries over to the next frame. In play a batch uses two threads fewer than there are cores, at normal priority: with every core planning, the main and render threads were starved into 80–140 ms frames while panning; behind the loading screen (`finish_all`) all threads plan at high priority.
4. **Terrain: global lattice, fine chunks near, coarse everywhere.** Heights are a pure function of the lattice index (`TerrainLattice`), so chunks agree on shared vertices; skirts hide the slivers between a fine chunk and its coarse neighbour or the backdrop. A coarse mesh (every 4th vertex) of every chunk is built up front, 4 × 4 chunks per node; a group's index buffer leaves out the chunks that have a fine mesh, so the whole map always shows. `mesh_height_at` reads height blocks computed on first use; a block is only computed after 48 queries into it (stray queries such as the camera's ground clearance read the four cell corners instead of computing a block on the main thread). The backdrop ring asks only for border heights and builds its vertices on the worker threads.
5. **Scatter is seeded per tile.** `ScatterPlanner` seeds every tile's RNG streams from (seed, tile, stream salt) instead of one stream over the whole map, so a chunk plans the tiles whose centre lies in it and the chunks together give exactly the eager plan, in any order. This changes the scatter layout once (the same counts per tile type and the same distributions, other positions); from now on the same seed always gives the same positions.

## Consequences

- (+) Build cost and live content follow the rings; a chunk's content never depends on build order or thread count (tested: shuffled chunk order = eager plan, threaded = single-thread, hysteresis builds/frees nothing after the first pass).
- (+) The Suwałki-sized battle builds everything within the rings, as before.
- (−) What is not chunked stays linear in the map: the coarse terrain (area), the farmland parcel texture (5 m/px over the whole map: ~72 MB at 16× Suwałki), the backdrop ring and its canopy shell (perimeter). Parcels need a windowed texture with an analytic planner query to follow (the bake's result near a window edge depends on the window, so it cannot simply be cropped).
- (−) Beyond the rings forests show as coarse ground without trees until TASK-135 adds canopy shells / impostors; overlays that cover the whole map (the reach dim) compute every height block on first use.
- `TerrainSurface.prime()` does not fill the neighbour offsets of the authored-elevation surface (imported maps); two planning threads filling that static array at once corrupted it (seen as non-deterministic scatter and a crash). `MapView.prime_surface` queries one height on the main thread first; the core could fill it in `prime()` (need for gameplay-engineer).
