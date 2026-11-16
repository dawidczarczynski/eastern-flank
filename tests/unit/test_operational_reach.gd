extends TestCase
## The one-turn reach of a formation (TASK-155): OperationalRoutes.reach, consistent with forecast.

const MARCH_BUDGET := 8


static func _plains(radius: int) -> HexGrid:
	var grid := HexGrid.new()
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			if absi(q + r) <= radius:
				grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
	return grid


static func _state(grid: HexGrid, enemies: Array[Vector2i] = []) -> OperationalState:
	var state := OperationalState.new()
	state.grid = grid
	state.formations.append(_formation(&"f", 0, Vector2i.ZERO))
	var n := 0
	for coord in enemies:
		n += 1
		state.formations.append(_formation(StringName("e%d" % n), 1, coord))
	return state


static func _formation(id: StringName, owner: int, coord: Vector2i) -> Formation:
	var f := Formation.new()
	f.id = id
	f.owner_id = owner
	f.coord = coord
	return f


func test_all_road_budget_8_reaches_8_hexes() -> void:
	var grid := HexGrid.new()
	for q in range(0, 14):
		grid.set_terrain(Vector2i(q, 0), Terrain.Type.PLAINS)
		grid.set_road_links(Vector2i(q, 0), 1)
	var state := _state(grid)
	var reach := OperationalRoutes.reach(state, state.formations[0], MARCH_BUDGET)
	assert_eq(reach.size(), 8)
	assert_eq(reach[Vector2i(8, 0)], 8)
	assert_false(reach.has(Vector2i(9, 0)))


func test_open_ground_budget_8_reaches_4_hexes_out() -> void:
	var state := _state(_plains(6))
	var reach := OperationalRoutes.reach(state, state.formations[0], MARCH_BUDGET)
	assert_eq(reach.size(), 3 * 4 * 5)  # rings 1..4 of a hex disc: 6 + 12 + 18 + 24 = 60
	for hex: Vector2i in reach:
		assert_true(Hex.distance(Vector2i.ZERO, hex) <= 4)
	assert_false(reach.has(Vector2i.ZERO))


func test_forest_costs_more() -> void:
	var grid := _plains(6)
	for hex in grid.coords():
		grid.set_terrain(hex, Terrain.Type.FOREST)
	var state := _state(grid)
	var reach := OperationalRoutes.reach(state, state.formations[0], MARCH_BUDGET)
	for hex: Vector2i in reach:
		assert_true(Hex.distance(Vector2i.ZERO, hex) <= 2)
	assert_true(reach.has(Vector2i(2, 0)))


func test_enemy_zone_of_control_ends_but_does_not_pass() -> void:
	var state := _state(_plains(6), [Vector2i(3, 0)])
	var reach := OperationalRoutes.reach(state, state.formations[0], MARCH_BUDGET)
	assert_false(reach.has(Vector2i(3, 0)))  # the enemy hex
	assert_true(reach.has(Vector2i(2, 0)))  # next to the enemy: can end there
	assert_false(reach.has(Vector2i(4, 0)))  # behind the zone: not through it
	assert_false(reach.has(Vector2i(5, 0)))


func test_water_is_impassable() -> void:
	var grid := _plains(6)
	for r in range(-6, 7):
		grid.set_terrain(Vector2i(2, r), Terrain.Type.WATER)
	var state := _state(grid)
	var reach := OperationalRoutes.reach(state, state.formations[0], MARCH_BUDGET)
	assert_false(reach.has(Vector2i(2, 0)))
	assert_false(reach.has(Vector2i(3, 0)))


func test_own_formation_is_passed_but_not_an_ending() -> void:
	var state := _state(_plains(6))
	state.formations.append(_formation(&"mate", 0, Vector2i(1, 0)))
	var reach := OperationalRoutes.reach(state, state.formations[0], MARCH_BUDGET)
	assert_false(reach.has(Vector2i(1, 0)))
	assert_true(reach.has(Vector2i(2, 0)))


func test_stuck_formation_makes_only_the_first_step() -> void:
	var grid := _plains(3)
	for hex in grid.coords():
		grid.set_terrain(hex, Terrain.Type.MARSH if hex != Vector2i.ZERO else Terrain.Type.PLAINS)
	var state := _state(grid)
	var reach := OperationalRoutes.reach(state, state.formations[0], 1)
	assert_eq(reach.size(), 6)
	for hex: Vector2i in reach:
		assert_eq(Hex.distance(Vector2i.ZERO, hex), 1)


func test_deterministic() -> void:
	var state := _state(_plains(6), [Vector2i(3, 1)])
	var a := OperationalRoutes.reach(state, state.formations[0], MARCH_BUDGET)
	var b := OperationalRoutes.reach(state, state.formations[0], MARCH_BUDGET)
	assert_eq(a, b)


func test_consistent_with_forecast() -> void:
	var grid := _plains(5)
	grid.set_terrain(Vector2i(1, 1), Terrain.Type.FOREST)
	grid.set_terrain(Vector2i(2, -1), Terrain.Type.WATER)
	for q in range(0, 5):
		grid.set_road_links(Vector2i(q, -2), 1)
	var state := _state(grid, [Vector2i(-3, 2)])
	var f := state.formations[0]
	var reach := OperationalRoutes.reach(state, f, MARCH_BUDGET)
	assert_false(reach.is_empty())
	for hex in grid.coords():
		if hex == f.coord or state.formation_at(hex) != null:
			continue
		var stops := OperationalRoutes.forecast(state, f, hex, MARCH_BUDGET, true)
		if stops.is_empty():
			assert_false(reach.has(hex), "no route to %s but in reach" % hex)
		elif reach.has(hex):
			assert_eq(stops[0], hex, "reach hex %s must be finished in one turn" % hex)
		else:
			assert_true(stops[0] != hex, "hex %s outside reach but forecast ends there" % hex)


func test_outline_of_one_hex_is_a_closed_hexagon() -> void:
	var loops := FrontLine.outline({Vector2i.ZERO: true})
	assert_eq(loops.size(), 1)
	var loop: PackedVector2Array = loops[0]
	assert_eq(loop.size(), 7)
	assert_true(loop[0].is_equal_approx(loop[6]))


func test_outline_of_a_disc_skips_inner_edges() -> void:
	var hexes := {Vector2i.ZERO: true}
	for n in Hex.neighbors(Vector2i.ZERO):
		hexes[n] = true
	var loops := FrontLine.outline(hexes)
	assert_eq(loops.size(), 1)
	assert_eq((loops[0] as PackedVector2Array).size(), 19)  # 18 edges
	assert_eq(FrontLine.outline({}), [])
