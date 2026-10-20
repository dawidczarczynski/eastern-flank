# TASK-054: HDRI sky – CC0 overcast/partly-cloudy panorama as sky, ambient and reflections

- **Status**: ready (blocked by TASK-053's decision)
- **Layers**: presentation (`battle_environment.tres`, sun direction in `battle.tscn`), `assets/third_party/hdri/`, tests
- **Depends on**: **TASK-053** (asset policy + manifest), **TASK-051** (AgX, fog, sun values to retune against the HDRI)
- **Model**: sonnet

## Goal

A real photographed sky over the battlefield: soft, cloudy, Eastern-European light. The same sky lights the scene (ambient) and shows in reflections on water and vehicles, so everything sits in one coherent atmosphere – and with the lower camera of TASK-052 the sky is actually visible.

## Design

- Pick **one** CC0 pure-sky HDRI (no ground/buildings in the lower half, or a lower half that disappears behind the backdrop haze) from Poly Haven, overcast or partly cloudy with a visible but soft sun. Examples to evaluate: the "Kloofendal … Partly Cloudy (Pure Sky)" family, any "overcast … puresky" panorama. Present 2–3 candidates to the human as screenshots if unsure; record the chosen one and why.
- Resolution **2K** (`.hdr` or `.exr`), stored at `assets/third_party/hdri/<id>/`, entry added to `credits.json` (TASK-053 test must pass).
- Environment: `Sky` with `PanoramaSkyMaterial` (the HDRI), `background_mode = BG_SKY`, `sky_rotation` chosen so the HDRI's sun azimuth matches the `Sun` light; set the `Sun` elevation to the HDRI sun's elevation if it is within 25–40° (otherwise keep TASK-051's 30° and rotate the sky so the brightest region is near the light). `ambient_light_source = SKY`, `reflected_light_source = SKY` (as TASK-026), sky energy so the exposure matches TASK-051's look (grass brightness ±10 % of the TASK-051 screenshot).
- Fog colour (`fog_light_color`) sampled from the HDRI horizon band (average) so the haze blends into the sky; `fog_sky_affect` tuned (≈ 0.5) so the horizon is not a flat grey line.
- `sky` process mode: `PROCESS_MODE_QUALITY` on HIGH, `INCREMENTAL` or `REALTIME` with low radiance size on LOW (via TASK-050) – the sky is static, so radiance is baked once.

## Acceptance criteria (testable)

- [ ] `credits.json` has the HDRI entry; `test_third_party_assets.gd` passes.
- [ ] `test_battle_look.gd`: the sky material is a `PanoramaSkyMaterial` with a non-null `panorama`; ambient and reflection sources are the sky; the sun elevation is in [25°, 40°]; `fog_light_color` is not the old `#a9b4b2` default (it was derived from the HDRI – record the value).
- [ ] The angle between the HDRI sun azimuth (recorded in the notes, measured from the image) and the `Sun` light azimuth is ≤ 10°.
- [ ] Agent visual check (Windows build): zoomed-in screenshot (TASK-052) shows clouds in the sky, the horizon haze matches the sky colour, shadows point away from the bright part of the sky; water reflects the sky colour. Default screenshot: overall brightness close to TASK-051's.
- [ ] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it, commit it with the change.

## Playtest (for the human)

1. Zoom in and rotate the camera 360°: a cloudy sky all around, no seams or stretched pixels; the brightest part of the sky is on the side the shadows point away from.
2. The haze at the horizon has the same colour as the sky just above it.
3. Look at the water and a vehicle top: they pick up the sky's colour.
4. Overall: does the light feel like a real cloudy day? Too bright/too dark/too blue?

## Player manual

None (presentation only).

## Out of scope

- Animated clouds, day/night cycle, weather. Cloud shadows on the ground (TASK-066).

## Implementation notes

_Filled in by the agent when done._
