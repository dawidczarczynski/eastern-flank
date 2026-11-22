# TASK-207: Continuous tactical space (3/9): ranges in metres, line of sight by ray

- **Status**: blocked
- **Layers**: core, data
- **Depends on**: TASK-205
- **Sections**: ADR 0029 (decision 4); GDD "Combat" (find with `tools/doc.py gdd`)
- **Model**: sonnet
- **Tags**: continuous-space

## Goal

Ranges and sight as honest distances, so a unit's reach can be a smooth circle.

## Acceptance criteria (testable)

- [ ] `UnitDefinition` ranges (weapon range, sight, minimum range, support ranges) get metre values next to the hex counts (`*_m`); a converter table (tile pitch of the tactical map) fills them; a test fails when a `.tres` has a hex range and no metre value. The hex fields stay until TASK-213.
- [ ] `TacticalLineOfSight.visible(map, a, b, eye_a_m, target_m, smoke_zones)`: ray sampled over `height_at` and obstacle heights (forest / buildings from `cover_at`); same inputs as `LineOfSight` give the same answers at hex centres on the `Fixtures` maps (comparison test; differences only where documented).
- [ ] Hit chance / damage tables take a **metre distance**: `AttackCommand.hit_on_at` and `CombatForecast` get metre overloads (the hex ones stay until TASK-208); at the converted distance of N hexes they give the numbers they gave for N hexes (test).
- [ ] Smoke is a circle (centre, radius): a ray through it is blocked (test).

## Playtest (for the human)

None (core only).

## Player manual

none

## Out of scope

- Switching the commands to positions (TASK-208).

## Implementation notes

_Filled in by the agent when done._
