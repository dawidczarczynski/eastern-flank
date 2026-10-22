# TASK-054: HDRI sky – CC0 overcast/partly-cloudy panorama as sky, ambient and reflections

- **Status**: done (playtested 2026-10-22)
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

- **HDRI**: Poly Haven `kloofendal_38d_partly_cloudy_puresky` (Greg Zaal / Jarod Guest, CC0), 2K `.hdr` at `assets/third_party/hdri/kloofendal_38d_partly_cloudy_puresky/sky_2k.hdr`, credited in `credits.json`. Chosen from the Poly Haven "pure skies" overcast/partly-cloudy set because it is the only candidate with visible cumulus and a soft sun inside 25–40° (37.9°); its horizon average (#abb1b5) is almost the old haze (#a9b4b2), so the TASK-051 look carries over. Rejected: `kloofendal_28d_misty_puresky` (washed-out, no cloud structure), `kloppenheim_03_puresky` (sun 58.5°), `farm_field_puresky` (sun 50.8°).
- **Measured from the image** (brightest pixel): u = 0.5999, elevation 37.9°. Horizon band 0–8° average linear (0.410, 0.439, 0.463) = sRGB #abb1b5.
- **Alignment**: Godot maps the panorama as u = atan2(x, −z) / TAU, so the HDRI sun is at sky-space azimuth −144°; the `Sun` toward-sun azimuth is −127.9° (unchanged from TASK-051) → `sky_rotation = (0, −16.1°, 0)`. Verified by a render aimed along the Sun's toward-sun direction: the sun disc is centred to ~0.1° in azimuth, < 1° in elevation (pinned by `test_sky_rotation_aligns_hdri_sun_with_sun_light`).
- **Environment**: `BG_SKY` + `PanoramaSkyMaterial` (energy 1.0), `background_energy_multiplier` 0.48; ambient/reflection sources SKY. `fog_light_color` #abb1b5, `fog_light_energy` 0.48 (= sky energy, tested), `fog_sky_affect` 0.5. `Sun` elevation 30° → 37.9°, energy 1.55 → 1.1.
- **Finding**: `ambient_light_energy` has no effect on sky-sourced ambient (tested 0 → 2.0, identical render); sky ambient and reflections scale with `background_energy_multiplier`, which also sets the visible sky brightness. So sky and ground brightness are coupled; the trade-off was a dimmer sky (0.48) and a weaker sun (1.1).
- **Quality**: `GraphicsQuality.features` gets `sky_process_mode` / `sky_radiance_size` – HIGH `PROCESS_MODE_QUALITY` + 256, LOW `PROCESS_MODE_INCREMENTAL` + 64 (LOW only unit-tested, not rendered). `apply_environment` duplicates `env.sky` so the cached resource is not mutated.
- **Brightness vs TASK-051** (mean sRGB luminance, default screenshot, Windows D3D12): grass regions 0.451/0.440/0.428 → 0.480/0.465/0.463 (+4…+8 %), rock/ground 0.347 → 0.380 (+9.5 %), top strip 0.179 → 0.188 – within ±10 %.
- **Visual check (agent, Windows build)**: default view nearly identical to before; close-ups (4 yaws) show a muted grey-blue partly cloudy sky, the horizon haze blends into it with no flat line. Weak spots: with the camera tilt limit only ~15–20° of sky is on screen and the clouds read faintly; shadows are a little softer/less contrasty than before. The HDRI sun is never in frame in normal play, so "shadows point away from the bright sky" holds by construction (shared azimuth) rather than by eye. No dedicated water-reflection close-up; ponds read blue-grey.
- `tools/render_unit.gd` cast the sky material to `ProceduralSkyMaterial`; it now uses a fixed flat ambient colour (0.675, 0.72, 0.745) at 0.65 (the old procedural mean). Unit sheets' reflections now come from the HDRI, so they may look slightly different from earlier sheets.
- README screenshot re-rendered with the final settings.
