# TASK-072: Scalability for very large maps – streaming, culling, aggressive LOD

- **Status**: idea – needs a study first: measure where time goes (CPU draw calls, GPU triangles/overdraw, memory, build time) for 1×, 4×, 16× the current map area.
- **Layers**: presentation (`map_view.gd`, `tree_field.gd`, `grass_field.gd`, terrain/backdrop meshes, ground marks), maybe `core` map generation limits; tools (benchmark)
- **Depends on**: soft **TASK-061**, **TASK-070**; related TASK-050 (quality presets), TASK-052 (backdrop)
- **Model**: opus

## Goal

Maps can grow far beyond today's size (hand-made maps, target "really large") with a stable frame rate and an acceptable load time, on the target GPU and still usable on LOW.

## Facts as of 2026-10-23 (default map, `tools/screenshot.sh`, SCREENSHOT_MEASURE_FRAMES=120, WSL build)

- Frame time 25.7 ms before TASK-061, 28.0 ms after (+9 %); the LOD0 triangle budget in `TreeField` is a global per-radius guard (now 1.1 M), not scaled by map size.
- Everything is built eagerly in `MapView.build()` (all tiles, all scatter, all trees, grass), so build time and memory grow linearly with the map area.

## Design (draft)

- **Benchmark tool** (`tools/bench.sh`): builds a map at a given size, prints build time, instance counts, triangles, frame time at fixed cameras (overview, close-up). The human has no FPS tool, so this is what decides.
- **Chunked world**: terrain, scatter, trees and grass built per chunk (e.g. 8×8 units, as `TreeField` already does), built lazily around the camera (distance rings) and freed far away; far chunks represented by merged low-poly impostors or only the terrain mesh + colour.
- **Culling and ranges**: per-chunk `visibility_range` for everything (grass ~25, undergrowth ~12, shrubs ~22, trees LOD0 ~30, LOD1 ~80, beyond: billboards/impostors or terrain tint only); frustum culling is automatic per MultiMesh – chunks keep AABBs tight.
- **Budgets by distance, not by map**: the triangle budget applies within the camera reach only, independent of map size; scale scatter density with quality preset.
- **Terrain**: clipmap or chunked heightfield with LOD; backdrop as part of the same system.
- **Instance data**: avoid per-instance GDScript loops at build time for huge counts (precomputed packed buffers, worker threads for planning – the planners are pure `RefCounted`, so they can run in `WorkerThreadPool`).

## Acceptance criteria (testable)

- [ ] (to be written when `ready`, after the study: benchmark tool exists; a map 16× the current area builds in ≤ X s and holds ≤ Y ms frame time in the benchmark; budgets are by camera reach.)

## Playtest (for the human)

1. Load a very large test map; pan across it; no hitches when new areas appear.
2. Zoom out fully: the whole map is visible and still smooth.

## Player manual

None.

## Out of scope

- Game-logic performance (pathfinding, AI) on large maps – separate task if it becomes a problem.

## Implementation notes

_Filled in by the agent when done._
