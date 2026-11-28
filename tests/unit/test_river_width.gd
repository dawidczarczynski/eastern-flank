extends TestCase
## River water width per hex (TASK-216): stored in the grid, the maps and the tactical layer, and
## followed by the ribbon planner, the shader attributes and the bridge span.

const Fixtures := preload("res://tests/fixtures.gd")
const KIND_RIVER := FeatureRibbonPlanner.Kind.RIVER
const KIND_ROAD := FeatureRibbonPlanner.Kind.ROAD
const SAMPLE_PATH := "res://tests/fixtures/maps/sample_map.tres"


func after_each() -> void:
	MapScale.reset()


func _link(grid: HexGrid, kind: FeatureRibbonPlanner.Kind, a: Vector2i, b: Vector2i) -> void:
	var dir := Hex.DIRECTIONS.find(b - a)
	if kind == KIND_ROAD:
		grid.set_road_links(a, grid.road_links(a) | (1 << dir))
		grid.set_road_links(b, grid.road_links(b) | (1 << ((dir + 3) % 6)))
	else:
		grid.set_river_links(a, grid.river_links(a) | (1 << dir))
		grid.set_river_links(b, grid.river_links(b) | (1 << ((dir + 3) % 6)))


## A river along r = `row` from q = -3 to q = 1, every tile `metres` wide (0 = unset).
func _river(grid: HexGrid, row: int, metres: float) -> void:
	for q in range(-3, 1):
		_link(grid, KIND_RIVER, Vector2i(q, row), Vector2i(q + 1, row))
	if metres > 0.0:
		for q in range(-3, 2):
			grid.set_river_width_m(Vector2i(q, row), metres)


## Water width in metres at every sample of chain `index` read from the mesh (`water_edge` times
## the half width of each side), like the shader draws it.
func _water_samples(grid: HexGrid, index: int) -> PackedFloat32Array:
	var mesh := FeatureRibbonPlanner.mesh(grid, KIND_RIVER)
	var points: PackedVector2Array = mesh["points"]
	var edge: PackedFloat32Array = mesh["water_edge"]
	var lines := FeatureRibbonPlanner.lines(grid, KIND_RIVER)
	var first := 0
	for i in index:
		first += lines[i].size()
	var result := PackedFloat32Array()
	var line := lines[index]
	for k in range(line.size() / 4, line.size() * 3 / 4):
		var left := points[2 * (first + k)].distance_to(line[k]) * MapScale.metres_per_unit
		var right := points[2 * (first + k) + 1].distance_to(line[k]) * MapScale.metres_per_unit
		result.append(edge[2 * (first + k)] * left + edge[2 * (first + k) + 1] * right)
	return result


func test_grid_default_is_eight_metres() -> void:
	var grid := Fixtures.plains_grid(2)
	assert_eq(grid.river_width_m(Vector2i(0, 0)), 8.0)
	grid.set_river_width_m(Vector2i(0, 0), 3.0)
	assert_eq(grid.river_width_m(Vector2i(0, 0)), 3.0)
	grid.set_river_width_m(Vector2i(0, 0), 0.0)
	assert_eq(grid.river_width_m(Vector2i(0, 0)), 8.0, "cleared")


func test_setting_a_width_invalidates_cached_plans() -> void:
	var grid := Fixtures.plains_grid(4)
	_river(grid, 0, 0.0)
	assert_eq(FeatureRibbonPlanner.water_widths_m(grid)[0], 8.0)
	_river(grid, 0, 20.0)
	assert_eq(FeatureRibbonPlanner.water_widths_m(grid)[0], 20.0)


func test_map_without_width_data_loads_eight_metres() -> void:
	var map := load(SAMPLE_PATH).duplicate() as ImportedMap
	map.river_width_rows = PackedStringArray()
	assert_eq(map.problem(), "")
	var grid := map.to_grid()
	var rivers := 0
	for c in grid.coords():
		if grid.is_river(c):
			rivers += 1
			assert_eq(grid.river_width_m(c), 8.0)
	assert_true(rivers > 0)


func test_map_with_width_data_loads_the_stored_width() -> void:
	var map := load(SAMPLE_PATH).duplicate() as ImportedMap
	var rows := PackedStringArray()
	for row in map.river_rows:
		var line := ""
		for ch in row:
			line += "c" if ch != "." else "."  # 'c' = 12 m
		rows.append(line)
	map.river_width_rows = rows
	assert_eq(map.problem(), "")
	var grid := map.to_grid()
	for c in grid.coords():
		if grid.is_river(c):
			assert_eq(grid.river_width_m(c), 12.0)
	map.river_width_rows = PackedStringArray(["x"])
	assert_true(map.problem().contains("river width"))


func _offset_grid() -> HexGrid:
	var grid := HexGrid.new()
	for r in 12:
		for c in 12:
			grid.set_terrain(MapGenerator.offset_to_axial(c, r), Terrain.Type.PLAINS)
	for c in range(2, 9):
		_link(
			grid,
			KIND_RIVER,
			MapGenerator.offset_to_axial(c, 4),
			MapGenerator.offset_to_axial(c + 1, 4)
		)
	return grid


func test_tactical_layer_keeps_widths_through_a_cut() -> void:
	var grid := _offset_grid()
	grid.set_river_width_m(MapGenerator.offset_to_axial(5, 4), 17.0)
	var layer := TacticalLayer.from_grid(grid, 12, 12, 250.0, 0.0, 0.0, 8)
	assert_eq(layer.river_width_at(Vector2i(5, 4)), 17)
	assert_eq(layer.river_width_at(Vector2i(5, 6)), 0)
	var cut := layer.region_grid(Rect2i(0, 0, 12, 12))
	assert_eq(cut.river_width_m(MapGenerator.offset_to_axial(5, 4)), 17.0)
	assert_eq(cut.river_width_m(MapGenerator.offset_to_axial(4, 4)), 8.0, "unset: default")


func test_layer_without_width_data_reads_eight_metres() -> void:
	var layer := TacticalLayer.from_grid(_offset_grid(), 12, 12, 250.0, 0.0, 0.0, 8)
	var cut := layer.region_grid(Rect2i(0, 0, 12, 12))
	var rivers := 0
	for c in cut.coords():
		if cut.is_river(c):
			rivers += 1
			assert_eq(cut.river_width_m(c), 8.0)
	assert_true(rivers > 0)


func test_chain_width_is_the_median_of_its_tiles_and_constant() -> void:
	var grid := Fixtures.plains_grid(4)
	_river(grid, 0, 12.0)
	grid.set_river_width_m(Vector2i(-3, 0), 40.0)  # one outlier tile
	assert_eq(FeatureRibbonPlanner.water_widths_m(grid)[0], 12.0)
	var samples := _water_samples(grid, 0)
	for w in samples:
		assert_true(w >= 12.0 * 0.5 and w <= 12.0 * 1.6 + 0.01, "water %f" % w)


func test_stream_and_river_cross_sections_in_one_grid() -> void:
	var grid := Fixtures.plains_grid(4)
	_river(grid, -2, 3.0)
	_river(grid, 2, 25.0)
	var widths := FeatureRibbonPlanner.water_widths_m(grid)
	assert_eq(widths.size(), 2)
	for index in 2:
		var base := widths[index]
		assert_true(base == 3.0 or base == 25.0)
		var samples := _water_samples(grid, index)
		assert_true(samples.size() > 4)
		for w in samples:
			assert_true(w >= base * 0.5 and w <= base * 1.6 + 0.01, "%f of %f m" % [w, base])
		var mesh := FeatureRibbonPlanner.mesh(grid, KIND_RIVER)
		var edge: PackedFloat32Array = mesh["water_edge"]
		for e in edge:
			assert_true(e >= 0.0 and e <= 1.0)
	# The bank band is 3 m plus a share of the water width (3 m and 25 m rivers).
	var plan := FeatureRibbonPlanner.mesh(grid, KIND_RIVER)
	var points: PackedVector2Array = plan["points"]
	var edge2: PackedFloat32Array = plan["water_edge"]
	var lines := FeatureRibbonPlanner.lines(grid, KIND_RIVER)
	var first := 0
	for line in lines:
		for k in range(line.size() / 4, line.size() * 3 / 4):
			for side in 2:
				var outer := points[2 * (first + k) + side].distance_to(line[k])
				outer *= MapScale.metres_per_unit
				var bank := outer * (1.0 - edge2[2 * (first + k) + side])
				assert_true(bank >= 3.0 * 0.5 - 0.01 and bank <= 6.0 * 1.5 + 0.01, "bank %f" % bank)
		first += line.size()


func test_max_half_width_follows_the_water_width() -> void:
	var base := FeatureRibbonPlanner.max_half_width(KIND_RIVER)
	var wide := FeatureRibbonPlanner.max_half_width(KIND_RIVER, 25.0)
	var narrow := FeatureRibbonPlanner.max_half_width(KIND_RIVER, 3.0)
	assert_true(narrow < base and base < wide)
	var per_metre := (wide - narrow) / MapScale.to_units(22.0)
	var factor := 0.5 * (1.0 + FeatureRibbonPlanner.RIVER_WIDTH_VARIATION)
	factor *= 1.0 + FeatureRibbonPlanner.WATER_EDGE_VARIATION
	factor += FeatureRibbonPlanner.BANK_PER_WATER * (1.0 + FeatureRibbonPlanner.BANK_VARIATION)
	assert_true(
		absf(per_metre - factor) < 1e-5, "the half width follows the water width and its bank share"
	)


func test_widths_are_metres_at_any_map_scale() -> void:
	var grid := Fixtures.plains_grid(4)
	_river(grid, 0, 20.0)
	var normal := _water_samples(grid, 0)
	MapScale.metres_per_unit = MapScale.DEFAULT_METRES_PER_UNIT / 2.0
	var grid2 := Fixtures.plains_grid(4)
	_river(grid2, 0, 20.0)
	for w in _water_samples(grid2, 0):
		assert_true(w >= 20.0 * 0.5 and w <= 20.0 * 1.6 + 0.01, "water %f" % w)
	assert_true(normal.size() > 0)


func test_bridge_over_a_wide_river_is_longer() -> void:
	var grid := Fixtures.plains_grid(4)
	_river(grid, 0, 25.0)
	# A road crossing the river at right angles through the middle.
	_link(grid, KIND_ROAD, Vector2i(-1, -2), Vector2i(-1, -1))
	_link(grid, KIND_ROAD, Vector2i(-1, -1), Vector2i(-1, 0))
	_link(grid, KIND_ROAD, Vector2i(-1, 0), Vector2i(-1, 1))
	_link(grid, KIND_ROAD, Vector2i(-1, 1), Vector2i(-1, 2))
	var sites := FeatureRibbonPlanner.bridges(grid)
	assert_eq(sites.size(), 1)
	var water_m: float = sites[0]["water_m"]
	assert_true(water_m > 25.0 * 0.5 and water_m < 25.0 * 1.6 + 0.01, "water %f" % water_m)
	var direction: Vector2 = sites[0]["direction"]
	var river := FeatureRibbonPlanner.lines(grid, KIND_RIVER)[0]
	var at: Vector2 = sites[0]["position"]
	var best := 0
	for j in river.size() - 1:
		var near := Geometry2D.get_closest_point_to_segment(at, river[j], river[j + 1])
		var best_near := Geometry2D.get_closest_point_to_segment(at, river[best], river[best + 1])
		if near.distance_to(at) < best_near.distance_to(at):
			best = j
	var sin_angle := absf(direction.cross((river[best + 1] - river[best]).normalized()))
	var expected := minf(water_m / sin_angle + 8.0, 40.0)
	assert_true(absf(sites[0]["span_m"] - expected) < 0.01)
	assert_true(sites[0]["span_m"] > 8.0 * 0.75 + 8.0 + 4.0, "longer than over the default 8 m")
