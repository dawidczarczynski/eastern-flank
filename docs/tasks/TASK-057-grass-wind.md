# TASK-057: Grass – MultiMesh alpha-card clumps near the camera, distance LOD, shared wind shader

- **Status**: done
- **Layers**: presentation (pure `GrassPlanner`, `assets/shaders/grass.gdshader`, shared wind include + global shader uniforms, `map_view.gd`), tests
- **Depends on**: **TASK-050** (`grass_density`, `wind`), soft **TASK-055** (grass tint matches the ground layers), soft **TASK-059** (grass height follows the chosen unit/tree scale), soft **TASK-052** (low camera shows grass at grazing angles)
- **Model**: sonnet

## Goal

Up close, plains and hillsides are covered in real grass that sways in the wind, breaking the flat ground silhouette; zoomed out, the grass fades into the ground texture so it costs nothing where it can't be seen.

## Design

- **Clump mesh**: 3 crossed vertical quads (60° apart), width 0.07, height **0.05** world units (≈ 0.4 m at the current scale) – both multiplied by the scale for world-scale vegetation from `VisualScale` (TASK-059; the human's preset choice), not hard-coded, pivot at the bottom. Texture: procedurally generated grass-blade alpha card (`GrassTexture.card(size 128, seed)` – tapered blades, alpha scissor 0.5, slight colour gradient root→tip) **or** a CC0 grass card if TASK-053 allows textures (credited). Bent-up normals (normals = up-ish) so cards don't light like flat walls.
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

- **Code**: pure `GrassPlanner` (4×4 chunks, view-local hash RNG, plains 90 / hills 50 / forest 25 per unit², none on water, shore band ≤ 0.06 or hill slope > 0.5); `GrassField` node (one `MultiMeshInstance3D` per chunk at the chunk centre, `visibility_range_end` 14, margin 3, `FADE_SELF`, shadows off; built lazily within 20 units of the camera target, nearest first, 1 chunk per frame, pending chunks rescanned only after the target moves > 0.5); `GrassMesh` (3 crossed cards, up normals); `GrassTexture.card` (procedural neutral-grey blade card – hue comes from the instance colour); `Wind` + `assets/shaders/wind.gdshaderinc` + `assets/shaders/grass.gdshader`. Documented in docs/ARCHITECTURE.md ("Grass and wind").
- **Size**: `VisualScale` got a `grass_scale` key equal to `bush_scale` in every preset (balanced → 1.4); card 0.07 × 0.05 × `grass_scale`.
- **Colour**: `TerrainTextures` computes each ground layer's mean linear albedo (× `TerrainGround.LAYER_TINTS`) while packing; the clump colour is that weighted by the `TerrainSplat` weights (sampled on a 0.5-unit grid per chunk) × `lerp(0.85, 1.1, tint)`; root darkening only in the shader.
- **Wind**: global shader params `wind_direction`, `wind_strength`, `wind_speed` registered at runtime in `MapView.build()` (once, guarded); strength 0 when quality `wind` is false. The headless dummy renderer keeps no global params, so the test checks `Wind.strength()` (the value pushed to the renderer), not the RenderingServer itself.
- **Budget**: 18 606 clumps on the default map at density 1.0 (budget 120 000; test with `GrassField.SEED`); `GrassField.setup()` estimates the count and cuts density over budget (debug assert + warning, tested with a tiny budget).
- **Screenshot tool**: the battle's `_process` is off in `tools/screenshot.gd`, so it calls `BattleController.debug_build_grass()` to build the chunks around the focus.
- **Visual check (Windows build)**: zoomed-in grass on plains near the camera, fading with distance without a visible ring, none on water/shore; colour in the ground's hue family (clumps slightly darker/more contrasty than the flat ground). README shot re-rendered. **Not verified**: sway (no frame diff), exact fade start of the margin, FPS – playtest items.
- Reviewed (reviewer agent); fixes applied: double colouring, per-clump splat cost, per-frame rescan, shader load test, budget assert/test, docs.
- **Overlay depth pull**: every draped ground overlay (unit marker ring/fill, reach/range/attack/hover washes) uses `GroundOverlay.material` (`assets/shaders/ground_overlay.gdshader`), which pulls the vertices towards the camera by `GrassField.max_clump_height() / sin(CameraMath.PITCH_CLOSE)` so they draw over the grass but stay occluded by trees, units and ridges. Only rings and outlines are pulled: fills (unit marker fill, hover fill, dim, attack/range fills) lie under the unit models and a pull tinted their lower half blue (playtest feedback), so fills keep normal depth. Fills also tinted the wheels/tracks/boots below their lift (noticeable when hovering an occupied hex: two fills stack), so fills are `ground_only`: the shader reconstructs the scene world Y from the depth texture (as water.gdshader) and keeps the fill only where the opaque surface behind it is ≥ `ground_band` (0.015) below it – the terrain, not models or grass blades. The path dots and grid lines are unchanged.
