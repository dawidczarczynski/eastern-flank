# TASK-075: Rocket salvo effects – backblast, motor plume and smoke trail, realistic impacts with a lingering smoke column (pooled particles)

- **Status**: blocked (hard dependency TASK-074)
- **Layers**: presentation (new `SalvoFxPool` (pooled particle layers) + its `SalvoEffects` implementation, `ParticleFx` (fire material variant), `BattleController._play_volley` (assigns the effects on HIGH), `CameraRig` (small shake), `GraphicsQuality.features` (`fx_lights`)), tests, docs (ARCHITECTURE, MANUAL), README screenshot. Role: **presentation-engineer**. No core change.
- **Depends on**: **[TASK-074](TASK-074-mlrs-salvo-sequence.md)** (salvo timing, rocket paths, `SalvoEffects` hooks, `FlashFx`, `SCREENSHOT_SALVO` hook), **TASK-064** (done: `ParticleFx`, `MotionEffects.dust_color`, `Wind`), **TASK-050** (done: `particles` switch), **TASK-058** (done: craters and scorch – the column and dust sit on top of them). Soft: **TASK-065** (wreck smoke at the same tile after a kill; shares `ParticleFx`), **TASK-073** (v3 launcher models – the backblast origin uses the pod meshes' length, with a fallback).
- **Model**: sonnet (the timing, callbacks and event queue are done in TASK-074; this task fills hooks with pooled particles and measures the frame time)

## Goal

The ripple salvo from TASK-074 looks real: every launch throws a cloud of fire and smoke out behind the launcher and kicks up dust; each rocket leaves the tube on a bright motor flame that burns out into a fading smoke trail; and the target area erupts – flash, fireball, a ring of dust and a column of smoke that hangs over the tile for a few seconds – all within the 60 FPS budget.

## Current state (before)

After TASK-074: `RocketVolley` plays the full salvo with `SalvoTiming` (counts, intervals, flight times, `crossings`, `MOTOR_BURN`, `SETTLE`), rocket meshes with a tail glow, `FlashFx` launch and impact cores, pod jolt, HP steps and ground marks at the first impact. It calls a `SalvoEffects` object (`begin(context)`, `on_launch(index, mouth, tube_dir)`, `on_flight(index, from, to, s, motor)`, `on_impact(index, point, first, last)`, `end(target_centre)`) that is a no-op base instance. The volley creates no particles and no lights. `tools/screenshot.gd` has the `SCREENSHOT_SALVO` hook.

## Design

All of this is an implementation of `SalvoEffects` backed by `SalvoFxPool`; `RocketVolley`, `SalvoTiming` and the event queue are not changed (if a hook turns out to be missing, add it to `SalvoEffects` with a no-op default and note it).

### Per launch (`on_launch`)

- **Launcher light**: one `OmniLight3D` per volley at the pod (child of `context.volley`), energy pulse 4 → 0 over 0.15 s per launch, colour `#ffb060`, range 2.0, no shadow (`fx_lights` only).
- **Backblast** (behind the launcher – direction opposite to the launch): pure `SalvoFxPool.backblast_origin(mouth, tube_dir, pod_length) = mouth − tube_dir × pod_length` (the rear end of the tube; `pod_length` from the pod meshes' AABB along pod +X, fallback 0.4 world units). Burst of `BACKBLAST_FIRE 4` fire puffs (additive, orange `#ff9a3c` → dark, lifetime 0.35 s, size 0.08 → 0.25) and `BACKBLAST_SMOKE 8` smoke puffs (grey-brown `#8a8478`, alpha 0.5, lifetime 2.5 s, size 0.15 → 0.7), initial velocity along `−tube_dir` (2.5–4 u/s, spread 25°), strong damping so the cloud billows and stops within ≈ 1.5 units, then rises slowly and drifts with `Wind`. Plus `BACKBLAST_DUST 6` ground-dust puffs at the ground point under / behind the tube rear, spreading horizontally, colour from `MotionEffects.dust_color(context.launcher_terrain)` (water: none). The cloud builds up over the salvo – that is intended.

### In flight (`on_flight`)

- **Motor plume** while `motor` is true: an elongated additive flame quad / cone behind the rocket (length 0.25 → 0.1 near burnout, flickering by a hash of time and index – no RNG call per frame), bright core `#fff2c0`, edge `#ff8a2a`, HDR-ish energy so HIGH's subtle glow catches it. One quad per rocket, child of `context.volley`, hidden when the motor stops; it sits over TASK-074's tail glow.
- **Smoke trail**: emitted by distance along the segment `from → to` (one puff every `TRAIL_SPACING 0.07` world units, carrying the remainder between calls, so fast rockets leave no gaps) while `motor` is true; light grey-white `#d8d4cc`, alpha 0.55 → 0, size 0.05 → 0.35, lifetime 2.2 s, slow rise 0.1 u/s, wind drift; the first 0.15 s of each puff tinted warm (lit by the flame). After burnout no new trail; the existing trail fades out by itself. Pure helper `SalvoFxPool.trail_points(from, to, spacing, carry) -> Dictionary` `{ "points": Array[Vector3], "carry": float }`.

### Per impact (`on_impact`, at the landing point)

- **Impact light**: one shared `OmniLight3D` per volley at the target, energy 8 → 0 over 0.2 s per impact, range 3.0 (`fx_lights` only). (The flash core itself is TASK-074's `FlashFx`.)
- **Fireball**: `FIREBALL 6` additive puffs, orange `#ff8a2a` → deep red → dark smoke, lifetime 0.8 s, size 0.2 → 0.7, rising 0.8 u/s.
- **Shockwave / dust ring**: `DUST_RING 10` dust puffs emitted radially in the ground plane (velocity 2.5 u/s, strong damping, lifetime 1.4 s, size 0.12 → 0.5, colour `MotionEffects.dust_color(context.target_terrain)`; water: white spray `#e8eef0` instead), plus a flat expanding ring quad (scale 0 → 1.2 units, alpha 0.4 → 0 over 0.25 s) just above the ground.
- **Smoke column** (one per volley, at the target tile centre): every impact adds `COLUMN_PER_IMPACT 4` large dark puffs (`#3b3936` → `#7a7772`, alpha 0.6, lifetime 5 s, size 0.3 → 1.4, rising 0.5 u/s to ≈ 3 units, wind drift); after the last impact the column keeps being fed at a decaying rate for `COLUMN_LINGER 4.0` s, then stops; the last puffs fade by ≈ 9 s after the last impact. The column lingers **outside** the event: the queue moves on after `SalvoTiming.SETTLE`; `end()` hands the column to the pool's linger list. A following `unit_died` (≈ `SETTLE` after the last impact) – with TASK-065 the wreck then appears inside the smoke.
- **Camera shake** (small, optional – may be left out if the session runs long; then recorded in the notes): on each impact `CameraRig.add_shake(strength)` adds a decaying offset to the camera transform only (never the rig target, the pitch or the picking ray outside playback; input is blocked during playback anyway): amplitude `CameraRig.shake_strength(distance camera → impact)` = `SHAKE_MAX 0.03` world units at ≤ 6 units, linearly to 0 at 25 units, decay 0.25 s, impacts of one salvo do not stack above `SHAKE_MAX`. Constant `SHAKE_ENABLED := true` to switch it off.

### Pooling and performance (60 FPS budget)

- **`SalvoFxPool`** (`src/presentation/salvo_fx_pool.gd`, `Node3D`, child of the battle scene, created once at battle start on HIGH): owns one world-space `GPUParticles3D` per layer – `trail` (amount 512), `fire` (backblast fire + fireballs, 128), `smoke` (backblast smoke, 192), `column` (256), `dust` (backblast dust + rings, 160) – built through `ParticleFx` (new `ParticleFx.fire_mesh()`: additive, unshaded variant of the puff material). `SalvoFxPool.effects_for_volley() -> SalvoEffects` returns the implementation that `BattleController._play_volley` assigns to `volley.effects`. Every volley emits into these layers with `GPUParticles3D.emit_particle()` (position, velocity, colour flags) – **no particle nodes are created per volley**. Lingering columns are fed by the pool's `_process` from a small list (`{position, until}`); at most `MAX_COLUMNS 2` are fed at once (the oldest stops early). The first session verifies `emit_particle()` on the target build; if it is unusable, fall back to a fixed pool of one-shot emitters per layer reused round-robin (same counts) and record it.
- **Warm-up**: the pool emits one invisible particle per layer at creation, so the particle shaders compile at battle start, not at the first salvo (no hitch).
- **Alive budget**: ≤ 1 250 particles alive across the pool at any time (sum of amounts), all billboards with `ParticleFx`'s 64 px texture, no shadows, `visibility_aabb` sized to the map. Lights: at most 2 `OmniLight3D` per volley (launcher + impact), no shadows, freed with the volley node.
- **`fx_lights`**: new `GraphicsQuality.features` key, `true` on HIGH, `false` on LOW.
- **LOW** (`particles = false`): no pool, no `GPUParticles3D`, no plume quads; `volley.effects` stays the no-op base, so the salvo plays exactly TASK-074's mesh-only look (rocket bodies, tail glow, `FlashFx` cores) with the same timing and HP steps. `fx_lights = false` on LOW: no lights.
- The `RocketVolley` node (with the plume quads and lights parented to it) is freed at the end of the event as in TASK-074; the pool keeps the particles alive.

## Acceptance criteria (testable)

- [ ] **Backblast** (`tests/unit/test_salvo_fx.gd`): `backblast_origin`: `(origin − mouth) · tube_dir < 0`, distance == `pod_length`; for a pod without meshes `pod_length` falls back to 0.4.
- [ ] **Trail spacing**: `trail_points` over a straight path from (0,0,0) to (1,0,0) fed in uneven steps (e.g. 0.013, 0.2, 0.0, 0.5, 0.287) with the carry passed along yields 14 points (1.0 / 0.07, ±1), consecutive points 0.07 ± 0.001 apart, none duplicated; a zero-length segment yields none and keeps the carry.
- [ ] **Shake** (if built): `shake_strength(3) == 0.03`, `(25) == 0`, `(40) == 0`, non-increasing over 0..30.
- [ ] **Graphics quality**: `GraphicsQuality.features(HIGH)["fx_lights"] == true`, `(LOW) == false`.
- [ ] **Pool and quality** (headless, with a built `homar_k` model as shooter):
  - with `particles = true`: the pool exists once with 5 `GPUParticles3D` layers whose amounts sum to ≤ 1 250; playing two volleys in a row does not increase the scene's `GPUParticles3D` count.
  - with `particles = false`: neither the volley nor the battle scene creates any `GPUParticles3D`, and `volley.effects` is the base `SalvoEffects`.
  - with `fx_lights = true`: the volley has at most 2 `OmniLight3D`, none casting shadows, all freed with the volley node; with `fx_lights = false` no `OmniLight3D` is created by the volley.
  - the pool's effects receive all 12 launches / impacts of a salvo (from TASK-074's hooks) without errors; after `end()` the column is in the linger list and drops out after `COLUMN_LINGER`; with 3 salvos in a row at most `MAX_COLUMNS 2` columns are fed.
- [ ] **Screenshots** with TASK-074's `SCREENSHOT_SALVO` hook on the Windows build (paths and frame numbers in the notes): (a) during the first launches – backblast cloud behind the launcher, flame at the tube, plume + trail; (b) mid salvo – several rockets in the air with burnt-out trails fading; (c) shortly after the last impact – fireball, dust ring, smoke column over the target tile. Read the PNGs and describe what is visible; if something is not visible (e.g. the trail too faint at battle zoom), say so – don't claim it looks good.
- [ ] **Frame time**: `SCREENSHOT_MEASURE_FRAMES` during an Uragan salvo (default camera, all units on screen, Windows build HIGH): average and worst frame recorded in the notes; the average stays ≤ 16.7 ms (60 FPS). If not, cut particle counts / sizes (overdraw first) before anything else.
- [ ] `docs/ARCHITECTURE.md`: `SalvoFxPool` listed where presentation effects are described (as the HIGH implementation of `SalvoEffects`). No new event types.
- [ ] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it (static shot without a salvo – should be unchanged), commit only if changed.

## Playtest (for the human)

1. Fire the Homar-K at an enemy: each launch throws fire and a growing grey-brown cloud **out behind** the launcher, and kicks a little dust off the ground there.
2. Watch a rocket: bright flame at its tail for the first part of the flight, a white-grey smoke trail behind it that stops when the motor burns out and slowly fades and drifts with the wind.
3. At the target: every impact throws up a small fireball and a ring of dust; a dark smoke column builds over the tile and hangs there a few seconds after the last rocket, drifting with the wind, while the next events already play.
4. Fire the Uragan: the backblast goes the opposite way from where its tubes point.
5. Kill a unit with a salvo: with TASK-065 the wreck appears inside the smoke column.
6. Camera: zoomed in near the target the view shakes very slightly on impacts; zoomed out it doesn't. Is it welcome or annoying?
7. No hitch at the first salvo of the battle; FPS counter stays at 60 during a salvo with all units on screen.
8. `tools/run.sh` (LOW): the same salvo timing with rockets, small tail glows and flashes, no smoke or lights, no slowdown.

## Player manual

In section 10 (Screen), in the "**Rocket salvos**" paragraph added by TASK-074, after "The target's HP bar drops as the rockets land." add: "Smoke hangs over the target for a few seconds." Nothing else – the effects are only for show.

## Open questions

- **Camera shake**: proposed on, very small, only near the camera. Keep, make it a setting, or drop?

## Out of scope

- Anything in TASK-074: salvo timing, rocket count, paths, landing points, pod jolt, HP steps, ground marks, event queue pacing, the screenshot hook.
- Any rule or core change; sound, rocket debris / secondary explosions, burning ground, smoke screens (a mechanic).
- Wrecks and their smoke (TASK-065), direct-fire muzzle flash (TASK-048).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
