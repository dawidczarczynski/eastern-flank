# TASK-206: Continuous tactical space (2/9): navigation grid, pathfinding, reachable area

- **Status**: blocked
- **Layers**: core
- **Depends on**: TASK-205
- **Sections**: ADR 0029 (decisions 3, 5)
- **Model**: opus
- **Tags**: continuous-space

## Goal

Smooth movement tracks and the area a unit can reach, without hexes.

## Acceptance criteria (testable)

- [ ] `NavGrid` (pure): hidden fine grid (cell size from a data resource, default 8 m) derived from `TacticalMap`; step cost from terrain, road (cheaper along it) and river (extra cost, bridge = road); impassable terrain closed.
- [ ] `find_path(from, to, budget, obstacles) -> {path, cost}`: A*, then smoothed (string pulling, never through impassable cells); deterministic (ties broken by a fixed order); the same inputs give the same path in two runs (test).
- [ ] `reachable_area(from, budget, obstacles) -> {cells, boundary polygon}`: the isochrone the view draws; a point is reachable exactly when `find_path` to it fits the budget (test).
- [ ] Obstacles are circles (other units, footprint radius from `UnitDefinition`, TASK-208 sets the data): a path never passes through one; a destination inside one is rejected.
- [ ] Cost is integer (fixed-point per metre); budget = metres of path times terrain cost.
- [ ] Performance: a path across a 4 km map < 5 ms, a reachable area < 20 ms on the CI machine (a test with a loose bound); results cached per (map version, unit state) where the AI repeats queries.

## Playtest (for the human)

None (core only).

## Player manual

none

## Out of scope

- Commands, the view, stepped execution (TASK-208).

## Implementation notes

_Filled in by the agent when done._
