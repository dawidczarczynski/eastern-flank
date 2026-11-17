# TASK-175a: Objectives window redesign (main / side), 5-round Gap rule, click to centre

- **Status**: ready
- **Layers**: core (data only) + presentation
- **Depends on**: TASK-165
- **Topic**: Two-layer game
- **Sections**: GDD "Sides" (Victory / Endings, Objective tiers), docs/design/operational_map/objectives_window.html, docs/design/operational_map/README.md (last paragraph "Objectives window and layer")
- **Model**: sonnet

## Goal

The player sees which objective decides the operation (the Gap road, held closed 5 rounds in a row) and which only add points at the end, in a readable window, and can click an objective to jump to it.

Design (human, 2026-11-17): variant A of `objectives_window.html`; split from TASK-175 on 2026-11-17.

## Acceptance criteria (testable)

Part 1 - rule and data
- [ ] `data/operations/suwalki_gap.tres`: `closed_rounds_to_win` = 5 (resource only; default in `operation_definition.gd` also 5).
- [ ] Tests assuming 2 are fixed: `test_operation_victory.gd` (`assert_eq(def.closed_rounds_to_win, 2)` and `test_closed_rounds_to_win`: chain held at the end of rounds 7-11 -> `operation_ended` winner 1, reason `gap_closed` after round 11; held 4 rounds then lost -> no ending, counter 0), `test_objective_events.gd`, `test_staff_map_objectives.gd` read the value from data (no literal 2).
- [ ] Gap held for 4 rounds in a row: no ending, counter 4; the 5th closed round ends it with reason `gap_closed`; Gap closed at the end of round 30 with counter 3: not an instant win, scored 10 for Russia.
- [ ] `tools/simulate.sh` AI vs AI (at least 20 matches per `--seed` set, report seeds and N): share of wins per side among decided operations is 40-60 %. If outside, write the numbers in Implementation notes and report; do NOT retune silently.

Part 2 - window (`StaffMapObjectivesModel`, `StaffMapObjectivesWindow`)
- [ ] Rows carry `hex`, `chain` (Gap only: ordered hexes), `tier` (`main` / `side`), `selected` (bool); exactly 1 row is `main` (the Gap), 4 are `side`.
- [ ] Main card title: NATO viewer "Keep the Gap road open", Russian viewer "Connect Kaliningrad with Belarus"; chain bar text "n of 13 held by Russia" (13 and n from data/state); progress "n / 5" with a 5-segment bar filled n segments (n from `gap_closed_rounds`, 5 from `closed_rounds_to_win`); rule text states "5 rounds in a row" from data.
- [ ] Side section header reads "Side objectives - scored at the end, round 30" (30 from `round_limit`).
- [ ] Row: holder shape (own rectangle / enemy diamond / neutral circle), name, chip HELD BY US / HELD BY ENEMY / NOBODY, points; holder colours are `side.own` / `side.enemy` (the old HP green/red is removed).
- [ ] "Scores for" sub-line only on the viewer's own objectives; enemy rows are muted, points muted, tagged "ENEMY". Tested for both viewers (NATO and Russia) with the same state.
- [ ] Window width 420 (`StaffMapWindow.WIDTH_REPORT`); each row is a button; Up/Down move the selection (wraps at the ends), Enter activates it; selected row has the amber 12 % background and 3 px bar.
- [ ] All new strings in `assets/i18n/strings.csv` with a Polish translation; texts built by pure functions, no literals in the view.

Part 3 - click to centre
- [ ] Click (or Enter) on a row emits the same centre request as a journal-entry click; camera eases 300 ms to the hex, zoom at least Z1 (never zooms out), target kept inside the clear zone (not under open windows).
- [ ] The Gap row fits the whole chain (all 13 hexes visible) instead of a single hex.
- [ ] A `StaffMapJournalRing` (r 30) pulses 2 s on the hex, then a 1.6 px hex outline stays while the row is selected; closing the window or selecting another row removes it.

## Design check

Compare a screenshot / render with `docs/design/operational_map/objectives_window.html` (variant A) and state every deviation and why in Implementation notes.

## Playtest (for the human)

1. Start as NATO, press O: Main card "Keep the Gap road open" with the chain bar and "0 / 5"; below it four side rows; enemy rows muted with ENEMY. Restart as Russia: title "Connect Kaliningrad with Belarus".
2. Up/Down/Enter and mouse click a row: camera glides to the hex (not under the window), ring pulses 2 s, outline stays; Gap row frames the whole chain.
5. Hold the whole chain as Russia: counter 1/5 ... 5/5, the operation ends after the fifth closed round; losing a chain hex resets it to 0.
6. Check texts in Polish.

## Player manual

docs/MANUAL.md 12b: objectives window (O) with the main / side split and click-to-centre. 12c: Gap win after **5** rounds in a row (replace "2 full rounds"); fix the "2 consecutive closed rounds" / "Closed 1/2 rounds" mentions in 12b (line ~749).

## Out of scope

- Score forecast / variant B score strip.
- Edge arrows for off-screen objectives.
- New victory rules beyond the 5-round count; scoring changes (Gap 10 points at the end stays).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
