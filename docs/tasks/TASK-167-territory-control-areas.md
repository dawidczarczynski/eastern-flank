# TASK-167: Territory control as whole areas instead of strips

- **Status**: idea
- **Layers**: core
- **Depends on**: TASK-152
- **Sections**: to be filled when specified
- **Model**: opus
- **Topic**: Two-layer game

## Goal

Ground held for a few turns flips whole zones (hexes around held positions, between supply lines) to the holder, not just a strip along the path.

## Notes for the later specification

Source: the human's notes after a full operation playthrough (2026-11-16). Control currently spreads as strips along routes; after some time whole stretches of terrain should pass under control.

- Builds on the terrain control layer (TASK-152); find the control rule in the operational state.
- Design with game-designer: flipping radius/time, contested hexes, effect of enemy units and supply; keep it deterministic and cheap per turn.
- Visual layer must read well with the existing hatch + contour.
- Acceptance criteria and playtest steps to be written (`/refine-task TASK-167`).

## Player manual

To be decided when specified.

## Out of scope

- To be decided when specified.

## Implementation notes
