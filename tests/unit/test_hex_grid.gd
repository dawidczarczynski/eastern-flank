extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var grid: HexGrid


func before_each() -> void:
	grid = Fixtures.plains_grid(3)


func test_reachable_with_budget_one_is_origin_and_neighbors() -> void:
	assert_eq(grid.reachable(Vector2i.ZERO, 1).size(), 7)


func test_forest_costs_two() -> void:
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	assert_false(grid.reachable(Vector2i.ZERO, 1).has(Vector2i(1, 0)))
	assert_eq(grid.reachable(Vector2i.ZERO, 2).get(Vector2i(1, 0)), 2)


func test_water_is_impassable() -> void:
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.WATER)
	assert_false(grid.reachable(Vector2i.ZERO, 5).has(Vector2i(1, 0)))


func test_blocked_tiles_are_skipped() -> void:
	var reach := grid.reachable(Vector2i.ZERO, 1, {Vector2i(0, 1): true})
	assert_false(reach.has(Vector2i(0, 1)))
	assert_eq(reach.size(), 6)


func test_cannot_leave_map() -> void:
	assert_false(grid.reachable(Vector2i(3, 0), 1).has(Vector2i(4, 0)))
