# TASK-164: Operation ends when one side is annihilated

- **Status**: done
- **Layers**: core (+ presentation: end-notice reason text only)
- **Depends on**: –
- **Sections**: GDD "Sides" (Victory > Endings bullet); ARCHITECTURE event table (`operation_ended` reasons); grep docs/CODEMAP.md for `OperationVictory`, `BattleConsequences`, `StrikeRules`, `StaffMapEndModel`, `OperationMatchRunner`
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

The operation ends at once, with a clear Victory / Defeat, when one side has no formations left on the map and none still due to arrive. Today a full operation did not end after all enemy units were destroyed (human playtest 2026-11-16).

## Decisions (2026-11-17, interview with the human)

- Annihilation alone ends the operation (no objectives required), symmetric for both sides. The survivor wins regardless of score: `winner` = `by` = survivor, reason `annihilation`.
- "Destroyed" = the side has no formation in `state.formations` (destroyed formations are erased from it, in `BattleConsequences.apply` and `StrikeRules`) AND no pending reinforcements (see below). A side that never fielded anything is not "destroyed".
- Presentation reuses the existing end notice and score table; only a new reason text. No new UI element.

## Rule (details, **[ASSUMPTION]** where marked)

- `OperationVictory.annihilation(state) -> Array[Dictionary]`: `wiped(side)` = `state.definition != null` AND `state.fielded_strength[side] > 0` AND no formation with `owner_id == side` in `state.formations` AND no pending support of that side. Pending support = a `SupportState` with `definition.side == side`, `requested()`, not `withdrawn`, and `waiting` not empty. Not-yet-requested packages do not count.
- **[ASSUMPTION]** Checked right after every command that can destroy a formation: at the end of `ResolveBattleCommand.apply` and of `StrikeCommand.execute` (after `StrikeRules.resolve`), so the operation ends the moment the last formation falls; also first thing in `OperationVictory.end_round` (covers a support package withdrawn at a round boundary). Does nothing when `state.result` is already set.
- **[ASSUMPTION]** Order: annihilation is checked before `gap_closed` and `round_limit`. The nuclear-use ending is unchanged (it ends the operation at once, before any check).
- **[ASSUMPTION]** Both sides wiped at once (e.g. a strike on the last formation of both is impossible, but a battle can destroy both): `winner` -1, `by` -1, reason `annihilation` (draw).
- No `rng` use; the result is stored in `state.result` and replays identically.

## Acceptance criteria (testable)

- [ ] Side 1 has 0 formations, side 0 has 1, `fielded_strength = [3, 3]`, no support: `annihilation` returns one `operation_ended` with `winner` 0, `by` 0, `reason` `annihilation`, and sets `state.result` identically; the `score` payload is present.
- [ ] Mirror case: side 0 wiped, side 1 alive: `winner` 1, `by` 1.
- [ ] Both sides wiped: `winner` -1, `by` -1, reason `annihilation`.
- [ ] Neither side wiped (each has >= 1 formation): returns `[]`, `state.result` stays `{}`.
- [ ] Side 1 has 0 formations but a requested, not withdrawn package of side 1 with 2 `waiting` placements: not wiped, `[]`. Same package with `withdrawn = true`, or with `waiting` empty: wiped.
- [ ] A package of side 1 that is not requested (`requested_turn == -1`) does not prevent annihilation; a pending package of side 0 does not protect side 1.
- [ ] `fielded_strength[1] == 0` and no formations of side 1 (never fielded): side 1 is not wiped, `[]`; `state.definition == null`: `[]`.
- [ ] A `ResolveBattleCommand` whose result destroys the last formation of the loser emits `formation_destroyed` then `operation_ended` (reason `annihilation`) in the same command, and clears `pending_battles`.
- [ ] A `StrikeCommand` that destroys the last formation of the target side emits `operation_ended` after the strike events; a strike that only damages a formation (strength > 0 left) does not.
- [ ] After the ending, any command is rejected with `operation_over` (existing behaviour), also from a battle command.
- [ ] Order: gap closed for 2 rounds and a wiped side 1 at the same `end_round`: reason is `annihilation`, not `gap_closed`. A wiped side 0 with higher score on side 0 still loses (score ignored).
- [ ] Replay of a recorded command list ending in annihilation gives the same `state.result` and `snapshot()`.
- [ ] `OperationMatchRunner._ending_of` maps `annihilation` to ending `annihilation` (add it to `ENDINGS`; no `push_error`, not `error`); `summarize` counts it in `wins_decided` (not `wins_by_score`), a -1 winner in `draws`; `tools/simulate.gd` prints the new ending column.
- [ ] `StaffMapEndModel.reason_line` returns a text for `annihilation` (not `GENERIC_REASON`): winner = viewer: "Enemy forces destroyed. The operation ends."; winner = other side: "Your forces were destroyed. The operation ends."; draw: "Both sides were destroyed. The operation ends."; headline via the existing `headline` (Victory / Defeat / Draw); `detail_line` shows the round count; the score table is unchanged.
- [ ] `StaffMapEndModel.rounds_played` for `annihilation` (ended mid-round) returns `state.turn` (not `turn - 1`), as for `nuclear_use`; unit-tested with a mid-round state.
- [ ] Check `staff_map_journal_text.gd` for `operation_ended` with the new reason (no crash, sensible line or the generic one); `OperationalJournal` records it as for other reasons.
- [ ] Docs: ARCHITECTURE event table lists `annihilation` among the `operation_ended` reasons (`tools/doc.py architecture`, and the long line 116/199 mentions); GDD Endings bullet updated.

## Playtest (for the human)

1. Start an operation; destroy every formation of the enemy side (contact battles and/or strikes) while no enemy reinforcement package is on its way (or let it be withdrawn / arrived and destroyed too).
2. Expect: the moment the last enemy formation is destroyed (not at the end of the round) the end notice appears: Victory, "Enemy forces destroyed. The operation ends.", the points table, rounds played.
3. Play as the other side and lose all formations: Defeat with "Your forces were destroyed."
4. With an enemy support package requested but not yet arrived, destroying the last enemy formation on the map must NOT end the operation; it ends after that reinforcement is destroyed.

## Player manual

docs/MANUAL.md, "Endings" paragraph (about line 824): add "A side that has no formations left on the map and none still on their way loses at once, whatever the points are; if both are wiped out at the same moment, it is a draw." Mention that reinforcements that are requested and still to arrive count as still in the game.

## Out of scope

- TASK-165 (objective readability), retreat / surrender rules, combinations of objectives plus annihilation, an "objectives reached" instant win.

## Implementation notes

- `OperationVictory.annihilation(state)` / `wiped(state, side)` (src/core/operational/operation_victory.gd); called at the end of `ResolveBattleCommand.apply` and `StrikeCommand.apply` (the task text says `execute`; the hook is `apply`, after `EscalationRules.on_strike`, so `operation_ended` is the last event) and first in `end_round`.
- `StaffMapEndModel.reason_line(state, event, viewer := 0)` got a viewer parameter (needed for the won/lost text); `StaffMapEscalationHud._show_end` passes it. `rounds_played` returns `state.turn` for `annihilation`.
- `OperationMatchRunner.ENDINGS` + `_ending_of` + `tools/simulate.gd` endings line carry `annihilation`. Existing runner tests now accept it as a possible AI ending.
- `StaffMapJournalText` needed no change (generic winner-based line); covered by a new test case.
- Docs: ARCHITECTURE (event table, victory paragraph), MANUAL "Endings". GDD was already updated.
- Tests: test_operation_victory (annihilation block), test_battle_consequences, test_strike_command, test_staff_map_end_model, test_operation_match_runner, test_staff_map_journal_text. The replay criterion is covered by the existing command-history determinism (no rng, result stored in the state); no dedicated replay test was added.
