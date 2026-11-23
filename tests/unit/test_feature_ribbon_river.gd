extends TestCase
## River ribbon of TASK-108c: real width with muddy banks, the flow coordinate, bridge sites.

const Fixtures := preload("res://tests/fixtures.gd")
const KIND_ROAD := FeatureRibbonPlanner.Kind.ROAD
const KIND_RIVER := FeatureRibbonPlanner.Kind.RIVER


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


## A river along the +x axis from (-3, 0) to (3, 0) on a plains grid.
func _river_grid() -> HexGrid:
	var grid := Fixtures.plains_grid(4)
	for q in range(-3, 3):
		_link(grid, KIND_RIVER, Vector2i(q, 0), Vector2i(q + 1, 0))
	return grid


func _slope(grid: HexGrid, per_tile: float) -> void:
	for c in grid.coords():
		grid.set_elevation(c, per_tile * c.x)


func _length_m(line: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, line.size()):
		total += line[i].distance_to(line[i - 1])
	return total * MapScale.metres_per_unit


func test_cross_section_is_water_plus_two_banks() -> void:
	var grid := _river_grid()
	var outer := FeatureRibbonPlanner.mesh(grid, KIND_RIVER)
	var metres := MapScale.metres_per_unit
	var points: PackedVector2Array = outer["points"]
	var edge: PackedFloat32Array = outer["water_edge"]
	var across: PackedFloat32Array = outer["across"]
	var line := FeatureRibbonPlanner.lines(grid, KIND_RIVER)[0]
	var widest := FeatureRibbonPlanner.max_half_width(KIND_RIVER)
	for k in range(line.size() / 4, line.size() * 3 / 4):
		var left := points[2 * k].distance_to(line[k]) * metres
		var right := points[2 * k + 1].distance_to(line[k]) * metres
		var water := edge[2 * k] * left + edge[2 * k + 1] * right
		assert_true(water >= 8.0 * 0.5 and water <= 8.0 * 1.6 + 0.01, "water %f" % water)
		assert_true(left <= widest * metres + 0.01 and right <= widest * metres + 0.01)
		assert_true(left >= 3.0 * 0.5 + 8.0 * 0.5 * 0.5 and right >= 3.0 * 0.5 + 8.0 * 0.5 * 0.5)
		assert_true(edge[2 * k] > 0.0 and edge[2 * k] < 1.0 and edge[2 * k + 1] < 1.0)
		assert_eq(across[2 * k], 1.0)


func test_world_width_follows_map_scale() -> void:
	var narrow := FeatureRibbonPlanner.width(KIND_RIVER)
	assert_true(absf(narrow - 14.0 / MapScale.metres_per_unit) < 1e-6)
	MapScale.metres_per_unit = MapScale.DEFAULT_METRES_PER_UNIT / 2.0
	assert_true(absf(FeatureRibbonPlanner.width(KIND_RIVER) - 2.0 * narrow) < 1e-6)


func test_flow_runs_downhill() -> void:
	var grid := _river_grid()
	_slope(grid, -0.05)  # down towards +x
	var line := FeatureRibbonPlanner.lines(grid, KIND_RIVER)[0]
	var along := FeatureRibbonPlanner.flows(grid)[0]
	assert_true(line[0].x < line[line.size() - 1].x, "stored downstream-first: -x end first")
	assert_eq(along[0], 0.0)
	for i in range(1, along.size()):
		assert_true(along[i] > along[i - 1], "monotonic")
	assert_true(absf(along[along.size() - 1] - _length_m(line)) < 0.1)
	var reversed := _river_grid()
	_slope(reversed, 0.05)
	var back := FeatureRibbonPlanner.lines(reversed, KIND_RIVER)[0]
	assert_true(back[0].x > back[back.size() - 1].x, "reversed slope: +x end first")
	assert_eq(FeatureRibbonPlanner.flows(reversed)[0][0], 0.0)


func test_flat_river_flows_from_its_dead_end_source() -> void:
	var grid := Fixtures.plains_grid(4)
	# A river with a dead end at (3, 0) (one link) and a through end at (-3, 0): the source is +x.
	for q in range(-3, 3):
		_link(grid, KIND_RIVER, Vector2i(q, 0), Vector2i(q + 1, 0))
	# (-3, 0) leaves the chain through a west port with no partner (a map edge: no dead end).
	grid.set_river_links(Vector2i(-3, 0), grid.river_links(Vector2i(-3, 0)) | (1 << 3))
	var chains := FeatureRibbonPlanner.lines(grid, KIND_RIVER)
	assert_eq(chains.size(), 1)
	var line := chains[0]
	var source_end := Hex.to_world(Vector2i(3, 0), TerrainField.HEX_SIZE)
	var a := FeatureRibbonPlanner.flows(grid)[0]
	assert_eq(a[0], 0.0)
	assert_true(line[0].distance_to(Vector2(source_end.x, source_end.z)) < 1.0, "source first")


func test_flat_river_without_a_source_flows_from_the_smaller_x_and_is_deterministic() -> void:
	var grid := _river_grid()
	var first := FeatureRibbonPlanner.flows(grid)[0]
	var line := FeatureRibbonPlanner.lines(grid, KIND_RIVER)[0]
	assert_true(line[0].x <= line[line.size() - 1].x)
	var again := _river_grid()
	assert_eq(first, FeatureRibbonPlanner.flows(again)[0])


func test_road_mesh_has_no_flow() -> void:
	var grid := Fixtures.plains_grid(3)
	_link(grid, KIND_ROAD, Vector2i(-1, 0), Vector2i(0, 0))
	_link(grid, KIND_ROAD, Vector2i(0, 0), Vector2i(1, 0))
	var indexed := FeatureRibbonPlanner.mesh(grid, KIND_ROAD)
	assert_false(indexed.has("along"))
	assert_false(indexed.has("water_edge"))


func test_scatter_keeps_ribbon_half_width_plus_three_metres_from_a_river() -> void:
	var grid := _river_grid()
	var line := FeatureRibbonPlanner.lines(grid, KIND_RIVER)[0]
	var halves := FeatureRibbonPlanner.half_widths(grid, KIND_RIVER)[0]
	var clear := MapScale.to_units(3.0)
	var i := line.size() / 2
	var dir := (line[i + 1] - line[i - 1]).normalized()
	var normal := Vector2(-dir.y, dir.x)
	var near := line[i] + normal * (halves[i] + clear * 0.9)
	var far := line[i] + normal * (halves[i] + clear * 1.5 + 0.02)
	assert_false(FeatureRibbonPlanner.is_clear(grid, near.x, near.y))
	assert_true(FeatureRibbonPlanner.is_clear(grid, far.x, far.y))


# --- bridges ---


## A road along +x and a river down the y axis crossing in tile (0, 0).
func _crossing_grid() -> HexGrid:
	var grid := Fixtures.plains_grid(4)
	for q in range(-3, 3):
		_link(grid, KIND_ROAD, Vector2i(q, 0), Vector2i(q + 1, 0))
	for r in range(-3, 3):
		_link(grid, KIND_RIVER, Vector2i(0, r), Vector2i(0, r + 1))
	return grid


## First crossing of a road polyline with a river polyline.
func _true_crossing(grid: HexGrid) -> Vector2:
	for road in FeatureRibbonPlanner.lines(grid, KIND_ROAD):
		for river in FeatureRibbonPlanner.lines(grid, KIND_RIVER):
			for i in road.size() - 1:
				for j in river.size() - 1:
					var hit: Variant = Geometry2D.segment_intersects_segment(
						road[i], road[i + 1], river[j], river[j + 1]
					)
					if hit != null:
						return hit
	return Vector2(INF, INF)


func test_one_site_where_the_road_crosses_the_river() -> void:
	var grid := _crossing_grid()
	var sites := FeatureRibbonPlanner.bridges(grid)
	assert_eq(sites.size(), 1)
	var truth := _true_crossing(grid)
	var metres := (sites[0]["position"] as Vector2).distance_to(truth) * MapScale.metres_per_unit
	assert_true(metres < 1.0, "%f m from the true crossing" % metres)
	assert_true(absf((sites[0]["direction"] as Vector2).length() - 1.0) < 1e-4)
	assert_eq(sites[0]["width_m"], 7.0)
	var span: float = sites[0]["span_m"]
	assert_true(span > 8.0 + 8.0 * 0.75 and span <= 40.0, "span %f" % span)


func test_span_formula() -> void:
	assert_true(absf(FeatureRibbonPlanner.bridge_span_m(8.0, 1.0) - 16.0) < 0.01, "90 degrees")
	var diagonal := FeatureRibbonPlanner.bridge_span_m(8.0, sin(PI / 4.0))
	assert_true(absf(diagonal - (8.0 / sin(PI / 4.0) + 8.0)) < 0.01, "45 degrees")
	assert_eq(FeatureRibbonPlanner.bridge_span_m(8.0, 0.05), 40.0, "shallow angle is capped")
	assert_eq(FeatureRibbonPlanner.bridge_span_m(8.0, 0.0), 40.0, "parallel")


func test_site_span_matches_the_local_water_width_and_angle() -> void:
	var grid := _crossing_grid()
	var site := FeatureRibbonPlanner.bridges(grid)[0]
	var river := FeatureRibbonPlanner.lines(grid, KIND_RIVER)[0]
	var at: Vector2 = site["position"]
	var best := 0
	for j in river.size() - 1:
		if (
			Geometry2D.get_closest_point_to_segment(at, river[j], river[j + 1]).distance_to(at)
			< Geometry2D.get_closest_point_to_segment(at, river[best], river[best + 1]).distance_to(
				at
			)
		):
			best = j
	var river_dir := (river[best + 1] - river[best]).normalized()
	var sin_angle := absf((site["direction"] as Vector2).cross(river_dir))
	var expected := FeatureRibbonPlanner.bridge_span_m(site["water_m"], sin_angle)
	assert_true(absf(site["span_m"] - expected) < 0.01)
	assert_true(site["water_m"] >= 6.0 - 0.1 and site["water_m"] <= 10.0 + 0.1)


func test_a_road_beside_a_river_has_no_bridge() -> void:
	var grid := Fixtures.plains_grid(4)
	for q in range(-3, 3):
		_link(grid, KIND_ROAD, Vector2i(q, 0), Vector2i(q + 1, 0))
		_link(grid, KIND_RIVER, Vector2i(q, 2), Vector2i(q + 1, 2))
	assert_eq(FeatureRibbonPlanner.bridges(grid).size(), 0)


func test_no_links_no_sites() -> void:
	assert_eq(FeatureRibbonPlanner.bridges(Fixtures.plains_grid(2)).size(), 0)
	assert_eq(FeatureRibbonPlanner.bridges(_river_grid()).size(), 0, "a river alone")


func test_suwalki_has_bridges_in_tiles_with_a_road_and_a_river() -> void:
	var grid := ImportedMap.find(Scenario.SUWALKI_MAP_ID).to_grid()
	MapScale.apply_map_id(Scenario.SUWALKI_MAP_ID)
	var sites := FeatureRibbonPlanner.bridges(grid)
	assert_true(sites.size() >= 1, "Suwalki has bridges")
	var merge := MapScale.to_units(10.0)
	for i in sites.size():
		var p: Vector2 = sites[i]["position"]
		var tile := Hex.from_world(Vector3(p.x, 0.0, p.y), TerrainField.HEX_SIZE)
		var near_road := false
		var near_river := false
		for t: Vector2i in [tile] + Hex.neighbors(tile):
			near_road = near_road or grid.road_links(t) != 0
			near_river = near_river or grid.river_links(t) != 0
		assert_true(grid.road_links(tile) != 0 or near_road, "a road near site %d" % i)
		assert_true(grid.river_links(tile) != 0 or near_river, "a river near site %d" % i)
		for j in range(i + 1, sites.size()):
			assert_true((sites[j]["position"] as Vector2).distance_to(p) >= merge, "10 m apart")
