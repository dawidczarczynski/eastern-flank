# TASK-048: `gun_recoil` mechanism – barrel recoil and muzzle flash on direct fire

- **Status**: idea – needs TASK-047 done and a look at it in game first (is the aim alone readable enough?); open: how much to exaggerate the recoil at miniature scale, whether the flash is a shared effect for all direct-fire units (also infantry), sound (none in the game yet).
- **Layers**: presentation (`UnitModels.pose_recoil`, muzzle flash effect, attack playback), `mechanisms.json`, tests
- **Depends on**: **TASK-047**
- **Model**: sonnet

## Goal

The tank's shot reads at game zoom: the barrel kicks back and returns, a short flash at the muzzle, at the moment the target is hit.

## Design (draft)

- Pivot `Turret/Gun/Barrel` (moves along its local −X by `recoil_m` × `UnitModels`' model scale, built pose = in battery); `Turret/Gun/Muzzle` for the flash (from TASK-047).
- Param `recoil_m` (registry: number 0…2, default 0.5; the real recoil length is shorter – the value is an exaggeration for the miniature, decided per unit (?)).
- In the TASK-047 sequence: at the start of the hit step the barrel snaps back (0.05 s) and returns (0.3 s, ease out) while a flash (billboard + light, ≈ 0.15 s, deterministic, view-local) plays at the `Muzzle`; no change to the event duration.

## Acceptance criteria (testable)

- [ ] (to be written when the task becomes `ready`) `pose_recoil(model, 1.0)` moves the `Barrel` origin by `recoil_m / METERS_PER_UNIT` along the gun's −X; `0.0` = built pose; the event duration of a direct-fire attack is unchanged (1.4 s).

## Playtest (for the human)

1. Attack with the tank at normal zoom: the barrel kicks and a flash appears at the muzzle as the target is hit.

## Player manual

None (presentation only).

## Out of scope

- Smoke, shell tracers, sound.

## Implementation notes

_Filled in by the agent when done._
