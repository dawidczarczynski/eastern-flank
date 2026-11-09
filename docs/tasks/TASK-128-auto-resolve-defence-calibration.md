# TASK-128: Auto-resolve calibration – defending on hills is far stronger in auto-resolve than in played battles

- **Status**: ready
- **Layers**: core (`src/core/auto_resolve.gd`, `data/battle/auto_resolve.tres`) and/or AI (`src/ai/`); no presentation
- **Depends on**: TASK-120
- **Model**: sonnet
- **Topic**: Two-layer game / balance

## Goal

TASK-120 measured auto-resolve against headless tactical AI-vs-AI battles of the same setups (50 seeds; wins are player 0 / player 1 / draws). "crush" and "mirror" agree, "fortress" ("mirror" with player 1 defending +1 on hills +2) does not:

| Case | Auto-resolve | Played (AI vs AI) |
|---|---|---|
| fortress | 2 / 47 / 1, mean losses 19.9 / 11.7 | 5 / 28 / 17, 31.0 / 23.5 |

The defender wins 94 % of auto-resolved battles but 56 % of played ones (the played draws are 60-turn harness limits). Played battles already read `position_bonus` (TASK-120 follow-up), so the rest of the gap is the auto-resolve numbers (almost every attack `hit_on` collapses to 1 against defender +1 and hills +2) and the AI attacking poorly into hills. The result of an auto-resolved contact must stay a plausible stand-in for a played one (TASK-103 relies on it).

## Acceptance criteria (testable)

- [ ] The gap is analysed first (measure, write down in "Implementation notes"): auto-resolve vs played "fortress", "crush", "mirror" plus two new cases (attacker 2:1 against a defender on hills; march-caught defender on plains), 50+ seeds each; the calibration script of TASK-120 (`calibrate.gd`, see its notes) can be reused as a starting point – put a reusable version in `tools/`.
- [ ] A fix chosen by the numbers – tuning `break_share` / `default_rounds`, the way terrain and posture enter the auto-resolve hit number, and/or the AI's behaviour when attacking fortified positions – so that in every measured case the win share of each side differs by ≤ 20 points between auto-resolve and played battles, and "crush" / "mirror" stay within their current criteria.
- [ ] TASK-120's acceptance tests ("salvo", "crush", "mirror", "fortress", determinism, golden) still pass; a changed golden is regenerated on purpose and noted. A changed AI behaviour is covered by its own test (TDD).
- [ ] Any rule change is mirrored in GDD "Battle hand-off and auto-resolve", docs/MANUAL.md and ADR 0015 if it alters what the player sees.

## Out of scope

- New rules (morale, suppression, ammunition – TASK-090 / TASK-099).
- Presentation.

## Implementation notes

_Filled in by the agent when done._
