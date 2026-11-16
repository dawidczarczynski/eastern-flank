# TASK-174b: POLITICS tab in the right dock (narrow column, retire the full-screen sheet)

- **Status**: done
- **Layers**: presentation
- **Depends on**: TASK-174a
- **Sections**: docs/design/operational_map/README.md "Slide-in side panels"; docs/design/operational_map/slide_in_panels.html (variant B); TASK-174a (dock framework)
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

The politics screen (decisions, overview, support) becomes the third tab of the right dock from TASK-174a instead of a full-screen sheet, so the map stays visible while the player makes political decisions.

## Decisions (human, 2026-11-16)

1. POLITICS is the third vertical tab (STRIKE / POLITICS / JOURNAL, 30x96 px); exclusion, slide, fade, tab memory, selection-closes-dock and Esc / X rules are those of TASK-174a.
2. Content: a single ~388 px column with sub-tabs DECISIONS / OVERVIEW / SUPPORT, fed by the same `StaffMapDecisionsModel` data (new narrow layout; no model change).
3. Key H (existing politics key) opens the tab; P stays the political tint toggle. The bar button opens it too; H on the open tab closes the dock.
4. The full-screen sheet (`StaffMapDecisionsPanel` / `StaffMapDecisionsHud` sheet layout, SHEET_MARGIN, the two-column layout with `StaffMapOverviewColumn` at 400 px) is retired. The Escalation ladder stays a full-screen sheet.

## Acceptance criteria (testable)

- [ ] POLITICS tab appears in the dock; opening it sets right inset 420 and map width 1020 at 1440 (same as TASK-174a).
- [ ] Dock model: `open(POLITICS)` while STRIKE or JOURNAL is open switches the tab; never two sections.
- [ ] Key H opens the dock on POLITICS; H again closes it; S / J while POLITICS is open switch the tab; P still toggles the political tint and does not open the dock.
- [ ] The column width is <= 388 px and fits inside the 420 px dock frame; no horizontal scroll bar at 1440x900.
- [ ] Three sub-tabs DECISIONS / OVERVIEW / SUPPORT; DECISIONS is shown first; each shows the same entries as the old sheet's matching part (same `StaffMapDecisionsModel` rows count in a test with the standard fixture).
- [ ] Choosing a decision card works from the narrow column (same command and result as before; test through the existing decision path).
- [ ] The last open top-level tab is remembered (POLITICS counts, as in TASK-174a); the sub-tab selection is kept while the dock is closed.
- [ ] Selecting a unit closes the dock (also on POLITICS); after deselect it stays closed.
- [ ] The full-screen politics sheet code is removed: no `SHEET_MARGIN`, no full-screen politics panel instance in `staff_map.gd`; grep finds no caller left.
- [ ] The Escalation ladder still opens as a full-screen sheet.
- [ ] No regression: all earlier politics tests (`StaffMapDecisionsModel`, support tab) pass.

## Playtest (for the human)

1. Press H: the dock slides in with POLITICS; the map stays visible and re-centres, no jump.
2. Switch the sub-tabs DECISIONS / OVERVIEW / SUPPORT: content fits the column, no text cut off at 1440x900.
3. Take a decision: it behaves as on the old sheet (cost, result, journal line).
4. Press S and J: the tab swaps with a fade; press H after closing: POLITICS (or the last tab) is remembered.
5. Press P: only the political tint toggles. Select a unit: the dock closes.
6. Open the Escalation ladder: still full screen.

## Player manual

docs/MANUAL.md politics section (key H): the politics screen is now the POLITICS tab of the right dock with sub-tabs DECISIONS / OVERVIEW / SUPPORT; the map stays visible and shrinks to the free area; H opens and closes, Esc or X close; selecting a unit closes it; P is still the tint toggle. Remove the wording about a full-screen sheet; the Escalation ladder stays full screen.

## Out of scope

- Dock framework, STRIKE and JOURNAL tabs (TASK-174a).
- Changes to decision rules, costs or the support model; the Escalation ladder; the formation panel; other windows; battle screen.

## Implementation notes

- `StaffMapRightDock.Tab` is now `{ STRIKE, POLITICS, JOURNAL }` (strip order). `StaffMapDecisionsPanel` is a `StaffMapWindow` (`Dock.TABBED`, dock width) registered in `StaffMapRightDockView` as the POLITICS section; scrim, `SHEET_MARGIN`, the title row, the two-column layout and `OVERVIEW_WIDTH` are gone. Sub-tabs DECISIONS / OVERVIEW / SUPPORT (`TAB_*`; SUPPORT only with packages; Tab cycles), each a single 388 px scrolling column from the same `StaffMapDecisionsModel` / `StaffMapOverviewModel` / `StaffMapSupportModel` data; the budget row and the country chips wrap (HFlowContainer); the overview's country rows are two-line.
- `StaffMapDecisionsHud` no longer owns a screen: `open()` fills the panel, `close()` / the X / Esc / H emit `close_requested`, which `StaffMap` turns into `close_dock()`. `StaffMap.toggle_decisions()` / `open_decisions()` mirror the journal (leave the strike mode, close the right info panel). `_modal_open()` no longer includes politics: the map stays live (wheel, drag, S / J / P work). `handle_key` consumes only the tab's own keys (Esc, H, Tab, 1-6, arrows, Enter) and returns false otherwise.
- Tests: `test_staff_map_right_dock.gd` (POLITICS in the model), `test_staff_map_right_dock_view.gd` (H / S / J / P / Esc / selection / sub-tabs / sub-tab memory), `test_politics_screen.gd` (the old "wheel idles the map" test now says the map stays live). Screenshot tool: `decisions:overview`.
- Manual updated (H, POLITICS tab, sub-tabs, no full-screen sheet; the Escalation ladder stays full screen).
- Known limitations: slide / fade not covered by tests; on windows shorter than about 790 px the content just scrolls. README gameplay shot unchanged (battle scene not affected).
