# TASK-025: Unit locomotion – marching soldiers, driving tank

- **Status**: done
- **Layers**: presentation only (pure helpers tested in `tests/unit/`); no core changes, no new events
- **Depends on**: **TASK-022** (hard – path movement and its `elapsed`/duration driver), TASK-019 (models in `src/presentation/unit_models.gd`). Soft: TASK-008 (burst speed scale), TASK-016b (`TerrainSurface.ground_height`).
- **Model**: sonnet

## Goal

While a unit moves along its path (TASK-022) it looks alive: the infantry squad visibly marches (each soldier bobs in step, sways slightly, the kneeling ones get up) and the tank visibly drives (wheels turn with the distance covered, the hull rocks a little and tilts with the terrain slope). When the move ends, everything settles back to the rest pose.

## Design values

All values are presentation constants in a new static helper `src/presentation/locomotion.gd` (`class_name Locomotion`) – they are feel, not balance, so no `.tres`.

**Driver.** Everything is a function of the move's animation time `elapsed` (the same value TASK-022 feeds into `MoveAnimation.sample`) and the move `duration` (`0.26 × path.size()`). Nothing advances from raw frame `delta`, so the TASK-008 burst speed scale (`tween.set_speed_scale`) speeds up locomotion exactly as much as the movement itself.

- `distance` = XZ length travelled along the polyline at `elapsed` (0.26 s per segment, same convention as `MoveAnimation.sample`, clamped to the total length). One tile step between hex centres is `√3 ≈ 1.732` world units.
- **Envelope** `env = clamp(min(elapsed, duration − elapsed) / 0.08, 0, 1)`: motion fades in over the first 0.08 s and out over the last 0.08 s, so at the end of the move every oscillation is **exactly 0** (no snap). `duration ≤ 0` → 0.

**Infantry** (per soldier, applied to a new `Rig` node inside each soldier, see Node structure):

| value | formula / number |
|---|---|
| step count | `steps = distance × 1.5 + phase` (≈ 2.6 steps per tile) |
| per-soldier phase | `phase_i = TerrainNoise.hash(i, 11.0, 4.0)` for soldier index `i` (0…4), in `[0, 1)` |
| step bob (Rig `position.y`, soldier-local units) | `0.012 × abs(sin(π × steps)) × env` (≈ 0.023 world at SOLDIER_SCALE 1.5 × MODEL_SCALE 1.3) |
| side sway (Rig `rotation.x`) | `0.06 × sin(π × steps) × env` rad – changes sign every step, one full sway per two steps |
| forward lean (Rig `rotation.z`) | `−0.08 × env` rad (models face +X; negative Z rotation tips the head forward) |
| kneeling soldiers (indices 1 and 4 in `UnitModels.SQUAD`) | **stand up** for the whole move and **kneel again** when it ends |

Kneel decision: a kneeling figure sliding across the map reads as a bug, and a squad that marches upright and drops back into cover on arrival tells the player "this unit has stopped". The switch is an instant pose swap (no blended leg animation – the legs are boxes built at a different height, `lh` 0.05 vs 0.085); at ≈ 0.37 world units tall the pop is barely visible and it coincides with the start/end of motion.

**Tank** (cavalry interim model):

| value | formula / number |
|---|---|
| wheel spin (wheel pivot `rotation.z`) | `wheel_angle = −distance × 5.0` rad, **accumulated across moves** (stored in `UnitView`, never reset – a wheel that snaps back would look like it spins backwards) |
| hull bob (Model `rotation.z` pitch, `rotation.x` roll) | pitch `0.012 × sin(TAU × 0.9 × distance)`, roll `0.008 × sin(TAU × 0.55 × distance + 1.3)`, both × `env` |
| slope tilt | sample `ground_height` at `center ± forward × 0.45` and `center ± right × 0.26` (forward = `(cos yaw, 0, −sin yaw)`, right = `(sin yaw, 0, cos yaw)`); `pitch = atan2(h_front − h_back, 0.9)`, `roll = atan2(h_left − h_right, 0.52)`; each clamped to `±0.35` rad |
| Model rotation | `rotation.z = slope_pitch + bob_pitch`, `rotation.x = slope_roll + bob_roll` |

- Wheel spin is deliberately **not** physical rolling: true rolling for a 0.0585 world-radius wheel is ≈ 17 rad per world unit, i.e. ≈ 1.9 rad per frame at 60 fps and 0.26 s/tile – that strobes (wagon-wheel effect). 5.0 rad/unit ≈ 0.55 rad per frame at speed 1. Known limitation: at high burst speeds it may still alias.
- Positive `rotation.z` = nose up; positive `rotation.x` = right side (+Z) down. Hence "front higher → pitch > 0" and "right lower → roll > 0".
- **Slope tilt is part of the rest pose**: it is updated every frame while moving, applied once in `UnitView.setup`, and kept after arrival (a tank parked on a slope stays tilted along it). "Rest pose" below means: all bob/sway/lean offsets 0, kneelers kneeling, tank Model rotation = slope tilt at its tile, wheels at their accumulated angle.
- The turret is a child of the Model, so it rocks/tilts with the hull (no turret stabilisation).
- Infantry soldiers never tilt with the slope (people stand vertical).

**Node structure changes in `UnitModels`** (so `UnitView` can find nodes by name; mesh/material sharing unchanged):

- Infantry: each soldier root is named `Soldier0` … `Soldier4` (keeps position, `SOLDIER_SCALE` and yaw jitter). Its only child is a `Rig` `Node3D` with identity transform at rest. Standing soldiers: meshes directly under `Rig`. Kneeling soldiers: `Rig/Kneel` (the current kneeling meshes, visible) and `Rig/Stand` (the standing variant, `visible = false`).
- Tank: each of the 12 wheels becomes a `Node3D` pivot `Wheel0` … `Wheel11` at the current wheel position (rotation 0); the existing wheel `MeshInstance3D` is its child at `Vector3.ZERO` with `rotation.x = PI / 2`. Add a **hub bar** per wheel so the spin is visible: a `TANK_DARK` box `Vector3(0.07, 0.012, 0.006)` under the pivot at `(0, 0, s × 0.017)` (on the wheel's outer face).
- `_make_tank` / `_make_infantry` return the Model node as now; locomotion acts on `Model` (tank tilt/bob) and on the named children.

## Acceptance criteria (testable)

Pure helpers – `tests/unit/test_locomotion.gd`, tolerance 0.001:

- [ ] `Locomotion.travelled(points: PackedVector3Array, elapsed: float, seconds_per_tile := 0.26) -> float`: points `[(0,0,0), (1,0,0), (1,0,2)]` → at 0 → 0; at 0.13 → 0.5; at 0.39 → 2.0; at 10 → 3.0; single point → 0; Y is ignored (`[(0,0,0), (1,5,0)]` at 0.26 → 1.0).
- [ ] `Locomotion.envelope(elapsed: float, duration: float, ramp := 0.08) -> float`: `(0, 0.78)` → 0; `(0.04, 0.78)` → 0.5; `(0.39, 0.78)` → 1; `(0.74, 0.78)` → 0.5; `(0.78, 0.78)` → 0; `(1.0, 0.78)` → 0; `(0.1, 0.0)` → 0.
- [ ] `Locomotion.step_phase(i: int) -> float` equals `TerrainNoise.hash(i, 11.0, 4.0)`; for `i` in 0…4 all values are in `[0, 1)` and not all equal; calling twice gives identical values.
- [ ] `Locomotion.step_bob(distance: float, phase: float) -> float` and `step_sway(distance, phase) -> float` (without envelope): phase 0 → bob at d 0 = 0, d 1/3 = 0.012, d 2/3 = 0; sway at d 1/3 = 0.06, d 1.0 = −0.06; bob is never negative over d in 0…5 step 0.05; phase 0.5 at d 0 → bob 0.012.
- [ ] `Locomotion.wheel_angle(distance: float) -> float`: 0 → 0; 1.0 → −5.0; 1.732 → −8.66.
- [ ] `Locomotion.hull_bob(distance: float) -> Vector2` (x = pitch, y = roll): at 0 → `(0, 0.008 × sin(1.3))`; over d in 0…5 step 0.05 `|pitch| ≤ 0.012` and `|roll| ≤ 0.008`.
- [ ] `Locomotion.slope_tilt(ground_height: Callable, center: Vector3, yaw: float, half_length := 0.45, half_width := 0.26) -> Vector2` (x = pitch, y = roll), with lambda planes:
  - flat `h = 0` → exactly `(0, 0)`;
  - `h = 0.2·x`, yaw 0 → pitch `atan(0.2)` = 0.1974, roll 0;
  - same plane, yaw π → pitch −0.1974;
  - same plane, yaw π/2 (facing −Z) → pitch 0, roll −0.1974;
  - `h = −0.1·z`, yaw 0 → pitch 0, roll `atan(0.1)` = 0.0997;
  - `h = 2·x`, yaw 0 → pitch clamped to 0.35.

Applying poses to the model tree (headless, `UnitModels.build` without a scene tree) – `tests/unit/test_unit_models.gd` or `test_locomotion.gd`:

- [ ] Infantry model has `Model/Soldier0` … `Model/Soldier4`, each with a `Rig` child; soldiers 1 and 4 have `Rig/Kneel` (visible) and `Rig/Stand` (hidden); the others have neither.
- [ ] Cavalry model has `Model/Wheel0` … `Model/Wheel11` pivots, each with 2 `MeshInstance3D` children (wheel + hub bar).
- [ ] Static `UnitModels.pose_infantry(model: Node3D, distance: float, env: float, moving: bool)`: with `moving = true`, `env = 1`, distance 1/3 → `Soldier0/Rig` has `position.y ≈ 0.012 × abs(sin(π × (0.5 + step_phase(0))))` and `rotation.z ≈ −0.08`; kneelers show `Stand` and hide `Kneel`. Then with `moving = false`, `env = 0` → **every `Rig.transform == Transform3D.IDENTITY` exactly** and kneelers show `Kneel` again.
- [ ] Static `UnitModels.pose_tank(model: Node3D, wheel_distance: float, env: float, tilt: Vector2)`: wheel_distance 1.0 → every `WheelN.rotation.z ≈ −5.0`; `env = 0`, tilt `(0.1, −0.05)` → Model `rotation.z == 0.1`, `rotation.x == −0.05` exactly (no bob residue); `env = 0`, tilt zero → Model rotation exactly `Vector3.ZERO`.
- [ ] Existing TASK-019 tests (`test_unit_models.gd`, including the upright AABB check) still pass with the new nodes.

Integration (`UnitView`, checked by reading code + playtest; adapt names to TASK-022's actual API):

- [ ] `UnitView`'s TASK-022 move driver calls the pose functions every frame with `distance = Locomotion.travelled(points, elapsed)`, `env = Locomotion.envelope(elapsed, duration)`, and for tanks `tilt = Locomotion.slope_tilt(_ground_height, position, current_yaw)`; the tank's wheel distance is `_wheel_distance_before_move + distance`.
- [ ] When the move finishes, and when it is interrupted (`play_death` snapping to the target, a new `move_along` killing the old one), the unit is set to the rest pose (`pose_infantry(..., 0.0, 0.0, false)` / tank `env = 0` with the slope tilt at the final position).
- [ ] `UnitView.setup` applies the slope tilt for tanks at the spawn position.
- [ ] No locomotion state is advanced from frame `delta` – only from the move's `elapsed` (burst speed scale applies automatically).
- [ ] No changes in `src/core/`, no new event types.
- [ ] Agent visual check: `tools/screenshot.sh` – the default screenshot is static: soldiers 1 and 4 of each squad are kneeling as before, tanks sit on the ground (tilted only if their tile slopes), hub bars visible on the wheels when zoomed in; no floating/clipping. Motion itself is checked by the human.

## Playtest (for the human)

1. Move infantry 3 tiles: all five soldiers bob up and down in step, **not in unison** (each has its own rhythm), lean slightly forward and sway a little side to side. The two kneeling soldiers stand up as the squad starts and kneel again when it stops.
2. When the squad stops, nothing keeps wobbling and there is no visible jump (motion fades out in the last moment).
3. Move the tank across flat ground: the wheels visibly turn (watch the dark hub bars) in the driving direction – rolling forward, not backwards, no obvious strobing; the hull rocks very slightly.
4. Drive the tank up/down a hill and along a slope: the hull tilts nose-up uphill, nose-down downhill and leans sideways on a side slope; the tracks stay on the ground without large gaps or clipping. Parked on a slope it stays tilted.
5. End the turn: AI units march/drive the same way; during the fast burst playback the animations speed up together with the movement (feet and wheels don't lag behind or slide).
6. Attack right after moving, and let a unit die: the hit shake still works and a dying unit doesn't keep marching.

## Out of scope

- **Dust puffs** behind the tank and other particles (`GPUParticles3D`) – follow-up task once locomotion is in: needs visual tuning by eye and is the riskiest part for a headless check; keeping it out keeps this task one session.
- Track tread animation (the tracks are plain boxes without texture; scrolling cleats would need new geometry or a material), turret stabilisation / turret aiming at the target.
- Leg/arm walk cycle (moving individual legs), blended kneel ↔ stand transition.
- Infantry squad formation changes while moving (e.g. single file on the path).
- Sound.
- Any change to movement timing or path following (TASK-022).

## Implementation notes

- New pure helper `src/presentation/locomotion.gd` (`Locomotion`): `travelled`, `envelope`, `step_phase`, `step_bob`, `step_sway`, `wheel_angle`, `hull_bob`, `slope_tilt`; tests in `tests/unit/test_locomotion.gd` (helper values, model node structure, `pose_infantry` / `pose_tank`).
- `UnitModels`: soldiers are `Soldier0..4` with a `Rig` child; kneelers (1, 4) have `Rig/Kneel` + hidden `Rig/Stand`. Tank wheels are `Wheel0..11` pivots (wheel mesh + `TANK_DARK` hub bar). New static `pose_infantry` / `pose_tank`; they accept either the built root or its `Model` child.
- `UnitView`: `_step_move` calls `_pose_moving(elapsed)` every frame (distance and envelope from the move's `elapsed` only, so burst speed scale applies). `_apply_rest_pose()` runs in `setup` and `_end_move`; `_end_move` is also reached on interruption (`play_death`, a new `move_along`) via `_finish_move`. `_wheel_distance` accumulates the full path length in `_end_move` and is never reset.
- Decisions / deviations:
  - Hull bob is sampled from the accumulated wheel distance (that is the only distance `pose_tank` receives); its phase therefore carries over between moves – invisible, since the envelope starts at 0.
  - The `pose_tank` rest test compares the tilt with 0.001 tolerance instead of exact equality: `Node3D.rotation` is read back from a float32 basis, so `0.1` comes back as `0.10000000149`. Bob residue (up to 0.012 rad) would still fail it. The zero-tilt case and the infantry `Rig.transform == IDENTITY` are asserted exactly.
  - Slope tilt uses `_pivot.rotation.y` as yaw; during a turn it lags the path direction slightly (cosmetic).
- Known limitations: wheel spin may alias at high burst speeds (as noted in the spec); kneelers keep a duplicate (hidden) standing mesh set.
