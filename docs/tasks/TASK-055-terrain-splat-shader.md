# TASK-055: Terrain shader v3 – blended CC0 PBR ground layers by terrain type and slope, triplanar slopes, anti-tiling

- **Status**: ready (TASK-053's decision: CC0 textures allowed, 2026-10-22; TASK-053 itself – ADR + manifest + test – must be done first)
- **Layers**: presentation (`assets/shaders/terrain.gdshader`, pure `TerrainSplat` weights, `map_view.gd` `_build_terrain`), `assets/third_party/textures/ground/`, tests
- **Depends on**: **TASK-053** (CC0 textures allowed + manifest), soft **TASK-050** (triplanar/second scale off on LOW), soft **TASK-051** (judge under the new light), soft **TASK-052** (the backdrop uses the same material). Related: **TASK-035** (rivers, roads, fields, urban ground) – this task reserves room for those layers but does not add them.
- **Model**: opus (shader with texture arrays, per-vertex weights in two attributes, tangents/triplanar normals, height blending, performance)

## Goal

The ground looks like real land instead of felt: lush grass on plains with dry patches, bare dirt and mud near water and in hollows, leaf litter and darker soil in forests, gravel and rock on steep hillsides – blended naturally, without visible tiling.

## Current state

`StandardMaterial3D`: vertex colour (`TerrainColors`, incl. macro dry/moist and the rock/snow colouring of high hills) × one grey procedural detail albedo + normal (`DetailTexture`, repeat 1.45 units). No per-terrain materials.

## Design

- **Layers (6)**, each a CC0 PBR set (albedo, normal in OpenGL convention, roughness; AO/height if available) from ambientCG or Poly Haven, 1K (1024²), stored at `assets/third_party/textures/ground/<set>/`, credited in `credits.json`:
  `0 grass`, `1 dry_grass`, `2 dirt` (also forest floor / leaf litter tint), `3 mud`, `4 gravel`, `5 rock`. Choose sets with similar scale (≈ 2 × 2 m per texture repeat in real metres; the game scale is 1 world unit ≈ 7.7 m, so one repeat ≈ 0.26 world units – tune for the default zoom and record the final repeat).
- Textures are loaded and packed at build into `Texture2DArray`s (albedo+height in alpha, normal, roughness) with `Texture2DArray.create_from_images` (same size and format; convert if needed) and cached in a static var. LOW quality may use 512² mips only.
- **Weights** – pure `TerrainSplat` (`src/presentation/terrain_splat.gd`, static): `weights(terrain: int, slope: float, height: float, water_level: float, moisture: float, macro: float) -> PackedFloat32Array` (6 values, sum 1). Rules (thresholds as named constants):
  - **plains**: grass; dry_grass by `smooth(0.55, 0.75, macro)` (replaces the vertex-colour dry patches); dirt patches where a fine noise `> 0.8` (weight ≤ 0.4).
  - **forest**: dirt (forest floor) 0.6 + grass 0.4; trees/bushes stay from the scatter.
  - **hills**: grass + dry_grass; rock by `smooth(0.35, 0.6, slope)`; gravel at the rock/grass transition; high elevations (today's rock/snow colouring) → rock.
  - **shore**: any land within **0.12** height above `water_level` gets mud by `1 − (height − water_level)/0.12` (≤ 0.7) and dirt.
  - **water** tiles: mud (the lake / river bed under the transparent water). The default battle has a river with fords (TASK-051, `Scenario._add_river`): river tiles are ordinary water tiles and get the same shore and bed rules; ford crossings are land tiles next to water and get the mud shore band.
  - `slope = 1 − normal.y`. Blending across tile borders comes for free from per-vertex weights on the continuous mesh (each vertex uses the terrain of the tile it lies in, then the weights are smoothed by averaging with neighbours within one mesh step).
- **Mesh**: weights in `ARRAY_COLOR` (layers 0–3) and `ARRAY_CUSTOM0` (RGBA float, layers 4–5, 2 channels free for TASK-035 roads/fields). The old vertex-colour tint is replaced; keep a gentle macro brightness variation (±8 %) in the shader from a low-frequency world-space noise.
- **Shader** `assets/shaders/terrain.gdshader`:
  - per layer: sample at world `xz / repeat`, and on HIGH a second sample at `xz / (repeat · 3.7)` rotated 37°, mixed by a low-frequency noise (anti-tiling);
  - **height blending**: `w_i' = max(0, w_i + h_i − max_j(w_j + h_j) + 0.2)` normalised (sharp grass-over-dirt edges instead of soft cross-fades);
  - **triplanar** for the rock layer where `slope > 0.35` (HIGH only), planar elsewhere;
  - normals blended (whiteout/RNM) with the mesh tangents from TASK-027; roughness from the arrays; AO multiplied into `AO`.
  - cloud-shadow hook: none yet (TASK-066 adds a shared include).
- Build-time budget: terrain build ≤ +0.3 s over the TASK-027 value (record before/after).

## Acceptance criteria (testable)

- [ ] `tests/unit/test_terrain_splat.gd` (tolerance 1e-4 for sums):
  - every result has 6 values ≥ 0 summing to 1;
  - flat plains (`slope 0`, `height 0.3`, `macro 0.5`) → grass ≥ 0.6;
  - plains with `macro 0.85` → dry_grass > grass;
  - hills with `slope 0.7` → rock ≥ 0.6; hills with `slope 0.05` → rock ≤ 0.05;
  - land at `height = water_level + 0.02` → mud ≥ 0.5; at `water_level + 0.2` → mud == 0;
  - forest → dirt ≥ 0.5;
  - deterministic (same inputs, same output).
- [ ] The terrain mesh has `ARRAY_COLOR` and `ARRAY_CUSTOM0` with per-vertex weights summing to 1 (±0.01) for every vertex; the material is a `ShaderMaterial` using `terrain.gdshader` with three `Texture2DArray` uniforms of 6 layers each.
- [ ] `credits.json` lists all 6 sets; `test_third_party_assets.gd` passes.
- [ ] Picking, overlays and scatter placement tests still pass (heights unchanged).
- [ ] Build time recorded; within budget or the deviation explained.
- [ ] Agent visual check (Windows build): default and zoomed-in screenshots: grass reads as grass, dry patches visible from afar, mud along the lake shores, rock on steep hillsides, no repeating tile pattern at default zoom, no seams at hex borders, no shimmering in a 2-frame comparison. Linux/LOW screenshot still renders (single scale, no triplanar).
- [ ] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it, commit it with the change.

## Playtest (for the human)

1. Zoom in on plains: you see grass texture (blades/clumps), not noise; pan around – no obvious repeating stamp.
2. Find a lake and the river (incl. the fords): the shore turns muddy/brownish before the water; no hard line.
3. Find a hill: its steep sides show rock and gravel, the gentle top stays grassy.
4. Forest tiles: darker soil/leaf litter between the trees.
5. Zoom out fully: large drier and greener areas; no checkerboard of tiles; hex borders don't show as colour steps.
6. Check the start-up time and frame rate compared to before.

## Player manual

None (presentation only; terrain types and their rules are unchanged).

## Out of scope

- Road, river bank, field and urban layers (TASK-035).
- Tessellation/parallax occlusion mapping, snow, wetness after rain.
- Grass blades (TASK-057), decals (TASK-058).

## Implementation notes

_Filled in by the agent when done._
