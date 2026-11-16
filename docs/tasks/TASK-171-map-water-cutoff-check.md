# TASK-171: Tactical map generation: avoid units cut off by water

- **Status**: idea
- **Layers**: core
- **Depends on**: –
- **Sections**: to be filled when specified
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

After map generation, every deployment zone and the objective are connected by land (for units that cannot swim); otherwise the map is repaired or regenerated.

## Notes for the later specification

Source: the human's notes after a full operation playthrough (2026-11-16). Generated tactical maps can leave units isolated by water.

- Per project direction maps come from real geography, so first check whether this applies to the import-based maps (pathfinding connectivity check) rather than tuning the random generator.
- Connectivity test over deployment zones + objective; deterministic fallback via `GameState.rng`.
- Acceptance criteria and playtest steps to be written (`/refine-task TASK-171`).

## Player manual

To be decided when specified.

## Out of scope

- To be decided when specified.

## Implementation notes
