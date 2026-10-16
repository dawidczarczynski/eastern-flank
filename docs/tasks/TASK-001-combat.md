# TASK-001: Basic melee combat

- **Status**: to playtest
- **Layers**: core / ai / presentation

## Goal

Units can attack adjacent enemies – the first real tactical decision.

## Acceptance criteria (testable)

- [ ] New command `AttackCommand(attacker_id, target_id)`.
- [ ] Attack allowed only on an enemy unit at distance ≤ `attack_range`; otherwise `validate()` returns `out_of_range`, `not_an_enemy` or `not_your_unit`.
- [ ] A unit can attack once per turn (`already_attacked`); attacking sets its remaining movement to zero.
- [ ] Damage = `max(1, attack − defense)`, deterministic (no RNG in this version).
- [ ] A unit with HP ≤ 0 dies: `unit_died` event, it stops blocking its tile and is not returned by `unit_at` / `units_of`.
- [ ] `unit_attacked` event with fields `attacker_id`, `target_id`, `damage`, `target_hp`.
- [ ] The AI attacks an enemy if it ends its move next to one.
- [ ] When a player has no living units – `game_over` event with `winner`.

## Playtest (for the human)

1. Select a unit, walk up to an enemy, click it – the enemy "twitches" and loses HP (label above the unit).
2. When HP drops to 0 the unit disappears.
3. After all enemies are wiped out, a victory message appears.

## Out of scope

- Counterattack, terrain defense bonuses, randomness, ranged attacks.

## Implementation notes

- Core/AI done: `AttackCommand` (src/core/commands/attack_command.gd), `Unit.has_attacked`, `GameState.winner` (-1 = running).
- Rejection codes in order: `game_over`, `unit_not_found`, `not_your_unit`, `not_an_enemy`, `already_attacked`, `out_of_range`. `MoveUnitCommand` and `EndTurnCommand` are rejected with `game_over` once `winner != -1`.
- `has_attacked` is reset in `EndTurnCommand` for the player whose turn starts (together with `moves_left`).
- AI attacks after its move (or without moving) the enemy in range with the lowest hp (ties: lowest id) and returns without ending the turn once the game is over.
- Tests: tests/unit/test_attack.gd, new cases in tests/unit/test_ai_player.gd.
- Presentation done (battle_controller.gd, unit_view.gd, no scene changes): clicking an enemy with a unit selected issues `AttackCommand`; HP `Label3D` above each unit; `unit_attacked` -> shake + white flash and HP update; `unit_died` -> shrink after the hit animation, then `queue_free` (pending move is snapped to its target); `game_over` -> "Victory!"/"Defeat!" in the HUD and input is blocked; the AI loop in `_end_human_turn` also stops when `winner != -1`; rejected commands are printed to the terminal.
- Headless smoke run (full match driven by script until `game_over`) finished without script errors; visuals still need a human playtest.
- After review: `game_over` fires only when exactly one player has living units (works for >2 players); `attack_range` covered by tests with a range-2 unit; `damage` in `unit_attacked` is the value before HP is clamped at 0 (documented in ARCHITECTURE.md); the hit reaction (and HP label update) on the target waits for the attacker's move animation to finish, because AI turns emit all events in one frame.
- Known limitation: AI units still animate simultaneously (several units move/attack at once). A proper event queue that plays animations one by one is a separate task.
- Lint (gdtoolkit 4.5.0) passes; `AttackCommand.validate` split into `_combat_rule_violation` to satisfy `max-returns`, and `test_attack.gd` disables `max-public-methods` (test files naturally have many test methods).
