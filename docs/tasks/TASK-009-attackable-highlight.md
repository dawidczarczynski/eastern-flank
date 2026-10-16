# TASK-009: Highlight attackable enemies

- **Status**: ready
- **Layers**: core / ai / presentation
- **Depends on**: TASK-001. Optional: TASK-008 (refresh after the event queue drains).

## Goal

When the player selects a unit, enemies it can attack right now are clearly marked, so the player doesn't have to count hexes or guess whether an attack is still available.

## Acceptance criteria (testable)

- [ ] New pure query `static func valid_targets(state: GameState, attacker_id: int) -> Array[int]` in `AttackCommand`. It returns ids of living units for which `AttackCommand.new(attacker_id, id).validate(state) == ""`, sorted ascending. It **must reuse `validate()`** (no duplicated range/ownership rules), so future rule changes (TASK-002, TASK-010, TASK-011) apply automatically.
- [ ] Tests (`tests/unit/test_attack_targets.gd`), plains map radius 3 (`Fixtures.plains_grid(3)`), `current_player == 0`:
  - attacker A (owner 0, range 1) at `(0, 0)`; enemy B at `(1, 0)` (distance 1); enemy C at `(2, 0)` (distance 2); ally D at `(0, 1)`; enemy E at `(-1, 0)` with `hp = 0` → `valid_targets(state, A) == [B]`.
  - Same layout with A at range 2 (`Fixtures.fighter(4, 2, 10, 2)`) → `[B, C]`.
  - After A executes `AttackCommand(A, B)` → `[]` (already attacked).
  - `state.current_player = 1` → `[]`; unknown attacker id `99` → `[]`; `state.winner = 0` → `[]`.
  - Consistency: for every living unit X in the layout, `X in valid_targets(state, A)` ⇔ `AttackCommand.new(A, X).validate(state) == ""`.
- [ ] `AiPlayer._weakest_enemy_in_range` is reimplemented on top of `valid_targets` (pick lowest hp, ties lowest id – unchanged behaviour); all existing tests in `tests/unit/test_ai_player.gd` still pass.
- [ ] `MapView` gets a separate marker set for attack targets (e.g. `show_attack_targets(coords: Array[Vector2i])`), visually distinct from the yellow movement highlight: a red, semi-transparent ring/disc on the target's tile, slightly above the movement highlight. `clear_highlights()` also clears these.
- [ ] `BattleController._refresh_highlights` shows markers on the tiles of `valid_targets(state, selected_id)`; no markers when nothing is selected, during the AI turn, or after `game_over`. Markers update after every executed command (move brings an enemy into range → it gets marked; attack → all markers disappear).
- [ ] No game rules in the view: the controller only maps ids → tiles (`get_unit(id).coord`).

## Playtest (for the human)

1. Select a unit far from enemies – only the yellow movement highlight, no red markers.
2. Move it next to an enemy – the enemy's tile gets a red marker immediately (still selected).
3. Click the marked enemy – the attack happens and all red markers disappear (the unit can't attack again this turn).
4. Select another unit that is adjacent to two enemies – both are marked.
5. Press Enter – no red markers are visible during the AI turn.

## Out of scope

- Threat range ("enemies attackable after moving") and damage preview on hover (follow-up; would reuse a pure damage function, see TASK-002).
- Marking which enemies can attack the selected unit.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
