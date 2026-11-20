extends TestCase

const WIDTH := 5
const HEIGHT := 4


## A source grid of WIDTH x HEIGHT offset tiles whose elevations and terrain all differ.
func _source() -> HexGrid:
	var grid := HexGrid.new()
	grid.authored_elevation = true
	for row in HEIGHT:
		for col in WIDTH:
			var c := MapGenerator.offset_to_axial(col, row)
			var terrain := Terrain.Type.PLAINS if (col + row) % 2 == 0 else Terrain.Type.FOREST
			grid.set_terrain(c, terrain)
			grid.set_elevation(c, float(col * 7 + row * 3) * 0.01)
			grid.set_elevation_m(c, 100.0 + float(col * 5 + row))
	return grid


func _at(col: int, row: int) -> Vector2i:
	return MapGenerator.offset_to_axial(col, row)


func test_tile_counts_follow_the_scale() -> void:
	assert_eq(MapTiler.tile(_source(), WIDTH, HEIGHT, 1, 1).coords().size(), WIDTH * HEIGHT)
	assert_eq(MapTiler.tile(_source(), WIDTH, HEIGHT, 2, 2).coords().size(), WIDTH * HEIGHT * 4)
	assert_eq(MapTiler.tile(_source(), WIDTH, HEIGHT, 4, 4).coords().size(), WIDTH * HEIGHT * 16)


func test_scale_factor_gives_a_square_tile_grid() -> void:
	assert_eq(MapTiler.tiles_for_scale(1), 1)
	assert_eq(MapTiler.tiles_for_scale(4), 2)
	assert_eq(MapTiler.tiles_for_scale(16), 4)


func test_first_tile_is_the_source_unchanged() -> void:
	var source := _source()
	var grid := MapTiler.tile(source, WIDTH, HEIGHT, 2, 2)
	for c in source.coords():
		assert_eq(grid.get_terrain(c), source.get_terrain(c))
		assert_true(absf(grid.elevation(c) - source.elevation(c)) < 0.001, "elevation")
		assert_true(absf(grid.elevation_m(c) - source.elevation_m(c)) < 0.001, "elevation_m")


func test_heights_match_across_the_column_seam() -> void:
	var grid := MapTiler.tile(_source(), WIDTH, HEIGHT, 2, 2)
	for row in HEIGHT:
		var west := _at(WIDTH - 1, row)
		var east := _at(WIDTH, row)
		assert_true(absf(grid.elevation(west) - grid.elevation(east)) < 0.001, "row %d" % row)
		assert_true(absf(grid.elevation_m(west) - grid.elevation_m(east)) < 0.001, "m row %d" % row)


func test_heights_match_across_the_row_seam() -> void:
	var grid := MapTiler.tile(_source(), WIDTH, HEIGHT, 2, 2)
	for col in WIDTH * 2:
		var north := _at(col, HEIGHT - 1)
		var south := _at(col, HEIGHT)
		assert_true(absf(grid.elevation(north) - grid.elevation(south)) < 0.001, "col %d" % col)
		assert_eq(grid.get_terrain(north), grid.get_terrain(south))


func test_tiling_is_deterministic() -> void:
	var a := MapTiler.tile(_source(), WIDTH, HEIGHT, 4, 4)
	var b := MapTiler.tile(_source(), WIDTH, HEIGHT, 4, 4)
	assert_eq(a.coords().size(), b.coords().size())
	for c in a.coords():
		assert_eq(a.get_terrain(c), b.get_terrain(c))
		assert_eq(a.elevation(c), b.elevation(c))


func test_suwalki_tiles_to_the_documented_sizes() -> void:
	var map := ImportedMap.find(Scenario.SUWALKI_MAP_ID)
	assert_true(map != null, "Suwalki map")
	var source := map.to_grid()
	for scale in [1, 4, 16]:
		var n := MapTiler.tiles_for_scale(scale)
		var grid := MapTiler.tile(source, map.width, map.height, n, n)
		assert_eq(grid.coords().size(), map.width * map.height * scale, "scale %d" % scale)
	assert_eq(map.width * map.height * 16, 11520)
