# TASK-074: Rocket salvo sequence – full ripple salvo, per-rocket timing, paths and HP steps (simple visuals, effect hooks)

- **Status**: ready (salvo pacing in AI turns is a proposed **[ASSUMPTION]**, see Open questions)
- **Layers**: presentation (new pure `SalvoTiming`, new `SalvoEffects` hook interface, `RocketVolley` rewritten, new `FlashFx` helper, `EventQueue` (playback speed of volley events), `BattleController._annotate` / `_play_volley` / `_volley_event_duration` / `_play_volley_hit`, `UnitView` (shown HP, pod jolt, `launch_directions()`)), tools (`tools/screenshot.gd` hook), tests, docs (ARCHITECTURE "View-only annotations", MANUAL). Role: **presentation-engineer**. No core change (see "Event data").
- **Depends on**: **TASK-011** (done: `RocketVolley`, view annotations `view_duration` / `view_fx`), **TASK-058** (done: craters and scorch from rocket strikes – moved to the first impact here). Soft: **TASK-073** (v3 launcher models – `Mouth<i>` one per tube on the tube axis; this task must work with the current models, which already have 12 / 16 `Mouth<i>` markers, and with a fallback when a model has none), **TASK-044 / TASK-045** (they edit the same `_play_volley` / `_volley_event_duration` and call `RocketVolley.total_duration()`; whichever lands second rebases onto the other – the aim / deploy / stow phases stay theirs, the salvo phase is this task's), **TASK-048** (idea: muzzle flash + recoil for direct fire – reuses the `FlashFx` helper and the pod jolt pattern from here). Follow-up: **[TASK-075](TASK-075-mlrs-salvo-effects.md)** (backblast, plume, trail, fireball, smoke column, lights, pooled particles – fills the hooks defined here).
- **Model**: opus (timing between the event queue, a time-driven effect and per-rocket callbacks; burst speed rule change)

## Goal

A rocket launcher's attack plays as a real ripple salvo: the Homar-K fires its 12 rockets and the Uragan its 16 one after another with clearly visible pauses, each rocket leaves along its tube and comes down steeply on the target tile, and the target's HP bar drops as the rockets land. The visuals stay simple (rocket mesh, small tail glow, short flashes) so the task is playable and shippable on its own; it defines the effect hooks that TASK-075 fills with smoke, fire and dust.

## Current state (before)

- `RocketVolley` (`src/presentation/rocket_volley.gd`, TASK-011): `ROCKET_COUNT = 6` for every MLRS, `GAP` 0.15 s, `FLIGHT` 1.0 s, a parabolic `arc_point` (straight horizontal chord + `apex_height(distance)`), a 6-sided cylinder per rocket with a glow ball, a trail of 4 glow balls, a muzzle flash sphere and an impact flash sphere per rocket; landing scatter `randfn(0, 0.3)` from `BattleController._fx_rng` (view-local, unseeded). Mouths are cycled when there are more than 6 (only 6 of 12 / 16 tubes fire). Everything is a pure function of the volley time (`update(t)`), driven by one `tween_method`, so the burst speed applies.
- `BattleController._annotate` gives a volley event `view_duration = _volley_event_duration(launcher)` (`2 × (0.9 + 0.9) + RocketVolley.total_duration()` for a turntable launcher, `AIM_DURATION 0.5 + total` otherwise) and `view_fx = rocket_volley`. `_play_volley` aims (raise + traverse, or body turn), reads the tube positions (`UnitView.launch_points()` – global positions of the `Mouth*` children of `Pod`) after aiming, plays the salvo, starts `_play_volley_hit` (ground marks + `play_hit(target_hp)`) at `last_impact_time()`, frees the volley node, then stows. The following `unit_died` event plays after the whole volley tween.
- `EventQueue.begin_burst()` = `max(1, pending_duration() / MAX_BURST_SECONDS 8.0)` over all queued events incl. volleys; `tween.set_speed_scale(burst_speed)` on every event.
- Models: `homar_k` has `Launcher/Pod/Mouth0..11` (Pod rotated so its +X runs to the truck's rear, mouths just beyond the tube ends), `bm27_uragan` has `Launcher/Pod/Mouth0..15` (Pod +X forward along the tubes, mouths just in front of the muzzles). In both the tube axis (launch direction) is the **Pod's global +X**.

## Event data – is a core change needed?

No. The salvo size is a property of the vehicle's look (one rocket per tube), not a game quantity: the view takes it from the model's `Mouth*` count (12 / 16), cross-checked against `SalvoTiming.PROFILES`. Per-rocket HP steps need the HP before the hit, which the event does not carry (`damage` is before clamping at 0), but the target `UnitView` already shows exactly that HP (events play in order), so the view uses its own shown HP. `unit_attacked` (`attacker_id`, `target_id`, `damage`, `target_hp`, `counter`) is enough; no new event type, no new field. If the salvo size should ever mean something in the rules (ammunition, salvo vs. single ripple – GDD "Ideas from the visual design": MLRS ammo), that is a separate game-designer + gameplay-engineer task, not this one.

## Design

### Timing (pure `SalvoTiming`, `src/presentation/salvo_timing.gd`, `extends RefCounted`)

Visual tunables, not balance (CLAUDE rule 5 is about balance data): they live as constants at the top of `SalvoTiming`, like `motion_effects.gd` / `heavy_move.gd`.

- `PROFILES := { &"homar_k": {count 12, interval 0.40}, &"bm27_uragan": {count 16, interval 0.30} }`, `DEFAULT_PROFILE := {count 6, interval 0.35}` (any other MLRS). Real ripple intervals are longer (Uragan full salvo ≈ 20 s, ≈ 1.3 s per rocket) – compressed ≈ 3–4× so the pauses stay visible without the attack dragging.
- `rocket_count(unit_id: StringName, mouth_count: int) -> int`: `mouth_count` when > 0, else the profile's count. `interval(unit_id) -> float`.
- `flight_time(distance: float) -> float` = `clampf(FLIGHT_BASE 1.0 + FLIGHT_PER_UNIT 0.09 × distance, FLIGHT_MIN 1.1, FLIGHT_MAX 2.2)` (distance = horizontal world distance launcher → target centre; 6 hexes ≈ 10.4 → 1.94 s). All rockets of one salvo share it.
- `launch_time(i, interval) = i × interval`; `impact_time(i, interval, flight) = launch_time + flight`.
- `SETTLE := 0.5` – time after the last impact the event keeps playing (the last flash, and in TASK-075 the fireball peak); anything after that (TASK-075's smoke column, trails, dust) lingers **outside** the event.
- `salvo_duration(count, interval, flight) = (count − 1) × interval + flight + SETTLE`. Replaces `RocketVolley.total_duration()` in `_volley_event_duration`, which gains the salvo's `count`, `interval` and `flight` (computed in `_annotate` from the shooter view's mouth count, the unit id and the tile distance; the aim / deploy / stow terms stay as TASK-044 / TASK-045 define them).
- `crossings(t0: float, t1: float, count, interval, flight) -> Dictionary` `{ "launches": Array[int], "impacts": Array[int] }`: indices whose launch / impact time lies in `(t0, t1]` (`t0 < 0` includes time 0). The volley calls it every `update(t)` with the previous `t`, so no launch or impact is skipped or doubled when frames are long or the burst speed is high.
- `flight_progress(s: float) -> float`: path parameter for flight-time fraction `s` (clamped 0..1); accelerating start (motor burn) then near-linear: `u = s` blended with `s²` as `lerp(s * s, s, smoothstep(0, MOTOR_BURN, s))` or similar – monotonic, `u(0)=0`, `u(1)=1`, `u(0.1) < 0.1`.
- `MOTOR_BURN := 0.4` – fraction of the flight with the motor burning (tail glow visible here; plume and dense trail in TASK-075); afterwards the rocket coasts dark.
- `hp_after_impact(hp_before: int, target_hp: int, k: int, count: int) -> int` = `hp_before − roundi((hp_before − target_hp) × (k + 1) / count)` for `k` in `0..count−1` (clamped): non-increasing, the last impact gives exactly `target_hp`.
- `landing_points(rng: RandomNumberGenerator, centre: Vector3, count: int, radius: float) -> Array[Vector3]`: uniform in a disc of `radius = LANDING_RADIUS 0.45 × hex_size` (inside the target tile; `y` is set by the caller from the ground height at each point). The rng is **view-local**, seeded per volley from `hash([_event_serial, attacker_id])` (replaces the unseeded `_fx_rng` use), never `GameState.rng`.

### Rocket path

- `RocketVolley.path_point(from, tube_dir, to, apex, u) -> Vector3`: cubic Bézier `P0 = from` (the `Mouth<i>`), `P1 = from + tube_dir × L` (`L = max(0.6, 0.35 × horizontal distance)`), `P2 = to + back × 0.25 × distance + UP × apex` (`back` = horizontal unit vector from the target towards the launcher), `P3 = to` (landing point on the ground). The rocket leaves along its tube and comes down steeply. `apex` from the existing `apex_height(distance)`. The old `arc_point` stays only if something else uses it.
- `tube_dir`: the `Pod`'s global +X basis vector (normalised) after aiming – `UnitView.launch_directions()` next to `launch_points()`. **Fallback** (no `Pod` / no `Mouth*`, e.g. a future model or a model built before TASK-073's contract): origins = `shooter.global_position + (0, 0.4, 0)` as today, `tube_dir` = horizontal direction to the target tilted up 45°.
- Rocket orientation from the path tangent (as today). Rocket mesh: keep a small cylinder but sized from `VisualScale.unit_model_scale()` and with a darker nose; one shared mesh and material per volley.

### Simple visuals (the shippable look of this task; also the LOW look after TASK-075)

- **Launch flash** at `Mouth<i>`: a short bright core (0.1 s) via the shared helper `FlashFx` (`src/presentation/flash_fx.gd`: expanding, fading additive sphere/quad, mesh only; reused by TASK-048 and TASK-075).
- **Tail glow**: a small emissive flame ball at the rocket's tail while `s < MOTOR_BURN`, hidden afterwards (replaces today's glow ball and the 4-ball trail).
- **Impact flash**: `FlashFx` core 0.12 s (white-yellow, size 0.5) at each landing point.
- No particles, no lights in this task: the volley creates no `GPUParticles3D` and no `OmniLight3D`.

### Per launch – pod jolt

- **Pod jolt** (TASK-048 recoil idea, cheap): each launch kicks the pod elevation by `−JOLT 0.012 rad` and eases it back over 0.12 s (`UnitView.set_launcher_pose` with an offset); after the last launch the pod is exactly at the aim pose again. Skipped for models without a `Launcher`.

### Per impact – ground marks and HP

- **Ground marks** (TASK-058, existing `_add_impact_marks`: craters + scorch): added at the **first** impact instead of the last (the strike starts marking the ground as soon as it lands); unchanged API and counts.
- **HP**: at every impact the target's tag shows `hp_after_impact(shown_hp_before_volley, target_hp, k, count)`; `play_hit` (shake + flash) on the first and the last impact only. The last impact shows exactly `target_hp`. A following `unit_died` plays after the volley event as today (≈ `SETTLE` after the last impact).

### Effect hooks (`SalvoEffects`, filled by TASK-075)

`src/presentation/salvo_effects.gd`, `extends RefCounted`, all methods no-ops in the base class. `RocketVolley` has `var effects: SalvoEffects` (default: a base instance, i.e. nothing happens) and calls it from `update(t)`; `BattleController._play_volley` assigns it before playing (in this task always the base class; TASK-075 assigns its pool-backed implementation on HIGH).

- `begin(context: Dictionary)` – once at the start of the salvo phase, after aiming. `context`: `volley` (the `RocketVolley` node – per-volley effect nodes such as lights are parented to it and freed with it), `shooter` (`UnitView`), `target_centre: Vector3`, `launcher_terrain: StringName`, `target_terrain: StringName`, `count`, `interval`, `flight`.
- `on_launch(index: int, mouth: Vector3, tube_dir: Vector3)` – at each launch time (from `crossings`).
- `on_flight(index: int, from: Vector3, to: Vector3, s: float, motor: bool)` – every `update(t)` for each rocket in the air: `from` = its position at the previous update (the mouth for the first call), `to` = its current position, `s` = flight fraction, `motor` = `s < MOTOR_BURN`. Consecutive segments of one rocket are contiguous; the last one ends at the landing point. This is what TASK-075's distance-emitted trail needs.
- `on_impact(index: int, point: Vector3, first: bool, last: bool)` – at each impact time.
- `end(target_centre: Vector3)` – once when the volley node is freed (end of the event); lingering effects after this are the implementation's business.
- `RocketVolley` also emits the signals `rocket_launched(index: int)` and `rocket_impacted(index: int, point: Vector3)` at the same moments (used by `BattleController` for HP steps and ground marks, and by the tests).

### Event queue (salvo pacing in AI turns) – **[ASSUMPTION]**

A full salvo makes an MLRS attack ≈ 10 s (Homar-K at 6 hexes: aim/stow 3.6 + salvo 4.4 + 1.94 + 0.5 = 10.4 s; Uragan at 5 hexes ≈ 10.4 s). With today's `begin_burst` one salvo alone would speed up the whole AI turn and squeeze the pauses away. Proposed:

- `EventQueue.burst_duration()` (used by `begin_burst`) leaves out events with `view_fx == rocket_volley`; `pending_duration()` stays the sum of everything.
- `EventQueue.playback_speed(event, burst_speed) -> float` = `minf(burst_speed, MAX_VOLLEY_SPEED 1.5)` for volley events, `burst_speed` otherwise; `BattleController._play_next_event` uses it instead of `_burst_speed` directly (and `_play_volley_hit`'s hit tween uses the volley's speed).
- Counter salvos (the Uragan countering a Homar-K within 5 hexes) are full salvos too.

## Acceptance criteria (testable)

- [ ] **Timing** (`tests/unit/test_salvo_timing.gd`):
  - `rocket_count(&"homar_k", 12) == 12`, `(&"bm27_uragan", 16) == 16`, `(&"bm27_uragan", 0) == 16`, `(&"unknown", 0) == 6`, `(&"unknown", 4) == 4`; `interval(&"homar_k") == 0.40`, `(&"bm27_uragan") == 0.30`, unknown `0.35`.
  - The built `homar_k` / `bm27_uragan` models (every faction in `data/factions/`) have exactly as many `Mouth*` nodes under their pod as `PROFILES` says (12 / 16).
  - `flight_time(0) == 1.1`, `flight_time(10.0) == 1.9`, `flight_time(100) == 2.2` (±0.001).
  - `salvo_duration(12, 0.40, 1.9) == 6.8`, `salvo_duration(16, 0.30, 1.9) == 6.9`, `salvo_duration(1, 0.4, 1.1) == 1.6` (±0.001).
  - `crossings`: stepping `t` from −0.01 to `salvo_duration` in increments of 0.016, of 0.37 and in one single step each yields every launch index 0..count−1 and every impact index exactly once, in ascending order; `crossings(0.39, 0.41, 12, 0.40, 1.9).launches == [1]`; `crossings(t, t, …)` is empty.
  - `flight_progress`: 0 → 0, 1 → 1, values outside clamp, monotonic over 101 samples, `flight_progress(0.1) < 0.1`.
  - `hp_after_impact(6, 1, k, 12)`: non-increasing over k = 0..11, `k = 11 → 1`, `k = 0 → 6`; `(6, 0, 15, 16) == 0`; `(5, 5, k, 12) == 5` for every k (no damage shown when HP did not change).
  - `landing_points`: all within `radius` of the centre (horizontal), `count` points; same seed → identical points; different seed → different points; the function never touches `GameState.rng` (it only takes the passed rng).
- [ ] **Path** (`tests/unit/test_rocket_volley.gd`, extended): `path_point(u = 0) == from`, `(u = 1) == to`; the tangent at `u = 0` is within 3° of `tube_dir`; the tangent at `u = 1` points down (y < 0) at ≥ 30° below horizontal for distances 2–10; the highest point over 50 samples is above both ends. Fallback `tube_dir` for a target at +X is `(cos 45°, sin 45°, 0)`.
- [ ] **Event queue** (`tests/unit/test_event_queue.gd`): 2 volley-annotated events (`view_fx = rocket_volley`, `view_duration` 10) + 12 × `unit_moved` with 1-tile paths (9.6 s) → `begin_burst() == 1.2`; only the 2 volleys → `1.0`; `playback_speed(volley, 3.0) == 1.5`, `(volley, 1.0) == 1.0`, `(move, 3.0) == 3.0`; `pending_duration()` still counts the volleys; the existing `test_long_volley_speeds_up_burst` (annotations without `view_fx`) passes unchanged.
- [ ] **Event duration**: `_volley_event_duration` for the Homar-K at 6 hexes equals the aim / stow terms of TASK-044 / TASK-045 (whatever is in the code then) + `salvo_duration(12, 0.40, flight_time(distance))`; for an MLRS without a launcher `AIM_DURATION + salvo_duration(...)`.
- [ ] **Volley node** (headless, `tests/unit/test_rocket_volley.gd` or a new `test_salvo_playback.gd` with a built `homar_k` model as shooter):
  - setup with 12 mouths creates 12 rockets; driving `update(t)` from 0 to the salvo duration in uneven steps emits the signal `rocket_impacted(index: int, point: Vector3)` exactly 12 times with indices 0..11 in order, and `rocket_launched(index)` 12 times; a synthetic `bm27_uragan` shooter with only 3 mouths fires 3 rockets (the mouth count wins over the profile's 16).
  - all rocket meshes are hidden at `t ≥` the last impact; no rocket is visible before its launch time; each rocket's tail glow is visible only while `s < MOTOR_BURN`.
  - after the last launch the pod elevation equals the aim pose within 0.0005 rad.
  - the volley creates no `GPUParticles3D` and no `OmniLight3D`.
  - with a model without `Pod` the volley still plays (fallback origin + direction) and emits all impacts.
- [ ] **Effect hooks** (same test file, a recording `SalvoEffects` subclass assigned to `volley.effects`): over one 12-rocket salvo driven in uneven steps, `begin` is called once (before any other hook) with all `context` keys listed in Design, `on_launch` 12 times (indices 0..11, `mouth` == the matching `Mouth<i>` global position, `tube_dir` normalised), `on_impact` 12 times with `first` true only for index 0 and `last` true only for index 11, and `end` once after freeing; per rocket the `on_flight` segments are contiguous (`from` == the previous call's `to`, the first `from` == its mouth, the last `to` == its landing point within 0.001) and `motor` is true exactly while `s < MOTOR_BURN`. With the base `SalvoEffects` (no subclass) the salvo plays identically (same signals).
- [ ] **HP steps** (playback test with a fixture battle view, or the volley + a `UnitView`): during a 12-rocket volley on a target showing 6 HP with `target_hp` 1, the tag's HP after each impact follows `hp_after_impact`, it ends at 1, and `play_hit` ran exactly twice (first and last impact). Ground marks are added once, at the first impact.
- [ ] **No simulation change**: `tests/fixtures/replays/default_battle_12345.json` replays unchanged (`test_replay.gd`), no file under `src/core/` or `src/ai/` changed; `tools/simulate.sh 20` results identical to before (the view is not involved).
- [ ] **Screenshot hook**: `SCREENSHOT_SALVO=<attacker id>,<target id>` in `tools/screenshot.gd` plays a volley **view-only** (a synthetic annotated `unit_attacked` with `damage 0`, `target_hp` = the target's current HP; no command, no state change) right after the scene is ready; with `--frames=N` the capture lands at a chosen moment. The agent renders on the Windows build (paths and frame numbers in the notes): (a) during the first launches – launch flash at the tube, rocket leaving along the tube with its tail glow; (b) mid salvo – several rockets in the air on their arcs, impact flashes on the target tile. Read the PNGs and describe what is visible; if something is not visible (e.g. rockets too small at battle zoom), say so – don't claim it looks good. TASK-075 reuses this hook for its effect shots.
- [ ] `docs/ARCHITECTURE.md`: the "View-only annotations" line mentions the volley playback speed cap; `SalvoEffects` (the hook interface of `RocketVolley`) listed where presentation effects are described. No new event types.

## Playtest (for the human)

1. Fire the Homar-K at an enemy: jacks / launcher aim as before, then 12 rockets leave **one after another** with clearly visible pauses (about 0.4 s), each with a short flash at its tube; the pod twitches slightly with every launch.
2. Watch a rocket: it leaves along its tube with a small glowing tail for the first part of the flight, then flies on dark and comes down steeply inside the target tile (the rockets land spread over the tile, not on one point).
3. At the target: every impact flashes; the target's HP bar drops step by step as the rockets land; the unit shakes on the first and the last rocket. Craters and a scorched patch appear at the first impact.
4. Fire the Uragan: 16 rockets, slightly quicker ripple (about 0.3 s).
5. End the turn so the AI fires its launcher: the AI's moves play fast, but the salvo still plays at (almost) normal speed with visible pauses. Is a whole AI turn with a salvo (and a counter salvo) too long? Report it (see Open questions).
6. Kill a unit with a salvo: it dies right after the last rocket.
7. Is the salvo already acceptable as it is (simple flashes, no smoke)? The smoke, fire and dust come in TASK-075.

## Player manual

Section 10 (Screen), next to "Ground marks", add: "**Rocket salvos**: rocket artillery fires its full salvo – 12 rockets for the Homar-K, 16 for the Uragan – one after another. The target's HP bar drops as the rockets land. The salvo is only for show: the damage is the same as for any attack (section on combat). During the enemy turn other animations speed up, but salvos play at almost normal speed." Adjust the last sentence to the human's answer on pacing. No change to stats or rules. (TASK-075 adds the sentence about the smoke over the target.)

## Open questions

- **Salvo pacing in AI turns [ASSUMPTION]**: volleys are left out of the burst speed-up and play at most 1.5× (≈ 7 s each in a fast AI turn); counter salvos are full salvos. Alternatives: shorter counter salvos (half the rockets), a global "fast animations" key, or compressing the interval instead of the whole event. Recorded in the GDD open questions.
- **Interval per unit**: 0.40 s (Homar-K) and 0.30 s (Uragan) are look choices, ≈ 3–4× faster than the real ripple. Human to judge in the playtest.

## Out of scope

- Any rule change: ammunition, salvo size as a stat, damage per rocket, misses (all rockets "hit" for the rules; scatter is cosmetic).
- The rich effects – backblast cloud and ground dust, motor plume, smoke trail, fireball, dust ring, smoke column, launcher / impact lights, particle pool, camera shake, frame-time measurement, README screenshot: **TASK-075**. (The README shot is static without a salvo, so it does not change here.)
- Sound, rocket debris / secondary explosions, burning ground, smoke screens (a mechanic), rocket noses staying visible in the tubes / reload animation.
- Launcher aim, jacks and shields (TASK-044 / TASK-045), the launcher models themselves (TASK-073), wrecks (TASK-065), direct-fire muzzle flash and recoil (TASK-048 – only the shared `FlashFx` helper is built here).
- Craters at the individual landing points (the existing TASK-058 crater set is kept).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
