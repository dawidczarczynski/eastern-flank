# TASK-163: Tactical battle deployment: defender placed around the objective

- **Status**: idea
- **Layers**: core
- **Depends on**: –
- **Sections**: to be filled when specified
- **Model**: opus
- **Topic**: Two-layer game

## Goal

The defending side starts in the vicinity of the battle objective; the attacker enters from its edge. Battles become attack-vs-defence, not a race.

## Notes for the later specification

Source: the human's notes after a full operation playthrough (2026-11-16). Deployment puts both sides on opposite map edges, so the defender must race to the objective instead of defending it. The defender should start around the objective.

- Find the deployment code (grep CODEMAP: deployment/spawn) and how the objective is chosen.
- Open: radius around the objective, terrain suitability, what happens in meeting engagements (no defender, keep edges), objectives for operation-spawned battles.
- Needs a GDD note (game-designer) and unit tests for placement; deterministic via `GameState.rng`.
- Acceptance criteria and playtest steps to be written (`/refine-task TASK-163`).

## Player manual

To be decided when specified.

## Out of scope

- To be decided when specified.

## Implementation notes
