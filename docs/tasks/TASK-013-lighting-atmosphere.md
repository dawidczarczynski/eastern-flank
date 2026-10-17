# TASK-013: Lighting & atmosphere like the visual design

- **Status**: done
- **Layers**: presentation (scene + environment resource; resource values checked in `tests/unit/`)
- **Depends on**: nothing. Best done before TASK-016b (terrain colours are judged under this light). Reference: `docs/design/README.md` ("Scene"), `docs/design/game_screen.scene.js` lines 265–276.
- **Model**: sonnet

## Goal

The battle looks like a hazy, warm late-morning day: grey-green sky that the map fades into, a warm sun with soft shadows, and a cool ambient fill – the mood of the design mock-up, on the current map.

## Design values (three.js → Godot)

| Design (three.js) | Godot 4 |
|---|---|
| `scene.background = #a9b4b2` | `Environment.background_mode = BG_COLOR`, `background_color = #a9b4b2` (the procedural sky is removed) |
| `Fog(#a9b4b2, 38, 90)` (linear) | `fog_enabled = true`, `fog_mode = FOG_MODE_DEPTH`, `fog_light_color = #a9b4b2`, `fog_depth_begin = 38`, `fog_depth_end = 90`, `fog_depth_curve = 1.0`, `fog_sun_scatter = 0`, `fog_aerial_perspective = 0`; `fog_density` chosen so geometry at 90 is fully fogged (verify on a screenshot) |
| ACES tone mapping, exposure 1.05 | `tonemap_mode = TONE_MAPPER_ACES`, `tonemap_exposure = 1.05` (white left at default) |
| `HemisphereLight(#dde7ee, #4b4534, 1.0)` | No hemisphere light in Godot → `ambient_light_source = AMBIENT_SOURCE_COLOR`, `ambient_light_color = #b9bfc0` (75 % sky + 25 % ground colour, because the terrain faces mostly up), `ambient_light_energy = 0.32` (starting value, see note) |
| `DirectionalLight(#fff0d8, 2.7)` at `(-18, 26, 14)` looking at the origin | `Sun` (DirectionalLight3D): `light_color = #fff0d8`, `light_energy = 0.86` (starting value), forward direction (`-basis.z`) = normalize(18, −26, −14) ≈ (0.520, −0.752, −0.405) |
| (Godot only) background/fog not tonemapped in three.js | `background_energy_multiplier = fog_light_energy = 0.55` – compensates ACES so the rendered haze is `#a9b4b2` (see implementation notes) |
| `PCFSoftShadowMap`, map 4096, bias −0.0004, normalBias 0.03 | `shadow_enabled = true`, `light_angular_distance = 1.0` (soft penumbra), `shadow_bias = 0.03`, `shadow_normal_bias = 1.0`, `directional_shadow_max_distance = 80`, project setting `rendering/lights_and_shadows/directional_shadow/size = 4096`, `.../soft_shadow_filter_quality = 3` |

Note on intensities: three.js r160 (physical lights) divides light contributions by π compared with Godot's energy convention, so 2.7 → ≈ 0.86 and 1.0 → ≈ 0.32. These are **starting values**: tune `light_energy` in 0.7–1.4 and `ambient_light_energy` in 0.25–0.6 against the reference screenshot and record the final numbers in the implementation notes.

## Acceptance criteria (testable)

- [ ] The environment lives in its own resource `assets/environments/battle_environment.tres` (an `Environment` resource), referenced by `WorldEnvironment` in `scenes/battle/battle.tscn`; the inline `Environment`/`Sky`/`ProceduralSkyMaterial` sub-resources are removed from the scene.
- [ ] Test `tests/unit/test_battle_look.gd` loads `battle_environment.tres` and checks: `background_mode == Environment.BG_COLOR`, `background_color` equals `Color.html("#a9b4b2")` (per channel tolerance 0.002), `fog_enabled`, `fog_mode == Environment.FOG_MODE_DEPTH`, `fog_depth_begin == 38.0`, `fog_depth_end == 90.0`, `fog_light_color == background_color`, `tonemap_mode == Environment.TONE_MAPPER_ACES`, `tonemap_exposure == 1.05`, `ambient_light_source == Environment.AMBIENT_SOURCE_COLOR`, `ambient_light_color` ≈ `#b9bfc0`, `ambient_light_energy` in [0.25, 0.6].
- [ ] The same test instantiates `battle.tscn` (`PackedScene.instantiate()`, **not** added to the tree, freed at the end) and checks the `Sun` node: `light_color` ≈ `#fff0d8`, `light_energy` in [0.7, 1.4], `shadow_enabled == true`, `light_angular_distance > 0`, and `-global_basis.z` (use `transform.basis` – the node is not in a tree) is within 0.01 of `(0.520, −0.752, −0.405)`.
- [ ] Project settings `rendering/lights_and_shadows/directional_shadow/size = 4096` and `rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality = 3` are set in `project.godot`.
- [ ] No other visual changes in this task (tile prisms, units, camera stay as they are).
- [ ] Agent visual check: take a screenshot with `tools/screenshot.sh` and compare with `docs/design/reference.png` / the values above: background and distant fog are the same grey-green `#a9b4b2`, the light is warm, shadows of units fall towards the bottom-right of the screen (camera at default yaw), shadow edges are soft. Mention in the notes what still differs (the terrain itself changes in TASK-016b).

## Playtest (for the human)

1. `tools/run.sh` – the sky is a flat grey-green, not the blue procedural sky.
2. Zoom out fully (wheel) – far parts of the map fade into the same grey-green.
3. Look at units: they cast soft-edged shadows onto the tiles; lit sides look warm, shaded sides are not black.
4. Compare overall brightness with `docs/design/reference.png` – it should feel similar (not washed out, not dark).

## Out of scope

- Terrain mesh, water plane, vertex colours (TASK-016b), unit models (TASK-019), camera FOV (TASK-015).
- SSAO, glow, volumetric fog, day/night cycle.
- The portrait lighting from the design (`makePortraits`) – follow-up of TASK-021.

## Implementation notes

- Environment moved to `assets/environments/battle_environment.tres` (table values; `fog_density = 1.0` = fully fogged at depth 90). `battle.tscn` references it; the procedural sky is gone. Sun: colour, angular distance 1.0, bias 0.03, normal bias 1.0, max distance 80, basis with forward ≈ (0.520, −0.752, −0.405). Shadow atlas 4096 + soft filter quality 3 in `project.godot`.
- Final intensities: `light_energy = 0.86`, `ambient_light_energy = 0.32` (starting values kept; can't be judged fairly until the TASK-016b terrain palette).
- **Deviation – tonemapped haze**: in three.js the clear colour isn't tonemapped and fog is applied *after* tonemapping, so the design shows exactly `#a9b4b2`. In Godot the background and fog go through ACES (and `fog_sky_affect = 1` fogs the background), which rendered `#d6dedc`. Fix: keep `background_color`/`fog_light_color = #a9b4b2` and scale `background_energy_multiplier` and `fog_light_energy` to 0.55 – calibrated by reading the screenshot pixel (0.54 → `#a8b2b0`, 0.55 → `#aab4b2`, 0.56 → `#abb5b3`). If exposure or tonemapper change, recalibrate. The test asserts both energies stay equal.
- Visual check (`tools/screenshot.sh`): background measured `#aab4b2`; unit shadows fall right/bottom-right with soft edges; shaded sides not black. `docs/design/reference.png` is not in the repo, so comparison was against the value table only. Not verified on screenshot: the far-fog fade (default camera barely reaches depth 38) – playtest step 2. Still differs from the design: very saturated tile colours (TASK-016b), primitive units (TASK-019).
