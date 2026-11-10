extends TestCase
## Roads at real width (TASK-108b): a 5 m carriageway with 2.5 m verges at MapScale, the across
## attribute of the ribbon mesh and the 3 m scatter clearance.

const Fixtures := preload("res://tests/fixtures.gd")
const EPSILON := 1e-4
const KIND_ROAD := FeatureRibbonPlanner.Kind.ROAD


func _near(actual: float, expected: float, message := "") -> void:
	assert_true(
		absf(actual - expected) < EPSILON, "expected %f, got %f %s" % [expected, actual, message]
	)


func _link(grid: HexGrid, a: Vector2i, b: Vector2i) -> void:
	var dir := Hex.DIRECTIONS.find(b - a)
	grid.set_road_links(a, grid.road_links(a) | (1 << dir))
	grid.set_road_links(b, grid.road_links(b) | (1 << ((dir + 3) % 6)))


func _link_path(grid: HexGrid, path: Array[Vector2i]) -> void:
	for i in path.size() - 1:
		_link(grid, path[i], path[i + 1])


func after_each() -> void:
	MapScale.reset()


func _straight_road() -> HexGrid:
	var grid := Fixtures.plains_grid(3)
	_link_path(grid, [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)])
	return grid


func test_road_ribbon_is_ten_metres_wide_on_the_default_scale() -> void:
	assert_true(absf(MapScale.metres_per_unit - 144.34) < 0.01)
	assert_true(absf(FeatureRibbonPlanner.width(KIND_ROAD) - 10.0 / 144.34) < 1e-4)
	var indexed := FeatureRibbonPlanner.mesh(_straight_road(), KIND_ROAD)
	var points: PackedVector2Array = indexed["points"]
	var across: PackedFloat32Array = indexed["across"]
	assert_eq(across.size(), points.size(), "one across value per point")
	# Strip vertices come in left / right pairs; the cross-section is the road width.
	for i in range(0, points.size() - 24, 2):
		if absf(across[i]) != 1.0:
			continue
		assert_true(absf(points[i].distance_to(points[i + 1]) - 10.0 / 144.34) < 1e-4)
		assert_eq(across[i], -across[i + 1], "opposite edges")
		break


func test_road_width_follows_map_scale() -> void:
	var grid := _straight_road()
	var narrow := FeatureRibbonPlanner.width(KIND_ROAD)
	MapScale.metres_per_unit = MapScale.DEFAULT_METRES_PER_UNIT / 2.0
	assert_true(absf(FeatureRibbonPlanner.width(KIND_ROAD) - 2.0 * narrow) < 1e-6)
	for w in FeatureRibbonPlanner.half_widths(grid, KIND_ROAD)[0]:
		_near(w, narrow, "plans are rebuilt for the new scale")
	var edge := FeatureRibbonPlanner.edge_distance(grid, KIND_ROAD, 0.0, narrow * 0.9)
	assert_true(edge < 0.0, "the index follows the scale too (%f)" % edge)


func test_across_values_and_directions() -> void:
	var grid := _straight_road()
	_link(grid, Vector2i(0, 0), Vector2i(0, 1))  # a junction disc
	var indexed := FeatureRibbonPlanner.mesh(grid, KIND_ROAD)
	var across: PackedFloat32Array = indexed["across"]
	var dirs: PackedVector2Array = indexed["across_dirs"]
	assert_eq(dirs.size(), across.size())
	var zero_centres := 0
	for i in across.size():
		assert_true(across[i] >= -1.0 and across[i] <= 1.0)
		if across[i] == 0.0:
			zero_centres += 1
			assert_eq(dirs[i], Vector2.ZERO)
		else:
			_near(dirs[i].length(), 1.0, "unit direction")
	assert_eq(zero_centres, FeatureRibbonPlanner.discs(grid, KIND_ROAD).size(), "disc centres")
	_near(FeatureRibbonPlanner.carriageway_across(), 0.5, "carriageway edge")


func test_scatter_clearance_on_a_road_is_three_metres() -> void:
	var grid := _straight_road()
	var half := FeatureRibbonPlanner.width(KIND_ROAD) / 2.0
	var three_m := 3.0 / 144.34
	_near(FeatureRibbonPlanner.clearance(KIND_ROAD), three_m)
	var y := half + three_m
	assert_false(FeatureRibbonPlanner.is_clear(grid, 0.0, y - 0.002))
	assert_true(FeatureRibbonPlanner.is_clear(grid, 0.0, y + 0.002))
