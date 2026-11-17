# TASK-170b: Battalion battle groups – tactical AI for artillery, balance and performance

- **Status**: ready
- **Layers**: ai
- **Depends on**: TASK-170a
- **Sections**: GDD "Balance of the default battle", GDD "Battle hand-off and auto-resolve", GDD "Formations"
- **Model**: opus (AI behaviour across the new role plus an iterative balance loop; a wrong tune silently skews both layers)
- **Topic**: Two-layer game

## Goal

The tactical AI plays the new 7-company battalions sensibly (artillery stays back and shells from range) and mirrored/default battles stay fair and smooth. Part 2 of TASK-170.

## Decisions (2026-11-17, human)

- Balance target 40–60 % win rate on mirrored / default setups; 7 v 7 must hold 60 FPS with an acceptable AI turn time. Numbers go to `data/**/*.tres`, not code.

## Acceptance criteria (testable)

- [ ] The AI never moves an `mlrs` company closer to the nearest enemy than its own `min_range_m` allows firing, and never ends its move nearer the enemy than the nearest own non-artillery company when it has a free tile farther back.
- [ ] An AI `mlrs` company with an enemy in range fires instead of moving when it can; if none is in range, it advances only to the first tile that puts an enemy in range, staying ≥ 2 hexes behind the front-most own direct-fire company.
- [ ] Direct-fire companies still head for the objective (existing objective tests green); no AI command is rejected in a 7 v 7 AI-vs-AI game over 20 seeds (zero rejected commands).
- [ ] `tools/simulate.sh 200` on the mirrored Poland v Poland and Russia v Russia setups: each seat wins 40–60 % of decided games.
- [ ] `tools/simulate.sh 200` on the default Poland v Russia contact setup (both attacker roles): each side wins 40–60 %; if not, tune `data/units/*.tres` or `data/formations/*.tres` only, and record the final numbers in the Implementation notes.
- [ ] AI turn time of a 7 v 7 battle (all 14 companies) stays at or under the pre-170 4 v 4 AI turn time × 2.5 on `tools/simulate.sh` timing output; no game exceeds 60 turns.
- [ ] Operation-level balance re-measured (`--mode=operation`, seeds 1..200): each side holds 40–60 % of decided operations with the new order of battle; update the numbers in GDD "Operational AI".
- [ ] A 7 v 7 battle scene renders at 60 FPS (HIGH) – measured and noted (see playtest).

## Playtest (for the human)

1. Play a contact battle as attacker and as defender: your rocket-artillery company is placed behind your line; the enemy's stays back and fires at your units in range.
2. Watch 3 AI turns: no artillery rushes the front; no long freeze while the AI thinks.
3. Check the frame rate during a full 7 v 7 fight (FPS counter in the debug overlay stays at 60).

## Player manual

docs/MANUAL.md (game-designer): add a short note that rocket artillery is used from behind the front and the enemy AI does the same; update any win-rate or difficulty wording if numbers changed in `data/`.

## Out of scope

- v2: air defence, helicopters; new unit models; a dedicated anti-tank unit; ammunition and morale.
- Changing the deployment rules or the order of battle (TASK-170a).

## Implementation notes

_Filled in by the agent when done._
