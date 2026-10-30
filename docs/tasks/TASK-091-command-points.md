# TASK-091: Command points – the tactical C2 delay

- **Status**: done
- **Layers**: core + ai (+ HUD counter)
- **Depends on**: – (soft: TASK-086 – N later comes from `BattleConditions`)
- **Model**: sonnet

## Goal

Command and control matters in battle (GDD "Vision decisions": C2 delay = command points): a side with damaged command cannot use every company every turn.

## Acceptance criteria (testable)

- [x] Each player has `command_points_per_turn` (N) in the battle data; 0 / unset = unlimited (default battle unchanged, existing tests and simulation stats unchanged).
- [x] At the start of a player's turn their command points are set to N. A unit's **first** move or attack in a turn costs 1 point (later actions of the same unit that turn are free); with 0 points left a not-yet-activated unit is rejected with `no_command_points` (`MoveUnitCommand`, `AttackCommand`). Counterattacks cost nothing.
- [x] Example: N = 2, three companies – moving A (1), attacking with A (free), moving B (1), moving C → rejected `no_command_points`.
- [x] Points and activated units are in the state snapshot and survive replay (test).
- [x] Event `command_points_changed` (`player`, `remaining`) in docs/ARCHITECTURE.md.
- [x] The AI spends its points on the best-scoring units first (test: with N = 1 it activates its highest-value action, not the first unit in id order).
- [x] HUD: the turn bar shows remaining points ("C2 2/3") when limited; once the points run out, units not yet activated get the "done" look (activated units keep acting and look normal – accepted in playtest instead of a direct "activated" marker).

## Playtest (for the human)

1. `tools/run.sh --scenario=command_points_battle` (both sides N = 2): the turn bar reads `C2 2/2`.
2. Move a unit → `C2 1/2`; moving / attacking again with the same unit costs nothing.
3. Move a second unit → `C2 0/2`; the units that have not acted dim and leave the READY count.
4. Try to move a dimmed unit → toast "NO COMMAND POINTS LEFT THIS TURN", nothing happens.
5. End turn; after the Russian turn the counter is back to `C2 2/2`.
6. `tools/run.sh` (default battle): no counter, no dimming – unchanged.

## Player manual

Command points: what activates a unit, what is free, where N comes from.

## Out of scope

Deep strikes lowering N (TASK-099 wires `BattleConditions` into it).

## Implementation notes

- **Data**: N comes from `BattleSetup.Conditions.command_points` (0 = unlimited) → `GameState.command_points_per_turn` (static, via `Scenario.from_setup`). Runtime state: `GameState.command_points` (current player's remaining) and `Unit.activated`, both in `snapshot()` (the regression fixture gained only these keys).
- **Rules**: `GameState.can_activate` / `activate`; `MoveUnitCommand` and `AttackCommand` reject `no_command_points` right after `not_your_unit`. `EndTurnCommand` refills N and resets `activated`. Unlimited units are still marked `activated` but no event is emitted and nothing is rejected.
- **Event** `command_points_changed` (`player`, `remaining`): right after the first `unit_moved` / `unit_attacked` of a unit's first action, and after `turn_started` (limited players only); in docs/ARCHITECTURE.md.
- **Debug / replay**: new scenario `command_points_battle` (default battle, N = 2 both sides) in `Scenario.NAMES` – `--scenario=` for the game and `tools/simulate.sh`; MatchRecord replays it by name.
- **AI**: when limited, units act in descending action score (attack 100 + damage, +100 for a kill; move 10; ties by id) and skip once no point is left; the unlimited order is unchanged.
- **HUD**: `C2 r/N` under the active side's name in the turn bar (hidden when unlimited, updates when the event queue drains); once the points run out, units not yet activated get the existing "done" look and leave the READY count; toast for `no_command_points`.
- **Playtest decision**: no direct "activated" marker – dimming the units that can no longer be activated once the points run out was accepted; the last criterion was reworded to match. Toast translated to Polish (`assets/i18n/strings.csv`); the devtools scenario dropdown now reads `Scenario.NAMES`.
- Tests: `test_command_points.gd`, `test_command_points_battle.gd`, `test_battle_hud.gd` (counter, dimming).
