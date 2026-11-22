# TASK-211: Continuous tactical space (7/9): view – smooth reach area, range circles, movement animation

- **Status**: blocked
- **Layers**: presentation
- **Depends on**: TASK-208, TASK-210
- **Sections**: ADR 0029; docs/design/ mockups (battle HUD, range overlay)
- **Model**: sonnet
- **Tags**: continuous-space

## Goal

Every unit's reach and range is drawn as a smooth shape on the ground, and units move along their tracks.

## Acceptance criteria (testable)

- [ ] Reach: the `reachable_area` boundary drawn as a soft ground decal (`OverlayGeometry`), bent by terrain and obstacles; `RangeOverlayModel` and `RangeText` switch from tile sets to metres and polygons (pure model tests).
- [ ] Weapon range: a circle (or arc by facing, if the unit type has a firing arc) with LOS-blocked parts dimmed; targets in range highlighted.
- [ ] Movement: `unit_moved.path` plays as a constant-speed slide along the smoothed polyline with the model turning along it; `move_interrupted` stops it at `stopped_at` with a short marker.
- [ ] Tile-shaped hover / selection decals are gone from the battle (the grid toggle G draws nothing in battle after TASK-213, see there).
- [ ] 60 FPS budget kept: reach polygons are rebuilt only when the selection or budget changes (measured; numbers in the notes).
- [ ] Screenshots Read next to the mockup (selected unit, reach, range, an interrupted move); deviations stated.

## Playtest (for the human)

1. Select a unit: a smooth reach area, bent by forest and water, and a range circle; hover an enemy – the forecast shows the metre distance.
2. Order a move past an enemy: the unit stops when it spots the enemy.

## Player manual

Reach and range display (by `game-designer`, in TASK-213).

## Out of scope

- Terrain look code (TASK-212).

## Implementation notes

_Filled in by the agent when done._
