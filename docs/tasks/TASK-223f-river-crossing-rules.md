# TASK-223f: Water network (6/7): river crossing rules from the water network (free movement, no hexes)

- **Status**: idea
- **Layers**: GDD (game-designer) → core rules + AI + presentation (path preview)
- **Depends on**: TASK-223c (soft: TASK-220; the hex-free movement design – no task yet)
- **Sections**: ADR 0034 decision 6; GDD movement and terrain sections (to be listed when refined)
- **Model**: opus
- **Tags**: battle-look

## Goal

Crossing a river is a real tactical decision: where, with what, and at what cost – computed from the same width, depth, current and bank parameters the player sees.

## Acceptance criteria (testable)

To be written in `/refine-task` after the hex-free movement design. Starting points from ADR 0034:
- a move whose path crosses a reach's water is a crossing (`WaterNetwork.crossings_of`), no hex edges;
- classes from the parameters: stream (slows), fordable (water depth ≤ the vehicle's fording depth, current below a limit), wide (bridge, engineers, amphibious only);
- the exit bank's height and steepness can block leaving the water even at a ford;
- bridges (capacity from TASK-220) and fords are explicit crossing points; the AI uses the same queries.

## Playtest (for the human)

To be written.

## Player manual

To be written (game-designer).

## Out of scope

- The hex-free movement system itself.

## Implementation notes

_Filled in by the agent when done._
