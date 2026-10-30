# TASK-091: Command points – the tactical C2 delay

- **Status**: ready
- **Layers**: core + ai (+ HUD counter)
- **Depends on**: – (soft: TASK-086 – N later comes from `BattleConditions`)
- **Model**: sonnet

## Goal

Command and control matters in battle (GDD "Vision decisions": C2 delay = command points): a side with damaged command cannot use every company every turn.

## Acceptance criteria (testable)

- [ ] Each player has `command_points_per_turn` (N) in the battle data; 0 / unset = unlimited (default battle unchanged, existing tests and simulation stats unchanged).
- [ ] At the start of a player's turn their command points are set to N. A unit's **first** move or attack in a turn costs 1 point (later actions of the same unit that turn are free); with 0 points left a not-yet-activated unit is rejected with `no_command_points` (`MoveUnitCommand`, `AttackCommand`). Counterattacks cost nothing.
- [ ] Example: N = 2, three companies – moving A (1), attacking with A (free), moving B (1), moving C → rejected `no_command_points`.
- [ ] Points and activated units are in the state snapshot and survive replay (test).
- [ ] Event `command_points_changed` (`player`, `remaining`) in docs/ARCHITECTURE.md.
- [ ] The AI spends its points on the best-scoring units first (test: with N = 1 it activates its highest-value action, not the first unit in id order).
- [ ] HUD: the turn bar shows remaining points ("C2 2/3") when limited; activated units are visually distinct from not-yet-activated ones (simple, presentation-engineer).

## Playtest (for the human)

1. Start the test battle with N = 2 (debug option); try to move a third company → toast with the reason.

## Player manual

Command points: what activates a unit, what is free, where N comes from.

## Out of scope

Deep strikes lowering N (TASK-099 wires `BattleConditions` into it).

## Implementation notes

_Filled in by the agent when done._
