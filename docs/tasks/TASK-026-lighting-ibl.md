# TASK-026: Lighting v2 – sky as ambient/reflection source, SSAO

- **Status**: ready
- **Layers**: presentation (environment resource + scene; values checked in `tests/unit/test_battle_look.gd`)
- **Depends on**: TASK-013 (current environment). Reference: `docs/design/v2/README.md` ("Lighting"), `docs/design/v2/game_screen.scene.js` lines 352–360 and 444–454.
- **Model**: sonnet

## Goal

Surfaces get light and reflections from a sky instead of one flat ambient colour. Shaded sides become cooler at the top and warmer at the bottom, metal and glass on the units have something to reflect, and contact shadows appear under trees and units. This is the base the later material tasks (TASK-027 … TASK-031) are judged under.

## Design values (three.js → Godot)

| Design | Godot 4 |
|---|---|
| `scene.environment = makeEnv()`: gradient sphere top `#7f9bb5`, horizon `#d5d8cc`, ground `#4f4a3a`, sun disk | `Environment.sky = Sky` with `ProceduralSkyMaterial`: `sky_top_color = #7f9bb5`, `sky_horizon_color = #d5d8cc`, `ground_bottom_color = #4f4a3a`, `ground_horizon_color = #d5d8cc`, `sun_angle_max` small (sun disk comes from the `Sun` light). **`background_mode` stays `BG_COLOR` `#a9b4b2`**: the sky only lights the scene, the visible haze doesn't change |
| `HemisphereLight(..., 0.45)` + environment | `ambient_light_source = AMBIENT_SOURCE_SKY`, `ambient_light_sky_contribution = 1.0`, `ambient_light_energy` starting value 0.5 (tune 0.3–0.8) |
| `envMapIntensity` 0.55 terrain / 0.4 foliage / 1.0 units | `reflected_light_source = REFLECTION_SOURCE_SKY`. Per-material intensity has no direct equivalent: leave it at the default here. TASK-027/-028 can lower specular on terrain and foliage if they look too shiny |
| (Godot only) contact shadows | `ssao_enabled = true`, `ssao_radius` 1.0, `ssao_intensity` 1.5, `ssao_detail` 0.5 (starting values, tune on a screenshot) |
| Shadow map 4096 | Project setting `rendering/lights_and_shadows/directional_shadow/size = 4096` (check it's set; TASK-013 required it) |

## Acceptance criteria (testable)

- [ ] `assets/environments/battle_environment.tres` has a `Sky` sub-resource with a `ProceduralSkyMaterial` using the four colours above (per-channel tolerance 0.002).
- [ ] `test_battle_look.gd` is updated: `background_mode == BG_COLOR` and `background_color == #a9b4b2` still hold; `ambient_light_source == AMBIENT_SOURCE_SKY`, `ambient_light_energy` in [0.3, 0.8]; `reflected_light_source == REFLECTION_SOURCE_SKY`; `ssao_enabled`; the sky material colours as above. The old `AMBIENT_SOURCE_COLOR` / `#b9bfc0` assertions are removed.
- [ ] Fog values from TASK-013 (begin 38, end 90, colour = background) are unchanged and still asserted.
- [ ] Agent visual check: `tools/screenshot.sh` before/after. The map edge haze keeps the same colour, the terrain keeps roughly the same brightness (tune `ambient_light_energy` and the sun `light_energy` if the average luminance changes by more than ~10 %), and darker contact shadows appear under tree clusters. Record final values in the implementation notes.

## Playtest (for the human)

1. Start a battle (`tools/run_windows.sh` for GPU rendering).
2. Zoom in on a forest edge and a unit. Under the trees and the unit there should be soft dark contact shadows, and slopes facing away from the sun should look slightly blue rather than flat grey.
3. Zoom out. The haze at the map edge looks the same as before, and overall brightness hasn't jumped.
4. Watch the frame rate in the editor's monitor at full zoom-out. SSAO shouldn't drop it noticeably on your GPU (if it does, note it; `ssao_detail` / half-size can be lowered).

## Out of scope

- Changing material roughness or metalness (TASK-029), terrain textures (TASK-027).
- SSIL, SDFGI, volumetric fog, a visible sky dome.

## Implementation notes

_Filled in by the agent when done._
