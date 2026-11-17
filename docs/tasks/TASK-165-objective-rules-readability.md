# TASK-165: Operation objectives: make the scoring rule readable and announce flips

- **Status**: done
- **Layers**: core + presentation
- **Depends on**: TASK-164 (done)
- **Sections**: GDD "Sides" (bullet Victory), ARCHITECTURE "Events", ARCHITECTURE "Two layers" (operational journal)
- **Model**: sonnet

## Goal

The player can read in the objectives window when each objective is scored (at the end vs. a win after N consecutive rounds), sees the Gap's closed-round progress, and is told by a toast and a journal entry whenever an objective changes state (either side).

## Rules as they are (no change)

- Hex objectives (Chernyakhovsk 5, Białystok 5, Vilnius 5, Grodno 40) are scored only at the end, after round 30 (`round_limit`); draw margin 5.
- The Gap (open = 10 NATO / closed = 10 Russia) is scored at the end too, but Russia also wins at once after 2 consecutive closed rounds (`closed_rounds_to_win`, `gap_closed_rounds`, advanced/reset in `OperationVictory.end_round`). Any chain hex lost resets the counter.

## Acceptance criteria (testable)

Core:
- [ ] New event `objective_changed` (add to the ARCHITECTURE events table) with `kind` (`holder`, `gap`, `gap_counter`), `objective_id`, `old`, `new`, `round`; emitted by `OperationalSimulation.execute` / end of round, never by the view.
- [ ] Objective hex Grodno moves from NATO to Russia (move or won battle): exactly one `objective_changed` {kind `holder`, old NATO, new Russia}; a move that leaves the holder unchanged emits none.
- [ ] One move that takes two objective hexes emits two events (one per hex).
- [ ] Russia takes the last open chain hex: one event {kind `gap`, old `open`, new `closed`}; losing one chain hex afterwards: {`closed` -> `open`}.
- [ ] End of round with the chain closed: `gap_counter` event with new = 1 (then 2 ends the operation with `gap_closed`; the counter event for 2 is still emitted before the end notice); chain broken -> counter 1 to 0 emits `gap_counter` {old 1, new 0}; a counter 0 -> 0 emits nothing.
- [ ] Events carry no side wording; both sides get the same events. Determinism untouched: same seed and commands give an identical event list (test with two runs).
- [ ] Journal: new kind `objective` in `OperationalJournal.KINDS`, category `move` **[ASSUMPTION]** (smallest change; no new filter button), recorded for both sides (not hidden by fog); one entry per `objective_changed`, with the round number.
- [ ] Save/load: journal entries of the new kind survive a round trip.

Presentation:
- [ ] `StaffMapObjectivesModel` rows get a `rule` string: hex objective -> "Scored at the end, round 30" (30 from `round_limit`); Gap -> "Russia wins after 2 consecutive closed rounds; otherwise scored at the end" (2 from `closed_rounds_to_win`); numbers read from the operation data, not hard-coded.
- [ ] The Gap row has `progress` "Closed 1/2 rounds" from `gap_closed_rounds` / `closed_rounds_to_win`; with counter 0 it reads "Closed 0/2 rounds"; a hint line "Any chain hex lost resets it" is shown while the counter is above 0.
- [ ] Wording is viewer-relative: for a NATO viewer the Gap progress reads as a threat ("Russia: closed 1/2 rounds - break the chain"), for a Russian viewer as a goal ("Hold it 1 more round"); same rule line for both.
- [ ] The window refreshes live on `objective_changed` (open window shows the new holder/counter without reopening).
- [ ] Toast per event, viewer-relative: "Grodno taken by Russia" / "Grodno taken by you"; "The Gap is closed" / "The Gap is open again"; "Gap closed - 1/2 rounds, hold it one more round" (Russian viewer) / "Russia holds the Gap - 1/2 rounds, break the chain" (NATO viewer); "Gap chain broken - counter reset". Texts are the designer's proposal, in `strings.csv` with translation keys like other UI text.
- [ ] Several events from one action show as separate toasts in order (existing toast queue behaviour; no new toast look).
- [ ] Model and toast text builders are pure functions with unit tests for both viewer sides (strings checked for NATO and Russia).
- [ ] Layout: reuse the existing objectives window parts; the rule line is a second, smaller text line per row; check `docs/design/operational_map/` (README, `terrain_control.html`) and report any deviation; no new look.

## Playtest (for the human)

1. Start an operation, open the objectives window with O: every row has a rule line; the Gap row shows "Closed 0/2 rounds".
2. Take an objective hex with a formation (or let the AI do it): a toast appears at once ("... taken by ...") and the journal (move category) has an entry with the round; the open window updates its holder.
3. Close the Gap chain (as Russia, or watch the AI do it) and end the round: toast "Gap closed - 1/2 rounds" and the counter shows 1/2; break a chain hex, end the round: counter back to 0 with a reset toast.
4. Hold the chain 2 rounds in a row: operation ends with the Gap-closed notice (unchanged).
5. Play once as NATO and once as Russia: wording is from your point of view.

## Player manual

docs/MANUAL.md section 12c: add that the objectives window gives each objective's rule ("scored at the end, round 30"; the Gap's "2 consecutive closed rounds" win) and the Gap's closed-round counter, that any chain hex lost resets it, and that every change of an objective (hex holder, Gap open/closed, counter) shows a toast and a journal entry for both sides. Mention the O window if section 12b does not.

## Out of scope

- Changing victory rules or scoring numbers.
- Score forecast / projection of the current totals.
- AI changes.
- Battle-layer objectives (the 8-turn objective battle).

## Decisions

- 2026-11-17 (human): layout "rule line + counter per objective" in the existing window.
- 2026-11-17 (human): flip feedback = toast and journal entry.
- 2026-11-17 (human): scope = all changes of either side, viewer-relative wording (holder change, Gap close/reopen, counter advance/reset).

## Size

Core ~4 files (event emission, journal kind, tests, ARCHITECTURE row) and presentation ~5 files (model, window, toast text, strings.csv, tests): within one session, ~300 lines per layer. If it overruns, split presentation into 165b (window rule lines) and 165c (toast + journal text).

## Implementation notes

Done in core + presentation, `tools/check.sh` green. `objective_changed` extended (kept hex/holder/previous; added kind holder|gap|gap_counter, objective_id, old, new, round); `HexControl.take` emits per objective hex, `OperationalSimulation` inserts the `gap` event, `OperationVictory.end_round` the `gap_counter`; journal kind `objective` (category move, both sides). Objectives window rows have rule / progress / hint lines (`StaffMapObjectivesModel`); toasts via new `Toast.enqueue()` + `shown` signal. Deviations: journal text says "us / the enemy" (journal tests forbid naming blocs); Russian hint "hold it one more round". Layout: `docs/design/operational_map/` has no objectives-window mockup, so only existing parts are reused (mono 10 small lines, amber progress); not seen in game. Known: small-line width is a fixed 240 px minimum. docs/design terrain_control.html still mentions `objective_changed` as a rebuild trigger (the layer actually hashes `hex_holders`).
