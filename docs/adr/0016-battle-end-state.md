# ADR 0016: Battle end state – `end_reason` + `is_over()`, draws, one place for the victory rules

- **Status**: accepted
- **Date**: 2026-10-30
- **Task**: TASK-088

## Context

Until TASK-088 a battle ended only by elimination, checked inline in `AttackCommand._strike`, and "the battle is running" was spelled `GameState.winner == -1` across the core, the AI, the tools and the presentation. Per-battle objectives (GDD "Vision decisions": hold / take hexes, destroy a share of the enemy, a turn limit) add a second way to end – by the clock – and with it a **draw**, which `winner == -1` cannot tell apart from "still running". The rules also have to be checked from three commands (move, attack, end turn).

## Decision

1. **End state** – `GameState.end_reason: StringName` (`&""` while running; `&"eliminated"`, `&"enemy_destroyed"`, `&"objective_taken"`, `&"turn_limit"`) and `GameState.is_over() -> bool` (`end_reason != &""`). `winner` stays the winning player; once over, `winner == -1` means a **draw**. Every "is the battle running" check uses `is_over()`; every command's `validate()` rejects with `game_over` when it is true. `GameState.finish(winner, reason)` is the only setter. Both fields are in `snapshot()` (`"winner"`, `"end_reason"`); `BattleResult.reason` is `end_reason`.
2. **Objectives as data** – `BattleObjectives` (`src/core/data/battle_objectives.gd`: `turn_limit`, objective `hexes` + parallel `initial_owners`, `conditions: Array[VictoryCondition]`) is part of `BattleSetup` (JSON `"objectives"`, `{}` = `default_objectives()` = ELIMINATE for both, no limit). The state keeps the static `objectives` and `starting_hp` (not in the snapshot – the scenario rebuilds them) and the changing `objective_owners` (in the snapshot as `"objectives": [[q, r, owner], ...]`).
3. **One place for the rules** – `BattleRules` (`src/core/battle_rules.gd`, static, pure) holds every victory rule. Commands call it at fixed points and append its events:
   - `MoveUnitCommand.apply` → `capture` (a move ending on an objective hex makes the mover's side its owner; `objective_captured`);
   - `AttackCommand._strike` → `after_strike` after each strike incl. the counter: ELIMINATE (after a death), DESTROY_SHARE; the striker's side is checked first; a strike that ends the battle gets no counter;
   - `EndTurnCommand.apply` → `at_turn_end` after `turn_ended`, before the turn passes: TAKE_HEXES for the player ending the turn, then – when the last player ends turn `turn_limit` – HOLD_HEXES decides (exactly one qualifying player wins, otherwise draw). An ended battle emits no `turn_started`.
   A battle end returns `game_over` {`winner`, `reason`}.
4. **No implicit elimination** – ELIMINATE is a condition like the others. A side wiped out while its opponent has no ELIMINATE condition does not end the battle; it runs to the turn limit. Both shipped scenarios list ELIMINATE for both players.
5. **Harness vs. rule limit** – `MatchRunner` / `tools/simulate.sh` report rule draws (`"draw"`) separately from matches cut by the harness `--max-turns` (`"harness_limit"`).

## Consequences

- New rules (survive N turns, exit through a map edge, victory points) are a new `VictoryCondition.Kind` + a branch in `BattleRules` at one of the three call points; commands stay thin.
- The presentation reads `is_over()`, `winner`, `end_reason`, `objectives.turn_limit` and `objective_owners` from the state and reacts to `objective_captured` / `game_over`.
- `snapshot()` gained keys, so the replay regression fixture was regenerated once (unit data unchanged).
- This supersedes the `objectives` placeholder row of ADR 0015's `BattleSetup` table.
