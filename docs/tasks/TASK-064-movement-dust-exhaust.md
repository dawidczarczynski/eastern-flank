# TASK-064: Movement effects – dust from tracks and wheels, exhaust smoke

- **Status**: done
- **Layers**: presentation (pure `MotionEffects` parameters, particle emitters attached to `UnitView` during move playback, optional `Exhaust`/`Dust*` anchors in model files), tests. Roles: **presentation-engineer**; **unit-modeler** adds `Exhaust` anchors to the vehicle models.
- **Depends on**: **TASK-050** (`particles`), TASK-022/TASK-025 (move playback, done); soft **TASK-058** (tracks appear under the dust), soft **TASK-055** (dust colour per ground layer)
- **Model**: sonnet

## Goal

Moving vehicles feel heavy and real: a tank kicks up a trail of dust behind its tracks, a truck leaves a lighter cloud, and engines puff dark exhaust when they start moving.

## Design

- **Only during move playback** (the `unit_moved` animation, TASK-022): emitters are enabled when the unit starts moving and stop emitting on arrival (particles already emitted finish their life). No effect on event durations.
- **Dust**: emitters at the rear bottom corners of the model (from `Dust_L`/`Dust_R` anchors if present, otherwise computed from the model AABB: rear, ±40 % width, ground level). `GPUParticles3D` on HIGH; nothing on LOW (`particles = false`). Billboard soft-noise quads (procedural texture), lifetime **1.6 s**, start size 0.12 → end 0.45 world units, rising slowly (0.15 u/s) and drifting with the wind uniform (TASK-057, if present), alpha 0.35 → 0. Emission rate ∝ ground speed: `rate = clamp(speed / 3.1, 0, 1) · base` (3.1 world units/s ≈ one hex spacing of 1.73 per `EventQueue.SECONDS_PER_TILE` 0.55 s – full rate at normal move speed, less while turning/accelerating; derive the constant from `SECONDS_PER_TILE` in code) with base 24/s for tanks, 14/s for mlrs, 0 for infantry. Max **40** particles per emitter.
- **Dust colour by ground** – pure `MotionEffects.dust_color(terrain: int, weights: PackedFloat32Array = []) -> Color`: plains/hills `#a39477`, forest `#7d6f58`, shore/mud (mud weight > 0.4 from TASK-055 if available) → mud spatter colour `#5a4a38` with rate ×0.4, water → no dust.
- **Exhaust**: from the `Exhaust` anchor (unit-modeler adds it to every vehicle model; fallback: rear top of the AABB). On move start a puff of 10 particles (dark grey `#3a3a38`, alpha 0.5, size 0.1 → 0.35, lifetime 1.2 s), then a thin stream 4/s while moving.
- Particles use their own random seeds (view-only), never `GameState.rng`.
- Particle sizes above are at the `current` scale preset and follow `VisualScale.unit_model_scale` (TASK-059). The soft-noise smoke texture and emitter setup go into a shared helper (`ParticleFx`), reused by TASK-065 smoke and TASK-048 muzzle smoke.
- **Anchor pass**: the vehicle anchors of TASK-063 (`Marking_*`, `Number_*`) and TASK-064 (`Exhaust`, `Dust_L`/`Dust_R`) are added to the four vehicle models in **one** `unit-modeler` rework per vehicle when the two tasks run close together (feedback lists both anchor sets; for the Homar-K / Uragan also the TASK-045 jacks / shields if that rework is still pending). The task done second only checks the anchors already exist.

## Acceptance criteria (testable)

- [ ] `tests/unit/test_motion_effects.gd`: `dust_rate(&"tank", 3.1) == 24`, `(&"tank", 0) == 0`, `(&"mlrs", 1.55) == 7`, `(&"infantry", 3.1) == 0`, `(&"tank", 10) == 24` (clamped) (±0.5 if the constant is derived from `SECONDS_PER_TILE`); `dust_color` per terrain as listed, water → `Color(0,0,0,0)` / "none" flag; mud weight 0.5 → mud colour.
- [ ] With `particles = false` no `GPUParticles3D` nodes are created for any unit.
- [ ] With `particles = true`: a tank `UnitView` has 2 dust emitters + 1 exhaust emitter, all `emitting == false` at rest; during a simulated move playback `emitting == true`, after arrival `false`; an infantry view has none.
- [ ] `test_unit_model_contract.gd`: every vehicle model has an `Exhaust` anchor inside its AABB.
- [ ] Agent visual check (Windows build): screenshot mid-move (hook or `--frames` during a scripted move) shows a dust trail behind the tank and an exhaust puff; nothing on LOW.
- [ ] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it (static shot – should be unchanged), commit only if changed.

## Playtest (for the human)

1. Move the Abrams across plains: a brown dust trail rises behind it and drifts away; a dark exhaust puff when it starts.
2. Move the Homar-K: lighter, smaller dust cloud.
3. Move infantry: no dust.
4. Drive along a lake shore: darker mud spatter instead of dust.
5. Dust doesn't hide the unit or its label at default zoom; it fades within ~2 s after stopping.
6. `tools/run.sh` (LOW): no particles, no slowdown.

## Player manual

None (presentation only).

## Out of scope

- Muzzle smoke (TASK-048), smoke screens (a mechanic), engine sound.

## Implementation notes

Done 2026-10-23 (all in presentation; `tools/check.sh` passes).

- `MotionEffects` (pure): dust rate by ground speed, dust colour / rate factor by terrain and mud weight, and an **engine load** model for the exhaust: a pull-away puff that decays over ~1 s (`START_DECAY`) or a hull pivoting in place (large heading error at low speed), whichever is larger; cruising leaves a thin stream. Tank peak 16/s vs 3/s cruising.
- `ParticleFx` (shared helper for TASK-065 / TASK-048): procedural soft-noise texture, billboard material, `emitter(config)` factory. `MotionFx` owns the 2 dust + 1 exhaust emitters of a vehicle (on the model root, emitting into world space), `UnitView` drives them from `_step_move` (speed from position delta, heading error from the turn). Emission strength is `amount_ratio`.
- Realism: particles are world-space and long-lived (dust 2.4 s, exhaust 3.4 s, damped, rising slowly, drifting with `Wind`), so the cloud hangs behind the vehicle after it stops instead of vanishing.
- Dust colour follows the terrain type under the vehicle (`BattleController._terrain_at`); water raises none. The mud-weight path exists in `MotionEffects` but the view does not pass splat weights yet (no shore mud spatter).
- **Not done**: `Exhaust` / `Dust_L` / `Dust_R` anchors in the vehicle models (`MotionFx` supports them and falls back to the model bounds: rear, ±40 % width, exhaust at 60 % height) and the matching `test_unit_model_contract.gd` check – left for the shared anchor pass with TASK-063. No screenshot of a mid-move frame was taken, so the look is unverified. `docs/images/gameplay.png` not re-rendered (static shot, no particles at rest).
- Second pass (human feedback: heavier exhaust, motion too brisk): tank exhaust peak 60/s with fast, dark (#1f1f1d), large puffs that decay over ~1.8 s; `EventQueue.SECONDS_PER_TILE` 0.55 → 0.8 (all units); vehicles move by `HeavyMove` (new): at the start and at every bend the hull stops and pivots in place (`PIVOT_RATE` 1 rad/s, min 0.3 s) and only then drives off; straight stretches are one run with 1.2 s acceleration/braking (`HEAVY_ACCEL_TIME`). A vehicle move therefore lasts longer than `MoveAnimation.duration()`; the tween governs, so the queue just waits. Track marks and exhaust use the same timeline (pivot = high engine load, no dust). Only **tracked** units use it (`UnitModels.is_tracked`); wheeled ones steer along the path (`MoveAnimation.steered_yaw`: heading = chord ±`WHEELED_LOOK`, initial heading error faded over `WHEELED_STEER_IN`; `WHEELED_ACCEL_TIME` 0.6) and raise smaller clouds (`MotionEffects.CLOUD_SIZE` 0.55, exhaust peak 14/s). Infantry keeps the light profile. Tunables: `heavy_move.gd`, `move_animation.gd`, `motion_effects.gd`.
- Tests: `test_heavy_move.gd`, `test_motion_effects.gd`, `test_motion_fx.gd`.

**Rework (2026-10-30, after TASK-075).** The exhaust read as one big flat grey blob hiding the tank and the dust as a wide flat sheet. `MotionFx` now builds its emitters with `ParticleFx.puff_emitter` (the TASK-075 shaders: drag towards the wind drift, sun-lit soft puffs, self-emission through the `emit_*` uniforms): dust 0.05 → 0.38 (tank scale), alpha 0.5, a low trail about the vehicle's width; exhaust 0.03 → 0.26, dark (`#1c1b19`, 0.75) at full load, thin grey (0.3) cruising; a puff keeps the tint it was born with. New screenshot hook `SCREENSHOT_MOVE=<unit id>,<direction>,<tiles>`. Playtested by the human.
