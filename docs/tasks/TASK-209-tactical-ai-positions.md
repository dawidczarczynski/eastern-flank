# TASK-209: Continuous tactical space (5/9): tactical AI chooses positions

- **Status**: blocked
- **Layers**: ai
- **Depends on**: TASK-208
- **Sections**: ADR 0029; GDD "AI" (find with `tools/doc.py gdd`)
- **Model**: opus
- **Tags**: continuous-space

## Goal

The AI plays on the continuous map: it picks positions from sampled candidates instead of tiles, and plays no worse than before.

## Acceptance criteria (testable)

- [ ] `AiPlayer` generates candidate positions per unit (ring samples around targets and objectives, cover points from `cover_at` / height, a fixed number from an `AiProfile` field); scoring uses distance, LOS, cover, threat; ties broken in a fixed order (deterministic, no `rng` unless through `GameState.rng`).
- [ ] The AI respects obstacles and the stepped-move interrupt (re-plans when `move_interrupted`).
- [ ] Per-turn AI time on the Suwałki scenario ≤ 1.5× the pre-change time (measured and written in the notes); `tools/simulate.sh` runs complete.
- [ ] Balance check: 100 AI-vs-AI matches per standard scenario – no side wins more than 65 % where the old AI stayed within 55 % (values in the notes; tuning data in `data/ai/`).
- [ ] The operational AI (`operational_ai.gd`) is untouched.

## Playtest (for the human)

1. Play a battle against the AI: it advances along natural tracks, uses cover and keeps objectives contested; no unit stands inside another.

## Player manual

none

## Out of scope

- Operational AI (TASK-214).

## Implementation notes

_Filled in by the agent when done._
