extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")


func test_defense_bonus_loaded_from_data() -> void:
	assert_eq(Terrain.definition(Terrain.Type.PLAINS).defense_bonus, 0)
	assert_eq(Terrain.definition(Terrain.Type.FOREST).defense_bonus, 1)
	assert_eq(Terrain.definition(Terrain.Type.HILLS).defense_bonus, 2)
	assert_eq(Terrain.definition(Terrain.Type.WATER).defense_bonus, 0)


func test_water_is_impassable_in_data() -> void:
	assert_true(Terrain.definition(Terrain.Type.WATER).impassable)
	assert_false(Terrain.definition(Terrain.Type.PLAINS).impassable)


func test_every_type_has_a_definition_with_matching_id() -> void:
	var ids: Array[StringName] = [&"plains", &"forest", &"hills", &"water"]
	for t: int in Terrain.Type.values():
		var definition := Terrain.definition(t as Terrain.Type)
		assert_true(definition != null)
		assert_eq(definition.id, ids[t])


func test_grid_move_cost_derives_from_definitions() -> void:
	var grid := HexGrid.new()
	grid.set_terrain(Vector2i(0, 0), Terrain.Type.PLAINS)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	grid.set_terrain(Vector2i(2, 0), Terrain.Type.HILLS)
	grid.set_terrain(Vector2i(3, 0), Terrain.Type.WATER)
	assert_eq(grid.move_cost(Vector2i(0, 0)), 1)
	assert_eq(grid.move_cost(Vector2i(1, 0)), 2)
	assert_eq(grid.move_cost(Vector2i(2, 0)), 2)
	assert_eq(grid.move_cost(Vector2i(3, 0)), Terrain.IMPASSABLE)


func test_grid_defense_bonus() -> void:
	var grid := Fixtures.plains_grid(2)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	grid.set_terrain(Vector2i(0, 1), Terrain.Type.HILLS)
	assert_eq(grid.defense_bonus(Vector2i(0, 0)), 0)
	assert_eq(grid.defense_bonus(Vector2i(1, 0)), 1)
	assert_eq(grid.defense_bonus(Vector2i(0, 1)), 2)


func test_defense_bonus_off_map_is_zero() -> void:
	assert_eq(Fixtures.plains_grid(1).defense_bonus(Vector2i(9, 9)), 0)
