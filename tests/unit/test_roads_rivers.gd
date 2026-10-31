# gdlint: disable=max-public-methods
extends TestCase
## TASK-108: roads (per link) and rivers (per hex) on HexGrid – HexGrid.step_cost and everything
## that plans with it (reachable, path_to, MoveUnitCommand, AiPlayer). Hand-made grids.

const Fixtures := preload("res://tests/fixtures.gd")
const UNITS_DIR := "res://data/units/"

var grid: HexGrid


func before_each() -> void:
	grid = Fixtures.plains_grid(3)


## Road link a <-> b stored on both tiles (the storage rule for two land tiles).
func _road(g: HexGrid, a: Vector2i, b: Vector2i) -> void:
	g.set_road_links(a, g.road_links(a) | (1 << Hex.DIRECTIONS.find(b - a)))
	g.set_road_links(b, g.road_links(b) | (1 << Hex.DIRECTIONS.find(a - b)))


## Road along consecutive tiles of `tiles`.
func _road_along(g: HexGrid, tiles: Array[Vector2i]) -> void:
	for i in range(1, tiles.size()):
		_road(g, tiles[i - 1], tiles[i])


## Makes `c` a river hex (a river link towards direction `dir`).
func _river(g: HexGrid, c: Vector2i, dir: int = 0) -> void:
	g.set_river_links(c, g.river_links(c) | (1 << dir))


# --- data ---


func test_features_come_from_data() -> void:
	var features := Terrain.features()
	assert_true(features != null, "data/terrain/features.tres loads")
	assert_eq(features.road_move_cost, 1)
	assert_eq(features.river_extra_cost, 1)


func test_most_expensive_step_fits_the_smallest_unit_move() -> void:
	var smallest := 1 << 30
	for file in DirAccess.get_files_at(UNITS_DIR):
		if file.ends_with(".tres"):
			var definition := load(UNITS_DIR + file) as UnitDefinition
			if definition != null:
				smallest = mini(smallest, definition.move_points)
	assert_true(smallest < 1 << 30, "unit definitions found")
	for t: int in Terrain.Type.values():
		var cost := Terrain.move_cost(t as Terrain.Type)
		if cost == Terrain.IMPASSABLE:
			continue
		var worst := cost + Terrain.features().river_extra_cost
		assert_true(
			worst <= smallest, "%s: %d > move %d" % [Terrain.Type.keys()[t], worst, smallest]
		)


# --- link masks ---


func test_links_default_to_zero() -> void:
	assert_eq(grid.road_links(Vector2i.ZERO), 0)
	assert_eq(grid.river_links(Vector2i.ZERO), 0)
	assert_false(grid.is_river(Vector2i.ZERO))
	assert_false(grid.has_road(Vector2i.ZERO, Vector2i(1, 0)))
	assert_eq(grid.road_links(Vector2i(9, 9)), 0, "off the map")


func test_has_links_only_with_a_mask() -> void:
	assert_false(grid.has_links())
	grid.set_river_links(Vector2i.ZERO, 1)
	assert_true(grid.has_links())
	grid.set_river_links(Vector2i.ZERO, 0)
	assert_false(grid.has_links(), "a zero mask removes the entry")


func test_has_road_follows_the_bit_of_the_direction() -> void:
	for dir in 6:
		var g := Fixtures.plains_grid(2)
		g.set_road_links(Vector2i.ZERO, 1 << dir)
		for other in 6:
			var n: Vector2i = Hex.DIRECTIONS[other]
			assert_eq(g.has_road(Vector2i.ZERO, n), other == dir, "bit %d, dir %d" % [dir, other])
		assert_false(g.has_road(Vector2i.ZERO, Vector2i(2, 0)), "not a neighbour")


func test_any_river_link_makes_a_river_hex() -> void:
	grid.set_river_links(Vector2i(1, 0), 1 << 4)
	assert_true(grid.is_river(Vector2i(1, 0)))
	assert_eq(grid.river_links(Vector2i(1, 0)), 1 << 4)


# --- step_cost ---


func test_step_cost_without_links_is_the_terrain_cost() -> void:
	var a := Vector2i.ZERO
	var b := Vector2i(1, 0)
	grid.set_terrain(b, Terrain.Type.FOREST)
	assert_eq(grid.step_cost(a, b), 2)
	grid.set_terrain(b, Terrain.Type.URBAN)
	assert_eq(grid.step_cost(a, b), 1)
	grid.set_terrain(b, Terrain.Type.MARSH)
	assert_eq(grid.step_cost(a, b), 2)
	grid.set_terrain(b, Terrain.Type.FIELDS)
	assert_eq(grid.step_cost(a, b), 1)


func test_road_link_makes_the_step_cost_one() -> void:
	var a := Vector2i.ZERO
	var b := Vector2i(1, 0)
	grid.set_terrain(b, Terrain.Type.FOREST)
	_road(grid, a, b)
	assert_eq(grid.step_cost(a, b), 1)
	grid.set_terrain(b, Terrain.Type.HILLS)
	assert_eq(grid.step_cost(a, b), 1)
	grid.set_terrain(b, Terrain.Type.MARSH)
	assert_eq(grid.step_cost(a, b), 1)
	assert_eq(grid.move_cost(b), 2, "move_cost stays the terrain cost")


func test_road_in_a_neighbouring_hex_does_not_leak() -> void:
	var a := Vector2i.ZERO
	var c := Vector2i(1, 0)
	grid.set_terrain(c, Terrain.Type.FOREST)
	_road(grid, a, Vector2i(0, 1))
	_road(grid, c, Vector2i(1, -1))
	assert_eq(grid.step_cost(a, c), 2)
	assert_eq(grid.step_cost(c, a), 1, "plains")


func test_entering_a_river_hex_costs_one_more() -> void:
	var a := Vector2i.ZERO
	var b := Vector2i(1, 0)
	_river(grid, b)
	assert_eq(grid.step_cost(a, b), 2, "plains river hex")
	grid.set_terrain(b, Terrain.Type.FOREST)
	assert_eq(grid.step_cost(a, b), 3, "forest river hex")
	grid.set_terrain(b, Terrain.Type.MARSH)
	assert_eq(grid.step_cost(a, b), 3, "marsh river hex")


func test_a_road_link_bridges_the_river() -> void:
	var a := Vector2i.ZERO
	var b := Vector2i(1, 0)
	grid.set_terrain(b, Terrain.Type.FOREST)
	_river(grid, b)
	_road(grid, a, b)
	assert_eq(grid.step_cost(a, b), 1)


func test_leaving_a_river_hex_costs_nothing_extra() -> void:
	var a := Vector2i.ZERO
	var b := Vector2i(1, 0)
	_river(grid, a)
	assert_eq(grid.step_cost(a, b), 1)


func test_moving_along_a_river_pays_every_hex() -> void:
	var a := Vector2i.ZERO
	var b := Vector2i(1, 0)
	_river(grid, a)
	_river(grid, b)
	assert_eq(grid.step_cost(a, b), 2)
	grid.set_terrain(b, Terrain.Type.FOREST)
	assert_eq(grid.step_cost(a, b), 3)


func test_road_towards_water_or_off_the_map_stays_impassable() -> void:
	var a := Vector2i(3, 0)
	var water := Vector2i(3, -1)
	grid.set_terrain(water, Terrain.Type.WATER)
	grid.set_road_links(a, (1 << 0) | (1 << 2))  # east = off the map, north-west = water
	assert_eq(grid.step_cost(a, water), Terrain.IMPASSABLE)
	assert_false(grid.has_tile(a + Hex.DIRECTIONS[0]))
	assert_eq(grid.step_cost(a, a + Hex.DIRECTIONS[0]), Terrain.IMPASSABLE)


# --- search ---


func test_path_takes_the_road_around_a_forest() -> void:
	for c: Vector2i in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, -1), Vector2i(2, -1)]:
		grid.set_terrain(c, Terrain.Type.FOREST)
	var road: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, -1), Vector2i(2, -1), Vector2i(2, 0)]
	_road_along(grid, road)
	assert_eq(grid.path_to(Vector2i.ZERO, Vector2i(2, 0), 5), road.slice(1))
	assert_eq(grid.reachable(Vector2i.ZERO, 5)[Vector2i(2, 0)], 3)


func test_road_through_forest_reaches_three_hexes() -> void:
	for c in grid.coords():
		if c != Vector2i.ZERO:
			grid.set_terrain(c, Terrain.Type.FOREST)
	var without := grid.reachable(Vector2i(-3, 0), 3)
	assert_false(without.has(Vector2i(-1, 0)), "forest: one hex")
	_road_along(grid, [Vector2i(-3, 0), Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0)])
	var reach := grid.reachable(Vector2i(-3, 0), 3)
	assert_eq(reach.get(Vector2i(-2, 0)), 1)
	assert_eq(reach.get(Vector2i(-1, 0)), 2)
	assert_eq(reach.get(Vector2i(0, 0)), 3)


# --- commands and AI ---


func test_move_spends_the_road_cost() -> void:
	for c in grid.coords():
		grid.set_terrain(c, Terrain.Type.FOREST)
	_road_along(grid, [Vector2i(-3, 0), Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0)])
	var state := GameState.new(grid, 2, 1)
	var unit := state.add_unit(0, Fixtures.infantry(), Vector2i(-3, 0))
	var sim := GameSimulation.new(state)
	assert_true(sim.execute(MoveUnitCommand.new(unit.id, Vector2i(0, 0))))
	assert_eq(unit.coord, Vector2i(0, 0))
	assert_eq(unit.moves_left, 0)


func test_move_across_a_river_hex_spends_the_extra_point() -> void:
	_river(grid, Vector2i(1, 0), 1)
	_river(grid, Vector2i(1, 0), 4)
	_river(grid, Vector2i(1, 1), 1)
	_river(grid, Vector2i(1, -1), 4)
	var state := GameState.new(grid, 2, 1)
	var unit := state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	var sim := GameSimulation.new(state)
	assert_true(sim.execute(MoveUnitCommand.new(unit.id, Vector2i(2, 0))))
	assert_eq(unit.moves_left, 0, "plains river hex 2 + plains 1 = 3")


func test_ai_takes_the_road_through_the_forest() -> void:
	var g := Fixtures.plains_grid(5)
	for c in g.coords():
		g.set_terrain(c, Terrain.Type.FOREST)
	var road: Array[Vector2i] = []
	for q in range(4, -2, -1):
		road.append(Vector2i(q, 0))
	_road_along(g, road)
	var state := GameState.new(g, 2, 1)
	state.add_unit(0, Fixtures.infantry(), Vector2i(-4, 0))
	var tank := state.add_unit(1, Fixtures.generic_tank(), Vector2i(4, 0))
	var sim := GameSimulation.new(state)
	sim.execute(EndTurnCommand.new())
	AiPlayer.new().take_turn(sim)
	assert_eq(tank.coord, Vector2i(-1, 0))


# --- generated maps ---


func test_generated_maps_have_no_roads_or_rivers() -> void:
	for seed_value in range(1, 21):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var g := MapGenerator.generate(12, 10, rng)
		for c in g.coords():
			assert_eq(g.road_links(c), 0, "seed %d %s" % [seed_value, c])
			assert_eq(g.river_links(c), 0, "seed %d %s" % [seed_value, c])
