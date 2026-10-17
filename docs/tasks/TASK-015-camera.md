# TASK-015: Camera like the design (drag-pan, RMB rotate, distance-based pitch, map clamp)

- **Status**: done
- **Layers**: presentation (pure `CameraMath` helper tested in `tests/unit/`)
- **Depends on**: nothing hard. Soft: TASK-023 (the new controls hint goes through `tr()`). Reference: `docs/design/game_screen.scene.js` lines 510–518 (camera), 572–614 (input).
- **Model**: sonnet

## Goal

The camera feels like the mock-up: a narrow-FOV view that tilts down more the further you zoom out, grab-and-drag panning with the left mouse button (without breaking click-to-select), right-drag rotation, and it can't be scrolled off the map.

## Design values

| Parameter | Value |
|---|---|
| FOV | 34° (was 50°), near 0.1, far 220 |
| Look-at height | `TARGET_HEIGHT = 0.4` above the rig's XZ target |
| Distance | default **24**, clamp **7–46** (was 14, 6–30) |
| Pitch | `pitch(d) = 0.82 + (d − 8) / 37 · 0.3` rad (≈ 46.5° at 7, 54.4° at 24, 64.6° at 46) |
| Camera offset from look-at point | `(sin(yaw)·cos(p)·d, sin(p)·d, cos(yaw)·cos(p)·d)`; yaw 0 = camera on the +Z side looking towards −Z |
| Wheel | one notch out: `d × 1.12`, one notch in: `d × 0.88` (scaled by `InputEventMouseButton.factor` when it is non-zero) |
| LMB drag pan | `s = d · 0.0016` world units per pixel, **grab semantics** (the ground follows the cursor): `target −= (right · dx + toward_camera · dy) · s` with `right = (cos yaw, 0, −sin yaw)`, `toward_camera = (sin yaw, 0, cos yaw)`. (The mock-up's vertical sign is inverted relative to its horizontal one; we use consistent grab panning.) |
| RMB drag rotate | `yaw −= dx · 0.005` |
| Keys | W/S/A/D and arrows pan at `d · 0.9` units/s (W = away from the camera), Q/E rotate at 1.2 rad/s (Q = +yaw) |
| Click vs drag | a press becomes a drag once the cursor is **more than 4 px** from the press position; a release without drag is a click |
| Map clamp | the XZ target stays inside the map rectangle shrunk by **2** units on every side; if the shrunk rectangle is empty on an axis, the target is fixed to the map centre on that axis |

## Acceptance criteria (testable)

- [ ] Pure helper `src/presentation/camera_math.gd` (`class_name CameraMath`, `extends RefCounted`, static functions only):
  - `pitch_for_distance(d: float) -> float`;
  - `camera_offset(yaw: float, d: float) -> Vector3`;
  - `zoom(d: float, notches: float) -> float` (positive = out) – `d · 1.12^n` for n > 0, `d · 0.88^|n|` for n < 0, clamped to 7–46;
  - `pan_delta(drag: Vector2, yaw: float, d: float) -> Vector2` (XZ change of the target);
  - `is_drag(press: Vector2, current: Vector2) -> bool`;
  - `map_bounds(centers: Array[Vector3], hex_size: float) -> Rect2` (XZ rect of all tile centres grown by `hex_size · √3/2` in X and `hex_size` in Z);
  - `clamp_target(target: Vector2, bounds: Rect2, margin: float) -> Vector2`.
- [ ] Tests `tests/unit/test_camera_math.gd` (float tolerance 0.001):
  - `pitch_for_distance(8) == 0.82`, `(45) == 1.12`, `(24) ≈ 0.94973`.
  - `camera_offset(0, 24)`: `x == 0`, `y == sin(p)·24`, `z == cos(p)·24` with `p = pitch_for_distance(24)`; `camera_offset(yaw, d).length() == d` for yaw ∈ {0, 1, π} and d ∈ {7, 24, 46}; `camera_offset(PI / 2, 24).z ≈ 0` and `.x > 0`.
  - `zoom(24, 1) == 26.88`, `zoom(24, -1) == 21.12`, `zoom(45, 1) == 46`, `zoom(7.5, -1) == 7`, `zoom(24, 0) == 24`.
  - `pan_delta(Vector2(100, 0), 0, 24) == Vector2(-3.84, 0)`, `pan_delta(Vector2(0, 100), 0, 24) == Vector2(0, -3.84)`, `pan_delta(Vector2(100, 0), PI / 2, 24) ≈ Vector2(0, 3.84)`.
  - `is_drag((0,0), (4,0)) == false`, `((0,0), (3,3)) == true` (4.24 px), `((10,10), (10,14)) == false`.
  - `map_bounds([(0,0,0), (10,0,6)], 1.0)` == `Rect2(-0.866, -1, 11.732, 8)`.
  - `clamp_target((−5, 30), Rect2(0, 0, 20, 14), 2) == (2, 12)`; a target inside stays unchanged; `clamp_target((9, 9), Rect2(0, 0, 3, 3), 2) == (1.5, 1.5)`.
- [ ] `CameraRig` uses `CameraMath` for everything above (no duplicated formulas), keeps the target on the XZ plane, places `Camera3D` at `target + (0, TARGET_HEIGHT, 0) + camera_offset(yaw, d)` looking at `target + (0, TARGET_HEIGHT, 0)`, and clamps the target to `map_bounds` of the map's tile centres (set once by `BattleController` after `MapView.build`, e.g. `set_bounds(rect)`).
- [ ] Input split: `CameraRig` owns mouse buttons and drags. It emits `signal clicked(screen_position: Vector2, button: MouseButton)` on a LMB/RMB release that never became a drag. `BattleController` no longer reacts to raw `MOUSE_BUTTON_LEFT` presses; it connects to `clicked`: LMB → the existing `_on_hex_clicked` flow (same turn/winner guards), RMB → deselect (`_select(-1)`). `Escape` also deselects. A press–drag–release over a tile selects/moves nothing.
- [ ] Hover keeps working while panning/rotating (the existing camera-transform check in `BattleController._process` re-picks the tile).
- [ ] The controls hint in the status label becomes `LMB – select/move/attack · drag – pan · RMB – rotate/deselect · wheel – zoom · WASD/QE – camera · Enter – end turn` (through `tr()`, CSV row en + pl `LPM – wybór/ruch/atak · przeciągnij – przesuń · PPM – obrót/odznacz · kółko – zoom · WASD/QE – kamera · Enter – koniec tury` if TASK-023 is done).
- [ ] The default view stays deterministic for `tools/screenshot.sh`: target = map centre, yaw 0, d 24.
- [ ] Agent visual check: take a screenshot with `tools/screenshot.sh` and compare with `docs/design/reference.png`: similar framing (narrow FOV, ~54° down-tilt, whole 12×10 map visible with margin). Drag/rotate behaviour is checked by the human.

## Playtest (for the human)

1. `tools/run.sh` – the view is flatter-looking (narrow FOV) and the whole map is visible.
2. Hold LMB on empty ground and drag – the map follows the cursor in both directions; releasing does **not** select or move anything.
3. A short click (cursor moved ≤ 4 px) still selects a unit / moves / attacks exactly as before.
4. Hold RMB and drag left/right – the camera orbits around the screen centre. A right click without dragging deselects the unit; so does Escape.
5. Wheel – zoom between very close (7) and far (46); far zoom looks more top-down, close zoom more from the side.
6. Pan with WASD / drag towards a map edge – the centre of the view stops ~2 units inside the map edge.
7. While dragging, the hovered tile / path preview updates without errors.

## Out of scope

- Camera smoothing/inertia, edge scrolling, focusing the camera on the acting AI unit, Input Map actions / key rebinding (CameraRig TODO stays).
- Picking against the terrain surface (TASK-016b).

## Implementation notes

- `src/presentation/camera_math.gd` holds every formula. Beyond the spec it adds `key_pan(input, yaw)`, the unit XZ direction for WASD, which shares the basis vectors with `pan_delta`. Tests are in `tests/unit/test_camera_math.gd`.
- `CameraRig` was rewritten:
  - It emits `clicked(screen_position, button)` for LMB/RMB releases that never became a drag.
  - `set_bounds(rect)` and `set_target(xz)` are called by `BattleController` after `MapView.build`.
  - FOV 34 / near 0.1 / far 220 are set in `battle.tscn` only.
  - The press state is reset on window/app focus loss. A new press also replaces a stale one whose release never arrived (`Input.is_mouse_button_pressed`), so input can't get stuck.
- `BattleController` changes:
  - It no longer handles raw mouse buttons. `clicked` LMB runs `_on_hex_clicked`, and RMB or Escape calls `_select(-1)`.
  - The shared turn/winner/playback guard is `_input_allowed()`.
- The controls hint goes through `tr()`. The old row in `assets/i18n/strings.csv` was replaced by the new en + pl row.
- **Known / deviations**:
  - `docs/design/reference.png` does not exist, so the screenshot was not compared against it.
  - At the spec default d = 24, the 1280×720 screenshot cuts off the bottom 1–2 map rows. The mock-up's map is 26×18 and never fits on screen, so the "whole 12×10 map visible" criterion conflicts with d = 24. The spec value was kept; a default of ~28–30 would fit the whole map if preferred.
  - The first motion after the 4 px threshold applies only its own delta, so up to 4 px of movement is not panned.
- Drag, rotate and click behaviour was not verified by the agent. See the Playtest section.
