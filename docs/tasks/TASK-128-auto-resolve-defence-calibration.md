# TASK-128: Auto-resolve calibration – defending on hills is far stronger in auto-resolve than in played battles

- **Status**: done
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

Measured with the new `tools/calibrate_auto_resolve.sh` (150 seeds; wins P0 / P1 / draws; played = `MatchRunner` AI vs AI, 60-turn harness limit, defender tiles forced to hills where the case says hills):

| Case | Played | Auto (old 8:50) | Auto (new 12:90) |
|---|---|---|---|
| crush | 149/0/1 | ~50/0/0 | 150/0/0 |
| mirror | 80/68/2 | 9/20/21 per 50 | 60/80/10 |
| fortress | 22/128/0 | 2/47/1 per 50 | 0/150/0 |
| siege (2:1 vs hills) | 142/8/0 | 49/0/1 per 50 | 149/0/1 |
| caught (march, plains) | 132/17/1 | 43/2/5 per 50 | 141/6/3 |

Findings: (1) the TASK-120 "fortress" gap was mostly an artefact: played spawn tiles are forced to plains, so the defender had only the +1 posture bonus while auto-resolve also counted hills +2; with real hills the gap is ~15 points. (2) Real remaining gap: auto-resolve broke a side at 50 % losses in 8 rounds (mirror: ~40 % draws) while played battles go almost to annihilation. Fix: `default_rounds` 12, `break_share` 90 (data only). Largest win-share gap now 15 points (fortress). No AI change needed. Golden mirror seed 7 regenerated; `test_command_points…` now uses turn_limit 1; speed budget 2 → 4 ms (longer battles). GDD, MANUAL (auto-resolve paragraph) and ADR 0015 updated.
