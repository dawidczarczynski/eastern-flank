# TASK-148b: Operational journal (2/2, view): the JRN window on the staff map

- **Status**: done
- **Layers**: presentation
- **Depends on**: hard TASK-148a
- **Topic**: Two-layer game
- **Sections**: `docs/design/operational_map/operational_journal.html` + README "Operational journal" (accepted variant A, follow it), `bottom_bar_windows.html`
- **Model**: sonnet

## Goal

The player opens the journal (bottom bar **JRN**, key **J**) and reads what happened to their side, turn by turn with dates, in their own words.

## Acceptance criteria (testable)

- [ ] `StaffMapJournalWindow` extends `StaffMapWindow` (width `WIDTH_REPORT`, left dock, tab "JOURNAL · <side>" in the side colour, X); looks as the mockup: filter chips, sticky turn headers (`TURN n`, `NOW`, date from `OperationalClock.date` + DAY / NIGHT range), entry rows (side shape, tag, sentence, place line), newest turn first, list scrolls (430 px viewport).
- [ ] Pure `StaffMapJournalText` builds the sentence of every kind of TASK-148a from `(entry, viewer)` in the viewer's words: own actor "We / Our …", enemy "Enemy …", never NATO / Russia; strike outcome words hit / intercepted / destroyed with the strike colours; place names via the existing place namer (fallback hex). Unit tests: one per kind, once as side 0 and once as side 1 (the wording flips); a political line never names who decided.
- [ ] Chips filter by category (ALL default; STRIKES, BATTLES, MOVES, POLITICS); empty state text "Nothing has happened yet…"; empty filter result "Nothing under this filter".
- [ ] Bottom bar button JRN (lit while open), key J, Esc and X close it; one left window at a time (`LeftWindow`); J no longer toggles strike cards: the strike chip / card opens the journal at its strike entry with **Enter** or a click (`StaffMapStrikeReports.handle_key` updated, hint text "↵ Log" in the card).
- [ ] Click on an entry with a place centres the map there and rings the hex for 2 s; hover = white 7 %; entries added since the window was last closed have a 3 px amber left bar until hovered; the window opens scrolled to the current turn.
- [ ] Rebuilt only on open and on new operational events while open (no per-frame work); a long operation (500 entries) opens in < 50 ms in a test; 60 FPS unaffected.
- [ ] Reads only `OperationalJournal.entries_for(viewed player)` (rule 3: no rules in the view); the viewed player flips with the hot-seat viewer like the other panels.
- [ ] docs/MANUAL.md: new "Journal" paragraph and the changed J / Enter keys; `tools/check.sh` passes; `tools/readme_screenshot.sh` not needed unless the default view changes.

## Playtest (for the human)

1. Start Suwałki Gap, issue a few orders, end the turn: press J / click JRN – our moves are listed under TURN 1 with the date.
2. Launch a strike: the card appears; press Enter on it – the journal opens at the strike line; the wording is "We struck…".
3. Play on until the enemy strikes or a contact appears: "Enemy … on our …" lines appear; enemy moves far away do not.
4. Switch the filter chips; click an entry – the map centres on it; close with J / Esc / X.
5. Play as the other side: the same events read from that side.

## Player manual

"Journal" (what it lists, what it hides, keys).

## Out of scope

- New events or rules; search; export; the battle's own log.

## Implementation notes

- New: `src/presentation/operational/staff_map_journal_text.gd` (pure sentences / tags / shapes / turn header), `staff_map_journal_window.gd` (window, chips, lazy rows, sticky header, unseen bars), `staff_map_journal_ring.gd` (2 s hex ring); tests `test_staff_map_journal_text.gd`, `test_staff_map_journal_window.gd`.
- Changed: `staff_map.gd` (JRN button, J, Esc, left dock `LeftWindow.JOURNAL`, dirty-flag rebuild in `_process`, hot-seat flip, strike -> journal), `staff_map_strike_reports.gd` / `staff_map_strike_report.gd` / `staff_map_strike_text.gd` (J removed, Enter / click emits `log_requested`, model carries `turn` + `coord`, footer "↵ Log"), `action_icons.gd` (`journal` icon), `assets/i18n/strings.csv`, `tools/screenshot.gd` (token `journal[:chip]`), MANUAL, ARCHITECTURE, three strike tests (J no longer toggles).
- Rows are built a page (40 entries) at a time, newest first; 500 entries open in well under 50 ms (test). The list height is estimated, then fitted to the real layout one frame later.
- Deviations from the mockup: the sticky header is a copy shown over the list once its own header scrolled away; strength / integrity change is appended to the strike sentence only when it fell; a destroyed formation's name is gone from the state, so those lines read "Our / Enemy formation was destroyed" (need for gameplay-engineer: store `name` in the `formation_destroyed` journal args); the unseen bar replaces the row divider while shown (one border colour per box); PL translations of the sentences are rough templates.
- `OperationalState.start_date` empty: the header shows only DAY / NIGHT.
