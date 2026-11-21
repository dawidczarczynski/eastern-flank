# TASK-195: Buildings in the world – chunk layer, LOD, ground fit

- **Status**: idea
- **Layers**: presentation (`BuildingField` chunk layer, `MapView`, `ChunkRings`)
- **Depends on**: TASK-193, TASK-194
- **Sections**: ARCHITECTURE "Chunked lazy world"; ADR 0024, ADR 0026, ADR 0027
- **Model**: opus

## Goal

The buildings of the map are drawn where they really stand, on the ground, at a frame time that holds 60 FPS on the target GPU, with distant villages as cheap masses and near ones in full.

## Acceptance criteria (testable)

- [ ] `BuildingField` is a chunk layer (build / free rings in `chunk_rings.tres`): buildings are planned per chunk from `buildings_in(rect)`; one MultiMesh or merged mesh per chunk and LOD; draws per chunk <= 4.
- [ ] LOD0 (full mass with facade UVs) within ~400 m, LOD1 (box + roof) to ~2 km, beyond that a per-chunk merged silhouette or nothing; hand-over per building in the vertex shader like the trees (no pop, no double draw).
- [ ] Buildings stand on the drawn terrain: the base follows the near surface (TASK-134) with a foundation skirt so slopes show no gap; flat ground plate under big halls; the terrain under a footprint is flattened visually only (heights unchanged for the simulation).
- [ ] No building floats or sinks more than 0.2 m on slopes (test on the Suwałki map).
- [ ] Trees, grass and scatter keep out of footprints (`ScatterPlanner` / `ForestFill` / `GrassPlanner` use a footprint mask); roads and hex overlays draw over them correctly.
- [ ] Planning cost per chunk <= 50 ms on a worker thread; first frame after a camera jump shows LOD1 buildings within 1 km (like TASK-189's acceptance); `balanced` preset draws buildings too (flat LOD only on LOW) – decide and record.
- [ ] Frame time on Suwałki over the densest village and Suwałki town centre at distances 1.2 / 5 / 24 <= 16.7 ms on the RX 580 (`true`, HIGH, 720p).
- [ ] Hit / selection on buildings is not required; units still stand on tile centres (the hex mechanics are untouched).

## Playtest (for the human)

1. Fly over a village and over Suwałki town: houses stand where they really are, no floating, no popping while zooming.
2. Frame rate while panning over the town.

## Player manual

None (look only) – unless buildings become cover (not in this task).

## Out of scope

- Building facades (TASK-196); destruction; building mechanics.

## Implementation notes

_Filled in by the agent when done._
