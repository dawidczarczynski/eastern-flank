# TASK-004: Movement path preview on hover

- **Status**: ready
- **Layers**: core / presentation
- **Depends on**: nothing. Optional: TASK-008 (hide the preview while events are playing).

## Goal

Before clicking, the player sees which way the selected unit will walk and how many movement points it costs – important once forests and hills make the cheapest route non-obvious.

## Acceptance criteria (testable)

- [ ] New query `HexGrid.path_to(origin: Vector2i, target: Vector2i, budget: int, blocked: Dictionary = {}) -> Array[Vector2i]`. The result **excludes** `origin` and ends with `target`. Returns `[]` when `target == origin`, the target is off the map/impassable/blocked, or it is not reachable within `budget`.
- [ ] `reachable()` and `path_to()` share one Dijkstra implementation (e.g. a private function returning both costs and parent links) – no second pathfinding algorithm. `reachable()`'s results stay unchanged (existing `test_hex_grid.gd` passes).
- [ ] Invariants (checked in tests for every returned path): consecutive tiles are neighbours (`Hex.distance == 1`, first tile adjacent to `origin`); no tile is impassable or in `blocked`; the sum of `move_cost` over the path equals `reachable(origin, budget, blocked)[target]`; same inputs → the same path (deterministic tie-breaking, follows `Hex.DIRECTIONS` order).
- [ ] Tests (`tests/unit/test_hex_grid.gd` or a new `test_path.gd`), plains map radius 2:
  - `path_to((0,0), (2,0), 3)` == `[(1,0), (2,0)]` (cost 2).
  - With `(1,0)` set to FOREST: `path_to((0,0), (1,1), 3)` == `[(0,1), (1,1)]` (cost 2, avoids the forest).
  - With `(1,0)` FOREST and `(0,1)` WATER: `path_to((0,0), (1,1), 3)` == `[(1,0), (1,1)]` (cost 3); with budget 2 → `[]`.
  - With `(1,0)` FOREST and `blocked = {(0,1): true}`: `path_to((0,0), (1,1), 3)` == `[(1,0), (1,1)]`.
  - `path_to((0,0), (0,0), 3)` == `[]`; target off the map `(5,5)` → `[]`.
- [ ] Presentation: when a human unit is selected on the human turn and the mouse hovers a tile that is in the unit's reachable set (excluding its own tile), the view draws a marker on every tile of `path_to(unit.coord, hovered, unit.moves_left, state.occupied())` (smaller and lighter than the movement highlight) and a `Label3D` above the target tile with the text `"<cost>/<moves_left>"` (e.g. `2/3`).
- [ ] Hovering a tile outside the reachable set, an occupied tile, or leaving the map removes the preview. The preview is recomputed only when the hovered tile changes (not every mouse-motion event) and is cleared on deselection, after a move, on turn end and on `game_over`.
- [ ] The view uses `path_to` and `reachable` only – no path or cost logic in `src/presentation/`.

## Playtest (for the human)

1. Select a unit and hover over a highlighted tile two hexes away on open plains – two path markers appear and the label reads `2/3` (infantry) or `2/5` (cavalry).
2. Hover a tile behind a forest – the path goes around the forest if that is cheaper; if it goes through, the label shows the higher cost.
3. Hover a tile outside the yellow highlight or a tile with a unit – no path.
4. Click the hovered tile – the unit moves there and the preview disappears.
5. Deselect / press Enter – no leftover markers.

## Out of scope

- Animating the unit along the path (follow-up: add a `path` field to `unit_moved`, then `UnitView` tweens tile by tile).
- Letting the player choose a non-optimal route (waypoints).
- Path preview for enemies or for attack-move.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
