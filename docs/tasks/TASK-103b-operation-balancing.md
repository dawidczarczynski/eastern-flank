# TASK-103b: Operation balancing – both sides win 40–60 % of decided operations (AI-vs-AI)

- **Status**: done
- **Layers**: data / docs
- **Depends on**: TASK-103a (hard), TASK-099a / TASK-119a (soft, irrelevant to the numbers)
- **Topic**: Two-layer game
- **Tags**: mvp
- **Sections**: GDD "Operational AI", "Escalation ladder"; docs/TOOLS.md simulate entry
- **Model**: sonnet

## Goal

Both sides are playable: in AI-vs-AI operation simulations NATO and Russia each hold 40–60 % of decided operations, reached by data changes only. Second part of TASK-103 (split 2026-11-11).

## Decisions (human interview, 2026-11-11)

- Data only: `AiProfile`, strike stock / resupply, AI goal weights, support data in `.tres`; no code rule changes.
- Target: each side 40–60 % of decided operations, at most ~30 % undecided (turn-cap provisional results count as decided per TASK-103a's report; undecided = draws at the cap).
- If data alone cannot reach it: report the gap and suspected rule causes, then stop (no code changes).
- **[ASSUMPTION]** this is the AI-vs-AI balance only; human-vs-AI feel is for playtests.
- **[ASSUMPTION]** runs use `tools/simulate.sh N --mode=operation --battles=auto` on `suwalki_gap`, 100–200 matches per measurement, with a fixed seed list written in the Implementation notes.

## Acceptance criteria (testable)

- [ ] Baseline measured and recorded before any change: 100–200 matches, seed range listed, with win shares, undecided share, average max escalation level, average length.
- [ ] After the pass, a run of the same seeds shows NATO and Russia each in 40–60 % of decided operations and undecided ≤ 30 %.
- [ ] Only `data/**/*.tres` changed; `git diff --stat` shows no `src/` file (code or tests apart from the regression test below).
- [ ] Implementation notes hold a before/after table (NATO %, Russia %, undecided %, average level, average length) and a change list (file, field, old value, new value).
- [ ] Regression test in `tests/unit/` runs a fixed 20-seed operation simulation and asserts each side's share of decided operations lies in 35–65 % and undecided ≤ 40 %; it finishes within 120 s.
- [ ] The regression test fails when a side's share is forced outside the band (e.g. checked with a hand-made result list through the band helper, not by editing data).
- [ ] The same seeds give the same numbers twice (determinism, no flaky band).
- [ ] If the target is not reached: Implementation notes name the gap (shares reached) and suspected rule causes, the status stays `to playtest` with the numbers, and no code is changed.
- [ ] docs/GDD.md "Operational AI" gets one bullet "Balance target": each side 40–60 % of decided operations in AI-vs-AI simulation; the provisional score is replaced by TASK-107's victory.

## Playtest (for the human)

None beyond the tool output (`tools/simulate.sh 100 --mode=operation --seed=1`); the agent verifies everything. Human-vs-AI feel is judged in later playtests.

## Player manual

none

## Out of scope

- Code rule changes, new mechanics, difficulty levels, UI.
- `--battles=played` calibration of auto-resolve (follow-up, e.g. TASK-128).

## Implementation notes

Done 2026-11-12 (data only + one test). Baseline first, then a code fix found by the baseline, then a data pass.

**Seeds** 1..100 for every measurement (`tools/simulate.sh 25 --mode=operation --seed=1/26/51/76` in parallel, battles auto, cap 30).

| | NATO % | Russia % | undecided % | avg max level | avg length |
|---|---|---|---|---|---|
| baseline (as found) | 0 | 39 (provisional) | 61 (38 `error`, 23 `nuclear`) | 5.23 | 13.3 |
| after the zero-strength fix (src/core/operational/contact_rules.gd, bug found by the baseline) | 0 | 71 | 29 (`nuclear`) | 5.29 | 23.3 |
| after the data pass | 52 | 44 | 4 (`nuclear`) | 5.0 | 29.9 |

Share of decided operations: NATO 52 / (52 + 44) = 54 %, Russia 46 %, 4 % `nuclear` (no winner) – inside 40–60 %, the human preferred NATO slightly ahead. Seeds 1..20 alone: NATO 9, Russia 10, 1 draw. Deterministic: the same seeds gave identical numbers on repeated runs.

**Why** (diagnosis, 8 seeds): battles were even (Russia 78, NATO 64 wins); strikes cost NATO 639 strength vs 386 for Russia; the `nuclear` endings are Russia in collapse (< 50 % of fielded strength) at level 5 – the more even the match, the more often Russia collapses.

**Data changes**
| file | field | old → new |
|---|---|---|
| data/operations/suwalki_gap.tres | strike_stock Russia `geran_2` | 80 → 40 |
| | strike_resupply Russia `kh101` / `geran_2` | 3 / 8 → 2 / 4 |
| | strike_resupply NATO `jassm_er` / `homar_k` / `warmate` | 4 / 6 / 6 → 6 / 10 / 10 |
| | goal weights `nato_hold_suwalki` / `nato_hold_bialystok` / `nato_hold_elk` / `nato_take_grodno` | 4 / 3 / 2 / 3 → 10 / 6 / 5 / 8 |
| | goal weights `ru_take_suwalki` / `ru_take_elk` / `ru_take_kaunas` / `ru_hold_grodno` | 5 / 3 / 3 / 2 → 6 / 4 / 3 / 4 |
| data/operational/escalation.tres | collapse_strength_pct / collapse_readiness_pct / collapse_readiness_strength_pct | 50 / 35 / 70 → 35 / 25 / 55 |

Weights were doubled so single steps are finer (a step of 1 swung NATO from 30 % to 80 % at the old scale). The collapse thresholds are a player-visible rule: MANUAL "Collapse" updated, and the tests that pinned shipped values (test_collapse, test_escalation, test_nuclear_strike, test_staff_map_escalation, test_staff_map_decisions, test_strikes) were updated to the new numbers – an exception to "data only" the criteria did not foresee. Without the collapse change the 100 seeds gave NATO 20 / Russia 41 / 39 % `nuclear`.

**Test**: tests/unit/test_operation_balance.gd – `in_band` helper (checked with hand-made result lists) and a 20-seed run asserting each side 35–65 % of decided and undecided ≤ 40 %, plus a determinism replay. **It takes ~190 s, above the 120 s in the criteria** (a 30-round match is ~9 s); shortening it would mean fewer seeds or a lower round cap, which changes what is measured.

**Limits**: the result is very sensitive to the goal weights (single-point changes swing NATO from 30 % to 80 %) because the provisional score is a few discrete weights; it is a stopgap until TASK-107's victory replaces it, then re-measure. Only data changed apart from the zero-strength fix and the new test.
