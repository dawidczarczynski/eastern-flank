# TASK-027: Terrain detail – tileable detail texture + normal map, denser mesh, macro colour, water normals

- **Status**: done
- **Layers**: presentation (pure texture generator and colour rules tested in `tests/unit/`)
- **Depends on**: TASK-016b (terrain mesh), soft: TASK-026 (judge it under the new light). Reference: `docs/design/v2/README.md` ("Terrain detail", "Macro variation", "Water"), `docs/design/v2/game_screen.scene.js` lines 361–379 (`tileH`, `canvasTex`, `normalTex`), 457–501 (terrain mesh, water).
- **Model**: sonnet

## Goal

Up close, the ground has grain and small bumps instead of smooth vertex-colour gradients. From afar, large dry and moist patches break the uniform green. Water has ripples that catch the sun. This is the biggest single step toward the v2 look.

## Design → Godot

- **Detail heightmap**: new pure class `src/presentation/detail_texture.gd` (`class_name DetailTexture`, static, `RefCounted`), a port of `tileH`: `height_map(size: int, periods: Array[int], seed: int) -> PackedFloat32Array` – sum of value-noise octaves, octave `o` uses lattice period `periods[o]` (lattice wraps modulo the period, so the map tiles seamlessly) and amplitude `0.55^o`, normalised by the amplitude sum. Use the same hash family as `TerrainColors`/`TerrainNoise`, not `randf()`.
- `albedo_image(h, size) -> Image`: `v = 0.76 + 0.34·H + (hash(x, y) − 0.5)·0.06`, RGB `(v, v, v·0.97)`, clamped, mipmaps generated.
- `normal_image(h, size, strength) -> Image`: central differences with wrap-around, `n = normalize(−dx·k, dy·k, 1)` encoded `n·0.5 + 0.5` (check Godot's normal map convention: green channel up, OpenGL style – flip `dy` if the bumps look inverted on the screenshot).
- **Terrain material** (`map_view.gd`, `_build_terrain`): add `ARRAY_TEX_UV` = world `xz / DETAIL_TILE` with `DETAIL_TILE` chosen so the texture repeats ~44× across the design's terrain width (≈ 1.45 world units; a constant in `map_view.gd`). `albedo_texture` = detail albedo (Godot multiplies it with the vertex colour), `normal_enabled`, `normal_texture` = detail normal, `normal_scale = 0.9`, `texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC`. Textures are generated once at build (size 256, periods `[8, 16, 32, 64]`, seed 201, strength 7) and cached in a static var.
- **Mesh resolution**: `RESOLUTION` 3 → 6. Measure the terrain build time before/after on the default map (`Time.get_ticks_msec()` around `build`) and record both in the notes. If it exceeds ~1.5 s, keep 6 only where it matters (try 5) and say so.
- **Macro variation** in `TerrainColors`: after the grass colour, lerp to `DRY #9c9558` by `smooth(0.55, 0.75, mac)·0.45`, then to `MOIST #4c6a2c` by `smooth(0.42, 0.28, mac)·0.4`, with `mac = fbm(x·0.12 + 5, z·0.12, seed 91, 3 octaves)`. Only on land tiles that aren't forest (forest colour overrides as today).
- **Water** (`_build_water`): colour `#264f5c`, alpha 0.84, roughness 0.07, metallic 0.1, normal map from `DetailTexture` (periods `[4, 8, 16, 32]`, seed 303, strength 5), `normal_scale = 0.3`, UV repeat 36 over the water plane.

## Acceptance criteria (testable)

- [x] `tests/unit/test_detail_texture.gd`:
  - `height_map(64, [4, 8], 1)` is deterministic (two calls equal) and differs for seed 2; all values in [0, 1].
  - Seamless: for every row, `|H[y][0] − H[y][63]|` is not larger than the largest step between neighbouring pixels inside the map (the wrap step is an ordinary step); same for columns.
  - `normal_image` of a constant height map is uniformly `(0.5, 0.5, 1.0)` (±1/255); of a ramp rising in +x every pixel has red < 0.5 (normal tilts toward −x) – fix the sign if Godot's convention requires it and document it.
  - `albedo_image` values in [0.73, 1.13] before clamping, i.e. pixels in [0.73, 1.0] after.
- [x] `test_terrain_colors.gd`: a plains vertex whose `mac` ≥ 0.75 moves toward `DRY` (its red channel is higher than with macro variation disabled at `mac = 0.5`); one with `mac` ≤ 0.28 moves toward `MOIST`; forest vertices are unaffected. (Expose `macro_k(x, z)` or inject `mac` so the test can pick values.)
- [x] The terrain mesh has UVs, the terrain material has `albedo_texture`, `normal_texture` and anisotropic filtering (checked in a test that builds `MapView` headless on a small grid, as existing tests do, or in `test_battle_look.gd`).
- [x] Hex picking (`mesh_height_at`, surface picking) still works with the denser mesh – existing tests pass.
- [x] Agent visual check: default screenshot and a close one (`--frames` / camera hook if available). The ground shows fine grain with no visible seams or tiling rectangles at default zoom, and large lighter/darker patches are visible on the plains. Compare with `docs/design/v2/shots/v2-map.jpg` and `01-v2-zoom.jpg`.

## Playtest (for the human)

1. Start a battle (Windows build for GPU).
2. Zoom fully in on a plains tile. The ground has fine bumpy grain that reacts to the sun. Rotate the camera (RMB): the highlights move with the light direction.
3. Zoom out. Check that no repeating grid pattern of the texture is visible across the map, and that there are larger yellowish (dry) and dark-green (moist) patches.
4. Look at the water: small ripples with sun glints; the coast still blends into sand.
5. Note the time from start to the first frame compared with before (a denser mesh is built in GDScript).

## Out of scope

- Per-terrain detail textures (one shared detail map is enough), triplanar mapping on cliffs, animated water.
- Field stripes, urban ground, river banks – those terrain types don't exist yet (GDD ideas, TASK-035).

## Implementation notes

- `src/presentation/detail_texture.gd` (`DetailTexture`): `height_map` (value-noise octaves on a lattice that wraps modulo each period, `TerrainNoise.hash`), `albedo_image`, `normal_image`. Normal map convention is OpenGL (Godot): red = +x, green = toward image row 0; `n = normalize(−dx·k, +dy·k, 1)` with `dy` over increasing rows, as in the design's `normalTex`. Tests pin a +x ramp → red < 0.5, a ramp toward higher rows → green > 0.5.
- `map_view.gd`: terrain gets UVs (world xz / `DETAIL_TILE` 1.45) and **tangents** (`(1, dh/dx, 0)` orthogonalised against the normal, `w = +1` so the binormal points −z = up the image, matching the normal map). Detail albedo + normal (0.9), anisotropic filtering; water per spec (normal scale 0.3, UV ×36). Textures are generated once and cached in static vars (`_ground_albedo`, `_ground_normal`, `_water_normal`), about 0.3 s once per run.
- **`RESOLUTION` = 4, not 6.** Terrain build on the default map (12×10): 3 ≈ 0.95 s (before), 4 ≈ 1.6 s, 5 ≈ 2.5 s, 6 ≈ 3.7 s. Almost all of it is `TerrainField.height` per vertex. 4 is about 0.1 s over the ~1.5 s budget; the normal map carries the fine detail.
- Macro variation (`TerrainColors.macro_k`, `color_at(..., mac := 0.5)`, 0.5 neutral) applies only to non-forest land. The design leaks about 15 % into forest; this follows the task text instead.
- The leak warnings at the end of the test run ("RID allocations leaked", "resources still in use") predate this task and are unchanged.
- Visual check (llvmpipe, default zoom only, no close-up camera hook): yellowish dry and dark moist patches are visible on the plains, with no seams or tiling rectangles. The fine grain is faint at this distance. Bump direction and water glints are **not verified**; the human checks them in the playtest. If the bumps look inverted, flip `w` in `_build_terrain` **or** `dy` in `DetailTexture.normal_image` (not both).
- Tests: `test_detail_texture.gd`, `test_map_view_detail.gd` (UVs, tangents, materials, water normal), additions to `test_terrain_colors.gd`.
- Playtested by the human on 2026-10-18: accepted.
