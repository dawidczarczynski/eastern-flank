# TASK-208: Continuous tactical space (4/9): core cutover – unit positions, move and attack commands, stepped execution

- **Status**: blocked
- **Layers**: core
- **Depends on**: TASK-205, TASK-206, TASK-207
- **Sections**: ADR 0029 (decisions 1, 5, 6); ARCHITECTURE "Flow of a single action", "Events"; GDD "Unit orders"
- **Model**: opus
- **Tags**: continuous-space

## Goal

The battle rules run on positions in metres: a unit stands anywhere, moves along a smooth track and its move can be interrupted. This is the cutover; the old tile commands are removed here.

## Acceptance criteria (testable)

- [ ] `Unit.coord` -> `Unit.position` (snapped `Vector2`) + `facing`; `GameState.grid` -> `GameState.map: TacticalMap`; `unit_at` / `occupied()` -> circle queries (`units_near(p, r)`); footprint radius is a field of `UnitDefinition`.
- [ ] `MoveUnitCommand(unit_id, target: Vector2)`: validated with `find_path` (`unreachable`, `blocked_destination`, `no_command_points` as before); the budget spent equals the path cost (test); command codec / `to_dict` carry the position in centimetres as integers.
- [ ] Execution is stepped: the move is simulated in fixed steps (data: step length) and emits `unit_moved` with `path` (polyline) and `stopped_at`; a move **stops early** when an enemy enters sight or weapon range at a step (new event `move_interrupted`, added to the ARCHITECTURE event table; the remaining budget is kept) – tests for stop, no stop and tie order.
- [ ] `AttackCommand`, `CombatForecast`, `BattleRules.capture`, `SmokeCommand`, `DigInCommand`, `EndTurnCommand` use positions, metre distances, circular objective / smoke / cover areas (objective radius is data).
- [ ] `ScenarioDefinition` / `BattleSetup` / formation placement place units at positions (a deployment area + spacing instead of tiles); `Scenario`, `Replay`, `MatchRecord` work with the new commands; **old replays are rejected with a clear reason** (version number in the replay).
- [ ] Determinism: the same seed and the same command list give the same final state in two runs (test); no `GameState.rng` use is added or reordered unintentionally.
- [ ] Tactical tests that used `Vector2i` are rewritten (not deleted); operational tests untouched; `tools/check.sh --full` green.

## Playtest (for the human)

None yet (the view still reads tiles until TASK-210); a headless match (`tools/simulate.sh 5`) finishes.

## Player manual

none (TASK-213 documents the player-facing change)

## Out of scope

- AI (TASK-209), the view (TASK-210 … 212).

## Implementation notes

_Filled in by the agent when done._
