# TASK-189: GPU-placed forest impostors – no CPU planning of impostor trees

- **Status**: blocked
- **Layers**: presentation (`ForestField`, `ForestFill`, `TreeImpostors`, `tree_impostor.gdshader`, `TerrainNear`, `MapView`)
- **Depends on**: TASK-135
- **Sections**: ARCHITECTURE "Real-scale vegetation", "Chunked lazy world"; ADR 0026, ADR 0027 (proposed – accept it when starting)
- **Model**: opus (GPU/CPU determinism, performance budget)

## Goal

At real size the forest around the camera appears at once after a zoom or a camera jump, instead of filling in chunk by chunk over seconds: impostor trees are derived in the vertex shader from their grid cell, not planned in GDScript (ADR 0027).

## Acceptance criteria (testable)

- [ ] Impostor chunks carry no per-instance buffer: `instance_count` = fill cells of the chunk, the shader derives point, size, species, atlas row, tint and hand-over phase from `INSTANCE_ID` + chunk origin; cells without a tree collapse to a point.
- [ ] Forest, keep-off (roads, rivers, parcels, tile-centre clearing) and ground height reach the shader as textures built once per map; the near-surface height comes from a cache filled by the near terrain chunks as they are built (no extra `TerrainSurface` queries).
- [ ] The integer hash and cell → tree formulas are shared by GDScript (`ForestFill`, used by full trees) and GLSL (`forest_hash.gdshaderinc`); a test fixes the GDScript results of ≥ 5 cells and the shader include carries the same constants (32-bit unsigned arithmetic).
- [ ] The impostor layer plans nothing on the worker threads; building an impostor chunk on the main thread takes < 0.5 ms (measured in a test).
- [ ] After a camera jump of ~2 km on Suwałki the impostors within 1 km of the camera exist in the first frame after the jump (headless: chunk nodes for all impostor chunks within 1 km after one `process()`); full trees within their ring follow within 2 s on 4 cores.
- [ ] Full trees and impostors hand over at the same positions (screenshot: no visible jump at the full range).
- [ ] Frame time on Suwałki (`SCREENSHOT_SCALE_PRESET=true`, RX 580, HIGH, 720p) at distances 1.2 / 5 / 24 ≤ 16.7 ms avg; numbers in the implementation notes.
- [ ] `balanced` unchanged (no forest fill, no impostors).

## Playtest (for the human)

1. `--debug`, DEVTOOLS SCALE = TRUE SIZE, Suwałki: zoom from the top into the middle of a forest several times – the forest is there at once, no chunks filling in.
2. Jump the camera across the map (pan fast / zoom to a far forest): no bare forest floor, no canopy-shell squares turning into trees.
3. Pan over large forests: smooth 60 FPS.

## Player manual

None (look only).

## Out of scope

- GPU placement of the full LOD0 trees (they stay CPU-planned: few, exact near-surface height).
- Grass / ground cover on the GPU (a possible follow-up with the same textures).
- Making `true` the default (TASK-138).

## Implementation notes

_Filled in by the agent when done._
