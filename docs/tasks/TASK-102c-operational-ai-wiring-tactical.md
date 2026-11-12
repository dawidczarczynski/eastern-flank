# TASK-102c: Operational AI – plays its turn; tactical AI heads for objectives

- **Status**: done
- **Layers**: ai / presentation
- **Depends on**: TASK-102a (hard), TASK-102b (hard), TASK-120 (hard), TASK-121 (soft)
- **Sections**: GDD "Operational AI", "Player roles", "Battle hand-off and auto-resolve", "Operational turns"; ARCHITECTURE: none (grep docs/CODEMAP.md for `StaffMap`, `AiPlayer`, `MatchRunner`, `BattleObjectives`, `VictoryCondition`)
- **Model**: sonnet

## Goal

The opponent really plays: on its operational turn the AI leader executes its plan and ends its turn, in the game and in headless runs; in a battle the tactical AI goes for the objectives instead of only annihilation.

## Acceptance criteria (testable)

- [ ] A pure helper in `src/ai/` (e.g. `OperationalAiTurn.play(sim, player)`) runs `plan` (TASK-102a / b), executes each command through `OperationalSimulation.execute()` and finally `EndOperationalTurnCommand`; returns the executed commands and results; it executes nothing when it is not `player`'s turn.
- [ ] The helper stops after `max_commands` + 1 commands and always ends the turn, even when a command is rejected (a rejected command is skipped, not retried).
- [ ] Headless: two AIs (player 0 and 1) play 10 operational rounds on `suwalki_gap` without a rejected command and without a loop; the same seed gives the same final state hash twice.
- [ ] A pending contact battle between two AI sides is auto-resolved by the runner; the AI never returns a *Play battle* / *Auto-resolve* choice for the human side (a test: the human side's pending battle is left untouched).
- [ ] `MatchRunner` (or a small sibling) can run an operational AI-vs-AI match: `tools/simulate.sh` option is out of scope, but a test calls it for 5 rounds with the AI as player 0 and as player 1.
- [ ] Tactical `AiPlayer`: with a `BattleObjectives` that has a take-hex condition, a company that can reach the hex within the turn limit moves towards it (destination within the shortest path to the objective hex) instead of the nearest enemy; a test with a map where the enemy is behind the objective.
- [ ] Tactical `AiPlayer`: a hold-hex objective makes companies already on or next to the hex stay and fire (no move that leaves the hex); with no objectives in the setup the behaviour is unchanged (existing `AiPlayer` tests still pass).
- [ ] Tactical AI plays for the objective within the turn limit: with a turn limit of 4 and the objective 3 moves away, a company reaches it on turn 3 or 4.
- [ ] The staff map plays the AI side: when the current operational player is the non-human side, `StaffMap` runs the helper once, then shows the usual end-of-turn marks (turn report, move slide, strike reports) for the AI's turn; a test with a stubbed sim checks the helper is called once per AI turn and never for the human's turn.
- [ ] The human's contact notice still asks *Play battle* / *Auto-resolve* only for the human side's battles; the AI's turn does not block on it.

## Playtest (for the human)

1. Start the Suwałki operation as NATO, give an order, end the turn.
2. The enemy's turn plays at once: its counters slide, a strike report may appear, a decision may be taken (visible in the escalation chip / Politics screen); then it is your turn again, the turn number grows.
3. Repeat as Russia: the NATO AI acts after your turn.
4. At a contact, you are asked to play or auto-resolve; the AI never decides for you. In a played battle the enemy company heads for the objective hex shown in the briefing.
5. No freeze, no endless enemy turn; Esc / menu still works during the AI's turn.

## Player manual

Add to docs/MANUAL.md (operation / turns section): the opponent's leader is played by an AI that gives orders, strikes and takes political decisions on its turn under the same rules as the player, and in a battle its companies go for the objectives. No numbers.

## Out of scope

- Difficulty levels, AI explanations / "thinking" UI, replay of AI turns beyond the usual records.
- Fog (TASK-100), balancing (TASK-103), operation victory (TASK-107).

## Implementation notes

- `OperationalAiTurn.play(sim, player, profile)` (src/ai/operational_ai_turn.gd): plan, execute (at most `max_commands`), always tries `EndOperationalTurnCommand`; returns `{commands, results, ended}`; nothing when out of turn. Rejected commands are skipped.
- `MatchRunner.play_operational(sim, rounds, ai_sides)`: AI turns for the listed sides; a pending battle between two AI sides is auto-resolved (AutoResolve + ResolveBattleCommand); a pending battle of a human side is never touched and the run stops (`stalled`). Returns rejected / commands / battles / stalled / state hash. Test: `tests/unit/test_operational_ai_turn.gd` (10 rounds on suwalki_gap, same seed = same hash).
- Tactical `AiPlayer` already headed for TAKE/HOLD objectives (TASK-088 era code); added a test for reaching a far objective within a turn limit of 4. Limitation: a hold objective keeps only companies standing ON the hex; companies merely next to it are not pinned.
- `StaffMap`: `ai_side` (the side that is not the viewer when the map opens; `--hotseat` disables) and `ai_turn` Callable (test seam, default `OperationalAiTurn.play`). `play_ai_turn_if_due()` is called from `_process`: once per AI turn, only when no slide runs and no battle is pending; the existing event handlers then show the report / slide / strike reports. The view no longer jumps to the AI side on `operational_turn_started`. Hot-seat tests in test_staff_map_turns.gd set `ai_side = -1`. Test: `tests/unit/test_staff_map_ai_turn.gd`.
