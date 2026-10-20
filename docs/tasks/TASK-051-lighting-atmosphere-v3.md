# TASK-051: Lighting & atmosphere v3 – AgX, lower sun, aerial perspective, SSIL, subtle glow, colour grading

- **Status**: ready
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

- [ ] `tests/unit/test_color_grade.gd` (tolerance 0.01 unless stated):
  - neutral greys stay neutral: `grade(Color(v, v, v))` has `max(r, g, b) − min(r, g, b) ≤ 0.03` for v in {0.1, 0.5, 0.9};
  - luminance is monotonic over a grey ramp of 11 steps;
  - saturation drops: HSV saturation of `grade(#5a8a2e)` < saturation of `#5a8a2e`;
  - `lut(17, DEFAULT)` returns 17 images of 17×17; the texel at grid `(r, g, b)` equals `grade(Color(r/16, g/16, b/16))` (±1/255);
  - deterministic (two calls equal).
- [ ] `test_battle_look.gd` (HIGH environment): `tonemap_mode == Environment.TONE_MAPPER_AGX`, `fog_aerial_perspective` in [0.5, 0.9], `ssil_enabled`, `glow_enabled`, `adjustment_enabled` with a 3D texture; sun elevation (angle between −light direction and the ground plane) in [25°, 35°]; no `CameraAttributes` with DOF enabled on the battle camera.
- [ ] With LOW (TASK-050), SSIL and glow are off and the scene still renders (headless test that applies LOW).
- [ ] Agent visual check (Windows build): `tools/screenshot.sh` before/after. Expected: longer shadows pointing away from the sun, shadow sides of units and trees lifted by bounce light (not black), distant hills hazier and bluer than near ones, greens more olive and less saturated, no bloom haze over the whole frame. If only the Linux renderer is available, say so – LOW hides SSIL/glow there.
- [ ] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it, commit it with the change.

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

_Filled in by the agent when done._
