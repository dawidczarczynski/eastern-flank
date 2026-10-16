extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var grid: HexGrid


func before_each() -> void:
	grid = Fixtures.plains_grid(2)


func test_straight_path_on_plains() -> void:
	var path := _checked_path(Vector2i.ZERO, Vector2i(2, 0), 3)
	assert_eq(path, _path([Vector2i(1, 0), Vector2i(2, 0)]))


func test_ties_follow_directions_order() -> void:
	# Via (1,0) and via (0,1) both cost 2; (1,0) comes first in Hex.DIRECTIONS.
	var path := _checked_path(Vector2i.ZERO, Vector2i(1, 1), 3)
	assert_eq(path, _path([Vector2i(1, 0), Vector2i(1, 1)]))


func test_path_avoids_forest_when_cheaper() -> void:
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	var path := _checked_path(Vector2i.ZERO, Vector2i(1, 1), 3)
	assert_eq(path, _path([Vector2i(0, 1), Vector2i(1, 1)]))


func test_path_goes_through_forest_when_no_alternative() -> void:
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	grid.set_terrain(Vector2i(0, 1), Terrain.Type.WATER)
	var path := _checked_path(Vector2i.ZERO, Vector2i(1, 1), 3)
	assert_eq(path, _path([Vector2i(1, 0), Vector2i(1, 1)]))


func test_path_empty_when_over_budget() -> void:
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	grid.set_terrain(Vector2i(0, 1), Terrain.Type.WATER)
	assert_eq(grid.path_to(Vector2i.ZERO, Vector2i(1, 1), 2), _path([]))


func test_path_avoids_blocked_tiles() -> void:
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	var blocked := {Vector2i(0, 1): true}
	var path := _checked_path(Vector2i.ZERO, Vector2i(1, 1), 3, blocked)
	assert_eq(path, _path([Vector2i(1, 0), Vector2i(1, 1)]))


func test_path_to_origin_is_empty() -> void:
	assert_eq(grid.path_to(Vector2i.ZERO, Vector2i.ZERO, 3), _path([]))


func test_path_to_off_map_target_is_empty() -> void:
	assert_eq(grid.path_to(Vector2i.ZERO, Vector2i(5, 5), 3), _path([]))


func test_path_to_impassable_target_is_empty() -> void:
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.WATER)
	assert_eq(grid.path_to(Vector2i.ZERO, Vector2i(1, 0), 3), _path([]))


func test_path_to_blocked_target_is_empty() -> void:
	var blocked := {Vector2i(1, 0): true}
	assert_eq(grid.path_to(Vector2i.ZERO, Vector2i(1, 0), 3, blocked), _path([]))


func test_every_reachable_tile_has_a_valid_path() -> void:
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	grid.set_terrain(Vector2i(-1, 1), Terrain.Type.WATER)
	var blocked := {Vector2i(0, -1): true}
	var reach := grid.reachable(Vector2i.ZERO, 4, blocked)
	for target: Vector2i in reach:
		if target == Vector2i.ZERO:
			continue
		var path := _checked_path(Vector2i.ZERO, target, 4, blocked)
		assert_false(path.is_empty(), "no path to %s" % str(target))


## Calls path_to twice and checks the invariants on the result.
func _checked_path(
	origin: Vector2i, target: Vector2i, budget: int, blocked: Dictionary = {}
) -> Array[Vector2i]:
	var path := grid.path_to(origin, target, budget, blocked)
	assert_eq(grid.path_to(origin, target, budget, blocked), path, "not deterministic")
	if path.is_empty():
		return path
	assert_eq(path[-1], target, "path must end with target")
	assert_false(path.has(origin), "path must exclude origin")
	var previous := origin
	var cost := 0
	for c in path:
		assert_eq(Hex.distance(previous, c), 1, "%s not adjacent to %s" % [c, previous])
		assert_true(grid.move_cost(c) != Terrain.IMPASSABLE, "impassable %s" % str(c))
		assert_false(blocked.has(c), "blocked %s" % str(c))
		cost += grid.move_cost(c)
		previous = c
	assert_eq(cost, grid.reachable(origin, budget, blocked).get(target), "cost mismatch")
	return path


func _path(tiles: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(tiles)
	return result
