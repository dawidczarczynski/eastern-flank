# TASK-088: Per-battle victory conditions and turn limit (`BattleObjectives`)

- **Status**: done
- **Layers**: core (+ ai, + minimal HUD text)
- **Depends on**: – (soft: TASK-086)
- **Model**: opus (end-of-game rules touch every command, AI goal change)

## Goal

Each battle defines how it is won and how long it lasts (GDD "Vision decisions"), instead of always "eliminate all enemy units" – the base for battles started from the operational map.

## Acceptance criteria (testable)

- [x] `BattleObjectives` resource (`src/core/data/`): `turn_limit` (0 = none) and a list of conditions, each for one player or both:
  - `hold_hexes` – at the end of the battle (turn limit) the player holds the listed hexes (a hex is held by the last side that had a unit on it; initial owner set in the data);
  - `take_hexes` – the player has a unit on all listed hexes at the end of any own turn → immediate win;
  - `destroy_share` – the enemy has lost ≥ X % of its starting total HP → immediate win;
  - `eliminate` – today's rule (kept as a condition, the default battle uses it).
- [x] Turn limit: when the last player's turn of turn `turn_limit` ends, the battle ends; the winner is decided by the `hold_hexes` / victory-point rule in the data; if nobody qualifies it is a **draw**. `game_over` carries `winner` (−1 = draw) and `reason` (`&"objective_taken"`, `&"enemy_destroyed"`, `&"turn_limit"`, `&"eliminated"`); add the fields to the event table in docs/ARCHITECTURE.md.
- [x] Objective hexes and their owner live in the state, are in `snapshot()` and survive replay (`MatchRecord`), with a test.
- [x] `Scenario.default_battle` keeps `eliminate` + no turn limit → all existing tests and the simulation statistics stay the same.
- [x] A second test scenario with `take_hexes` + `turn_limit = 8` exists; the AI moves toward objective hexes when it has an objective condition (simple: objective distance in its move scoring); `tools/simulate.sh` reports draws by turn limit separately from the harness limit.
- [x] HUD: the turn bar shows "Turn 3 / 8" when there is a limit; objective hexes have a simple marker (placeholder, presentation-engineer may restyle later).

## Playtest (for the human)

1. Start the objective test scenario (debug option); capture the marked hexes before turn 8 → win screen with reason.
2. Let turn 8 run out → draw / hold result.

## Player manual

Victory conditions and turn limits per battle; how holding a hex works.

## Out of scope

Deriving objectives from the operational map (TASK-094), victory points per unit type.

## Implementation notes

- **Logic** (ADR 0016): `GameState.end_reason` + `is_over()` + `finish(winner, reason)`; `winner == -1` after the end = draw. Victory rules live in `src/core/battle_rules.gd` (`capture` from MoveUnitCommand, `after_strike` from AttackCommand, `at_turn_end` from EndTurnCommand). Data: `BattleObjectives` / `VictoryCondition` (`src/core/data/`), `BattleSetup.objectives` is a `BattleObjectives` (JSON `{}` = default). State: `objectives`, `objective_owners` (in `snapshot()` as `"objectives": [[q, r, owner]]`, plus `"end_reason"`), `starting_hp`. New event `objective_captured`; `game_over` gained `reason`.
- **Scenarios**: `Scenario.build(name, …)` / `NAMES`; `objective_battle` = default battle + `data/scenarios/objective_battle.tres` (limit 8, hexes (6,2) and (4,7) east of the fords, owned by player 1; P0 take both, P1 hold both, eliminate for both). Replay and `MatchRecord.from_simulation(…, scenario_name)` carry the scenario name; the replay fixture gained only the two new snapshot keys.
- **AI**: goals = hexes of the player's take/hold conditions; a unit on a goal stays (still attacks), otherwise it heads for the nearest goal not held by its side when it is no farther than the nearest enemy. Without goals the code path is unchanged.
- **Simulation**: `tools/simulate.sh 100` identical before/after (46 / 48 wins, 6 harness limits, 10.4 / 12.7 turns). `--scenario=objective_battle`, 50 matches: P0 6, P1 21, draws (rules) 23, harness 0 – the attacker is weak; tuning is a follow-up.
- **Decisions [ASSUMPTION]** (also in GDD Open questions): a hex changes hands only when a unit *ends a move* on it (passing through or spawning doesn't capture); a side wiped out while the opponent has no `eliminate` condition does not end the battle (runs to the limit; unreachable in today's scenarios); a battle-ending strike gets no counter; take_hexes is checked before the turn limit on the last turn; several hold conditions – one satisfied is enough; destroy_share with >2 players counts all others together.
- **Presentation**: `--scenario=objective_battle` for `tools/run.sh` / `tools/run_windows.sh` (`BattleOptions`), `SCREENSHOT_SCENARIO` and `SCREENSHOT_SHOTS=result:<victory|defeat|draw>` in tools/screenshot.gd. Turn bar "01" + small "/08"; result banner caption "TURN 08 / 08", DRAW in neutral grey, reason subtitle depending on the winner (`HudModel.REASON_TEXTS`); placeholder `ObjectiveMarkers` (edge ring, pole + flag, OBJECTIVE tag in the holder's colour), recoloured when `objective_captured` is played back. `debug_marks_demo` body moved to `GroundMarksView.debug_demo` (battle_controller line limit). Default battle look unchanged → README screenshot not re-rendered.
- **Review**: no blocking findings; removed a dead null check in `HudModel.turn_limit_of`.
