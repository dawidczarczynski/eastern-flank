# TASK-111: Fixed-pixel unit markers and a much closer camera for real-size units

- **Status**: done
- **Layers**: presentation (`UnitLabel` → unit marker with class icon, anchoring, `CameraMath` / `CameraRig` zoom range and pitch curve, near plane, pan speed) + docs (ARCHITECTURE, MANUAL)
- **Depends on**: TASK-110 (marker look, camera numbers and the real-size preset come from the study) (priority: after the operational core loop 092 → 094 → 095)
- **Model**: opus (camera curves, near plane and every distance-based LOD / visibility range interact)
- **Tags**: battle-look
- **Topic**: Visual realism

## Goal

Decided 2026-10-31: unit models are drawn at real size, with no enlarged units. At real size a tank is ~3 px long at the default zoom, so the player finds units by **on-screen markers** – a class icon plus the existing tag (faction tab, short name, HP bar) at a **fixed pixel size**, readable at every zoom. A **much closer minimum camera distance** lets the player look at the real-size models. This task only adds the markers and the camera range. Switching the models to real size is one of TASK-110's follow-up tasks and depends on this one.

## Confirmed targets (human, 2026-11-10, TASK-110 study; they override the proposals below)

- **Minimum camera distance ~0.18 world units (≈ 26 m)** – changed 2026-11-21 (human, after a zoom study on a Leopard-class tank in the `true` preset, `.screenshots/zoom/`: at 0.15–0.25 the vehicle reads well and the model's simplicity (flat colour, boxy track guards, no texture detail) is not yet exposed; at 0.12 it is; at 0.3 the shot reads as a map). Supersedes the earlier ~1.0 (≈ 144 m, 2026-11-10, tank ≥ 40 px at 1.2). `MAX_DISTANCE` stays 46.
- **Close-range camera** as in the prototype (`CameraRig` / `SCREENSHOT_MIN_DISTANCE`): below 7 the camera looks at the ground under the target; ground clearance ∝ (d / 7)²; the pitch curve approaches the horizon at the minimum (about 17°, `PITCH_CLOSE` 0.30 rad, at 0.18–0.25). The "2 m above terrain" rule below stays (26 m at 17° is ~7.6 m high).
- **Marker look**: class icon next to today's fixed-pixel tag; the label is anchored to the unit's ground point (fixed pixel offset), no longer 0.62 units (90 m) above the unit.
- **Group-drawing hook** (for the company group, TASK-136): the camera/marker code exposes one constant `GROUP_DRAW_DISTANCE` = 3.0 units. Below it the unit is drawn as a 3–4 model group (TASK-136) and the marker stays; above it only the marker (plus the single model). TASK-111 adds only the constant and a `UnitView`-readable "distance to camera" query, no group drawing.

## Design (numbers to be confirmed by TASK-110's study before the task starts; the targets above win)

- **Marker** = today's `UnitLabel` (HUD control, already a fixed pixel size) plus a **class icon** in front of the short name: a small frame in the faction colour with an APP-6-like symbol for the unit class (`infantry` cross, `tank` oval, `mlrs` filled dot with a rocket mark), 15 × 11 px, drawn with `HudShapes` (procedural, no new asset). The class comes from `UnitDefinition.unit_class` (view reads only).
- **Anchor**: the marker sits a fixed **18 px** above the screen position of the unit's **ground point** (tile centre at terrain height), not above the model top, so it doesn't move with the model scale. Hidden behind terrain like today's labels (same occlusion rule).
- **Overlap**: when two markers would overlap on screen (zoomed out), the one closer to the camera wins and the other is shifted up by its height (at most one shift step); the HUD never hides a unit's marker.
- **Picking and hover** stay hex-based (a 3 px model can't be clicked); clicking a marker selects its unit.
- **Camera**: `CameraMath.MIN_DISTANCE` from 7 to the study's value (**0.18 units ≈ 26 m** since 2026-11-21: a real tank is then ~300 px long at 720p; it was 1.0 ≈ 144 m, ~55 px, before), `MAX_DISTANCE` stays 46. The pitch curve extends to the new close range, approaching the horizon at the closest zoom; zoom steps are geometric (each wheel step × the same factor), so going from 46 to 0.4 takes a similar number of steps to today plus the extra range; pan speed scales with the distance; the camera never goes below the terrain plus **2 m**; near clip plane small enough (≤ 0.01 units) at the closest zoom, with no z-fighting of ribbons and overlays (checked on screenshots).
- **Distance-based ranges** (grass `visibility_range_end`, tree / bush LODs, wind distance, decals) are measured from the camera or chunk, so they keep working; TASK-110's follow-ups rescale them to metres. This task only makes sure nothing breaks at the new close range.

## Acceptance criteria (testable)

- [ ] `UnitLabel` (marker) has a class icon for every `unit_class` in `docs/design/units/classes.json`; icon size 15 × 11 px; the marker's pixel size is the same at camera distances 0.4, 24 and 46 (test via the control's size).
- [ ] The marker's screen anchor = `camera.unproject_position(ground point)` − (0, 18 px) (± 0.5 px) for a unit at a known position, at any model scale (the model's AABB doesn't change it).
- [ ] Overlap: two units whose markers would overlap → the farther one is shifted up by its height; no shift without overlap.
- [ ] `CameraMath.GROUP_DRAW_DISTANCE` = 3.0.
- [ ] `CameraMath.MIN_DISTANCE` = 0.18 (changed 2026-11-21 from the earlier 1.0); zooming in from the default reaches it; the near plane, pan speed per step, the "distance to camera" query and every distance-based range (unit label hide distance, decals, effects, `visibility_range`) work at 26 m; the pitch at MIN_DISTANCE is within the new curve's limit and the camera height over the terrain is ≥ 2 m (in world units via `MapScale`) everywhere on the Suwałki map (sampled).
- [ ] Zoom steps: the ratio between consecutive distances is constant (± 1 %); from 46 to 0.18 takes at most ~25 wheel steps.
- [ ] Close-up readability (from the 2026-11-21 zoom study): at 0.18 / 0.25 the near grass (`GrassNear`) and the river / lake overlays show no artefact that exposes the camera (grass cards read as paper cut-outs and the water ribbon hovers over the terrain in the study screenshots: record what was done or file a follow-up; at least no flicker, no ground clipping the camera, no rings or decals popping).
- [ ] Clicking a marker selects its unit; hovering and selecting by hex are unchanged.
- [ ] Screenshots Read by the agent: Suwałki and the default battle at distances 46, 24 and the minimum, with the real-size preset from TASK-110 (`SCREENSHOT_SCALE_PRESET=true`) and with today's preset: every unit has a readable marker, no ribbon / overlay flicker at the minimum distance; frame time at the minimum distance recorded (60 FPS rule).

## Playtest (for the human)

1. Zoom all the way out and in: every unit always has its marker (icon + name + HP bar) at the same size on screen.
2. Zoom in much closer than before: the camera goes down to ~26 m from the unit (a few metres above the ground), looking towards the horizon; you can look at a single vehicle up close and it still looks good. No flickering roads, rings or ground.
3. Click a marker: selects the unit. Hover and select hexes as before.

## Player manual

§10 "Screen": unit tags become unit markers with a class icon (infantry / tank / rocket artillery), always at the same size on screen. Camera controls table: the zoom now goes much closer (down to about 25 m from the focus point, looking towards the horizon). Units are drawn at their real size, so at a distance you find them by their markers – write this once TASK-110's follow-up switches the models to real size.

## Out of scope

- Switching unit models, trees, grass, textures and effects to real size (TASK-110 follow-ups).
- Company representation (one vehicle or a group – decided in TASK-110).
- Terrain mesh refinement near the camera (TASK-110 follow-up).

## Implementation notes

2026-11-22 (presentation-engineer):

- **Marker**: `UnitLabel` now has a `UnitClassIcon` (`src/presentation/unit_class_icon.gd`, 15 × 11 px plate in the faction colour, dark ink glyph) between the faction tab and the short name. The glyphs are `HudShapes.class_glyph` / `class_glyph_dots`, which give polylines and dots for all 11 classes in `docs/design/units/classes.json` (infantry cross, tank oval, mech_infantry / ifv cross + oval (the same APP-6 symbol), apc cross + wheels, recon slash, sp_artillery oval + dot, mlrs dot + two rockets (as on the staff-map counter), air_defense dome, atgm inverted V, engineer bridge mark). An unknown class gets an empty plate.
- **Anchor**: the bottom centre of the label is `unproject_position(UnitView.ground_point()) − (0, 18)` (`UnitLabel.ANCHOR_OFFSET`). The ground point is the unit's node origin (its feet on the terrain), so the model scale never moves the label. `UnitModels.label_height` / the models' `LABEL_HEIGHT` are no longer used by the view (they stay in the model files, which belong to unit-modeler). The marker is still hidden only behind the camera; there was no terrain-occlusion rule to keep.
- **Overlap**: `UnitLabel.overlap_shifts` is pure. Markers are ordered by `UnitView.distance_to_camera`, and a marker that overlaps a closer one that kept its place moves up by its own height, at most once. `BattleController._layout_markers` runs it every frame and in the screenshot hook.
- **Click**: `BattleController._on_camera_clicked` checks `UnitView.marker_hit` first (the closest marker wins), and a marker click counts as a click on that unit's tile. Selection, targeting and fire support therefore work through markers too. Hover is still hex-based.
- **Camera**: `CameraMath.MIN_DISTANCE` 0.18, `CLOSE_RANGE_DISTANCE` 7 (the old minimum, now the start of the close range), `GROUP_DRAW_DISTANCE` 3.0 + `draws_group()`, `UnitView.distance_to_camera()` / `distance_from()`. Zoom is geometric with `ZOOM_STEP_FACTOR` 1.25: 46 → 0.18 in 25 notches and 24 → 0.18 in 22. This is coarser than the old 1.12 per notch (7 → 46 now takes ~8.5 notches instead of ~17), as the ≤ 25-step criterion requires. Below 7 the pitch stays at `PITCH_CLOSE` 0.30, as in the prototype. `CameraMath.look_height` follows the ground under the target in the close range and blends back to the fixed 0.4 between 7 and 14, so zooming through 7 never jumps (the prototype jumped there when the ground was not at 0). `CameraMath.clearance` = 1.5 × (d/7)², never below `MIN_HEIGHT_METRES` 2 m (via `MapScale`). It is measured against the new `MapView.camera_ground_height` (lattice, the finer `TerrainNear` surface and the water plane). `CameraMath.near_plane` = 0.05 × d clamped to 0.005..0.1, so it is 0.009 at the minimum and the scene's 0.1 from 2 units out. The camera is aimed in the rig's local space (`Basis.looking_at`), which is the same as `look_at` because the rig only translates, and this lets the rig run headless in tests. Pan speed was already proportional to the distance (100 px of drag at 0.18 ≈ 4 m). The impact shake shrinks with d/7 in the close range, which keeps the same angular shake and no 4 m jumps.
- **Distance-based ranges**: the grid fade (`OverlayGeometry.grid_alpha`) is now anchored at `CLOSE_RANGE_DISTANCE`, so it is unchanged. `TreeField.BUDGET_RADIUS` (41) still bounds the worst case (comment updated). `TerrainNear` turns on below 12, and grass, tree / bush LODs, wind and decals are measured from the camera or chunk, so they need no change. `SCREENSHOT_MIN_DISTANCE` still accepts 0.05–7, but only values below 0.18 have an effect.
- **Tests**: `tests/unit/test_unit_marker.gd` (icons for every class, 15 × 11, pixel size, 18 px ground anchor at model scale 1 and 4, overlap, at most one shift, pick / hit, distance query), `tests/unit/test_close_camera.gd` (Suwałki map, HIGH: ≥ 2 m above the drawn ground at 8 distances × 5 yaws × every 7th tile, lowest sample 2.60 m; near plane; close-up pitch and aim; pan scaling), and additions to `test_camera_math.gd` / `test_camera_rig.gd`. Unit tests can't project with a real `Camera3D` (the test runner's root is not inside a tree), so the anchor test projects with its own `Projection` and checks `UnitLabel.place_at`. `BattleController`'s marker click is not covered headlessly; it is in the playtest.
- **Screenshots** (RX 580, HIGH, `.screenshots/t111_*.png`): default battle at 24 and at the minimum in the `current` and `true` presets, Suwałki (`true`) at 46 and at the minimum. At every zoom every unit has a readable marker. At 0.18 in the `true` preset a single M1A2 fills ~330 px and reads well, with no ribbon, ring or terrain flicker, and the river ribbon and near grass show no camera-exposing artefact in a still. Frame time at the minimum distance: `current` avg 9.2 ms (max 10.6), `true` avg 8.8 ms (one 33.9 ms spike over 120 frames). The 46 shot of Suwałki made a shifted marker land on a third one, so shifted markers now count as obstacles for farther ones. Very tight clusters (side-by-side tags) can still overlap partly, which the one-step rule allows. Grass cards still read as paper cut-outs up close (TASK-110 follow-up territory, not changed here).
- **Known limitations**: **in the `current` preset (today's enlarged models, ~3x real size) the camera at 0.18 ends up inside the model of the unit it is focused on** (the screenshot is dark brown, the hull from inside). At real size (`true`) the problem is gone. Until TASK-110's follow-up switches the models, zooming fully onto a unit in the shipped preset shows its insides. A possible stop-gap, not done: clamp the minimum to the model scale (e.g. `max(0.18, 0.5 × VisualScale.unit_model_scale())`). With today's enlarged models (preset `current`) the marker at close zoom covers the upper part of the model, because it sits 18 px above the feet. That is by design for the real-size follow-up. Zoom steps are not smoothed (a 25 % jump per notch).
