extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")


func _grid_with(t: Terrain.Type, elevation: float, offset := Vector2i(2, 4)) -> HexGrid:
	var grid := Fixtures.plains_grid(0)
	var c := MapGenerator.offset_to_axial(offset.x, offset.y)
	grid.set_terrain(c, t)
	grid.set_elevation(c, elevation)
	return grid


func _build(grid: HexGrid, offset := Vector2i(2, 4), cost := -1, left := 0) -> Dictionary:
	return TerrainPanelModel.build(
		grid, MapGenerator.offset_to_axial(offset.x, offset.y), cost, left
	)


func test_hex_is_one_based_zero_padded() -> void:
	var m := _build(_grid_with(Terrain.Type.PLAINS, 0.0))
	assert_eq(m["hex"], "03·05")


func test_hex_two_digits() -> void:
	var grid := _grid_with(Terrain.Type.PLAINS, 0.0, Vector2i(11, 9))
	assert_eq(_build(grid, Vector2i(11, 9))["hex"], "12·10")


func test_plains() -> void:
	var m := _build(_grid_with(Terrain.Type.PLAINS, 0.0))
	assert_eq(m["name"], "Plains")
	assert_eq(m["move"], "1")
	assert_eq(m["defense"], "+0")
	assert_eq(m["tags"], PackedStringArray())


func test_names_come_from_definitions() -> void:
	assert_eq(_build(_grid_with(Terrain.Type.FOREST, 0.0))["name"], "Forest")
	assert_eq(_build(_grid_with(Terrain.Type.HILLS, 0.0))["name"], "Hills")
	assert_eq(_build(_grid_with(Terrain.Type.WATER, 0.0))["name"], "Water")


func test_forest_values_from_data() -> void:
	var grid := _grid_with(Terrain.Type.FOREST, 0.0)
	var c := MapGenerator.offset_to_axial(2, 4)
	var m := _build(grid)
	assert_eq(m["move"], str(grid.move_cost(c)))
	assert_eq(m["defense"], "+%d" % grid.defense_bonus(c))


func test_water_is_impassable() -> void:
	var m := _build(_grid_with(Terrain.Type.WATER, 0.0))
	assert_eq(m["move"], "—")
	assert_eq(m["defense"], "—")
	assert_eq(m["tags"], PackedStringArray(["Impassable"]))


func test_real_terrain_shows_the_real_metres() -> void:
	var grid := _grid_with(Terrain.Type.PLAINS, 0.2)
	grid.set_elevation_m(MapGenerator.offset_to_axial(2, 4), 183.6)
	assert_eq(_build(grid)["elevation"], "184 m")


func test_elevation_formula() -> void:
	assert_eq(_build(_grid_with(Terrain.Type.PLAINS, 0.2))["elevation"], "96 m")
	assert_eq(_build(_grid_with(Terrain.Type.PLAINS, -0.3))["elevation"], "12 m")
	assert_eq(_build(_grid_with(Terrain.Type.PLAINS, 1.0))["elevation"], "432 m")


func test_path_text_and_raw_values() -> void:
	var m := _build(_grid_with(Terrain.Type.PLAINS, 0.0), Vector2i(2, 4), 2, 3)
	assert_eq(m["path"], "2 / 3 MP")
	assert_eq(m["path_cost"], 2)
	assert_eq(m["moves_left"], 3)


func test_no_path_is_empty() -> void:
	var m := _build(_grid_with(Terrain.Type.PLAINS, 0.0), Vector2i(2, 4), -1, 3)
	assert_eq(m["path"], "")
	assert_eq(m["path_cost"], -1)


func test_city_name_is_empty_without_a_city() -> void:
	assert_eq(_build(_grid_with(Terrain.Type.PLAINS, 0.0))["city"], "")


func test_city_name_is_passed_through() -> void:
	var grid := _grid_with(Terrain.Type.PLAINS, 0.0)
	var c := MapGenerator.offset_to_axial(2, 4)
	assert_eq(TerrainPanelModel.build(grid, c, -1, 0, "Gdańsk")["city"], "Gdańsk")


func test_path_row_only_for_a_valid_move_target() -> void:
	assert_eq(_build(_grid_with(Terrain.Type.PLAINS, 0.0), Vector2i(2, 4), -1, 5)["path"], "")
	assert_eq(
		_build(_grid_with(Terrain.Type.PLAINS, 0.0), Vector2i(2, 4), 0, 5)["path"], "0 / 5 MP"
	)
