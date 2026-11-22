# TASK-201a: Real-scale shadows and sun data

- **Status**: done
- **Layers**: presentation (sun, `GraphicsQuality`, `LookPreset` sun data)
- **Depends on**: TASK-191 (done)
- **Sections**: ARCHITECTURE "Graphics quality", "Real-scale vegetation"; ADR 0023, 0026, 0027; look reference TASK-190
- **Model**: opus
- **Tags**: battle-look

## Goal

Forests and relief cast soft, stable shadows at the default camera range, hillsides facing away from a warm, lower sun are visibly darker – within the frame budget.

## Decisions (2026-11-22)

- TASK-201 is split into 201a (shadows, sun data) and 201b (cloud shadows, colour grade).
- Both forest-shadow options are measured; the one that holds the budget wins, the baked mask is the fallback.
- Reference look = Arma 3 Chernarus / Arma Reforger Everon aerial views, as in TASK-190.

## Acceptance criteria (testable)

- [ ] ADR 0030 records the plan: both options measured on the RX 580 (ms per option) – real cascaded sun shadows (longer far cascade under `true`, distance in metres via `MapScale`; impostors and the canopy shell casting; impostors of single trees already cast, commit 50e19fe) versus a cheap baked per-chunk forest shadow mask darkening terrain – and the one that holds the budget is chosen, the mask being the fallback.
- [ ] Visible, stable shadow from forest edges and relief at the default camera range: no shimmer on camera move, no peter-panning on trunks.
- [ ] LOW keeps the current setup (test: `GraphicsQuality` features `shadow_max_distance` 80 / 40 and atlas 4096 / 2048 unchanged).
- [ ] Test: `GraphicsQuality` features define the far-cascade distance for `true` (in metres via `MapScale`), larger than the current value.
- [ ] Sun direction, colour, energy and ambient are data in `LookPreset` (today the sun lives in scenes/battle/battle.tscn: energy 1.1, blur 0.8, bias 0.03); test: every preset has all sun fields.
- [ ] `balanced` values equal today's (test compares them to the scene's current numbers).
- [ ] `true` has a warm, lower sun: hills facing away are visibly darker, shadows not crushed (test: sun elevation of `true` < `balanced`; ambient floor > 0).
- [ ] Frame time at camera 1.2 / 5 / 24 <= 16.7 ms avg on the RX 580 (`true`, HIGH, 720p), or the shortfall and the quality level that holds it recorded.
- [ ] Screenshots (tools/screenshot.sh) Read at 5 / 12 / 24: shadows on slopes and behind forests, no light leaking.

## Playtest (for the human)

1. `true` preset: orbit the camera around a forest and a hill – shadows stay consistent with the sun direction, no flicker or shimmer.
2. Frame rate while panning at all zoom levels.

## Player manual

None.

## Out of scope

- Time of day / weather, volumetric light rays.
- Cloud shadows and colour grade (TASK-201b).

## Implementation notes

- **Chosen: real cascaded shadows (option A)**, ADR 0030 with the RX 580 numbers (720p, HIGH, `true`): frame avg 8.34 / 7.47 / 6.21 ms at camera 1.2 / 5 / 24 (budget 16.7). Impostor + shell casting cost 0.83 / 0.42 / 0.00 ms, the longer far cascade + tighter splits 0.53 / 0.14 / ~0 ms; the baked mask (option B) measured as a proxy only (one land-cover sample up-sun in `terrain.gdshader`, temporary, reverted): 0.03 / 0.12 / 0.15 ms. Both hold the budget; A shades everything with the casters actually drawn, B stays the fallback.
- Impostors turn to the sun in the shadow pass (`impostor_facing`, `tree_impostor_view.gdshaderinc`; both impostor shaders), so their shadows do not turn with the camera; the bands still follow the main camera. `ForestField` impostor chunks and `ForestShell` cast; `canopy.gdshader` fades by the main camera's position in the shadow pass too.
- `GraphicsQuality.features`: `shadow_max_distance_true_m` (HIGH 14 000 m = 97 units > 80; LOW 0 = unchanged) and `shadow_splits_true` (0.04 / 0.12 / 0.35); `apply_sun` uses them only under `true` and restores Godot's split defaults otherwise.
- `LookPreset.SUN_DEFAULT` / `sun()` / `apply_to_sun()`: direction, colour, energy, penumbra, shadow blur / bias / normal bias and ambient energy as data; equals the scene's Sun + environment (test), `REAL_SIZE_SUN` under `true`: 24° (balanced 37.9°), `#ffdcb8`, energy 1.45, ambient 0.5. Applied by `BattleController._setup_graphics_quality` (also on the arena's rebuild).
- Tests: `test_graphics_quality.gd` (true far cascade in metres > 80 units, apply under true / LOW / balanced), `test_look_preset.gd` (every preset has all sun fields, balanced = battle scene, true lower + warmer + ambient > 0).
- Screenshots read (`true`, camera unit 1, yaw 30, distance 5 / 12 / 24; close-ups 1.5 at yaw 30 and 120): tree and wood shadows fall the same way from both yaws, attached to the trunks, no light leaking; at 12 / 24 a forest edge shadow is a few pixels (54 m at real scale) and lee slopes / depressions read darker. An A/B shot at 12 with forest casting off shows the darker forest interior and edge strip it adds.
- Not verified here: shimmer while moving (stills only), 1080p and panning frame times.
