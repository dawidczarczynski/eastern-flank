# TASK-009: Highlight attackable enemies

- **Status**: done
- **Layers**: core / ai / presentation
- **Depends on**: TASK-001. Optional: TASK-008 (refresh after the event queue drains).
- **Model**: sonnet

## Goal

When the player selects a unit, enemies it can attack right now are clearly marked, so the player doesn't have to count hexes or guess whether an attack is still available.

## Acceptance criteria (testable)

- [x] New pure query `static func valid_targets(state: GameState, attacker_id: int) -> Array[int]` in `AttackCommand`. It returns ids of living units for which `AttackCommand.new(attacker_id, id).validate(state) == ""`, sorted ascending. It **must reuse `validate()`** (no duplicated range/ownership rules), so future rule changes (TASK-002, TASK-010, TASK-011) apply automatically.
- [x] Tests (`tests/unit/test_attack_targets.gd`), plains map radius 3 (`Fixtures.plains_grid(3)`), `current_player == 0`:
  - attacker A (owner 0, range 1) at `(0, 0)`; enemy B at `(1, 0)` (distance 1); enemy C at `(2, 0)` (distance 2); ally D at `(0, 1)`; enemy E at `(-1, 0)` with `hp = 0` → `valid_targets(state, A) == [B]`.
  - Same layout with A at range 2 (`Fixtures.fighter(4, 2, 10, 2)`) → `[B, C]`.
  - After A executes `AttackCommand(A, B)` → `[]` (already attacked).
  - `state.current_player = 1` → `[]`; unknown attacker id `99` → `[]`; `state.winner = 0` → `[]`.
  - Consistency: for every living unit X in the layout, `X in valid_targets(state, A)` ⇔ `AttackCommand.new(A, X).validate(state) == ""`.
- [x] `AiPlayer._weakest_enemy_in_range` is reimplemented on top of `valid_targets` (pick lowest hp, ties lowest id – unchanged behaviour); all existing tests in `tests/unit/test_ai_player.gd` still pass.
- [x] `MapView` gets a separate marker set for attack targets (e.g. `show_attack_targets(coords: Array[Vector2i])`), visually distinct from the yellow movement highlight: a red, semi-transparent ring/disc on the target's tile, slightly above the movement highlight. `clear_highlights()` also clears these.
- [x] `BattleController._refresh_highlights` shows markers on the tiles of `valid_targets(state, selected_id)`; no markers when nothing is selected, during the AI turn, or after `game_over`. Markers update after every executed command (move brings an enemy into range → it gets marked; attack → all markers disappear).
- [x] No game rules in the view: the controller only maps ids → tiles (`get_unit(id).coord`).

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

- `AttackCommand.valid_targets(state, attacker_id)` (static) iterates living units and keeps those for which `validate()` returns `""`, sorted ascending – no duplicated rules. Tests: `tests/unit/test_attack_targets.gd` (7 tests).
- `AiPlayer._weakest_enemy_in_range` now loops over `valid_targets`; the ascending order plus a strict `<` keeps the "ties → lowest id" behaviour (covered by the existing `test_ai_breaks_hp_ties_by_lowest_unit_id`).
- `MapView.show_attack_targets(coords)`: own root node, red translucent hex disc (`Color(0.9, 0.12, 0.1, 0.6)`, radius 0.9 × hex_size vs 0.8 for the yellow highlight) at `ATTACK_MARKER_OFFSET = 0.07` above the tile top (above the movement highlight 0.02 and path markers 0.05). A disc rather than a ring – a ring would need a custom mesh; TASK-017 restyles overlays anyway.
- `show_highlights` / `show_attack_targets` each replace only their own markers; `clear_highlights()` clears both.
- `BattleController._refresh_attack_targets` maps ids → tiles only. It relies on `valid_targets` returning `[]` on the AI's turn and after game over (no extra guards). Markers refresh via `_refresh_selection_ui` on selection and when the event queue drains (TASK-008).
- Not verified visually by the agent (no screenshot with a selected unit).
