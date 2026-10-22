# TASK-044: Launcher mechanism with parameters – traverse range, stowed direction, elevation per unit

- **Status**: blocked (revised 2026-10-22: the stowed direction is partly done – the Uragan was built front-stowed with an ad-hoc `stowed_yaw` meta read by `UnitModels.launcher_traverse_for`; this task replaces it with the `stowed` param)
- **Layers**: presentation (`UnitModels`, `UnitView`, `BattleController._play_volley` / `_volley_event_duration`), tools (`tools/render_unit_options.gd`, `render_unit.gd`), tests
- **Depends on**: **TASK-043** (mechanism metadata). The Uragan model exists already; after this task it reads `stowed: front` and its verified `traverse_deg` from `MECHANISMS` instead of the `stowed_yaw` meta.
- **Model**: opus (angle wrapping + tween sequence and event duration must stay in step)

## Goal

Every rocket launcher animates like its real vehicle: how far its launcher can turn, which way the tubes face when stowed and how high it elevates come from the unit's `launcher` mechanism. A launcher that cannot turn far enough (e.g. the Uragan firing over its cab) first turns the whole vehicle, then traverses the rest. The Homar-K looks and behaves exactly as now.

## Decisions

- Human (2026-10-19): the Homar-K keeps its current behaviour – full traverse, tubes facing the rear when stowed, ~180° turn to fire over the cab.
- Target outside the traverse range: **the vehicle turns first** (like the current fixed-pod path), towards the nearer traverse limit, then the launcher traverses to that limit. The vehicle **stays turned** after the volley (like the fixed-pod path today) – see open questions.
- The launcher fires at `max_elevation_deg` (no range-dependent elevation – open question).
- Durations stay global constants in `BattleController` (pacing, not a vehicle property). For a limited-traverse launcher the body-turn step is **always** in the sequence (zero angle if not needed), so the event duration doesn't depend on the view state at annotation time.

## Design

- `UnitModels.LAUNCHER_DEFAULTS := {"traverse_deg": "full", "max_elevation_deg": 40, "stowed": "rear"}` (= registry defaults) and `launcher_params(model) -> Dictionary` (the model's `launcher` metadata over the defaults; legacy `Launcher` models without metadata get the defaults).
- `UnitModels.traverse_aim(traverse_deg: Variant, stowed_offset: float, facing_yaw: float, target_yaw: float) -> Vector2` – x = body yaw change, y = turntable angle (radians). `desired = wrapf(target_yaw − facing_yaw − stowed_offset, −PI, PI)` (`stowed_offset` = PI for `rear`, 0 for `front`). `"full"` → `(0, desired)`. `[lo, hi]` (degrees): inside → `(0, desired)`; outside → for each limit `body = wrapf(desired − limit, −PI, PI)`, take the limit with the smaller `|body|` (tie within 1e-6 → `lo`), return `(body, limit)`. Shared with the turret (TASK-047).
- `UnitModels.launcher_aim(model, facing_yaw, target_yaw) -> Vector2` (from `launcher_params`), `launcher_elevation(model) -> float` (`deg_to_rad(max_elevation_deg)`), `launcher_limited(model) -> bool` (traverse not `"full"`). `launcher_traverse`, `launcher_traverse_for`, `launcher_stowed_yaw`, the `stowed_yaw` meta (set in `bm27_uragan.gd`) and `LAUNCHER_ELEVATION` are removed (callers and tests move to the new functions; `stowed_offset` comes from the `stowed` param).
- `UnitView`: `launcher_aim_towards(point) -> Vector2`, `launcher_limited()`, `set_launcher_pose(traverse, elevation)` unchanged.
- `BattleController._play_volley` for a launcher: [limited only: body turn `AIM_DURATION` from the current yaw by `aim.x` (lerp_angle)] → raise to `launcher_elevation` (`LAUNCHER_RAISE_DURATION`) → traverse to `aim.y` (`LAUNCHER_TRAVERSE_DURATION`) → salvo (tube positions read after aiming, as now) → traverse back → lower. `_tween_launcher` takes the elevation in radians instead of a fraction of the global constant.
- `_volley_event_duration(launcher: bool, limited: bool)`: launcher full = `2 × (RAISE + TRAVERSE) + RocketVolley.total_duration()`; launcher limited = that `+ AIM_DURATION`; no launcher = `AIM_DURATION + total_duration()` (unchanged).
- `tools/render_unit.sh --pose=rest|fire` (default `rest`): `fire` renders the launcher at traverse 0 and its `max_elevation_deg`, so the modeler can check the actuators at full extension. `unit-modeler.md` workflow: render once with `--pose=fire` when the unit has a launcher.
- GDD "Unit feel": the launcher sentence describes the per-unit behaviour (game-designer updates it when this is done).

## Acceptance criteria (testable)

- [ ] `traverse_aim`, front-stowed (offset 0), `[-30, 30]`, facing 0: target 20° → (0, 20°); 90° → (60°, 30°); −45° → (−15°, −30°); 180° → (−150°, −30°) (tie → lower limit); facing 90°, target 100° → (0, 10°). Front-stowed `"full"`, facing 0, target 90° → (0, 90°). Rear-stowed `[-30, 30]`, facing 0, target 170° → (0, −10°). Tolerance 1e-4 rad.
- [ ] **Homar-K regression**: `launcher_aim(homar, 0, PI/2)` = (0, −PI/2) (same as the old `launcher_traverse`); `launcher_elevation(homar)` within 0.01 rad of 0.7; `launcher_limited(homar)` false; its event duration is unchanged: `_volley_event_duration(true, false) == 2 × (0.9 + 0.9) + RocketVolley.total_duration()`.
- [ ] `_volley_event_duration(true, true) == 0.5 + 3.6 + total_duration()`, `(false, false) == 0.5 + total_duration()`.
- [ ] `launcher_params` of a synthetic `Launcher` model without metadata == `LAUNCHER_DEFAULTS`; `LAUNCHER_DEFAULTS` equals the launcher defaults in `mechanisms.json` (test-only read through `tests/mechanism_contract.gd`).
- [ ] The pose tests in `test_launcher_pose.gd` pass with `launcher_elevation(model)` in place of `LAUNCHER_ELEVATION`; the actuators still connect at the Homar-K's elevation.
- [ ] `test_render_unit_options.gd`: `--pose=fire` parsed, default `rest`, `--pose=up` → exit code 2.
- [ ] `tools/screenshot.sh` before/after identical; `tools/check.sh` passes.

## Playtest (for the human)

1. Fire with the Polish rocket artillery (Homar-K model) at targets ahead, to the side and behind: as before – the pod rises on its actuators, turns (over the cab for targets ahead), fires, turns back and lowers; the truck itself doesn't turn.
2. Fire with the Russian Uragan (front-stowed, limited traverse if its catalog entry says so) at a target behind the launcher: the truck turns first, then the launcher traverses the rest; the truck stays turned afterwards.
3. `tools/render_unit.sh homar_k --pose=fire`: the pod is raised, the actuator cylinders and pistons stay connected.

## Player manual

None (presentation only, no rule effect).

## Open questions

- After a volley with a limited traverse, should the vehicle **stay turned** (proposed, like the fixed-pod path) or turn back to its previous facing (longer sequence)?
- Elevation: always `max_elevation_deg`, or scaled with the target distance (e.g. range 2 → low, maximum range → `max_elevation_deg`)?
- Per-unit timing (a heavy launcher traverses slower) – proposed no, durations stay global.
- Uragan values (`traverse_deg`, `max_elevation_deg`, `stowed: front`): verified in the catalog by TASK-042 – use them as they are.

## Out of scope

- Range-dependent elevation, per-unit durations, stabilisers and shields (TASK-045), Uragan geometry changes.

## Implementation notes

_Filled in by the agent when done._
