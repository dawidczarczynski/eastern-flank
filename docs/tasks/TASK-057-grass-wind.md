# TASK-057: Grass – MultiMesh alpha-card clumps near the camera, distance LOD, shared wind shader

- **Status**: ready
- **Layers**: presentation (pure `GrassPlanner`, `assets/shaders/grass.gdshader`, shared wind include + global shader uniforms, `map_view.gd`), tests
- **Depends on**: **TASK-050** (`grass_density`, `wind`), soft **TASK-055** (grass tint matches the ground layers), soft **TASK-059** (grass height follows the chosen unit/tree scale), soft **TASK-052** (low camera shows grass at grazing angles)
- **Model**: sonnet

## Goal

Up close, plains and hillsides are covered in real grass that sways in the wind, breaking the flat ground silhouette; zoomed out, the grass fades into the ground texture so it costs nothing where it can't be seen.

## Design

- **Clump mesh**: 3 crossed vertical quads (60° apart), width 0.07, height **0.05** world units (≈ 0.4 m at the current scale; scale with TASK-059's choice), pivot at the bottom. Texture: procedurally generated grass-blade alpha card (`GrassTexture.card(size 128, seed)` – tapered blades, alpha scissor 0.5, slight colour gradient root→tip) **or** a CC0 grass card if TASK-053 allows textures (credited). Bent-up normals (normals = up-ish) so cards don't light like flat walls.
- **Planner** – pure `GrassPlanner` (static, view-local hash RNG like `ScatterPlanner`): the playable map is split into **chunks of 4 × 4 world units**; `plan_chunk(chunk: Vector2i, grid: HexGrid, surface: TerrainSurface, seed: int, density: float) -> Array` of `{position: Vector3, yaw: float, scale: float, tint: float}`. Density per world unit²: plains **90**, hills **50** (none where slope > 0.5), forest **25**, water / shore band (≤ 0.06 above water level) **0**. Scale 0.7–1.3, tint 0–1. Multiplied by `density` (quality).
- **Instances**: one `MultiMeshInstance3D` per chunk; `visibility_range_end` **14** world units from the camera with `visibility_range_end_margin` 3 (fade, `VISIBILITY_RANGE_FADE_SELF`); chunks are built lazily the first time the camera target comes within 20 units and kept. Instance budget on HIGH: ≤ **120 000** clumps total (assert in debug; cut density if exceeded on the default map).
- **Colour**: instance colour = ground tint at the clump (from `TerrainSplat` grass/dry_grass weights if TASK-055 is done, else `TerrainColors`) × `lerp(0.85, 1.1, tint)`; root darkened to blend into the ground.
- **Wind** (shared by grass, TASK-060 trees, TASK-061 undergrowth): `assets/shaders/wind.gdshaderinc` + global shader uniforms registered at runtime with `RenderingServer.global_shader_parameter_add` (not in `project.godot`): `wind_direction: vec2` (normalised, default `(0.8, 0.6)`), `wind_strength: float` (0.6), `wind_speed: float` (1.2). Vertex offset = `dir · strength · 0.012 · sin(TIME·speed + dot(world_xz, dir)·2.3 + phase) · h²` with `h` = vertex height / card height; `phase` from the instance position hash. `wind = false` (LOW) → strength 0.
- Grass is not drawn under units: out of scope (it pokes through slightly; TASK-058 track marks flatten the look).
- No shadows cast by grass (receive only).

## Acceptance criteria (testable)

- [ ] `tests/unit/test_grass_planner.gd`:
  - deterministic: same chunk + seed → identical arrays; different seed → different;
  - a 4×4 chunk fully on plains (`Fixtures.plains_grid`) with density 1.0 yields 90·16 ± 10 % clumps; with density 0.5 about half; density 0 → empty;
  - no clump on water tiles or within the shore band; no clump on hills with slope > 0.5;
  - all positions inside the chunk rectangle and on the playable map; `y == surface.ground_height(x, z)` (±0.001);
  - scales in [0.7, 1.3], tints in [0, 1].
- [ ] `MapView` with `grass_density = 0` creates no grass instances; with 1.0 creates chunk `MultiMeshInstance3D`s with `visibility_range_end == 14`, shadow casting off.
- [ ] Global shader parameters `wind_direction`, `wind_strength`, `wind_speed` exist after the battle scene starts; `wind_strength == 0` on LOW.
- [ ] Total instance count on the default map at HIGH ≤ 120 000 (logged; test or note).
- [ ] Agent visual check (Windows build): zoomed-in screenshot shows grass clumps on plains near the camera that fade out with distance, no visible LOD line (compare a far region); two frames 0.5 s apart show sway; FPS noted if measurable.
- [ ] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it, commit it with the change.

## Playtest (for the human)

1. Zoom fully in on plains: dense grass clumps, swaying gently and not in sync.
2. Zoom out slowly: the grass thins out smoothly into the ground; no hard ring where it ends, no popping chunks.
3. Pan across the map quickly: no stutter when new grass chunks appear.
4. Lakes and shores have no grass on the water; steep rocky slopes are bare.
5. Units standing in grass: readable (their base marker and label still visible).
6. Frame rate zoomed in over the largest plains vs. before (Windows). Run `tools/run.sh` (LOW): no grass, no slowdown.

## Player manual

None (presentation only).

## Out of scope

- Grass bending under units, flattened trails, flowers, seasonal colours.
- GPU-driven culling / compute shaders.

## Implementation notes

_Filled in by the agent when done._
