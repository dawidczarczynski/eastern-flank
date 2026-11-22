# ADR 0030: Real-scale sun shadows – cascaded shadows from impostors and the canopy shell, sun as look data

- **Status**: accepted
- **Date**: 2026-11-22
- **Task**: TASK-201a (builds on ADR 0021 real-scale visuals, ADR 0023 frame budget, ADR 0026 real-scale vegetation, ADR 0027 GPU-placed forest)

## Context

Under the `true` VisualScale preset (ADR 0021) forests and relief cast almost no shadow at the default camera ranges: only the full 3D trees (within ~250 m of the camera, ADR 0026) cast; the GPU-placed forest impostors (ADR 0027) and the canopy shell had casting off. Single-tree impostors had just been switched to cast (commit 50e19fe), but their quads faced the main camera in the shadow pass too, so their shadows turned with every camera orbit. The sun itself was a hand-set node in `scenes/battle/battle.tscn` (37.9° high, energy 1.1), the same for every scale and look.

TASK-201a asked for two forest-shadow options to be measured on the target GPU and the one that holds the 16.7 ms budget to be chosen:

- **A. Real cascaded sun shadows**: impostors and the canopy shell cast into Godot's PSSM directional shadow, with a longer far cascade under `true` (in metres via `MapScale`).
- **B. A baked per-chunk forest shadow mask**: the terrain shader darkens the ground where a forest stands up-sun of it (one extra texture sample per terrain fragment).

## Measurements

RX 580 (D3D12, Forward+), HIGH, `true` preset, default scenario, 1280×720, `tools/perf.sh` with temporary breakdown rows (camera on unit 1, yaw 30°, distance in world units; 1 unit = 144 m):

| Camera | Frame avg (A, all on) | A: impostor + shell casting | A: longer far cascade + tighter splits | B: mask proxy in terrain shader | All sun shadows |
| --- | --- | --- | --- | --- | --- |
| 1.2 | 8.34 ms | 0.83 ms | 0.53 ms | 0.03 ms | 1.47 ms |
| 5 | 7.47 ms | 0.42 ms | 0.14 ms | 0.12 ms | 1.36 ms |
| 24 | 6.21 ms | 0.00 ms | ~0 (noise) | 0.15 ms | 0.67 ms |

Option B was measured as a cost proxy, not built: a temporary branch in `terrain.gdshader` sampled the land-cover raster once at a point shifted up-sun by the shadow length of a 24 m tree and darkened the albedo there; a real mask would be a baked, blurred R8 texture per chunk, sampled the same way (one fetch), plus the bake on the worker threads. Its frame cost is ~0.1 ms, but it shades only the terrain (not units, scrub, other trees or the relief), does not follow the drawn trees (burnt circles, the impostor thinning), needs a bake per chunk and a sun direction baked in.

## Decision

1. **Option A: real cascaded shadows.** Both options hold the budget with a wide margin (worst case 8.3 ms of 16.7 ms at 720p); A costs at most ~1.4 ms more than B at the closest zoom and gives real shadows from the same casters the player sees, on everything. B stays the documented fallback for a slower GPU (or LOW, which has no shadows at all).
2. **Impostors face the sun in the shadow pass** (`impostor_facing` in `tree_impostor_view.gdshaderinc`, used by `forest_impostor.gdshader` and `tree_impostor.gdshader`): when the view matrix is not the main camera's, the quad and its atlas view turn to the light, so it casts the tree's silhouette as the sun sees it, which does not change when the camera orbits (no shimmer). Band choice (full / impostor / culled, the far thinning) still uses the main camera's distance in both passes, so the caster set equals the drawn set. `ForestField` impostor chunks cast.
3. **The canopy shell casts** (`ForestShell`), so beyond the impostors forest edges still throw a shadow onto the fields; `canopy.gdshader` fades crowns by the main camera's position (a varying from `MAIN_CAM_INV_VIEW_MATRIX`), not `CAMERA_POSITION_WORLD`, which is the light's in the shadow pass.
4. **Far cascade in metres under `true`**: `GraphicsQuality.features` `shadow_max_distance_true_m` (14 km on HIGH, > the 80 units = 11.5 km of HIGH) and `shadow_splits_true` (0.04 / 0.12 / 0.35 instead of Godot's 0.1 / 0.2 / 0.5, so the first cascade spans ~560 m and keeps trunk and vehicle detail at the close zoom); `apply_sun` converts with `MapScale` and restores the defaults outside `true`. LOW is unchanged (40 units, 2048 atlas, shadows off).
5. **The sun is look data**: `LookPreset.SUN_DEFAULT` (direction as elevation / azimuth, colour, energy, angular distance, shadow blur / bias / normal bias, ambient energy) equals the battle scene's Sun node and environment (tested), a preset may override it (`"sun"`), and `REAL_SIZE_SUN` sets the `true` sun: 24° high (balanced 37.9°), warmer (`#ffdcb8`), energy 1.45, ambient 0.5 (> 0: shadows not crushed). `BattleController` applies it with `LookPreset.apply_to_sun` after `GraphicsQuality.apply_sun`. Azimuth stays the HDRI sun's.

## Consequences

- (+) Forest edges, single trees and relief cast stable shadows at every zoom of `true`; lee slopes of hills read darker under the lower sun.
- (+) The sun can differ per look (e.g. a lower autumn sun) without touching the scene.
- (−) ~0.4–0.8 ms more at the close and middle zooms (impostor vertex work in up to four cascades); free at the overview.
- (−) An impostor is a flat card: its own shadow-pass quad and its camera-facing quad cross, so the half of a crown behind the sun-facing card receives its own shadow (reads as the shaded side of the crown; a playtest decides whether it shows).
- (−) The `true` sun (24°) no longer matches the HDRI sun disc's height (37.9°); only visible when the sky near the sun is in view.
- The RX 580 numbers above are from this machine's Windows Godot build, 720p, one static frame per row; panning and 1080p were not measured here.
