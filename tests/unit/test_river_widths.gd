extends TestCase
## RiverWidths: the water width of a river hex from the land-cover raster.

const CELL := 0.1


func after_each() -> void:
	MapScale.reset()


## A raster of 60 x 40 cells, a water strip `rows` cells wide (north-south) across the middle.
func _cover(rows: int) -> LandCover:
	var cells := PackedByteArray()
	cells.resize(60 * 40)
	var start := 20 - rows / 2
	for j in range(start, start + rows):
		for i in 60:
			cells[j * 60 + i] = LandCover.Kind.WATER
	return LandCover.from_cells(cells, 60, 40, Vector2(-1.0, -1.0), CELL)


func test_measures_strip_width() -> void:
	var cover := _cover(4)
	var m := RiverWidths.measure_m(cover, Vector3(2.0, 0.0, 0.95))
	assert_true(absf(m - 4.0 * CELL * MapScale.metres_per_unit) < 16.0, "width %f" % m)


func test_no_water_is_zero() -> void:
	var cover := _cover(0)
	assert_eq(RiverWidths.measure_m(cover, Vector3(2.0, 0.0, 0.95)), 0.0)


func test_lake_is_capped() -> void:
	var cover := _cover(38)
	assert_true(RiverWidths.measure_m(cover, Vector3(2.0, 0.0, 0.95)) <= RiverWidths.MAX_WIDTH_M)


func test_apply_widens_but_never_narrows() -> void:
	var grid := HexGrid.new()
	var a := Vector2i(0, 0)
	var b := Vector2i(0, 1)
	for c: Vector2i in [a, b]:
		grid.set_terrain(c, Terrain.Type.PLAINS)
	grid.set_river_links(a, 1)
	grid.set_river_links(b, 8)
	grid.set_river_width_m(a, 3.0)
	grid.set_river_width_m(b, 500.0)
	var cover := _cover(14)
	RiverWidths.apply(grid, cover)
	assert_true(grid.river_width_m(a) > 3.0)
	assert_eq(grid.river_width_m(b), 500.0)
