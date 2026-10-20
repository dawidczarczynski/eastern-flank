# TASK-064: Movement effects – dust from tracks and wheels, exhaust smoke

- **Status**: ready
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

_Filled in by the agent when done._
