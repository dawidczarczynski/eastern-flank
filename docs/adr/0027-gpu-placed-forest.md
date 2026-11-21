# ADR 0027: GPU-placed forest – impostor trees derived in the vertex shader, not planned on the CPU

- **Status**: proposed
- **Date**: 2026-11-21
- **Task**: TASK-189 (builds on ADR 0024 chunked world, ADR 0026 real-scale vegetation)

## Context

At real size (ADR 0026) a forest hex holds ~2 000 trees. Each one is planned in GDScript on the worker threads (`ForestFill.plan_rect` + `TreeSpecies.pick` + `TreeImpostors.entry` + the MultiMesh buffer): ~50–80 µs a tree, ~100–200 ms per 2-unit impostor chunk, ~16 s of CPU to rebuild the impostor ring after a camera jump (measured on 4 WSL cores, TASK-135 playtest round 1). The playtest shows the consequence: after a zoom or a jump the forest fills in chunk by chunk over seconds (the canopy shell stands in meanwhile, but the player sees the swap). Micro-optimisations already took ~2.3x; the rest is the cost of interpreted per-tree work.

Everything that decides a fill tree is a pure function of its grid cell: a hash of (seed, cell) gives the jittered point, size, species roll and colour variation; the tile under the point decides forest / clearing; roads, rivers and field parcels keep it off; the ground gives its height. A vertex shader can evaluate the same function per instance, in parallel, every frame, for free compared with the CPU path.

## Decision

1. **Impostor trees are placed by the GPU.** An impostor chunk is a MultiMesh of the `TreeImpostors` quad with `instance_count` = the fill grid cells of the chunk and **no per-instance data**. `tree_impostor.gdshader` derives the cell from `INSTANCE_ID` and the chunk origin (instance shader parameter), and from it everything `ForestFill` / `TreeSpecies` / `TreeImpostors.entry` compute today; an instance whose cell holds no tree is collapsed to a point (as the LOD hand-over already does). Building a chunk is creating a node – no worker plan, no buffer.
2. **The map is handed to the shader as textures**, built once per map: a forest mask (tile is FOREST), a keep-off mask (roads, rivers, field parcels, the tile-centre clearing) at ~4.5 m, and the ground height (the lattice, plus a near-surface height tile cache around the target filled from the near terrain chunks' own height arrays as they are built – no extra surface queries).
3. **One hash, two implementations.** The integer hash and the cell → tree formulas exist once in GDScript (the reference, used by the full trees and by tests) and once in GLSL (`assets/shaders/forest_hash.gdshaderinc`). They use 32-bit unsigned arithmetic only, so both give the same bits; a test fixes the GDScript values of a few cells, the shader include carries the same constants, and a screenshot check confirms a full tree and its impostor stand at the same point.
4. **Full trees stay CPU-planned** (`ForestField` full layer, 170 m ring, ≤ 6 000 trees): few, near the camera, and they need the exact near-surface height. Their planning becomes cheaper still because the impostors no longer compete for the worker threads.
5. **Determinism and the simulation are untouched**: placement is cosmetic, uses no `GameState.rng`, and the game state never reads it.

## Consequences

- (+) An impostor chunk appears the frame its node is created: no seconds of filling in, no shell stand-in near the camera; the worker threads are free for terrain, grass and full trees.
- (+) Denser or farther impostors cost GPU vertex work only (collapsed instances are cheap), so the impostor range could grow towards the horizon and the canopy shell shrink.
- (−) The tree rules exist twice (GDScript + GLSL); a change to one must be mirrored, guarded by the fixed-value test and a screenshot.
- (−) Headless tests cannot see GPU placement: they test the GDScript reference and the mask / height textures, not the drawn trees.
- (−) Vertex work for every cell of a chunk, tree or not (a chunk is only created where it touches forest); to be measured on the RX 580 against the 16.7 ms budget.
- (−) The near-surface height cache is new state in the view layer (filled by `TerrainNear`, read by the shader), with its own resolution / memory limit.
