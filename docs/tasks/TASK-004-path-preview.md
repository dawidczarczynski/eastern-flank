# TASK-004: Movement path preview on hover

- **Status**: to playtest
- **Layers**: core / presentation
- **Depends on**: nothing. Optional: TASK-008 (hide the preview while events are playing).

## Goal

Before clicking, the player sees which way the selected unit will walk and how many movement points it costs – important once forests and hills make the cheapest route non-obvious.

## Acceptance criteria (testable)

- [x] New query `HexGrid.path_to(origin: Vector2i, target: Vector2i, budget: int, blocked: Dictionary = {}) -> Array[Vector2i]`. The result **excludes** `origin` and ends with `target`. Returns `[]` when `target == origin`, the target is off the map/impassable/blocked, or it is not reachable within `budget`.
- [x] `reachable()` and `path_to()` share one Dijkstra implementation (e.g. a private function returning both costs and parent links) – no second pathfinding algorithm. `reachable()`'s results stay unchanged (existing `test_hex_grid.gd` passes).
- [x] Invariants (checked in tests for every returned path): consecutive tiles are neighbours (`Hex.distance == 1`, first tile adjacent to `origin`); no tile is impassable or in `blocked`; the sum of `move_cost` over the path equals `reachable(origin, budget, blocked)[target]`; same inputs → the same path (deterministic tie-breaking, follows `Hex.DIRECTIONS` order).
- [x] Tests (`tests/unit/test_hex_grid.gd` or a new `test_path.gd`), plains map radius 2:
  - `path_to((0,0), (2,0), 3)` == `[(1,0), (2,0)]` (cost 2).
  - With `(1,0)` set to FOREST: `path_to((0,0), (1,1), 3)` == `[(0,1), (1,1)]` (cost 2, avoids the forest).
  - With `(1,0)` FOREST and `(0,1)` WATER: `path_to((0,0), (1,1), 3)` == `[(1,0), (1,1)]` (cost 3); with budget 2 → `[]`.
  - With `(1,0)` FOREST and `blocked = {(0,1): true}`: `path_to((0,0), (1,1), 3)` == `[(1,0), (1,1)]`.
  - `path_to((0,0), (0,0), 3)` == `[]`; target off the map `(5,5)` → `[]`.
- [x] Presentation: when a human unit is selected on the human turn and the mouse hovers a tile that is in the unit's reachable set (excluding its own tile), the view draws a marker on every tile of `path_to(unit.coord, hovered, unit.moves_left, state.occupied())` (smaller and lighter than the movement highlight) and a `Label3D` above the target tile with the text `"<cost>/<moves_left>"` (e.g. `2/3`).
- [x] Hovering a tile outside the reachable set, an occupied tile, or leaving the map removes the preview. The preview is recomputed only when the hovered tile changes (not every mouse-motion event) and is cleared on deselection, after a move, on turn end and on `game_over`.
- [x] The view uses `path_to` and `reachable` only – no path or cost logic in `src/presentation/`.

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

Core:
- `HexGrid._search(origin, budget, blocked)` is the single Dijkstra; it returns `{costs, parents}`. `reachable()` returns its `costs` unchanged, `path_to()` rebuilds the route from `parents`.
- A parent is replaced only on a strictly lower cost and the frontier pops the first minimum by index, so ties go to the first discovery (`Hex.DIRECTIONS` order) – pinned by `test_ties_follow_directions_order`.
- Tests: tests/unit/test_path.gd – the task's exact paths, edge cases (origin, off-map, impassable, blocked, over budget) and invariants checked on every returned path.

Presentation:
- `MapView` has a separate path marker set (`_path_root`): `show_path(coords, label_text)` / `clear_path()`. The markers are small, pale hexes (radius 0.35·hex_size, alpha 0.75) placed 0.05 above the tile top. The movement highlight sits at 0.02, so the two don't z-fight. One reused `Label3D` (billboard, `no_depth_test`, outlined, like the HP labels) is shown 0.6 above the target tile. `clear_highlights()` clears only the movement highlight. The controller clears the path separately.
- `BattleController` handles `InputEventMouseMotion` before the turn/winner check, so the hovered tile is always tracked. `_set_hovered_hex()` recomputes the preview only when the tile changes. `_refresh_path_preview()` shows the path only for a living, selected human unit on the human turn with `winner == -1`. It calls `grid.path_to(unit.coord, hovered, unit.moves_left, state.occupied())`, and the label cost comes from `grid.reachable(...)[hovered]`. An empty path means no preview, which covers the unit's own tile, occupied tiles, out-of-range tiles and off-map tiles.
- `_refresh_selection_ui()` recomputes the preview for the hovered tile (select/deselect, after a move or attack, `turn_started`, `turn_ended`, `game_over`); it hides itself whenever there is no valid target.
- After review: when the camera moves under a still cursor (WASD/QE/wheel), `_process` notices the camera transform change and re-picks the hovered tile, so the preview doesn't go stale. Test-only helpers in `MapView` were removed.
- Known limitation: two searches per hover change (`path_to` + `reachable` for the cost) – fine for the current map size.

