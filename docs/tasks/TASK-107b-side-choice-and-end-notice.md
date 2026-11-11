# TASK-107b: Side choice at the start of an operation and the end-of-operation notice

- **Status**: blocked
- **Layers**: presentation / docs
- **Depends on**: TASK-107a (hard)
- **Topic**: Two-layer game
- **Tags**: mvp
- **Sections**: GDD "Sides" (side choice, Victory bullet), "Escalation ladder" (notice after the end); grep docs/CODEMAP.md for `main_menu`, `MenuStyle`, `StaffMap`, `StaffMapEscalation`, `CampaignRecord`; grep `operation_ended` in `src/presentation/operational`; docs/design (grep main_menu, notice)
- **Model**: sonnet

## Goal

The player picks NATO or Russia when starting an operation and, when it ends, sees Victory / Defeat / Draw with the reason and the points table. Second part of TASK-107 (split 2026-11-11).

## Decisions (human interview, 2026-11-11)

- The side choice stays **outside the operational state** (session + `CampaignRecord`); the operation and its replay are the same for both choices.
- A NATO / Russia chooser in the main-menu start flow **before "New operation"**; **NATO is listed first**; the `--side` flag keeps working (it preselects / overrides the chooser). Reuse `MenuStyle` and the main-menu buttons.
- The end notice reuses the existing end-of-operation notice (the one that handles `operation_ended`): headline Victory / Defeat / Draw for the human's side, the ending reason, the points table, the round count; buttons **Back to menu** / **Review map**.
- **[ASSUMPTION]** `nuclear_use` is shown as "Defeat for Russia, nobody wins": headline Defeat for a human playing Russia, and for a human playing NATO the headline is "Nobody wins" (winner −1 is neither Victory nor Draw).

## Acceptance criteria (testable)

- [ ] **Design check first**: grep `docs/design/` for a side chooser and for an end-notice points table; if one is missing, run `/design-ui` and implement only the variant the human picks; record the mockup used (or the picked variant) in Implementation notes.
- [ ] The chooser lists exactly two entries, NATO first then Russia (order test on the entry list), each showing the side's name and lead-faction colour from `SideDefinition` data (no literal side names in code).
- [ ] Choosing Russia and starting stores side 1 in the session and in the `CampaignRecord`; the operational state's `to_dict()` is byte-identical for both choices (test); the staff map is built from side 1's point of view.
- [ ] `--side=russia` (and the existing `--side` values) start the operation as before without showing the chooser; an unknown value falls back to the chooser (no crash).
- [ ] A saved campaign loads with the side it was started with; a record without a stored side loads as NATO (side 0).
- [ ] The end notice appears on `operation_ended` for every reason (`gap_closed`, `round_limit`, `nuclear_use`, the existing ones); headline for the human's side: winner = own side → Victory, other side → Defeat, −1 from `round_limit` → Draw, −1 from `nuclear_use` → "Nobody wins" (view-model test on a pure text function per case).
- [ ] The ending reason line has a text for each reason code (i18n keys in `assets/i18n/strings.csv`); an unknown reason shows a generic line, not a missing key.
- [ ] The points table shows, per side, the held objectives with their points, the escalation penalty (e.g. "−6") and the total, plus the round count; values come from the `score` payload (test: payload NATO 14 / Russia 10 → rows and totals text).
- [ ] The notice has the buttons **Back to menu** and **Review map**; *Review map* closes the notice and leaves the map readable with no command accepted (`operation_over`); *Back to menu* returns to the main menu.
- [ ] The notice appears once per ended operation (a second `operation_ended` or a reload of an ended record does not stack a second one); the nuclear ending keeps its existing grey-out sequence before the notice.
- [ ] i18n keys added for the chooser, headlines, reasons and table labels; no hard-coded English strings in the new code.
- [ ] docs/MANUAL.md updated (see Player manual); `tools/check.sh` passes.

## Playtest (for the human)

1. Start the game, open the start flow: NATO is listed first; pick Russia and start the operation – the map is shown from Russia's side, Russia moves first.
2. Play or end turns until the round limit (use the debug option or end turns repeatedly), or set up a Gap closure.
3. At the end check: headline for your side, the reason, the points table (objectives, escalation penalty, total) and the round count.
4. *Review map* leaves the map visible, no orders possible; *Back to menu* returns to the main menu.
5. Run once more with `--side=nato` and confirm the chooser is skipped.

## Player manual

Add to docs/MANUAL.md: a section on starting an operation (choosing the side, NATO listed first, what the choice does and does not change), a section on objectives and scoring (who holds a hex, the Gap road link open / closed, points per objective, −3 per net escalation step, the 30-round limit, the instant Russian win after 2 rounds with the Gap closed, the draw margin of 5, the nuclear ending) with numbers from `data/operations/suwalki_gap.tres`, and a section on the end notice (headline, reason, points table, buttons).

## Out of scope

- Core rules and data (TASK-107a); a mid-operation side switch; campaign / multi-operation flow; new endings.

## Implementation notes

_Filled in by the agent when done: mockup used, decisions, known limitations._
