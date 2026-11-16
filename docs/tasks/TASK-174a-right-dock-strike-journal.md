# TASK-174a: Right-hand tabbed dock (framework + STRIKE and JOURNAL tabs) that shrinks the map

- **Status**: done
- **Layers**: presentation
- **Depends on**: TASK-150 (soft: TASK-162)
- **Sections**: docs/design/operational_map/README.md "Slide-in side panels", "Docked windows", "HUD clear zone"; docs/design/operational_map/slide_in_panels.html (variant B); TASK-150 and TASK-162 implementation notes
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

Strike and journal no longer cover the map: they live in one tabbed dock on the right edge, and the map is re-centred on the remaining free area, so no target, unit or marker is hidden under them. This task builds the dock framework; the POLITICS tab follows in TASK-174b.

## Decisions (human, 2026-11-16)

1. Design variant B: ONE tabbed dock on the right edge, 420 px wide, between the turn bar (92 px) and the bottom bar (76 px), `StaffMapWindow` frame, vertical tabs 30x96 px (STRIKE / POLITICS / JOURNAL; POLITICS is added by TASK-174b and is not shown here).
2. Strike, politics and journal EXCLUDE each other (never two at once). Slide 200 ms ease-out, tab swap 120 ms fade, the camera keeps the centre of the visible map (no jump). Minimum map width = screen width minus the dock (1020 px at 1440).
3. Keys S / J and the bar buttons open the section or switch the tab; the key of the open tab closes the dock; Esc / X close; a click on the bare map does NOT close it.
4. The formation panel is unchanged. Selecting a unit (normal selection, the INFO ring, key I) CLOSES the dock. In strike mode a map click is a strike-target pick and never closes the dock. After a selection closed the dock it STAYS closed on deselect; it opens only by S / J or a bar button. The last open tab is remembered for the next open (within the session).
5. Other windows (objectives O, map options, country card, strike result report card, confirm cards) stay left docked windows / overlays unchanged.
6. Split: this task = dock framework + STRIKE and JOURNAL tabs + camera / inset integration; the politics sheet is UNCHANGED here (key H still opens the full-screen sheet).
7. **[ASSUMPTION]** Map resize works like the existing clear-zone logic: the map renders full width and the camera re-centres on the free rectangle (right inset = dock width) with the 200 ms slide, no zoom change.
8. **[ASSUMPTION]** Opening the dock while the left dock is busy is allowed (both sides can be occupied). If the formation panel is open on the right, selecting the unit already closed the dock, so there is no conflict.
9. **[ASSUMPTION]** Leaving strike mode (S, X, Esc) closes the dock tab.

## Acceptance criteria (testable)

- [ ] Dock model (pure class, no Node): `open(tab)` -> open with that tab; `open(other)` while open -> same dock, tab switched, never two sections; `close()` -> closed.
- [ ] Pressing the key of the open tab (S on STRIKE, J on JOURNAL) closes the dock; pressing the other key switches the tab.
- [ ] Dock open: right inset is 420 (>= 420 at a 1440 px viewport) and the visible map width is 1020; closed: right inset 0 (no regression).
- [ ] Minimum map width equals viewport width minus 420 (1020 at 1440), also at 1920 (1500).
- [ ] Opening with J while strike mode is open switches to JOURNAL and leaves strike mode; the opposite switch re-enters strike mode (never two sections active).
- [ ] Esc and X close the dock; a click on the bare map (not in strike mode) leaves it open.
- [ ] Selecting a unit (selection, INFO ring, key I) closes the dock; in strike mode a map click picks a strike target and the dock stays open.
- [ ] After a selection closed the dock, deselecting does not reopen it; S / J / bar button opens it.
- [ ] Last open tab is remembered: open JOURNAL, close, press the bar button of the dock again -> JOURNAL (default STRIKE on first open).
- [ ] The camera keeps the centre of the visible map on open and on close (centre shift 0 px apart from the 200 ms ease); the 200 ms ease ends exactly at the target inset.
- [ ] TASK-162 preserved: with the dock open the eastmost strike target (Lida) is inside the clear zone (reachable by panning).
- [ ] The strike-panel special case is removed: no `StaffMapCameraMath.right_inset` use for the strike panel and no `covered_rects` feed in `_clear_insets()`; the TASK-150 right inset is taken from the dock for these sections.
- [ ] The journal no longer claims the left dock (`LeftWindow.JOURNAL` gone): opening the journal while objectives (O) is open leaves objectives visible on the left.
- [ ] The politics sheet (key H) still opens full screen and is unaffected; no POLITICS tab is shown.

## Playtest (for the human)

1. Open the staff map, press S: a 420 px dock slides in from the right (about 0.2 s); the map is not covered and the view does not jump.
2. Press J: the content swaps with a short fade, the dock stays put; press J again: it closes and the map slides back.
3. Click the vertical tabs and the bar buttons: each opens or switches the section; the lit button shows the open section.
4. In strike mode pan to the eastmost target (Lida): it is reachable and visible next to the dock.
5. Click bare map with the dock open: it stays open. Esc or X closes it.
6. Open the dock, select a unit: the dock closes and the formation panel appears as before. Deselect: the dock stays closed. Press J: the last tab (JOURNAL) comes back.
7. Open objectives (O) on the left and then the journal: both stay visible.
8. Press H: the full-screen politics sheet still works as before.

## Player manual

docs/MANUAL.md "Deep strikes" and the Journal lines (keys table ~line 408): the strike panel and the journal sit in one tab dock on the right edge that shrinks the map; S / J (bar buttons) open or switch, the same key closes, Esc or X close, a click on the map does not; selecting a unit closes the dock; the last tab is remembered. Politics (H) is unchanged until TASK-174b.

## Out of scope

- The POLITICS tab and retiring the politics sheet (TASK-174b).
- The formation panel, objectives, map options, country card, report and confirm cards, battle screen.
- The Escalation ladder (stays a full-screen sheet).
- Saving the last tab beyond the session.

## Implementation notes

- Pure model `StaffMapRightDock` (`Tab { STRIKE, JOURNAL }`, `WIDTH` 420, `open` / `toggle` / `close`, remembered tab, `on_selection(strike_mode)`, `inset()`, `min_map_width(viewport_x)`); tests `tests/unit/test_staff_map_right_dock.gd`.
- View `StaffMapRightDockView`: a full-viewport click-through holder (slid by `set_progress`) with the section panels and the vertical tab strip (30 x 96, `DockTab`, 120 ms `fade_in` on a tab swap). The strike panel and the journal window are reparented into it unchanged (rows, card, chips untouched); `StaffMapWindow.Dock.TABBED` places them flush right at y 92, as tall as the free area (viewport - 92 - bottom bar).
- `StaffMap`: `_dock` model, `_dock_changed` brings panels, tabs, bar lights and the slide in line; `_animate_dock` tweens the animated inset `_dock_inset` 0..420 (200 ms cubic ease-out) and `_set_dock_inset` shifts the camera by half of each step, so the centre of the visible map stays; `_clear_insets()` right = max(window insets, `_dock_inset`); `_move_camera` passes the dock inset to `StaffMapCameraMath.clamp_position(..., dock_right)` (a narrow theatre is centred beside the dock); `_update_limits()` uses `min_map_width`, so the minimum zoom is the same open or closed (no zoom jump).
- Sync both ways: S (handled by `StaffMapStrikeHud`) and the strike panel's X go through `open_changed`, which opens / closes the STRIKE tab; J, the bar buttons, tabs, Esc (`_close_dock_key`), the journal X go through `open_journal` / `close_dock`. Opening one section leaves the other (J leaves strike mode, S leaves the journal). `select_formation` (new non-empty selection) and `open_info` close the dock (`_close_dock_on_selection`, no-op in strike mode); a click on the bare map no longer touches it. Opening the dock closes a right-docked formation panel.
- TASK-162 special case removed: `StaffMapCameraMath.right_inset`, `StaffMapStrikeHud.covered_rects` and the `_clear_insets()` feed are gone (their tests replaced by `test_a_narrow_map_is_centred_in_the_area_beside_the_dock` and `test_eastmost_target_reaches_the_free_area_with_the_dock_inset` in `test_hud_clear_zone.gd`). `LeftWindow.JOURNAL` is gone: the journal no longer closes / is closed by left windows or the report (R); ladder (`_close_other_windows`) closes the dock.
- Changes in other classes: `StaffMapStrikeHud.layout` no longer positions the panel and the confirm card no longer hides it (the dock would be empty behind the card); `StaffMapJournalWindow.max_list_height` (was a constant) so the list may use the taller dock; `tools/screenshot.gd` calls `StaffMap.settle_dock()` (no frames run there, the slide tween would not advance).
- Tests: `tests/unit/test_staff_map_right_dock_view.gd` (keys, switching, Esc / X, selection / INFO, strike-mode selection, memory, left dock unaffected, flush-right placement, centre kept on open and close); `test_staff_map_journal_window.gd` updated (journal in the right dock, coexists with left windows, the strike card stays when the journal opens).
- Deviations from the mock: closing hides the section at once and only the map slides back (the section is not drawn sliding out; the strike hud hides its panel itself); the tab strip hides with it; on a window shorter than about 790 px the strike panel (content about 580 px + chrome) is taller than the free area and overlaps the bottom bar (fine at 1440 x 900); POLITICS tab not shown (TASK-174b).
- Known limitations: the slide tween and the fades are not covered by tests (the test map is outside the tree, so they jump to the end) - playtest.
- Review follow-up: while the dock is open (strike mode keeps it on a selection / INFO) the formation panel is forced to the LEFT dock (`_dock_panel_for`; test `test_info_in_strike_mode_docks_the_formation_panel_on_the_left`); redundant `_panel.show()` calls in the strike hud removed.
- The remembered tab (`remembered_tab` / `open_remembered`) is covered by model tests; the bar has separate STR and JRN buttons, so in the game it only shows through the tab strip. A generic "dock" button is not part of this task.
- Minimum zoom now keeps the map at least (screen - 420 px) wide even with the dock closed (criterion 4, no zoom jump on open): check the zoomed-out look at 1440 and 1920.
- Narrow windows (< ~1100 px wide, < ~790 px high): the strike confirm card is centred on the whole viewport and the dock may overlap it; the strike panel may overlap the bottom bar. Not handled here.
