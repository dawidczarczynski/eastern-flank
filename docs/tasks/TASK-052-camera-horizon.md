# TASK-052: Camera v2 – lower pitch with a visible horizon, backdrop terrain beyond the map

- **Status**: done (playtested 2026-10-22; playtest 2026-10-22: add player-adjustable tilt; revised 2026-10-22: the backdrop must not rely on the random generator – target maps are hand-made)
- **Layers**: presentation (`camera_math.gd`, `camera_rig.gd`, `battle.tscn` camera FOV, `map_view.gd` backdrop), tests (`test_camera_math.gd`, map view tests), `tools/readme_screenshot.sh` framing if needed
- **Depends on**: soft **TASK-051** (aerial-perspective fog hides the end of the backdrop), soft **TASK-050** (`backdrop_scatter`)
- **Model**: sonnet

## Goal

Zoomed in, the camera looks across the land toward a hazy horizon and sky, like standing on a hill above the battlefield; zoomed out it turns almost top-down for planning. The map no longer ends in a void at its edges – the countryside continues, clearly outside the playable area.

## Current state

`CameraMath.pitch_for_distance(d) = 0.82 + (d − 8)/37 · 0.3` → ≈ 46° at d 7, 54° at the default 24, 65° at 46. Camera `fov = 34°` (vertical), so the top of the frame is ≥ 29° below the horizon: no horizon is ever visible. The terrain mesh, water and scatter stop at the map rectangle.

## Design (starting values – the human judges the trade-off in the playtest)

- **FOV** 34° → **40°**.
- **Pitch**: piecewise linear through `(7, 0.30 rad ≈ 17°)`, `(24, 0.56 rad ≈ 32°)`, `(46, 1.05 rad ≈ 60°)`, clamped outside [7, 46]. At d 7 the horizon is inside the frame (pitch < FOV/2); at the default 24 the top of the frame shows far, fogged backdrop terrain; at 46 the view is close to top-down. Keep these points as named constants in `CameraMath`.
- **Zoom clamp near the ground**: the camera must never go below `ground_height(camera xz) + 1.5` (raise the look-at height or the pitch locally if a hill is under the camera); a pure helper computes the minimum pitch for a given ground height.
- **Backdrop terrain**: `MapView` builds a non-playable ring around the map, **14 world units** wide, at **half** the mesh resolution of the playable terrain, with the same material. Heights must not depend on the random map generator (the target is hand-made maps, where nothing exists beyond the edge): a pure helper `BackdropHeights` (presentation, static) continues the border heights outward (edge-clamped `TerrainSurface` height at the nearest border point) plus a low-amplitude view-local noise that fades in with distance from the edge, eased towards a gentle mean level, so it works for any map; terrain colour/type continues from the nearest border tile. (Later, a hand-made map may supply its own backdrop – out of scope.) Water plane extended to cover it. On HIGH (`backdrop_scatter`) the backdrop gets trees/bushes by the same `ScatterPlanner` rules at **50 %** density; on LOW none.
  - The backdrop has **no grid lines, no overlays, no picking**: surface raycasts hitting it return "off map" (the hover ring hides as it does today off the map). The camera target clamp (`CameraMath.clamp_target`) stays on the playable map.
  - **Playable edge cue**: backdrop ground is slightly desaturated/darkened (×0.85 value, ×0.7 saturation, blended over 1.5 units from the edge) so the edge is readable without a hard line.
  - Seam: heights at the map border must match exactly (same function), no cracks.
- **No DOF / tilt-shift** (explicit design decision, see GDD "Visual direction: realism").
- `tools/readme_screenshot.sh` keeps its framing goal (close-up with units); adjust its fixed camera values if the new pitch makes the shot worse, and note the new values.

## Acceptance criteria (testable)

- [ ] `test_camera_math.gd`: `pitch_for_distance(7) == 0.30`, `(24) == 0.56`, `(46) == 1.05`, `(15.5) == 0.43` (±0.001), clamped below 7 and above 46; monotonic over [7, 46]. Remove/replace the old formula's assertions.
- [ ] `min_pitch_for_ground(...)`/equivalent: with the ground under the camera at height 2.0 and target height 0.4, the camera height is ≥ 3.5 for every distance in [7, 46].
- [ ] Battle camera `fov == 40`.
- [ ] `MapView` on `Fixtures.plains_grid(…)`: a backdrop mesh exists whose AABB extends the playable terrain AABB by 14 ± 0.5 on every side in x and z; the height at 5 sample points on the shared border is equal (±0.001) for the playable and the backdrop mesh.
- [ ] `BackdropHeights`: deterministic; at distance 0 from the edge equals the border height; does not call `MapGenerator` / `TerrainField` (works on a grid built by hand in the test).
- [ ] Picking: a ray hitting the backdrop returns no map coordinate; hover is cleared.
- [ ] Grid lines and overlay helpers produce no vertices outside the playable map rectangle.
- [ ] Backdrop scatter: present with `backdrop_scatter = true`, absent with false.
- [ ] Agent visual check (Windows build): screenshot at d 7 (hook or `CameraRig.set_view`) shows sky above a hazy horizon; default screenshot shows fogged land at the top of the frame, no black/void edge; at d 46 the map edge shows continuing countryside, slightly greyer than the playable area.
- [ ] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it, commit it with the change.

## Playtest (for the human)

1. Zoom fully in: you see the horizon and sky over the hills; the ground near the camera is not clipped through.
2. Zoom out step by step: the view tilts down smoothly toward top-down; no jumps.
3. Pan to every map edge and rotate: the land continues beyond the edge (trees, hills, water), slightly greyer; the hover ring does not appear beyond the edge; you cannot pan the camera target off the map.
4. Readability: at the default zoom, can you still judge hexes, reach and enemy positions comfortably? If the default is too low, say which zoom felt right – the pitch points are constants.
5. Hover over a tall hill near the camera at full zoom-in: the camera stays above the ground.

## Player manual

Section 11, Zoom row: "Mouse wheel – the camera tilts toward the horizon as you zoom in and looks almost straight down when zoomed out." Section 10 (or 1): "The land beyond the map edge (slightly greyer) is scenery; units cannot go there."

## Out of scope

- Free-look/first-person camera, camera shake, cinematic cameras for attacks.
- Distant impostor mountains/skybox geometry beyond the 14-unit backdrop.

## Playtest revision (2026-10-22): player-adjustable tilt

The human wants to adjust the camera tilt, with a way back to the default.

- The player sets a **pitch offset** on top of the automatic `pitch_for_distance` curve, not an absolute pitch. Zooming keeps following the curve, shifted by the offset.
- Clamps:
  - offset within ±0.35 rad (≈ ±20°);
  - resulting pitch within [0.14 rad ≈ 8°, PI/2];
  - the ground clearance (+1.5) still applies on top.
  All of these are named constants in `CameraMath`.
- Controls:
  - **Ctrl + wheel**: tilt step (wheel up = toward the horizon);
  - **R / F**: continuous tilt (R = toward the horizon, F = toward top-down);
  - **middle mouse drag (vertical)**: continuous tilt;
  - **Home**: smooth reset of the offset to 0 over about 0.3 s.
  Plain wheel still zooms.
- The offset persists until reset (per match; not saved to settings).
- Update the camera_rig header comment and the HUD hint line if it lists controls.

### Acceptance criteria (revision)

- [ ] `test_camera_math.gd`: `pitch_with_offset(d, 0) == pitch_for_distance(d)`; the offset is clamped to ±0.35; the result is clamped to [0.14, PI/2] (e.g. d 7 with offset −0.35 → 0.14; d 46 with +0.35 → 1.40, inside the PI/2 cap); the tilt step and reset helpers are pure and tested.
- [ ] `CameraRig`: a test that Ctrl+wheel changes the offset and leaves the distance unchanged, plain wheel changes the distance and leaves the offset unchanged, and Home brings the offset back to 0 (after the reset animation).
- [ ] MANUAL section 11: tilt controls and reset.

## Implementation notes

- **Camera** (`camera_math.gd`): the pitch is piecewise linear through the named constants `(7, 0.30)`, `(24, 0.56)`, `(46, 1.05)` and clamped outside that range. `GROUND_CLEARANCE = 1.5`. `min_pitch_for_ground()` and `clear_pitch(ground_fn, …)` raise the pitch, re-sampling the ground under the camera up to 8 times; if that does not settle, they fall back to straight down (PI/2). `CameraRig.set_ground_query()` gets `MapView.visible_ground_height` from `battle_controller`. Battle camera `fov` is 40.
- **Backdrop**:
  - `BackdropHeights` is static and pure. It takes the edge-clamped `TerrainSurface` height at the nearest point of the playable rectangle and eases it toward a mean of 0.35 over 12 units, adding fbm noise (amplitude 1.1) that fades in over 5 units. It does not use `MapGenerator` or `TerrainField`.
  - `BackdropMesh` builds a ring 14 wide at twice the playable cell size and uploads only the ring vertices.
  - Seam: the playable mesh now has an even cell count, and its odd outer-margin border vertices are averaged between their even neighbours, so the half-resolution ring meets it with no cracks. The margin lies outside the hexes, so this is invisible.
  - Colour: at the seam it equals the playable margin colour, then blends over 1.5 units to the nearest border tile's colour with value ×0.85 and saturation ×0.7.
  - `BackdropSurface` (a `TerrainSurface` with callable heights) lets `ScatterPlanner` plant the ring at 50 % density, thinned by a position hash, only when `backdrop_scatter` is on.
  - The water plane already covered the ring (margin 80).
  - `MapView.pick_coord()` returns null off the map; the controller's `_pick_hex` uses it.
- The ring code lives in separate files because `map_view.gd` reached the 1000-line lint limit.
- `tools/readme_screenshot.sh` framing is unchanged (`SCREENSHOT_CAMERA=2,-40,11`); the shot was re-rendered.
- Agent visual check (Windows build): at d 7 the horizon is about 13 % from the top of the frame; the default zoom shows fogged backdrop at the top with no void; at d 46 countryside continues at the edges.
- **Playtest revision, player tilt (2026-10-22)**:
  - Constants in `CameraMath`: `PITCH_OFFSET_LIMIT` 0.35, `PITCH_MIN` 0.14, `PITCH_MAX` PI/2, `TILT_STEP` 0.05, `TILT_KEY_SPEED` 0.6, `TILT_MOUSE_SPEED` 0.004, `TILT_RESET_SECONDS` 0.3.
  - Helpers: `pitch_with_offset`, `clamp_pitch_offset`, `tilt_step`, `reset_offset`, `camera_offset_at_pitch` (no curve floor); `clear_pitch` takes the offset.
  - `CameraRig` controls: Ctrl+wheel (no zoom); R/F (ignored while Ctrl/Alt is held); middle-drag (cleared when its release is lost to a HUD control); Home eases back to the curve in ≤ 0.3 s and is cancelled by any tilt input.
  - HUD hint extended; its label is widened to 600 px so it stays on two lines.
  - Screenshot hook: `SCREENSHOT_PITCH_OFFSET` (radians).
  - Review caught that the ground-clearance path floored negative offsets back to the curve; fixed, with a rig test using a ground query.
  - Tests: `test_camera_tilt.gd`, `test_camera_rig.gd`. R/F polling and the positive middle-drag direction are not covered: `Input` state can't be simulated headless.
  - At d 46, +0.35 gives 1.40 rad (~80°), not top-down; widen the limit if the human wants full top-down there.
- Open points for the playtest:
  - The sky reads dark slate rather than light haze (`background_energy_multiplier = 0.55` in `battle_environment.tres`, from TASK-051).
  - At d 46 the backdrop's muting is barely visible, and the water plane ends in a straight line at the frame sides.
  - Only the plains fixture and the default battle were checked, not a hand-made map.
