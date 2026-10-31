# TASK-111: Fixed-pixel unit markers and a much closer camera for real-size units

- **Status**: blocked
- **Layers**: presentation (`UnitLabel` → unit marker with class icon, anchoring, `CameraMath` / `CameraRig` zoom range and pitch curve, near plane, pan speed) + docs (ARCHITECTURE, MANUAL)
- **Depends on**: TASK-110 (marker look, camera numbers and the real-size preset come from the study) (priority: after the operational core loop 092 → 094 → 095)
- **Model**: opus (camera curves, near plane and every distance-based LOD / visibility range interact)
- **Topic**: Visual realism

## Goal

Decided 2026-10-31: unit models are drawn at real size, with no enlarged units. At real size a tank is ~3 px long at the default zoom, so the player finds units by **on-screen markers** – a class icon plus the existing tag (faction tab, short name, HP bar) at a **fixed pixel size**, readable at every zoom. A **much closer minimum camera distance** lets the player look at the real-size models. This task only adds the markers and the camera range. Switching the models to real size is one of TASK-110's follow-up tasks and depends on this one.

## Design (numbers to be confirmed by TASK-110's study before the task starts)

- **Marker** = today's `UnitLabel` (HUD control, already a fixed pixel size) plus a **class icon** in front of the short name: a small frame in the faction colour with an APP-6-like symbol for the unit class (`infantry` cross, `tank` oval, `mlrs` filled dot with a rocket mark), 15 × 11 px, drawn with `HudShapes` (procedural, no new asset). The class comes from `UnitDefinition.unit_class` (view reads only).
- **Anchor**: the marker sits a fixed **18 px** above the screen position of the unit's **ground point** (tile centre at terrain height), not above the model top, so it doesn't move with the model scale. Hidden behind terrain like today's labels (same occlusion rule).
- **Overlap**: when two markers would overlap on screen (zoomed out), the one closer to the camera wins and the other is shifted up by its height (at most one shift step); the HUD never hides a unit's marker.
- **Picking and hover** stay hex-based (a 3 px model can't be clicked); clicking a marker selects its unit.
- **Camera**: `CameraMath.MIN_DISTANCE` from 7 to the study's value (proposal **0.4 units ≈ 58 m**: a real tank is then ~170 px long at 720p, a close-up; it reaches 40 px already at ~1.7 units ≈ 245 m), `MAX_DISTANCE` stays 46. The pitch curve extends to the new close range, approaching the horizon at the closest zoom; zoom steps are geometric (each wheel step × the same factor), so going from 46 to 0.4 takes a similar number of steps to today plus the extra range; pan speed scales with the distance; the camera never goes below the terrain plus **2 m**; near clip plane small enough (≤ 0.01 units) at the closest zoom, with no z-fighting of ribbons and overlays (checked on screenshots).
- **Distance-based ranges** (grass `visibility_range_end`, tree / bush LODs, wind distance, decals) are measured from the camera or chunk, so they keep working; TASK-110's follow-ups rescale them to metres. This task only makes sure nothing breaks at the new close range.

## Acceptance criteria (testable)

- [ ] `UnitLabel` (marker) has a class icon for every `unit_class` in `docs/design/units/classes.json`; icon size 15 × 11 px; the marker's pixel size is the same at camera distances 0.4, 24 and 46 (test via the control's size).
- [ ] The marker's screen anchor = `camera.unproject_position(ground point)` − (0, 18 px) (± 0.5 px) for a unit at a known position, at any model scale (the model's AABB doesn't change it).
- [ ] Overlap: two units whose markers would overlap → the farther one is shifted up by its height; no shift without overlap.
- [ ] `CameraMath.MIN_DISTANCE` = the study's value (0.4 if confirmed); zooming in from the default reaches it; the pitch at MIN_DISTANCE is within the new curve's limit and the camera height over the terrain is ≥ 2 m (in world units via `MapScale`) everywhere on the Suwałki map (sampled).
- [ ] Zoom steps: the ratio between consecutive distances is constant (± 1 %).
- [ ] Clicking a marker selects its unit; hovering and selecting by hex are unchanged.
- [ ] Screenshots Read by the agent: Suwałki and the default battle at distances 46, 24 and the minimum, with the real-size preset from TASK-110 (`SCREENSHOT_SCALE_PRESET=true`) and with today's preset: every unit has a readable marker, no ribbon / overlay flicker at the minimum distance; frame time at the minimum distance recorded (60 FPS rule).

## Playtest (for the human)

1. Zoom all the way out and in: every unit always has its marker (icon + name + HP bar) at the same size on screen.
2. Zoom in much closer than before: the camera goes down to a few tens of metres above the ground, looking towards the horizon; you can look at a single vehicle up close. No flickering roads, rings or ground.
3. Click a marker: selects the unit. Hover and select hexes as before.

## Player manual

§10 "Screen": unit tags become unit markers with a class icon (infantry / tank / rocket artillery), always at the same size on screen. Camera controls table: the zoom now goes much closer (down to about 60 m above the ground). Units are drawn at their real size, so at a distance you find them by their markers – write this once TASK-110's follow-up switches the models to real size.

## Out of scope

- Switching unit models, trees, grass, textures and effects to real size (TASK-110 follow-ups).
- Company representation (one vehicle or a group – decided in TASK-110).
- Terrain mesh refinement near the camera (TASK-110 follow-up).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
