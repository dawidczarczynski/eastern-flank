# TASK-099b: Battle conditions – contact notice, fire-support button, manual

- **Status**: done
- **Layers**: presentation
- **Depends on**: TASK-099a (hard); soft: design check (first acceptance criterion – `/design-ui` if no mockup fits)
- **Topic**: Two-layer game
- **Tags**: mvp
- **Sections**: GDD "Battle hand-off and auto-resolve" (incl. "Battle conditions"), ARCHITECTURE "Presentation"
- **Model**: sonnet

## Goal

The player sees what the operation did to each side's command and fire support before choosing Play / Auto-resolve, and can call fire support in a played battle.

## Acceptance criteria (testable)

- [ ] **Design first**: grep `docs/design/` and CODEMAP for a similar component (action button with a counter, target mode). If none fits, run `/design-ui` and implement only the variant the human picks; record the choice in the Look section. No implementation before this is settled.
- [ ] Pure view model (e.g. `ConditionsModel`, no scene access) turns a `BattleSetup` into per-side lines: `Command points n / N` (N = `command_points`, 0 -> "unlimited"), `Fire support m` (m = `fire_support`). Tests: (4, 2) -> "Command points 4 / 4", "Fire support 2"; command_points 0 -> "Command points unlimited"; fire_support 0 -> "Fire support none".
- [ ] The contact notice (`StaffMapContactNotice`) lists both sides' lines before the Play / Auto-resolve choice; a side with reduced value (below its base from `BattleConditionsRules.shipped()`) is marked as reduced (colour or "reduced" tag per the design). Model test: command_points 1 of base 4 -> reduced flag true; full -> false.
- [ ] Battle HUD: remaining command points are shown (exists – `HudModel.command_points_text`): verify it reads 1 for a side with a destroyed C2 and unlimited for scenario battles (test on the model).
- [ ] Battle HUD: fire-support counter "Fire support m" for the current player (hidden in scenario battles with fire_support 0 at start); model test: left 2 -> "2", after use -> "1", used this turn -> button disabled with reason text.
- [ ] Fire-support button enters a target mode: only enemy companies visible to the side are targetable (marker per the design); a click sends `FireSupportCommand`; Esc cancels without a command. Controller test: click on a visible enemy -> command sent with that unit id.
- [ ] Rejections (`no_fire_support`, `fire_support_used_this_turn`, `not_your_turn`, `target_not_visible`) show a short English message in the battle log / status line; button disabled when none left or already used this turn.
- [ ] On `fire_support_used` the view plays an effect (shell impact on the target hex or a flyover per the design) and the existing damage / destroyed feedback; no game rules in the view layer.
- [ ] Both Play and Auto-resolve start from the same shown conditions; the battle report (result screen) mentions fire support missions used when > 0 (model test).
- [ ] Screenshot compared with the mockup / the chosen variant; deviations stated.

## Look

Design check (first criterion): similar components exist, so no `/design-ui` run. The button is an icon button of the bottom action bar (docs/design/hud_v3/README.md "Bottom bar": 38x38 line icon, hover tooltip), with a count badge in its top-right corner. The target mode uses the targeting bar (HUD v3 "06 Notices", top 118) and the existing red attack-target hex markers. The notice lines sit under the strength line of each side card of the contact notice (mockup 03); a reduced value is drawn in the alert colour with a "reduced" tag. Deviation: the fire-support icon (shell on a ground line) and the badge are new line art in the existing style.

## Playtest (for the human)

1. Debug-strike a Russian command post and an airfield, trigger a contact battle: the notice shows Russia "Command points 1 / 4" and "Fire support" reduced, NATO unchanged, reduced values marked.
2. Choose Play battle: the HUD shows the fire-support counter; press the button, click a visible enemy company: effect plays, company loses strength, counter drops by 1, button greys out until next own turn.
3. Try it on a hidden enemy, with no missions left, and twice in one turn: each is refused with a message.
4. Same contact with Auto-resolve: it runs; the result matches a repeat of the same save.

## Player manual

docs/MANUAL.md, chapter on the two-layer game / battles: how command posts set the command points of a battle (4 at full integrity, never below 1; a side with no command post is not penalised), how airfields set the fire-support missions (2 at full integrity, 0 when badly damaged), what the notice lines mean, how to call fire support (button, target mode, one mission per turn, no command point, no counter-fire, needs a visible target), and that auto-resolve uses the same conditions. Numbers from `data/battle/conditions.tres`.

## Out of scope

- Ammunition and morale display (TASK-081, TASK-090); AI calling fire support; changing the rules (TASK-099a).

## Implementation notes

- `ConditionsModel` (notice lines, reduced flags vs `BattleConditionsRules.shipped()`) and `FireSupportModel` (counter, button problem, visible targets, click -> command, report text), both pure in `src/presentation/`; tests in `test_battle_conditions_view.gd`, `test_battle_hud.gd`, `test_staff_map_contacts.gd`.
- `StaffMapContactNotice`: two condition lines per side card. `BattleHud`: Fire support action-bar button (key F, badge = missions left, tooltip carries the reason when off), hidden unless the setup gave missions (`set_fire_support_start`); the end banner appends "FIRE SUPPORT USED n".
- `BattleController`: target mode (`toggle_fire_support`, `cancel_fire_support`, `fire_support_click`), Esc / RMB cancel, rejection toasts, `fire_support_used` playback (craters + scorch, impact sound, hit feedback via `target_hp`, added to the event and ARCHITECTURE). `_play_attack` split out of `_play_event` for the lint return limit.
- Not covered by a test: the controller wiring itself (no controller test harness exists); its click logic is `FireSupportModel.click_command`. README screenshot not refreshed: the shipped battle scenario has no missions, so the battle scene looks the same. Not seen in the running game.
- Change (human, 2026-11-13): the contact notice shows only the Fire support line (`ConditionsModel.command_text`/`command_reduced` removed); the turn bar shows `ORDERS LEFT n / N` (`StaffMapOrders.orders_left_text`) and the order ring/toast shows `no_orders_left`.
