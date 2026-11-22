# TASK-210: Continuous tactical space (6/9): view – selection, placement and orders by clicking a point

- **Status**: blocked
- **Layers**: presentation
- **Depends on**: TASK-208
- **Sections**: ADR 0029; ARCHITECTURE "Unit visuals"; docs/design/ mockups (battle HUD)
- **Model**: opus
- **Tags**: continuous-space

## Goal

The player picks units, places them and gives orders by clicking any point of the ground.

## Acceptance criteria (testable)

- [ ] `BattleController` ray-casts the mouse to the terrain (`TerrainSurface`) and passes a snapped `Vector2` to commands; hover / click no longer go through `Hex.from_world`; clicking a unit marker still selects it (`UnitView.marker_hit`).
- [ ] Deployment (scenario start): the player places units freely inside the deployment area with spacing enforced (ghost model, red when invalid, reason shown); verified by a headless input test of the pure placement helper.
- [ ] A move order: the click shows the planned track (smoothed polyline) and its cost; right click / Esc cancels; an unreachable point shows the reason.
- [ ] Units face their movement direction; the facing of a stopped unit is kept; unit models and markers stand on `TerrainSurface` height.
- [ ] No game rule in the view (rule 3); a test that the controller only issues commands.
- [ ] Mockup comparison for any changed HUD part (screenshot Read, deviations stated); if a new element has no mockup, `/design-ui` first.

## Playtest (for the human)

1. Start a battle, place a unit at a free spot; select a unit, click a point 300 m away – the track bends around a lake; confirm, the unit slides along it and ends exactly at the clicked point.
2. Place two units almost on top of each other – the second is refused with a reason.

## Player manual

Controls table: selecting, placing, move orders (by `game-designer`, in TASK-213).

## Out of scope

- Reach and range overlays (TASK-211), terrain planners (TASK-212).

## Implementation notes

_Filled in by the agent when done._
