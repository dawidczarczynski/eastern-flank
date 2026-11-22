# TASK-189: GPU-placed forest impostors – no CPU planning of impostor trees

- **Status**: done
- **Layers**: presentation (`ForestField`, `ForestFill`, `ForestMaskSource`, `TreeImpostors`, `tree_impostor.gdshader`, `forest_impostor.gdshader`, `ChunkManager`, `MapView`)
- **Depends on**: TASK-135
- **Sections**: ARCHITECTURE "Real-scale vegetation", "Chunked lazy world"; ADR 0026, ADR 0027 (proposed – accept it when starting)
- **Model**: opus (GPU/CPU determinism, performance budget)

## Goal

At real size the forest around the camera appears at once after a zoom or a camera jump, instead of filling in chunk by chunk over seconds: impostor trees are derived in the vertex shader from their grid cell, not planned in GDScript (ADR 0027).

## Acceptance criteria (testable)

- [ ] Impostor chunks carry no per-instance buffer: `instance_count` = fill cells of the chunk, the shader derives point, size, species, atlas row, tint and hand-over phase from `INSTANCE_ID` + chunk origin; cells without a tree collapse to a point.
- [ ] Forest and keep-off (roads, rivers, tile-centre clearing; from one `ForestMaskSource`) and the parcels and ground height reach the shader as textures built once per map; the ground height is the lattice texture, impostors sunk 1.5 m more than the full trees (no near-surface height cache – evidence: screenshots at distance 0.8–1.2 show no floating impostors).
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
4. Orbit slowly at distance ~0.8–1.2 over a forest: at the full-tree / impostor hand-over (~230–250 m) trees do not shift or change species, and impostors at 250–450 m do not float above the ground.

## Player manual

None (look only).

## Out of scope

- GPU placement of the full LOD0 trees (they stay CPU-planned: few, exact near-surface height).
- Grass / ground cover on the GPU (a possible follow-up with the same textures).
- Making `true` the default (TASK-138).

## Implementation notes

- **What changed**: `ForestFill` is now an instance (the reference): one cell -> tree function (point, size, species / variant / colour from a third integer hash `PICK_SALT` instead of `TreeSpecies.pick`'s sin hash, which stays for the planned trees and `balanced`), a stand mask at 32 texels / unit (~4.5 m) and the lattice height for every decision. `forest_hash.gdshaderinc` is its GLSL twin (uint32), `forest_impostor.gdshader` places the impostors from `INSTANCE_ID` + the chunk's `cells` instance uniform; the picture code moved to `tree_impostor_view.gdshaderinc` (shared with `tree_impostor.gdshader`, TreeField's path unchanged). `ForestField`'s impostor layer is an `instant` ChunkLayer (new: built in the scan, no worker plan); all chunks share one MultiMesh without colour / custom data. Removed: `plan_impostors`, `_trees_in`, `Ground`, `_is_far`, `set_plan_target`, `FAR_*`, the `thin` plan path.
- **Forest shape source (human decision)**: the forest and keep-off masks come from one interface, `ForestMaskSource.build(grid, area, per_unit)`; today `HexForestMaskSource` (FOREST tiles, tile-centre clearing, road / river ribbons) – hex-edged and transitional. **TASK-108g** (sub-hex land-cover raster) is a soft follow-up: it becomes a second source; the shader, the layers and the 4.5 m mask resolution stay.
- **Deviation from the original criterion – for the human to confirm in the playtest (playtest step 4: impostors at 250–450 m must not float)**: criterion 2 asked for a near-surface height cache filled by TerrainNear; it was not built (lattice texture + 1.5 m extra sink instead), not confirmed in motion yet.
- **Ground**: no near-surface height cache – impostors stand on the lattice texture, sunk 1.5 m more than the full trees (ADR 0027 refinements). Every decision (shore, conifer share) reads the lattice, so CPU and GPU agree; full trees still stand on the near surface.
- **Far thinning** moved into the shader (camera distance > 900 m: every other cell, crowns 1.4x, per-tree band) – without it the GPU path cost +2–4 ms at distance 5–24. Sink and thinning are `LookPreset.vegetation()` values (`impostor_sink_m`, `impostor_thin_from_m`, `impostor_thin_widen`).
- **Instant builds are budgeted** (`ChunkManager.instant_budget_usec`, 4 ms, nearest first, in the scan and in each `process()`): headless on Suwałki the target update after a ~2 km jump takes ~3.8 ms (before the budget the whole ring was built at once, ~10 ms for the first frame in total), and every impostor chunk within 1 km still exists after one `_process()` (first frame ~8.5 ms); full trees complete after ~66 frames of 16 ms.
- **Burns**: the field keeps the last 128 circles (`MAX_BURNS`) for full trees and impostors alike (a battle leaves a few dozen wrecks).
- **ChunkLayer.priority** (new): the full trees plan before the near grass on the camera manager; without it the full trees waited ~19 s behind near-grass plans (~275 ms each) after a jump.
- **Impostor yaw = full tree yaw** (`k × 6`), so the hand-over shows the same side of the tree.
- **Fix found on the way**: the shader's early near cull now respects the budget's `full_reach` (with `full_tree_cap` 0 the near impostors were missing).
- **Measured** (Suwałki, RX 580, HIGH, 720p, `SCREENSHOT_FOCUS=25.1,16.5,-40,d`, 120 frames; baseline = HEAD before the task, same session): d 1.2: 11.67 ms (GPU 11.20) vs 11.61 (11.22); d 5: 6.76 ms (6.38) vs 6.65 (6.31); d 24: 6.40 ms (6.08) vs 9.30 (6.58); after the switch to the mask source: d 1.2 11.48 ms (10.99), d 5 6.94 ms (6.50); after the review fixes: d 1.2 11.61 ms (11.09), d 24 6.14 ms (5.70). Headless: impostor chunk build ~0.13 ms (Suwałki, 243 forest chunks, 3 249 instances each); impostor setup ~0.18 s per map at load; after a ~2 km jump every impostor chunk within 1 km exists after one `_process()` (first frame ~9.5 ms headless), full trees around the camera complete after ~1.2 s (2 worker threads in play on 4 cores).
- **Tests**: `test_forest_fill` (fixed hash values of 5 cells checked against an independent uint32 model, fixed trees of 6 cells, include constants = GDScript constants, chunk cells partition the grid, roads kept off, the hex mask source), `test_real_scale_vegetation` (no instance data, build < 0.5 ms best of 5 rounds, every full tree has its impostor cell with the exact near/lattice sink gap, height and mask textures match the reference texel by texel, the shader keeps the reference expressions, burns capped alike), `test_chunk_manager` (instant layer, instant budget, priority), `test_real_scale_suwalki` (jump: impostors within 1 km after one frame, full trees within 360 frames).
- **Known limits**: GPU placement is not testable headless (the reference is); the hand-over was compared on screenshots with all-full vs all-impostor (`full_tree_cap` 0, in a scratch copy) – same trees, same spots, impostors blurrier up close; a motion check is left to the playtest. CPU float64 vs GPU float32 can differ for a tree exactly on a mask texel / hex / species-share border (rare, one tree). Forests are still hex-edged (TASK-108g).
