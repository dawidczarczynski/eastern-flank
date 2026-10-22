# TASK-056: Water v2 – depth colour, shore foam, scrolling ripples, screen-space reflections

- **Status**: done
- **Layers**: presentation (`assets/shaders/water.gdshader`, `map_view.gd` `_build_water`, environment SSR), tests
- **Depends on**: soft **TASK-050** (SSR on HIGH only), soft **TASK-051**/**TASK-054** (reflections of the sky), soft **TASK-055** (mud shore under the water edge)
- **Model**: sonnet

## Goal

Lakes and the river look like real water: dark in the middle, clearer and greener at the edges, a thin broken line of foam where water meets land, slowly moving ripples, and the sky and trees reflected in the surface.

## Current state

`StandardMaterial3D`, colour `#264f5c` alpha 0.84, roughness 0.07, metallic 0.1, a static generated normal map (`DetailTexture`, scale 0.3, UV ×36). One flat plane at the water level. Since TASK-051 the default battle has a river with fords between the armies (water tiles forced by `Scenario`); it uses the same plane.

## Design

- `assets/shaders/water.gdshader` (`render_mode` blend mix, depth draw opaque-off, cull back, `specular_schlick_ggx`):
  - **Depth colour**: water depth from `DEPTH_TEXTURE` (linearised scene depth − fragment depth, in world units): shallow `#4c7464` at 0 → deep `#1b3842` at **0.45**; alpha 0.55 → 0.92 over the same range.
  - **Shore foam**: where water depth < **0.05**: white-ish `#dfe4dc`, broken by the detail noise (threshold scrolling slowly), max alpha 0.6; zero beyond 0.05.
  - **Ripples**: two normal-map samples (the existing water normal texture) scrolling in different directions (speeds 0.010 and 0.016 world units/s, UV ×36 and ×23), blended; `normal_scale` 0.3. Wind direction from the global wind uniform if TASK-057 has added it, otherwise a fixed direction.
  - **Fresnel**: reflection strength Schlick with `F0 = 0.02`; roughness 0.05; metallic 0.
- **SSR** (environment, HIGH only via TASK-050): `ssr_enabled`, max steps 48, fade in 0.15, fade out 2.0, depth tolerance 0.2. LOW: no SSR, the sky reflection (TASK-026 radiance) still applies.
- Time comes from `TIME` (view-only animation, no simulation coupling).

## Acceptance criteria (testable)

- [ ] `_build_water` uses a `ShaderMaterial` with `water.gdshader`; uniforms `shallow_color`, `deep_color`, `deep_distance = 0.45`, `foam_distance = 0.05`, `foam_color`, `ripple_speeds = (0.010, 0.016)` are set to the design values (test reads them).
- [ ] HIGH environment has `ssr_enabled` with the values above; LOW has it off (`test_graphics_quality.gd` / `test_battle_look.gd`).
- [ ] The shader compiles headless (a test that instantiates the material on a mesh and renders 1 frame, or `Shader.get_shader_uniform_list()` returns the uniforms – pick what works in the headless runner and note it).
- [ ] Existing water tests (normal map, level) pass.
- [ ] Agent visual check (Windows build): zoomed-in screenshot of a lake: lighter edge, darker centre, thin foam line at the shore, trees/hills reflected on HIGH; two screenshots 1 s apart differ in the ripple pattern (`--frames`).
- [ ] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it, commit it with the change.

## Playtest (for the human)

1. Zoom in on a lake and on the river: the shallow edge is lighter and greener, the middle dark; a thin, broken foam line follows the shore; at the fords the water is shallow and light.
2. Watch for a few seconds: the ripples move slowly, without a visible repeat.
3. Rotate the camera to look across the lake: the sky and trees on the far shore are reflected (Windows build).
4. Check that the shore foam doesn't flicker when the camera moves, and there is no dark halo around units standing next to water.

## Player manual

None (presentation only; water stays impassable).

## Out of scope

- Flowing water (current direction along the river, needs river data – TASK-035), waves, refraction distortion, caustics, splash effects. The river is rendered as still water here.

## Implementation notes

- `assets/shaders/water.gdshader` replaces the `StandardMaterial3D`; `_build_water` sets only the `normal_map` parameter, all design values are shader uniform defaults. `WATER_COLOR`, `WATER_UV_REPEAT` and `WATER_NORMAL_SCALE` were removed.
- **Depth** = vertical (world Y) distance from the surface to the scene behind it: `hint_depth_texture` is unprojected with `INV_PROJECTION_MATRIX` / `INV_VIEW_MATRIX` (NDC z is `d` on Forward+ (reverse-Z), `d * 2 - 1` on Compatibility, via `#if CURRENT_RENDERER`). Vertical depth does not change with the camera angle, so colour and foam do not swim when the camera moves.
- **Ripples** sample in world XZ: `ripple_scales` 0.33 / 0.21 per world unit approximate the old ×36 / ×23 over the plane. TASK-057's global wind does not exist yet, so `wind_direction` is a fixed uniform (0.8, 0.6) – switch it to the global uniform in TASK-057.
- **Fresnel**: Godot 4's dielectric F0 is `0.16 * SPECULAR²`, so `SPECULAR = 0.354` gives F0 = 0.02.
- **Foam**: the noise is the R/G channels of the water normal texture (no dedicated noise texture). The foam colour mix is what shows; `foam_max_alpha` 0.6 barely matters because the base alpha is already ≥ 0.55. The two ripple normals are averaged, which flattens them slightly (a whiteout blend would keep their full strength) – both are cosmetic and left as is.
- **SSR: not enabled** (human decision after review). Godot applies SSR only to opaque surfaces, and the water is alpha-blended (needed to read its own depth texture), so SSR would cost GPU on HIGH without reaching the water. The water reflects the sky radiance only – no trees or hills; the SSR acceptance criterion and playtest step 3 (tree reflections) are dropped. `test_battle_look.gd::test_no_ssr_on_any_quality` guards it. Tree/hill reflections would need opaque water with fake refraction, or planar reflections (a future task).
- **Tests**: the headless runner uses the dummy renderer, so `Shader.get_shader_uniform_list()` and `RenderingServer` return no uniforms. The tests therefore parse the shader source: uniform declarations and defaults (design values), render modes, and the per-renderer depth branch. Actual compilation is only verified by the Windows Forward+ screenshot runs (no shader errors).
- **Visual check** (Windows, HIGH): close-up `SCREENSHOT_CAMERA=5,0,8` on two lakes – darker centre, lighter edge, pale shore rim, no halos. The same view at 60 and 120 frames differs only on the water (land diff 0), so the ripples move. Compatibility / LOW was not rendered. `docs/images/gameplay.png` re-rendered: the river and ponds are paler than before because at the README's shallow viewing angle the Fresnel sky reflection dominates.
