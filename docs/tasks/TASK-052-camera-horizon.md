# TASK-052: Camera v2 – lower pitch with a visible horizon, backdrop terrain beyond the map

- **Status**: ready (revised 2026-10-22: the backdrop must not rely on the random generator – target maps are hand-made)
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

## Implementation notes

_Filled in by the agent when done._
