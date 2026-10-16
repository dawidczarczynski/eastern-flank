# TASK-003: Selected unit info panel

- **Status**: to playtest
- **Layers**: presentation (pure text formatter tested in `tests/unit/`)
- **Depends on**: TASK-001 (`Unit.has_attacked`). Optional: TASK-008 (refresh after the queue drains).

## Goal

The player can see the selected unit's numbers (HP, movement left, attack, defense, range, whether it can still attack) without remembering the GDD table.

## Acceptance criteria (testable)

- [ ] New pure formatter `UnitInfo` (`src/presentation/unit_info.gd`, `extends RefCounted`) with `static func lines(unit: Unit) -> PackedStringArray` returning exactly 5 lines:
  1. name – `definition.display_name`; if empty, `String(definition.id)`;
  2. `"HP <hp>/<max_hp>"`;
  3. `"Moves <moves_left>/<move_points>"`;
  4. `"Attack <attack> · Defense <defense> · Range <attack_range>"`;
  5. `"Ready to attack"` when `has_attacked == false`, otherwise `"Already attacked"`.
- [ ] Tests `tests/unit/test_unit_info.gd`:
  - Fresh unit from `data/units/infantry.tres` → `["Infantry", "HP 10/10", "Moves 3/3", "Attack 4 · Defense 3 · Range 1", "Ready to attack"]`.
  - Fresh unit from `data/units/cavalry.tres` with `hp = 3`, `moves_left = 0`, `has_attacked = true` → `["Cavalry", "HP 3/8", "Moves 0/5", "Attack 5 · Defense 2 · Range 1", "Already attacked"]`.
  - `Fixtures.fighter(...)` (empty `display_name`, id `test_fighter`) → first line `"test_fighter"`.
- [ ] HUD: a panel (built in code, e.g. `PanelContainer` + `Label` under the existing `HUD` CanvasLayer, bottom-left corner) shows `UnitInfo.lines(selected)` joined with newlines. Hidden when nothing is selected.
- [ ] The panel refreshes on selection change and after every executed command / processed event that may change the selected unit (move, attack, being hit, turn start). It is hidden when the selected unit dies, on turn end and on `game_over`.
- [ ] No game rules in the view: the panel only formats fields of `Unit` / `UnitDefinition`.

## Playtest (for the human)

1. Click your infantry – bottom-left shows `Infantry`, `HP 10/10`, `Moves 3/3`, `Attack 4 · Defense 3 · Range 1`, `Ready to attack`.
2. Move it 2 tiles on plains – `Moves 1/3`.
3. Attack an adjacent enemy – `Moves 0/3`, `Already attacked`.
4. Click cavalry – values switch to `Cavalry`, `Moves 5/5`, etc.
5. Press Enter – the panel disappears; after the AI turn, select a unit that was hit – its HP is lower and it shows `Ready to attack` again.
6. The panel doesn't overlap the status text at the top-left and is readable at 1280×720.

## Out of scope

- Info for enemy units (hover / right-click), terrain info of the unit's tile (follow-up after TASK-002), portraits/icons.

## Implementation notes

- `UnitInfo` (`src/presentation/unit_info.gd`) – pure static formatter, 3 tests in `tests/unit/test_unit_info.gd` (written first, failed on assertions against an empty stub, then implemented).
- `battle_controller.gd`: the panel (`HUD/UnitInfoPanel`, `PanelContainer` + `Label`, font size 18 like the status label) is built in code in `_build_info_panel()`; `battle.tscn` is unchanged. It is anchored bottom-left with a 16 px margin (`PRESET_BOTTOM_LEFT` + `PRESET_MODE_MINSIZE`, re-applied after every text change so it grows upward). Both controls use `MOUSE_FILTER_IGNORE` so clicks on map tiles under the panel still work.
- One `_refresh_selection_ui()` (highlights + info) replaces the old direct `_refresh_highlights()` calls: on selection change, after move/attack commands and on `turn_started`. `unit_attacked` refreshes only the info. Hiding on turn end, death of the selected unit and `game_over` comes from the existing `_select(-1)` calls.
- The panel is also hidden when the selected unit is dead (`get_unit` may still return dead units), so it never shows `HP 0/x` between `unit_attacked` and `unit_died`.
- Known limitation: the panel updates as soon as an event arrives, before the move/hit animations finish (no TASK-008 queue yet).
- After review: the selection (and with it the panel) is cleared on the `turn_ended` event for the human player instead of inside `_end_human_turn`, so any future way of ending a turn (auto-end, replay, network) also hides the panel.
- Known limitation: the panel updates as soon as a command executes, before the move/hit animation finishes (until TASK-008 adds the event queue).
