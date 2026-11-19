# TASK-188a: Infantry walks normally: leg swing (legs as separate pivots)

- **Status**: ready
- **Layers**: presentation
- **Depends on**: (soft: TASK-183)
- **Sections**: docs/design/units/mechanisms.json (`squad_march`), ARCHITECTURE "Events" (only to confirm no new events are needed)
- **Model**: sonnet

## Goal

An infantry squad marches like soldiers walking: legs swing in alternating steps with a small bob, with no sway of the body. Fire effects are TASK-188b.

## Decisions (2026-11-19, the human)

- March: legs only. The legs swing in alternating steps with a small vertical bob. Weapon and arms stay still, and there is no lateral sway of the body. Kneelers stand up first (as today).

## Working-tree note

The soldier parts (`src/presentation/models/parts/soldier_body.gd`, `soldier_pose.gd`, `soldier.gd`, `src/presentation/models/model_parts.gd`) are also being reworked by the TASK-183 pilot. Start from the current working tree (uncommitted changes included), do not revert them, and commit only your own hunks.

## Acceptance criteria (testable)

- [ ] `UnitModels.pose_infantry` with `moving` and env 1: the two legs of a soldier rotate in opposite directions (phase from `Locomotion.step_phase`), and the swing is non-zero at some distance.
- [ ] Same call: Rig rotation about X/Z is zero (no `step_sway`, no `LEAN`), the Rig y offset equals `Locomotion.step_bob * env`, and arms/weapon transforms are unchanged from the standing pose.
- [ ] Not moving or env 0: every Rig and leg transform is exactly identity; kneelers are visible and Stand hidden (and the reverse while moving).
- [ ] Legs are separate pivots under each soldier (structure only: the standing silhouette and look are unchanged); the catalog animation `squad_march` (MARCH) and the `mechanisms.json` description show the leg swing.
- [ ] No new simulation state or events: the pose is driven only by distance and envelope as today; 60 FPS budget kept (no extra nodes beyond the leg pivots, no per-frame allocations).

## Playtest (for the human)

1. Move an infantry squad: legs swing in alternating steps with a small vertical bob.
2. Arms and weapons stay still, no side-to-side rocking of the body.
3. Kneelers stand up first; when the squad stops it returns exactly to the standing/kneeling pose.
4. Open the unit catalog, play the march animation: the same leg swing.

## Player manual

none (visual only)

## Out of scope

- Fire effects (TASK-188b), the infantry model's look (TASK-183 pilot), arm/weapon animation, walking sounds.

## Implementation notes

_Filled in by the agent when done._
