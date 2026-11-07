# TASK-092c: Operational routes on the map – step costs as data, route planner, one turn's walk, per-turn forecast, route preview

- **Status**: blocked
- **Layers**: core (`src/core/operational/`, `src/core/data/`) + data + presentation (route preview)
- **Depends on**: TASK-092b (view: TASK-093a)
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

The movement rules that multi-turn orders run on (GDD "Operational layer" → "Orders and postures", "Movement costs"): formations follow the cheapest road / terrain route across the real Suwałki Gap, blocked by lakes and enemy formations, stopped by an enemy's zone of control. This task is **pure functions only** – no command, nothing changes state. Orders and postures are TASK-092d, their execution at the end of a turn TASK-092e. (Reworked 2026-11-01: the human chose orders over direct moves – there is no `MoveFormationCommand`.)

## Acceptance criteria (testable)

Data:

- [ ] `OperationalMovement` (Resource, `src/core/data/operational_movement.gd`, `data/operational/movement.tres`): `move_costs: PackedInt32Array` indexed by `Terrain.Type` (0 = impassable), `road_cost`, `river_extra_cost`, `problem() -> String` ("" when valid: one entry per `Terrain.Type`, costs ≥ 0, road cost ≥ 1; one test per broken case). Values: plains 2, forest 3, hills 3, water 0, fields 2, urban 2, marsh 4; road 1; river +2.
- [ ] `step_cost(grid, from, to) -> int` (on `OperationalMovement`): `road_cost` when `from` has a road link towards `to` and `to` is not water; otherwise `move_costs[terrain of to]` + `river_extra_cost` when `to` is a river hex; water and off-map → impassable (`Terrain.IMPASSABLE`). It reads terrain, road links and river links from the `HexGrid` (no tactical `Terrain.features()` costs). Examples (test): plains 2, forest 3, marsh 4, river plains hex 4, river marsh hex 6, the same river hex along a road link 1, water along a road link impassable.

Pure functions (`OperationalRoutes`, `src/core/operational/operational_routes.gd`, static; tests on small hand-made `HexGrid`s in an `OperationalState` built by `Operation.from_definition`, costs from the shipped `movement.tres`). Below, "row" = tiles q = 0 … 9, r = 0, plains unless stated, formation F of player 0 on (0, 0); "enemy" = a formation of the other player; "zone of control" (ZOC) = the hexes adjacent to an enemy formation.

`plan(state, formation, destination, avoid_contact: bool) -> Array[Vector2i]` – the full route, no move-point limit (excludes the start, ends with `destination`):

- [ ] Cheapest by summed `step_cost`; enemy hexes are impassable; hexes of other own formations can be passed through; empty when `destination` is the start, off the map, impassable, or holds any other formation, or when no route exists.
- [ ] Row examples: route to (6, 0) has 6 hexes, cost 12; with a road along the whole row cost 6; with (3, 0) water → empty; with an own formation on (2, 0) the route still goes through (2, 0), but a route **to** (2, 0) is empty.
- [ ] `avoid_contact = true`: ZOC hexes are impassable, except the destination (and the start – a formation that starts next to an enemy can leave). `false`: ZOC hexes are passable like any other hex (the walk below stops in them).
- [ ] Contact grid (tiles q = 0 … 6, r = 0 … 1, plains; enemy on (4, 1)): `plan(F, (6, 0), false)` = (1, 0) … (6, 0) (row 0); `plan(F, (6, 0), true)` = empty; `plan(F, (4, 0), true)` = (1, 0) … (4, 0) (a ZOC hex as the destination is allowed).
- [ ] Open grid (9 × 9 plains, enemy in the centre, F and the destination on opposite sides of it): the `avoid_contact` route contains no ZOC hex and costs more than the `false` route; the `false` route passes through at least one ZOC hex.
- [ ] Deterministic tie-breaking: the same state always gives the same route (test: two equal-cost routes, run twice, identical; the choice follows `Hex.DIRECTIONS` order like `HexGrid.path_to`). Implementation may reuse `HexGrid`'s Dijkstra by giving it a step-cost `Callable` (tactical tests must stay green) or be a separate search with the same tie rule.

`walk(state, formation, from: Vector2i, route, budget: int) -> Dictionary` – one turn's movement along a route, without changing state; returns `{steps: Array[Vector2i] (hexes entered, ends with end), end: Vector2i, cost: int, stop: StringName}`:

- [ ] Steps are taken in route order while the step's cost ≤ the points left. **The first step of a walk is always taken**, whatever it costs (a formation can always move one hex per turn). Points left after the walk are lost (not returned).
- [ ] `stop`: `&"arrived"` when the last route hex is entered (wins over contact – arriving next to an enemy is "arrived"); `&"contact"` when a ZOC hex that is not the last route hex is entered (the walk ends there); otherwise `&"out_of_points"`.
- [ ] The walk never ends on another formation's hex: `end` is the last entered hex without another formation (`from` if none), and `steps` / `cost` are cut back to it.
- [ ] Examples (test each): row, budget 8, route to (6, 0) → end (4, 0), cost 8, `out_of_points`; road row, budget 6, route to (6, 0) → end (6, 0), cost 6, `arrived`; (1, 0) a marsh river hex, budget 4, route to (3, 0) → end (1, 0), cost 6, `out_of_points` (first step always taken); own formation on (2, 0), budget 4 → end (1, 0), steps [(1, 0)], cost 2, `out_of_points`; same with budget 8 → end (4, 0), 4 steps, cost 8; contact grid, budget 6, route to (6, 0) from (0, 0) → end (3, 0), `out_of_points`; then from (3, 0) → end (4, 0), cost 2, `contact`; contact grid, route to (4, 0), budget 8 → end (4, 0), `arrived`.

`forecast(state, formation, destination, budget, avoid_contact) -> Array[Vector2i]` – the hex where the formation will stand after each of its turns, assuming nothing else moves (for TASK-093's route preview and TASK-092d's order event):

- [ ] Plans once, then repeated `walk`s along the rest of the route; ends after the walk that arrives, after a `contact` walk (its end is the last entry), after a walk that does not move, or after 99 walks. Empty when `plan` is empty.
- [ ] Examples: row to (6, 0), budget 8 → [(4, 0), (6, 0)]; budget 4 → [(2, 0), (4, 0), (6, 0)]; contact grid to (6, 0), budget 6, `avoid_contact` false → [(3, 0), (4, 0)].

Real map:

- [ ] Sanity (test): on `Operation.build("suwalki_gap", 7)`, every formation has a non-empty `plan(..., true)` to at least one hex at hex distance ≥ 3.
- [ ] Speed on the theatre map (68 × 64 = 4 352 hexes, added 2026-11-01 with the bigger map): `plan` across the map (a formation near one corner to a land hex near the opposite corner, `avoid_contact` false) ≤ **30 ms** median of 5 headless (test with a generous CI margin, e.g. fails above 90 ms; the measured value goes into the implementation notes next to TASK-092a's `HexGrid.path_to` baseline). `HexGrid._search` uses a linear minimum search over the frontier; if that misses the budget, use a bucket queue (step costs are small integers) or a binary heap that keeps the same tie rule – the tie-breaking test above must stay green.
- [ ] docs/ARCHITECTURE.md "Two layers": `OperationalMovement` and `OperationalRoutes` (plan / walk / forecast, the ZOC and first-step rules).

View (route preview on the staff map – no order is given yet, TASK-092d turns the preview into orders):

- [ ] With a formation selected (TASK-092b panel), moving the cursor over a hex shows the planned route from `plan` as a line along the hex centres with a tick at every per-turn stop from `forecast` (numbered 1, 2, 3 … = "after your turn n"), and a label at the cursor: total cost, number of turns, and the stop reason of the last walk (`arrived` / `contact`). Unreachable hexes (water, enemy, no route) show a red cross and the reason. Hover is debounced so scanning the map never drops below 60 FPS (the 4 352-hex speed criterion above applies; measured and noted).
- [ ] Preview paces: keys **1 / 2 / 3** switch the preview between the three paces listed in `data/operational/movement.tres` (`preview_paces`: id, budget, `avoid_contact` – 8 / avoid, 6 / enter, 4 / avoid; TASK-092d replaces them with postures read from the same numbers). The panel shows the active pace and the formation's budget.
- [ ] The preview is read-only: the state, snapshot and history are identical before and after (test on the controller: hover and key presses create no command).
- [ ] Translations for all labels.

## Playtest (for the human)

1. **Operation**, click a Polish battalion in the Gap (Suwałki).
2. Move the cursor east along the road towards Budzisko: a line follows the road, ticks `1`, `2` mark where the battalion stands after each of its turns; the label shows the cost and the number of turns. The same distance across forest / marsh costs visibly more turns.
3. Hover a lake or a Russian counter: a red cross with the reason. Hover a hex next to a Russian formation with pace 2 (advance): the route ends there with "contact"; with pace 1 (march) the route goes around the enemy's zone of control.
4. Press 1 / 2 / 3: the number of turns changes (8 / 6 / 4 points per turn).
5. Move fast over the whole map: no stutter.

## Player manual

Section "Routes": step costs (road 1, open ground and towns 2, forest and hills 3, marsh 4, river without a bridge +2, lakes impassable), one formation per hex (own formations can be passed), the zone of control (an advancing formation stops next to an enemy; marching and defending formations plan around enemies), the one-hex-per-turn minimum, unused points are lost, how to read the route preview.

## Out of scope

- Orders, postures, commands (TASK-092d); executing orders and their events (TASK-092e).
- What adjacency to an enemy causes (contact → battle, TASK-094); supply and readiness effects (TASK-096, TASK-095); fog – planning on known enemies only (TASK-100); operational AI (TASK-102).
- Giving orders (TASK-092d); the preview creates no command.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
