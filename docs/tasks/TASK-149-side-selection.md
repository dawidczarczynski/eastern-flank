# TASK-149: Side selection before an operation starts

- **Status**: done
- **Layers**: presentation (+ `SideDefinition.briefing` data)
- **Depends on**: TASK-102c
- **Sections**: docs/design/operational_map/README.md "Side selection"
- **Model**: sonnet

## Goal

Pressing **Operation** in the main menu asks which side to command (NATO or Russia) before the staff map opens; the other side is played by the AI.

## Acceptance criteria (testable)

- [x] `SideSelectWindow` (variant A of side_selection.html): one card per side of the operation with flag, name, briefing (`SideDefinition.briefing`, data), lead faction, alliance decision, nuclear option, formations; nothing pre-picked, START disabled until a pick.
- [x] Picked card = "◆ YOU COMMAND" (rectangle, `side_own`), the other "OPPONENT · AI" (diamond, `side_enemy`); BACK / X / Esc / click on the scrim go back, START / Enter starts.
- [x] The pick goes through `Session.chosen_side`; the staff map takes it once: `viewer_player` = that side, `ai_side` = the other; `--side=` and Continue are unaffected (Continue skips the screen).
- [x] No hot-seat option on the screen (`--hotseat` stays a command-line flag).

## Playtest (for the human)

1. Main menu → OPERATION: a centred window "SELECT YOUR SIDE · SUWAŁKI GAP" opens over the dimmed menu; START OPERATION is dimmed.
2. Click NATO: the card gets a blue frame and "◆ YOU COMMAND", Russia shows "OPPONENT · AI" with a red diamond; START lights up. Click Russia: it swaps.
3. ←/→ + Space picks with the keyboard, Enter starts, Esc / BACK / the X / a click outside returns to the menu.
4. START: the staff map opens as the picked side (own blue counters, turn bar); the AI plays the other side. Try both sides; Continue still loads a save without asking.

## Player manual

docs/MANUAL.md: the side selection step (one line under starting an operation).

## Out of scope

- Hot-seat on the screen; remembering the last side; several operations to choose from.

## Implementation notes

`src/presentation/ui/side_select_window.gd` (extends `StaffMapWindow`), opened from `MainMenu._on_operation_pressed` over a scrim; `Session.chosen_side` / `take_chosen_side`; `SideDefinition.briefing` + strings in strings.csv. Tests: tests/unit/test_side_select.gd. Menu overlay fade is 150 ms. Playtested by the human.
