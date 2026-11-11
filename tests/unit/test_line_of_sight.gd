extends TestCase
## LineOfSight (TASK-131a): forests, buildings and hills between two hexes block direct fire.

const Fixtures := preload("res://tests/fixtures.gd")

var grid: HexGrid


## An all-plains map of radius 6 with every tile at 0 m.
func before_each() -> void:
	grid = Fixtures.plains_grid(6)
	for c in grid.coords():
		grid.set_elevation(c, 0.0)


func _place(c: Vector2i, terrain: Terrain.Type, metres: float) -> void:
	grid.set_terrain(c, terrain)
	grid.set_elevation(c, metres / LineOfSight.ELEVATION_METRES)


func test_open_plains_line_is_visible() -> void:
	assert_true(LineOfSight.visible(grid, Vector2i(0, 0), Vector2i(4, 0)))
	assert_true(LineOfSight.visible(grid, Vector2i(-3, 0), Vector2i(3, -3)))


func test_forest_between_blocks() -> void:
	_place(Vector2i(2, 0), Terrain.Type.FOREST, 0.0)
	assert_false(LineOfSight.visible(grid, Vector2i(0, 0), Vector2i(4, 0)))


func test_urban_between_blocks() -> void:
	_place(Vector2i(2, 0), Terrain.Type.URBAN, 0.0)
	assert_false(LineOfSight.visible(grid, Vector2i(0, 0), Vector2i(4, 0)))


func test_forest_as_target_or_attacker_hex_does_not_block() -> void:
	_place(Vector2i(4, 0), Terrain.Type.FOREST, 0.0)
	assert_true(LineOfSight.visible(grid, Vector2i(0, 0), Vector2i(4, 0)))
	_place(Vector2i(0, 0), Terrain.Type.FOREST, 0.0)
	assert_true(LineOfSight.visible(grid, Vector2i(0, 0), Vector2i(4, 0)))


func test_hill_of_40_m_between_blocks() -> void:
	_place(Vector2i(2, 0), Terrain.Type.HILLS, 40.0)
	assert_false(LineOfSight.visible(grid, Vector2i(0, 0), Vector2i(4, 0)))


## The task's example of a 3 m hill that does not block contradicts its own rule (sight at 2 m
## above 0 m ground, 3 m > 2 m blocks); the rule wins: a rise below the eye height doesn't block.
func test_rise_below_eye_height_does_not_block() -> void:
	_place(Vector2i(2, 0), Terrain.Type.HILLS, 1.5)
	assert_true(LineOfSight.visible(grid, Vector2i(0, 0), Vector2i(4, 0)))
	_place(Vector2i(2, 0), Terrain.Type.HILLS, 3.0)
	assert_false(LineOfSight.visible(grid, Vector2i(0, 0), Vector2i(4, 0)))


## From a 40 m hill the sight line passes 22 m over the 20 m forest two hexes out; a unit on the
## plain behind the same forest does not see the target.
func test_unit_on_a_hill_sees_over_a_forest() -> void:
	_place(Vector2i(2, 0), Terrain.Type.FOREST, 0.0)
	assert_false(LineOfSight.visible(grid, Vector2i(0, 0), Vector2i(4, 0)))
	_place(Vector2i(0, 0), Terrain.Type.HILLS, 40.0)
	assert_true(LineOfSight.visible(grid, Vector2i(0, 0), Vector2i(4, 0)))
	assert_true(LineOfSight.visible(grid, Vector2i(4, 0), Vector2i(0, 0)))


func test_real_heights_of_imported_maps_are_used() -> void:
	grid.set_elevation_m(Vector2i(2, 0), 40.0)
	grid.set_elevation_m(Vector2i(0, 0), 0.0)
	grid.set_elevation_m(Vector2i(4, 0), 0.0)
	grid.set_elevation(Vector2i(2, 0), 0.0)
	assert_false(LineOfSight.visible(grid, Vector2i(0, 0), Vector2i(4, 0)))


func test_adjacent_hexes_always_see_each_other() -> void:
	_place(Vector2i(0, 0), Terrain.Type.HILLS, 900.0)
	for n in Hex.neighbors(Vector2i(0, 0)):
		_place(n, Terrain.Type.FOREST, 0.0)
		assert_true(LineOfSight.visible(grid, Vector2i(0, 0), n))
		assert_true(LineOfSight.visible(grid, n, Vector2i(0, 0)))


func test_visibility_is_symmetric_on_a_generated_map() -> void:
	var map := Scenario.default_battle(7).grid
	var coords := map.coords()
	var rng := RandomNumberGenerator.new()
	rng.seed = 131
	for i in 100:
		var a := coords[rng.randi_range(0, coords.size() - 1)]
		var b := coords[rng.randi_range(0, coords.size() - 1)]
		assert_eq(
			LineOfSight.visible(map, a, b), LineOfSight.visible(map, b, a), "%s <-> %s" % [a, b]
		)
	for c in coords:
		for n in Hex.neighbors(c):
			if map.has_tile(n):
				assert_true(LineOfSight.visible(map, c, n))


func test_hex_line_runs_from_a_to_b_through_neighbours() -> void:
	var line := Hex.line(Vector2i(0, 0), Vector2i(3, -2))
	assert_eq(line.size(), 4)
	assert_eq(line[0], Vector2i(0, 0))
	assert_eq(line[3], Vector2i(3, -2))
	for i in line.size() - 1:
		assert_eq(Hex.distance(line[i], line[i + 1]), 1)
