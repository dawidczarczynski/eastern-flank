# TASK-051: Lighting & atmosphere v3 – AgX, lower sun, aerial perspective, SSIL, subtle glow, colour grading

- **Status**: done
- **Layers**: presentation (`assets/environments/battle_environment.tres`, `scenes/battle/battle.tscn` sun, pure `ColorGrade` LUT generator), tests (`test_battle_look.gd`, new `test_color_grade.gd`)
- **Depends on**: soft **TASK-050** (SSIL/glow are switched off on LOW). Builds on TASK-013/TASK-026. The HDRI sky is a separate task (TASK-054) because it needs the asset decision (TASK-053).
- **Model**: sonnet

## Goal

The battlefield looks like a real overcast-to-partly-cloudy day in Eastern Europe instead of a bright toy table: a lower sun with longer shadows, distance haze that takes the sky's colour, light bouncing between surfaces, and a muted military colour palette.

## Current state

Environment: procedural sky, ambient from sky (energy 0.5), SSAO (radius 1.0, intensity 1.5), tonemap ACES (`tonemap_mode = 3`, exposure 1.05), depth fog 38–90 with `fog_aerial_perspective = 0`, no glow, no SSIL, no adjustments. Sun: elevation ≈ 49° (direction `(0.52, −0.75, −0.40)`), energy 0.86, colour `#fff0d8`, shadow max distance 80.

## Design (starting values – tune on the Windows screenshot, record the final values)

| Setting | New value |
|---|---|
| Tonemap | **AgX** (`tonemap_mode = 4`, Godot 4.4+), exposure ~1.0, white 6–8 (whatever keeps grass mid-tones close to today's brightness) |
| Sun | elevation **30°** (keep today's azimuth so the README framing keeps its light direction), energy **1.3–1.6** under AgX, colour `#ffeedd`, `light_angular_distance` 1.0 (soft penumbra), `shadow_blur` 1.2 |
| Ambient | sky contribution 1.0, energy 0.5 → retune to keep shadow sides readable (target: shadowed side of a tank hull is not black, ≥ ~25 % of lit brightness) |
| Procedural sky (until TASK-054) | overcast-leaning: top `#8fa3b5`, horizon `#c9cdc6`, lower sky energy; sun disc small/dim |
| Fog | depth fog begin **30**, end **140** (TASK-052 adds backdrop terrain beyond the map), **`fog_aerial_perspective = 0.7`**, `fog_sun_scatter = 0.1`, colour/energy so far hills fade toward the horizon colour |
| SSAO | keep, retune intensity (≤ 1.5) so it does not double up with SSIL |
| SSIL | **on** (HIGH): radius 3.0, intensity 0.6, sharpness 0.98 |
| Glow | **on** (HIGH): intensity 0.25, bloom 0.0–0.02, `glow_hdr_threshold` 1.2, blend mode soft light; must not make the HUD-less terrain look hazy – only sun glints on water / bright highlights glow |
| Colour grading | `adjustment_enabled`, `adjustment_color_correction` = a 3D LUT built at startup by `ColorGrade` (below); brightness/contrast/saturation stay 1.0 (the LUT carries the grade) |
| DOF / tilt-shift | **none** (explicitly – it makes the scene look like a miniature) |

- **`ColorGrade`** (pure, `src/presentation/color_grade.gd`, static): `grade(c: Color, p: Dictionary) -> Color` and `lut(size: int, p: Dictionary) -> Array[Image]` (slices for `ImageTexture3D.create`). Default params `DEFAULT := {saturation 0.82, contrast 1.06, shadow_tint #1e2a2c (cool, weight 0.06), highlight_tint #fff1dc (warm, weight 0.05), green_shift: −0.03 hue toward olive}`. Order: contrast around 0.5 luminance → saturation toward Rec.709 luminance → split tint (shadows by `1 − L`, highlights by `L`) → clamp. Muted military palette = lower saturation and greens pushed toward olive, not a strong colour cast.
- The LUT is generated once (size 17 or 33) and cached in a static var; LOW quality may skip it.

## Acceptance criteria (testable)

- [x] `tests/unit/test_color_grade.gd` (tolerance 0.01 unless stated):
  - neutral greys stay neutral: `grade(Color(v, v, v))` has `max(r, g, b) − min(r, g, b) ≤ 0.03` for v in {0.1, 0.5, 0.9};
  - luminance is monotonic over a grey ramp of 11 steps;
  - saturation drops: HSV saturation of `grade(#5a8a2e)` < saturation of `#5a8a2e`;
  - `lut(17, DEFAULT)` returns 17 images of 17×17; the texel at grid `(r, g, b)` equals `grade(Color(r/16, g/16, b/16))` (±1/255);
  - deterministic (two calls equal).
- [x] `test_battle_look.gd` (HIGH environment): `tonemap_mode == Environment.TONE_MAPPER_AGX`, `fog_aerial_perspective` in [0.5, 0.9], `ssil_enabled`, `glow_enabled`, `adjustment_enabled` with a 3D texture; sun elevation (angle between −light direction and the ground plane) in [25°, 35°]; no `CameraAttributes` with DOF enabled on the battle camera.
- [x] With LOW (TASK-050), SSIL and glow are off and the scene still renders (headless test that applies LOW).
- [x] Agent visual check (Windows build): `tools/screenshot.sh` before/after. Expected: longer shadows pointing away from the sun, shadow sides of units and trees lifted by bounce light (not black), distant hills hazier and bluer than near ones, greens more olive and less saturated, no bloom haze over the whole frame. If only the Linux renderer is available, say so – LOW hides SSIL/glow there.
- [x] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it, commit it with the change.

## Playtest (for the human)

1. `tools/run_windows.sh`. First impression: does it read as a grey-green Eastern European day rather than a sunny toy table?
2. Shadows: trees and vehicles throw longer, softer shadows than before; the dark side of a tank is dark but you can still see its shape and camo.
3. Rotate the camera so you look across the map: far tiles fade into a light haze; near tiles keep full contrast.
4. Sun glints on the water may glow slightly; nothing else should look blurry or foggy up close.
5. Compare with an old screenshot: colours are more muted/olive, but faction colours (blue/red HUD and markers) stay clearly readable – the HUD is not graded.
6. Report anything too dark (especially units in forest shadows).

## Player manual

None (presentation only).

## Out of scope

- HDRI sky (TASK-054), cloud shadows (TASK-066), volumetric fog, time of day / weather changes.
- Grading the HUD (CanvasLayer UI is not affected by `Environment` adjustments – keep it so).

## Implementation notes

2026-10-21 (presentation-engineer, reviewed).

- **New**: `src/presentation/color_grade.gd` (`ColorGrade`, pure static): `grade()`, `lut()`, `cached_texture()` (a 17³ `ImageTexture3D`, built once) and `apply_to(env)`. Grade order: contrast, then saturation, then a green-only hue shift weighted by how green the colour is (greys untouched), then split tint, then clamp. Tests are in `tests/unit/test_color_grade.gd`.
- **GraphicsQuality**: new feature key `color_grade` (HIGH on, LOW off). `apply_environment` assigns the LUT on HIGH and turns `adjustment_enabled` off on LOW. `battle_controller.gd` did not change, because it already calls `apply_environment`.
- **Final values**, tuned on the Windows D3D12 Forward+ screenshot (RX 580, HIGH):

| Setting | Value |
|---|---|
| Tonemap | AgX, exposure **1.3** (at ~1.0 AgX came out too dark), white 6.0 |
| Sun | elevation 30°, same azimuth as before, energy 1.55, `#ffeedd`, angular distance 1.0, shadow_blur 1.2 |
| Ambient | sky, energy 0.65 |
| Sky | top `#8fa3b5`, horizon and ground horizon `#c9cdc6`, `sun_angle_max` 3, `sun_curve` 0.3 |
| Background / fog colour | unchanged flat haze `#a9b4b2` (fully fogged tiles still blend into the background) |
| Fog | depth 30–140, aerial perspective 0.7, sun scatter 0.1 |
| SSAO | intensity 1.2 |
| SSIL | radius 3.0, intensity 0.6, sharpness 0.98 |
| Glow | intensity 0.25, bloom 0.01, soft light, HDR threshold 1.2 |
| Grade | saturation **0.92**, contrast 1.06, shadow tint `#1e2a2c` at 0.06, highlight tint `#fff1dc` at 0.05, green_shift **−0.02** |

- **Deviations from the spec**: saturation 0.92 instead of 0.82 and green_shift −0.02 instead of −0.03. AgX already desaturates, so the spec values came out muddy brown.
- **Visual check**: compared `.screenshots/task051_before.png` with `task051_after.png`. Shadows are longer and point away from the sun, and the dark sides of units and trees are not black. Grass is olive and muted instead of yellow-green, there is no bloom haze, and the HUD is unaffected. Mid-tones are slightly darker than before.
  - The default top-down shot hardly shows the far haze; only the corners look hazier. The human should check it by looking across the map.
  - The ≥ 25 % shadow-side brightness target was judged by eye only; there is no measurement.
- **LOW test**: it applies LOW to a duplicated environment and instantiates the scene. It does not run `BattleController`'s own path.
- **README**: `docs/images/gameplay.png` was re-rendered and read.
- **River**: added at the human's request so the water look can be checked. `Scenario.RIVER_COLUMNS` holds a north–south chain of water hexes between the armies, and the plains rows in `RIVER_FORDS` (2 and 7) are the crossings. Tests are in `test_scenario.gd`, and the replay fixture was regenerated.
  - In 20 AI-vs-AI matches, player 1 won 60 % (80 % before), with 0 errors and 9.1 turns on average (7.4 before).
  - Each water hex still renders as a separate pond with land between, because the terrain surface pulls toward each hex's own height. Making it one continuous river is follow-up presentation work.
