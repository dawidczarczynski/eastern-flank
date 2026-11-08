# gdlint: disable=max-public-methods
extends TestCase
## Operational movement data and routes (TASK-092c): step costs, plan, walk, forecast.

const Fixtures := preload("res://tests/fixtures.gd")


static func _row_grid() -> HexGrid:
	var grid := HexGrid.new()
	for q in range(0, 10):
		grid.set_terrain(Vector2i(q, 0), Terrain.Type.PLAINS)
	return grid


## A state on `grid` with formation "f" of player 0 on (0, 0) and the extras
## {coord: owner} (enemy = owner 1).
static func _state(grid: HexGrid, extras: Dictionary = {}) -> OperationalState:
	var state := OperationalState.new()
	state.grid = grid
	state.formations.append(_formation(&"f", 0, Vector2i.ZERO))
	var n := 0
	for coord: Vector2i in extras:
		n += 1
		state.formations.append(_formation(StringName("x%d" % n), extras[coord] as int, coord))
	return state


static func _formation(id: StringName, owner: int, coord: Vector2i) -> Formation:
	var f := Formation.new()
	f.id = id
	f.owner_id = owner
	f.coord = coord
	return f


static func _contact_state() -> OperationalState:
	var grid := HexGrid.new()
	for q in range(0, 7):
		for r in range(0, 2):
			grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
	return _state(grid, {Vector2i(4, 1): 1})


static func _route(from_q: int, to_q: int) -> Array[Vector2i]:
	var route: Array[Vector2i] = []
	for q in range(from_q, to_q + 1):
		route.append(Vector2i(q, 0))
	return route


# --- data ---


func test_shipped_data_is_valid() -> void:
	var m := OperationalMovement.shipped()
	assert_eq(m.problem(), "")
	assert_eq(Array(m.move_costs), [2, 3, 3, 0, 2, 2, 4])
	assert_eq(m.road_cost, 1)
	assert_eq(m.river_extra_cost, 2)


func test_problem_cases() -> void:
	var m := OperationalMovement.shipped().duplicate() as OperationalMovement
	m.move_costs = PackedInt32Array([2, 3])
	assert_true(m.problem() != "")
	m = OperationalMovement.shipped().duplicate() as OperationalMovement
	m.move_costs = PackedInt32Array([2, -1, 3, 0, 2, 2, 4])
	assert_true(m.problem() != "")
	m = OperationalMovement.shipped().duplicate() as OperationalMovement
	m.road_cost = 0
	assert_true(m.problem() != "")


func test_step_costs() -> void:
	var grid := _row_grid()
	var m := OperationalMovement.shipped()
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	assert_eq(m.step_cost(grid, a, b), 2)
	grid.set_terrain(b, Terrain.Type.FOREST)
	assert_eq(m.step_cost(grid, a, b), 3)
	grid.set_terrain(b, Terrain.Type.MARSH)
	assert_eq(m.step_cost(grid, a, b), 4)
	grid.set_river_links(b, 1)
	assert_eq(m.step_cost(grid, a, b), 6)
	grid.set_terrain(b, Terrain.Type.PLAINS)
	assert_eq(m.step_cost(grid, a, b), 4)
	grid.set_road_links(a, 1)
	assert_eq(m.step_cost(grid, a, b), 1)
	grid.set_terrain(b, Terrain.Type.WATER)
	assert_eq(m.step_cost(grid, a, b), Terrain.IMPASSABLE)
	assert_eq(m.step_cost(grid, a, Vector2i(0, 5)), Terrain.IMPASSABLE)


# --- plan ---


func test_plan_row() -> void:
	var state := _state(_row_grid())
	var route := OperationalRoutes.plan(state, state.formations[0], Vector2i(6, 0), false)
	assert_eq(route, _route(1, 6))


func test_plan_road_is_cheaper() -> void:
	var grid := _row_grid()
	for q in range(0, 9):
		grid.set_road_links(Vector2i(q, 0), 1)
	var state := _state(grid)
	var m := OperationalMovement.shipped()
	var route := OperationalRoutes.plan(state, state.formations[0], Vector2i(6, 0), false)
	var cost := 0
	var prev := Vector2i.ZERO
	for hex in route:
		cost += m.step_cost(grid, prev, hex)
		prev = hex
	assert_eq(route.size(), 6)
	assert_eq(cost, 6)


func test_plan_empty_cases() -> void:
	var grid := _row_grid()
	grid.set_terrain(Vector2i(3, 0), Terrain.Type.WATER)
	var state := _state(grid)
	var f := state.formations[0]
	assert_true(OperationalRoutes.plan(state, f, Vector2i(6, 0), false).is_empty())
	assert_true(OperationalRoutes.plan(state, f, Vector2i(0, 0), false).is_empty())
	assert_true(OperationalRoutes.plan(state, f, Vector2i(3, 0), false).is_empty())
	assert_true(OperationalRoutes.plan(state, f, Vector2i(20, 0), false).is_empty())


func test_plan_through_own_not_to_own() -> void:
	var state := _state(_row_grid(), {Vector2i(2, 0): 0})
	var f := state.formations[0]
	assert_eq(OperationalRoutes.plan(state, f, Vector2i(4, 0), false), _route(1, 4))
	assert_true(OperationalRoutes.plan(state, f, Vector2i(2, 0), false).is_empty())


func test_plan_enemy_blocks_and_destination_enemy_empty() -> void:
	var state := _state(_row_grid(), {Vector2i(2, 0): 1})
	var f := state.formations[0]
	assert_true(OperationalRoutes.plan(state, f, Vector2i(5, 0), false).is_empty())
	assert_true(OperationalRoutes.plan(state, f, Vector2i(2, 0), false).is_empty())


func test_plan_contact_grid() -> void:
	var state := _contact_state()
	var f := state.formations[0]
	assert_eq(OperationalRoutes.plan(state, f, Vector2i(6, 0), false), _route(1, 6))
	assert_true(OperationalRoutes.plan(state, f, Vector2i(6, 0), true).is_empty())
	assert_eq(OperationalRoutes.plan(state, f, Vector2i(4, 0), true), _route(1, 4))


func test_plan_avoid_contact_open_grid() -> void:
	var grid := Fixtures.plains_grid(4)
	var state := _state(grid, {Vector2i(0, 0): 1})
	state.formations[0].coord = Vector2i(-4, 0)
	var dest := Vector2i(4, 0)
	var f := state.formations[0]
	var zone := {}
	for n in Hex.neighbors(Vector2i.ZERO):
		zone[n] = true
	var straight := OperationalRoutes.plan(state, f, dest, false)
	var around := OperationalRoutes.plan(state, f, dest, true)
	assert_false(around.is_empty())
	for hex in around:
		assert_false(zone.has(hex), "route enters the zone at %s" % hex)
	var zone_hexes := 0
	for hex in straight:
		if zone.has(hex):
			zone_hexes += 1
	assert_true(zone_hexes >= 1)
	assert_true(around.size() > straight.size())


func test_plan_tie_break_is_deterministic() -> void:
	var grid := Fixtures.plains_grid(3)
	var state := _state(grid)
	var f := state.formations[0]
	var dest := Vector2i(1, 1)
	var first := OperationalRoutes.plan(state, f, dest, false)
	var second := OperationalRoutes.plan(state, f, dest, false)
	assert_eq(first, second)
	# (1, 0) comes first in Hex.DIRECTIONS.
	assert_eq(first, [Vector2i(1, 0), dest] as Array[Vector2i])


# --- walk ---


func _walk(
	state: OperationalState, from: Vector2i, route: Array[Vector2i], budget: int
) -> Dictionary:
	return OperationalRoutes.walk(state, state.formations[0], from, route, budget)


func test_walk_out_of_points() -> void:
	var state := _state(_row_grid())
	var r := _walk(state, Vector2i.ZERO, _route(1, 6), 8)
	assert_eq(r["end"], Vector2i(4, 0))
	assert_eq(r["cost"], 8)
	assert_eq(r["stop"], &"out_of_points")
	assert_eq(r["steps"], _route(1, 4))


func test_walk_arrived_on_road() -> void:
	var grid := _row_grid()
	for q in range(0, 9):
		grid.set_road_links(Vector2i(q, 0), 1)
	var r := _walk(_state(grid), Vector2i.ZERO, _route(1, 6), 6)
	assert_eq(r["end"], Vector2i(6, 0))
	assert_eq(r["cost"], 6)
	assert_eq(r["stop"], &"arrived")


func test_walk_first_step_always() -> void:
	var grid := _row_grid()
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.MARSH)
	grid.set_river_links(Vector2i(1, 0), 1)
	var r := _walk(_state(grid), Vector2i.ZERO, _route(1, 3), 4)
	assert_eq(r["end"], Vector2i(1, 0))
	assert_eq(r["cost"], 6)
	assert_eq(r["stop"], &"out_of_points")


func test_walk_never_ends_on_formation() -> void:
	var state := _state(_row_grid(), {Vector2i(2, 0): 0})
	var r := _walk(state, Vector2i.ZERO, _route(1, 6), 4)
	assert_eq(r["end"], Vector2i(1, 0))
	assert_eq(r["steps"], _route(1, 1))
	assert_eq(r["cost"], 2)
	assert_eq(r["stop"], &"out_of_points")
	r = _walk(state, Vector2i.ZERO, _route(1, 6), 8)
	assert_eq(r["end"], Vector2i(4, 0))
	assert_eq((r["steps"] as Array).size(), 4)
	assert_eq(r["cost"], 8)


func test_walk_contact() -> void:
	var state := _contact_state()
	var r := _walk(state, Vector2i.ZERO, _route(1, 6), 6)
	assert_eq(r["end"], Vector2i(3, 0))
	assert_eq(r["stop"], &"out_of_points")
	r = _walk(state, Vector2i(3, 0), _route(4, 6), 6)
	assert_eq(r["end"], Vector2i(4, 0))
	assert_eq(r["cost"], 2)
	assert_eq(r["stop"], &"contact")
	r = _walk(state, Vector2i.ZERO, _route(1, 4), 8)
	assert_eq(r["end"], Vector2i(4, 0))
	assert_eq(r["stop"], &"arrived")


# --- forecast ---


func test_forecast_row() -> void:
	var f := _state(_row_grid())
	var dest := Vector2i(6, 0)
	assert_eq(
		OperationalRoutes.forecast(f, f.formations[0], dest, 8, false),
		[Vector2i(4, 0), Vector2i(6, 0)] as Array[Vector2i]
	)
	assert_eq(
		OperationalRoutes.forecast(f, f.formations[0], dest, 4, false),
		[Vector2i(2, 0), Vector2i(4, 0), Vector2i(6, 0)] as Array[Vector2i]
	)


func test_forecast_contact_and_empty() -> void:
	var state := _contact_state()
	var f := state.formations[0]
	assert_eq(
		OperationalRoutes.forecast(state, f, Vector2i(6, 0), 6, false),
		[Vector2i(3, 0), Vector2i(4, 0)] as Array[Vector2i]
	)
	assert_true(OperationalRoutes.forecast(state, f, Vector2i(6, 0), 6, true).is_empty())


# --- real map ---


func test_every_formation_can_move_on_the_real_map() -> void:
	var state := Operation.build(&"suwalki_gap", 7)
	assert_true(state != null)
	for f in state.formations:
		var found := false
		for hex in state.grid.coords():
			if Hex.distance(f.coord, hex) < 3 or hex == f.coord:
				continue
			if not OperationalRoutes.plan(state, f, hex, true).is_empty():
				found = true
				break
		assert_true(found, "%s has no route" % f.id)


func test_plan_speed_on_theatre_map() -> void:
	var state := Operation.build(&"suwalki_gap", 7)
	var f := state.formations[0]
	var land: Array[Vector2i] = []
	for c in state.grid.coords():
		if state.grid.get_terrain(c) != Terrain.Type.WATER:
			land.append(c)
	# The farthest land hex that can be reached (untimed probe), so the search crosses the map.
	var origin := f.coord
	land.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return Hex.distance(origin, a) > Hex.distance(origin, b)
	)
	var dest := origin
	for c in land:
		if (
			state.formation_at(c) == null
			and not OperationalRoutes.plan(state, f, c, false).is_empty()
		):
			dest = c
			break
	var times: Array[float] = []
	var route: Array[Vector2i] = []
	for _i in 5:
		var t0 := Time.get_ticks_usec()
		route = OperationalRoutes.plan(state, f, dest, false)
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
	times.sort()
	print("operational plan median %.1f ms (%d hexes)" % [times[2], route.size()])
	assert_true(route.size() > 0, "no route across the map")
	assert_true(times[2] <= 90.0, "plan median %.1f ms" % times[2])
