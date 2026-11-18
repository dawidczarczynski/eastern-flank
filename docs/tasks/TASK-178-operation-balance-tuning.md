# TASK-178: Operation balance tuning after the connection objectives

- **Status**: ready
- **Layers**: core (data) + ai
- **Depends on**: TASK-177
- **Topic**: Balance
- **Sections**: GDD "Sides" (Victory, Endings, Objective tiers; the AI plays either side)
- **Model**: opus

## Goal

Both sides win 40-60 % of the decided operations again (AI vs AI, `tools/simulate.sh N --mode=operation`) after TASK-177 changed the main objectives to connection conditions: Russia wins by holding a land link Kaliningrad - Belarus for 5 rounds, NATO scores by keeping Suwałki connected with Kaunas.

Human decision (2026-11-18): the balance is tuned in its own task; until it is done the failing `test_operation_balance.gd:test_both_sides_win_a_fair_share_of_operations` is accepted (`tools/check.sh` is red on that one test only).

## Starting point (measured at the end of TASK-177, 20 matches per seed set, report only)

- Seeds 1..20: NATO 0 % / Russia 100 %, `corridor_closed` in 90 % of the matches, average 15.4 rounds.
- Seeds 101..120: NATO 0 % / Russia 100 %, `corridor_closed` in 85 %, average 16.8 rounds.
- Before TASK-177 (fixed chains): NATO 40 % / Russia 60 %, the instant win never fired.
- Cause: the shortest Kaliningrad - Belarus land link through the Polish strip of the Gap is 17 steps and the Russian AI holds it for 5 rounds; the NATO AI does not contest it enough.

## Acceptance criteria (testable)

- [ ] Measure first and write the numbers (seeds, N >= 20 per set, at least 2 sets) in Implementation notes before changing anything.
- [ ] Tune with data and AI weights only, in this order of preference, and justify each change: NATO AI goals and weights (`data/operations/suwalki_gap.tres`), starting positions / order of battle, `closed_rounds_to_win`, `corridor_points`, `gap_open_points`, escalation penalty. Rules, determinism and the connection definitions from TASK-177 stay unchanged (changing them is a human decision: stop and ask).
- [ ] After tuning: `tools/simulate.sh` with at least 40 matches over 2 seed sets: each side wins 40-60 % of the decided operations; instant `corridor_closed` endings are neither 0 % nor the typical ending (report the share).
- [ ] `test_operation_balance.gd:test_both_sides_win_a_fair_share_of_operations` passes without loosening its thresholds; `tools/check.sh` is green apart from nothing.
- [ ] Docs: GDD numbers that changed (points, rounds, positions) and docs/MANUAL.md if a player-visible number changed.

## Playtest (for the human)

1. Play a full operation as NATO and as Russia against the AI: neither side should feel lost from round 1; the Russian link should be contestable and holding it for 5 rounds a real effort.

## Out of scope

- New rules, new objectives, changes to hex-control or to the connection definitions.

## Implementation notes

(to be filled in by the implementer)
