# TASK-103b: Operation balancing – both sides win 40–60 % of decided operations (AI-vs-AI)

- **Status**: ready
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

_Filled in by the agent when done: what was done, decisions, known limitations._
