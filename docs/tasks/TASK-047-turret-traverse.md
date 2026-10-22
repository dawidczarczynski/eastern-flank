# TASK-047: `turret_traverse` mechanism – the tank turns its turret and elevates its gun before firing

- **Status**: ready (revised 2026-10-22: the tank models exist – `m1a2_sepv3`, `t72b3` – so the dependency on TASK-031 is replaced by them)
- **Layers**: presentation (`UnitModels.pose_turret` / `turret_aim` / `gun_elevation`, `UnitView`, `BattleController` attack playback, `EventQueue` FX key), `mechanisms.json`, tests; catalog tank entries
- **Depends on**: **TASK-044** (`traverse_aim`), **TASK-043** (`MECHANISMS` metadata on the tanks). The models `m1a2_sepv3.gd` and `t72b3.gd` already have `Turret` and `Turret/Gun` (`VehicleFrame.add_turret` / `add_gun`); check the hinge position and add `Turret/Gun/Muzzle` if missing.
- **Model**: sonnet

## Goal

A tank attacking (or countering) visibly aims: its turret turns towards the target and the gun elevates or depresses to it, the hit lands, then the turret returns to the front. Today a direct-fire attack shows only the target's hit reaction.

## Decisions

- Parameters per unit in the catalog (`turret_traverse` – today the tank entries declare only `wheels` (TASK-043); add `turret_traverse` with researched params and have the human verify it): `traverse_deg` (`"full"` for tanks; a limited range for e.g. assault guns – then the vehicle turns first, as with the launcher) and `elevation_deg` `[min, max]` (real gun depression/elevation limits; Abrams [−9, 20] (?), T-72B3 [−6, 14] (?) – research and verify in the catalog).
- The turret **returns to the front** after the hit (consistent with the launcher; open question whether it should keep pointing at the last target).
- Durations are global constants (`TURRET_AIM_DURATION := 0.5`).

## Design

- **Pivot contract** (registry `turret_traverse` → `implemented`): `Turret` (turns about its local Y; built pose = gun along the model's +X), `Turret/Gun` (hinge at the trunnions, elevation about its local Z, positive = muzzle up; built pose = level; `rest` meta stored on first use like the `Pod`), `Turret/Gun/Muzzle` (just in front of the muzzle; effects in TASK-048). Owns `Turret`.
- `UnitModels.pose_turret(model, traverse: float, elevation: float)` (no-op without the pivots), `turret_aim(model, facing_yaw, target_yaw) -> Vector2` (= `traverse_aim(params.traverse_deg, 0.0, …)`), `gun_elevation(model, from: Vector3, to: Vector3) -> float` = `clamp(atan2(to.y − from.y, horizontal distance), min, max)` with the unit's `elevation_deg` in radians. `has_turret(model)` = declares `turret_traverse` and has `Turret/Gun`.
- `UnitView`: `turret_aim_towards(point)`, `gun_elevation_towards(point)` (from the `Turret/Gun` global position to the target's position + 0.15 up, the impact height of the volley), `set_turret_pose(traverse, elevation)`.
- **Playback**: `BattleController._annotate` marks a `unit_attacked` event whose attacker view `has_turret()` (and doesn't fire a volley) with `EventQueue.FX_DIRECT_FIRE` and a duration of `TURRET_AIM_DURATION + EventQueue.ATTACK_DURATION + TURRET_AIM_DURATION` (+ `AIM_DURATION` for a limited traverse, body-turn step always present as in TASK-044). Sequence: [limited: body turn] → turret traverse and gun elevation together (sine in-out) → the target's `play_hit` → turret and gun back to (0, 0). Counterattacks (`counter: true`) play the same way with the counter-attacker aiming. Units without a turret keep today's hit-only playback.
- **Existing tank models**: check that `Turret/Gun` hinges at the trunnions in both tank models and add `Muzzle` where missing (a small `unit-modeler` touch-up, or directly if it's one node); add `turret_traverse` to their `MECHANISMS` (TASK-043 contract).
- Docs: `docs/ARCHITECTURE.md` events/FX note for `FX_DIRECT_FIRE`; GDD "Unit feel" (game-designer, when done).

## Acceptance criteria (testable)

- [ ] `gun_elevation` with `elevation_deg [-9, 20]`: from (0, 0.5, 0) to (1, 0.4, 0) → −5.711° (±0.01°); with `[-3, 20]` → −3°; to (1, 1.0, 0) → 20° (clamped).
- [ ] `turret_aim` full traverse, facing 0, target 135° → (0, 135°); limited `[-30, 30]`, target 90° → (60°, 30°) (same rules as `traverse_aim`).
- [ ] `pose_turret` on a synthetic model: (0, 0) = built pose exactly; traverse PI/2 turns the `Muzzle` from +X to −Z of the model (±1e-4); elevation +10° raises the `Muzzle` and keeps the `Gun` origin; no-op on a model without `Turret/Gun`.
- [ ] Event annotation: a tank attack → `view_fx = FX_DIRECT_FIRE`, duration 1.4 s; a volley and an infantry attack are annotated as before (0.4 s for the infantry hit).
- [ ] Contract helper: a tank model with `Turret` but no `Turret/Gun/Muzzle` declaring `turret_traverse` → violation.
- [ ] `tools/check.sh` passes; README screenshot re-rendered only if the battle at rest changed (it shouldn't).

## Playtest (for the human)

1. Attack an enemy with the tank from a side hex: the turret swings round, the gun dips or rises towards the target (try a target on a hill and one in a valley), the target flashes, the turret returns to the front.
2. Attack a tank so that it counters: the defending tank's turret turns towards the attacker for its counter.
3. Watch an enemy turn with several tank attacks: the sequence plays faster in the burst but stays readable.

## Player manual

None (presentation only, no rule effect).

## Open questions

- Turret after the shot: return to the front (proposed) or keep pointing at the last target until the tank moves?
- Real gun elevation limits per tank (Abrams, T-72B3) to research and verify in the catalog (?).

## Out of scope

- Recoil and muzzle flash (TASK-048), turret stabilisation while moving, infantry firing animation.

## Implementation notes

_Filled in by the agent when done._
