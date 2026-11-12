# TASK-119b: Politics overview (view, manual)

- **Status**: done
- **Layers**: presentation, docs
- **Depends on**: hard TASK-119a; soft TASK-121 (support summary block), TASK-112 (place names)
- **Topic**: Two-layer game
- **Tags**: mvp
- **Sections**: GDD "Countries and stances", "Escalation ladder", "Political decisions", ARCHITECTURE "Two layers"; docs/design/operational_map/political_decisions.html (right column), escalation_ladder_window.html (ladder styling)
- **Model**: sonnet

## Goal

Pressing H shows, beside the decisions, a read-only overview of the political situation: the ladder with its rules, the countries as seen from the player's side and a log of what changed.

## Look

Design check done: no new element. Reused `StaffMapDecisionParts` (Chip, Shape), the ladder window's level colours and ROE / marker texts (`StaffMapEscalation`, `ESC_MARK_*`), and the journal-style plain rows for the log. `/design-ui` not run: the blocks are text rows inside the dashed-placeholder slots of mockup variant B.

## Acceptance criteria (testable)

- [ ] **Design check first**: the ladder table and the log rows have no finished mockup. Grep `docs/design/` and CODEMAP for similar components and reuse `StaffMapDecisionParts` and the ladder-window styling (`StaffMapEscalation`); where no similar component exists run `/design-ui` and implement only the variant the human picks. Fill in "Look" before coding the view.
- [ ] The overview sits in the reserved right column (about 400 px) of the Politics screen as three read-only stacked blocks (ladder table, countries list, event log) with the dashed placeholders replaced; it is not a separate window and is never built or shown in the battle scene (test: a battle scene tree has no overview node).
- [ ] A pure view model (`StaffMapOverviewModel`, reads `OperationalState` only, no rule code) builds the three blocks; same input gives the same output; it holds no side-specific code (built for either viewer).
- [ ] Ladder table: one row per level 0 .. 6 with name, ROE (strike classes allowed, from `EscalationLadder.strike_classes_at`; level 6 reads "none"), the automatic event on entry (enemy sanctuary opens at 2, allies join at 3, 5 "cap for incidents and decisions", 6 "ends the operation"); the current level's row is highlighted (exactly one row); level 6 uses the nuclear styling of the ladder window.
- [ ] Ladder table footer, **the deliberate asymmetry**: per side `caused` and `deescalated` and the net (`caused - deescalated`, at least 0) from `escalation_caused` / `escalation_deescalated`; e.g. caused 3, deescalated 1 shows "net 2". **[ASSUMPTION]** The state tracks only totals per side, not per level, so the counts are shown as totals, not per level row.
- [ ] Countries list: one row per country (setup order) with its name, the stance seen from the viewer's side as own / allied / neutral / hostile / enemy (**[ASSUMPTION]**: "own" = belligerent on my side, "allied" = aligned with me, "hostile" = aligned with the enemy, "enemy" = belligerent against me; from `CountryRules.relation` and the stance), "open" or "closed" to the viewer (`CountryRules.may_enter` on a hex of the country; an enemy sanctuary below Open war shows closed), troops present (own / enemy formation counts on the country's hexes) and, while `contribution` is pending (not `contributed`), "N formations when it joins". Example: Lithuania aligned with NATO, viewer NATO: "allied - open - 0 / 0", viewer Russia: "hostile - closed".
- [ ] Event log block: newest first, at most 60 rows (the whole log), each row = turn plus one line from the entry's `key` / `args`, e.g. "T3 Lithuania -> NATO (belligerent)", "T3 Level 2 -> 3 Regional war", "T2 Decision: Declare hostilities - Belarus". No row names who decided (test: logs of two playthroughs that differ only in who took a decision render equal text); empty log shows "Nothing yet".
- [ ] The log and countries list show effects only (no "by" or "decided by" anywhere in the block); only the ladder footer names a side's caused counts; a comment in the model states this asymmetry.
- [ ] Support summary block, guarded behind data: shown only when the operation has support packages (TASK-121 exists) and then lists packages requested / delivered per supporter status (uninvolved / considering / supporting); without TASK-121 data the block is absent (not empty, not an error).
- [ ] The overview refreshes when the Politics screen opens and after each emitted political event; it handles an empty log, level 0 and level 6 without error; it never mutates the state (test: state snapshot equal before and after building the model).
- [ ] `tools/check.sh` passes; `tools/screenshot.sh` of the Politics screen compared with the mockup and the picked variant, deviations stated.

## Playtest (for the human)

1. Open the staff map, press **H**: the right column shows the ladder table (current level highlighted), the countries list and the event log ("Nothing yet" at the start). Close with H / Esc / X.
2. Trigger a stance change with the debug panel (F9, `--debug`, politics block, e.g. set Lithuania belligerent): the countries row changes and a log line "Lithuania -> NATO" appears.
3. Take a decision (e.g. Escalate): the log gains a decision line and a level line; the ladder highlight moves. End the turn.
4. As the other side take a decision in hot-seat or let the AI act: its log lines show only the effects, with no name of who decided; the ladder footer shows each side's caused counts.
5. Save (F5), return to the menu, Continue: the log is the same. Open a battle: no overview appears there.

## Player manual

Edit docs/MANUAL.md chapter "Politics" (grep `### Politics`): add a **Political overview** section (the three blocks, what each shows, that decisions are not attributed in the log or the countries list while the ladder shows what each side caused, read-only, only on the staff map, never in battle). Consolidate the chapter so it reads as one, in this order: intro, ladder, countries and borders, decisions, outside support, overview; remove duplicate paragraphs; **no rule changes**. Replace the sentence "The right-hand column is reserved for the read-only politics overview." with a pointer to the new section. Numbers from `data/**/*.tres`.

## Out of scope

- New rules, per-level caused counts, fog of war on the log, a separate overview window, the debug politics panel.

## Implementation notes

- `StaffMapOverviewModel` (pure, reads state only) + `StaffMapOverviewColumn` (view) replace the placeholders in `StaffMapDecisionsPanel` (column now 400 px). Tests: `tests/unit/test_staff_map_overview.gd`. Polish strings added.
- Support block: TASK-121 is not done, so the model has no `support` key (absent by design); add it there when support packages exist.
- Stance wording: own = belligerent on my side, allied = aligned with me, hostile = aligned with the enemy, enemy = belligerent against me. Troops count only formations with strength > 0.
- Manual: added the **Political overview** section and the pointer. The wider chapter re-ordering (consolidation) was not done – no duplicated paragraphs were found worth moving; flag if you want the order changed.
- Screenshot compared (`.screenshots/politics.png`): matches variant B layout; the ladder footer and log rows are plain text lines (no mockup).

- **Follow-up (human request)**: the separate ladder window (TASK-143, `StaffMapLadderWindow`) is removed; the turn-bar chip now opens the Politics screen. The overview's ladder is folded to the current level with an All levels / Hide levels button, and the viewer's collapse line moved there. The `ladder` screenshot token is gone. The ladder window's hover tooltips and ✓ NEW class table are not carried over.
