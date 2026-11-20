# TASK-188b: Infantry fire effects: tracers vs. infantry, anti-tank launcher rocket vs. vehicles

- **Status**: done
- **Layers**: presentation
- **Depends on**: –
- **Sections**: ARCHITECTURE "Events" (`unit_attacked`, `view_fx`)
- **Model**: sonnet

## Goal

Infantry attacks are readable and spectacular: glowing tracers against infantry, one anti-tank launcher rocket (Carl Gustaf for Poland, RPG-7 for Russia; the visual kind per country is chosen in the squad model, behaviour and nodes are shared) with a smoke trail against a vehicle. The march animation is TASK-188a (independent).

## Decisions (2026-11-19, the human)

1. Infantry vs infantry: every 4th round is a tracer (interval is a devtools tunable).
2. Infantry vs vehicle: ONE soldier (the anti-tank launcher gunner, the kneeling slot) fires one anti-tank rocket; the rest fire rifles as usual.
3. The rocket's impact reuses the existing tank-shell hit effect (cheap, consistent); the rocket still leaves a smoke trail along its flight.
4. Spectacle comes from tracers (glowing streak, flash light pulse) and the rocket's smoke trail and launch flash, not from a new explosion.

## Acceptance criteria (testable)

- [ ] Pure helper (e.g. `TracerPlan.is_tracer(shot_index, interval)`): with interval 4 shots 3, 7, 11 are tracers (0-based) and the others are not; interval 1 makes all tracers; the interval is read from a new `DevTunables` key `tracer_interval` (default 4, min 1, max 12, step 1).
- [ ] `unit_attacked` with an infantry attacker and an infantry target gets `view_fx` = a new `FX_INFANTRY_FIRE`; every soldier alive fires: muzzle flash (MuzzleFlash) at its weapon and a bullet shot, impact puffs at the target; the playback duration is set via `view_duration` so EventQueue timing stays correct.
- [ ] A tracer is a bright additive streak along the bullet's flight with a short light pulse at the muzzle (FlashFx); non-tracer rounds have no streak.
- [ ] `unit_attacked` with an infantry attacker and a non-infantry target gets `FX_INFANTRY_AT`: exactly one rocket is launched, from the anti-tank launcher gunner (kneeling slot) with a launch flash and back-blast puff; the other soldiers fire rifles as in the infantry case.
- [ ] The rocket flies from the anti-tank launcher gunner to the target with a smoke trail (pooled particles) along the path; on arrival it plays the same hit effect as a tank shell (`_play_direct_hit`), no new explosion effect.
- [ ] anti-tank launcher gunner dead or slot missing: the vehicle attack falls back to rifles only, no error.
- [ ] No rules in the view layer: only event fields are read (`unit_attacked`, `damage`, `target_hp`), no new simulation state; a test shows damage and events are identical with and without the new fx.
- [ ] 60 FPS budget kept: streaks, flashes and smoke trails are pooled/freed after the shot, extra particles drop on lower quality levels (like MuzzleFlash on HIGH only).
- [ ] The effects look spectacular (the human's explicit wish): glowing tracers, bright muzzle flash with a light pulse, dense smoke trail and launch flash for the rocket; within the 60 FPS budget.

## Playtest (for the human)

1. Attack infantry with infantry: muzzle flashes, bullets, every 4th a glowing tracer, impacts at the target.
2. Attack a tank with infantry: the anti-tank launcher gunner fires one rocket with a smoke trail, the rest shoot rifles, the tank gets the usual shell-hit effect.
3. In the dev arena change the tracer interval slider (1, 4, 12) and Fire again: the tracer rhythm follows.
4. Watch the FPS overlay during a big infantry fight: stays at 60.

## Player manual

none (visual only)

## Out of scope

- Hit / damage rules, targeting, the infantry model's look (TASK-183 pilot), the march animation (TASK-188a).
- A new explosion effect for the rocket; several rockets per attack; ATGM guidance arcs.

## Implementation notes

- Follow-up (human): the rocket also explodes on the target (fireball flash, light pulse, SalvoFxPool impact particles, camera shake; flash only on LOW). Tracers are red and laser-like, default interval 2 (every 2nd round).
- `TracerPlan` (pure): tracer rhythm (`is_tracer`), 2 rounds per soldier, flight/rocket timing, `duration`. `DevTunables.TRACER_INTERVAL` (1..12, default 4) gives the arena slider automatically.
- `InfantryFire` (pooled Node3D, created next to `MuzzleFlash`): muzzle flash + impact puff per round, additive tracer streaks, light pulse on HIGH, the rocket (launch flash, body streak, `SalvoTrail` smoke + `emit_backblast` from `SalvoFxPool`, none on LOW). Pose is a pure function of the attack's age, driven by one tween.
- `EventQueue.FX_INFANTRY_FIRE` / `FX_INFANTRY_AT`, set in `BattleController._annotate_infantry` (only for `infantry` attackers whose model has Soldier nodes; vehicle target + launcher gunner = AT). The hit reuses `_play_direct_hit` (rocket arrival / first round landing).
- `UnitModels.at_slot / at_muzzle_of / squad_muzzles`: rifles have no muzzle marker, so the rifle muzzle is a fixed offset in the Soldier node frame (`RIFLE_MUZZLE`) – check the position in game.
- Non-tracer rounds draw no bullet (muzzle flash + impact puff only). Soldiers do not die individually, so all five always fire.
- Tests: tests/unit/test_infantry_fire.gd.
