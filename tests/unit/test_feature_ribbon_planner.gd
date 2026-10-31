extends TestCase
## FeatureRibbonPlanner (TASK-108): smooth road and river ribbons from the link masks (chains,
## curves inside their hexes, river meander), and scatter kept off them.

const Fixtures := preload("res://tests/fixtures.gd")
const EPSILON := 1e-4
const KIND_ROAD := FeatureRibbonPlanner.Kind.ROAD
const KIND_RIVER := FeatureRibbonPlanner.Kind.RIVER


func _near(actual: float, expected: float, message := "") -> void:
	assert_true(
		absf(actual - expected) < EPSILON, "expected %f, got %f %s" % [expected, actual, message]
	)


func _lines(grid: HexGrid, kind: FeatureRibbonPlanner.Kind) -> Array[PackedVector2Array]:
	return FeatureRibbonPlanner.lines(grid, kind)


func _centre(c: Vector2i) -> Vector2:
	var w := Hex.to_world(c, 1.0)
	return Vector2(w.x, w.z)


func _side_midpoint(c: Vector2i, dir: int) -> Vector2:
	return (_centre(c) + _centre(c + Hex.DIRECTIONS[dir])) / 2.0


## Links `a` and `b` (neighbours) both ways.
func _link(grid: HexGrid, kind: FeatureRibbonPlanner.Kind, a: Vector2i, b: Vector2i) -> void:
	var dir := Hex.DIRECTIONS.find(b - a)
	if kind == KIND_ROAD:
		grid.set_road_links(a, grid.road_links(a) | (1 << dir))
		grid.set_road_links(b, grid.road_links(b) | (1 << ((dir + 3) % 6)))
	else:
		grid.set_river_links(a, grid.river_links(a) | (1 << dir))
		grid.set_river_links(b, grid.river_links(b) | (1 << ((dir + 3) % 6)))


## Links consecutive tiles of `path`.
func _link_path(grid: HexGrid, kind: FeatureRibbonPlanner.Kind, path: Array[Vector2i]) -> void:
	for i in path.size() - 1:
		_link(grid, kind, path[i], path[i + 1])


## A path that alternates east and north-east steps: the hex zigzag of a diagonal road.
func _zigzag() -> Array[Vector2i]:
	var path: Array[Vector2i] = [Vector2i(-3, 1)]
	for i in 6:
		path.append(path[-1] + Hex.DIRECTIONS[0 if i % 2 == 0 else 1])
	return path


## Largest direction change (radians) between consecutive pieces of `line`.
func _max_turn(line: PackedVector2Array) -> float:
	var worst := 0.0
	for i in range(1, line.size() - 1):
		var a := line[i] - line[i - 1]
		var b := line[i + 1] - line[i]
		if a.length() > 1e-6 and b.length() > 1e-6:
			worst = maxf(worst, absf(a.angle_to(b)))
	return worst


func test_a_straight_road_is_one_straight_line_between_side_midpoints() -> void:
	var grid := Fixtures.plains_grid(2)
	grid.set_road_links(Vector2i.ZERO, (1 << 0) | (1 << 3))  # both ends off the linked graph
	var lines := _lines(grid, KIND_ROAD)
	assert_eq(lines.size(), 1, "one chain")
	var line := lines[0]
	var ends := [line[0], line[line.size() - 1]]
	assert_true(
		(
			ends.has(_side_midpoint(Vector2i.ZERO, 0))
			or (ends[0] as Vector2).distance_to(_side_midpoint(Vector2i.ZERO, 0)) < EPSILON
			or (ends[1] as Vector2).distance_to(_side_midpoint(Vector2i.ZERO, 0)) < EPSILON
		),
		"ends on the east side midpoint"
	)
	for p in line:
		_near(p.y, 0.0, "straight along the row")
	assert_eq(_lines(grid, KIND_RIVER).size(), 0, "no rivers")


func test_an_off_map_link_ends_on_the_border_side_midpoint() -> void:
	for kind: FeatureRibbonPlanner.Kind in [KIND_ROAD, KIND_RIVER]:
		var grid := Fixtures.plains_grid(1)
		if kind == KIND_ROAD:
			grid.set_road_links(Vector2i(1, 0), 1 << 0)  # east of (1, 0) is off the map
		else:
			grid.set_river_links(Vector2i(1, 0), 1 << 0)
		var lines := _lines(grid, kind)
		assert_eq(lines.size(), 1)
		var line := lines[0]
		# The river's meander may shift its ends a little (sideways).
		var slack := EPSILON if kind == KIND_ROAD else FeatureRibbonPlanner.RIVER_MEANDER
		var start := line[0].distance_to(_centre(Vector2i(1, 0)))
		var end := line[line.size() - 1].distance_to(_side_midpoint(Vector2i(1, 0), 0))
		assert_true(start <= slack, "kind %d from the dead-end centre (%f)" % [kind, start])
		assert_true(end <= slack, "kind %d to the side midpoint (%f)" % [kind, end])


func test_linked_tiles_form_one_continuous_chain() -> void:
	var grid := Fixtures.plains_grid(4)
	_link_path(grid, KIND_ROAD, _zigzag())
	var lines := _lines(grid, KIND_ROAD)
	assert_eq(lines.size(), 1, "one polyline through all tiles")
	var line := lines[0]
	_near(line[0].distance_to(_centre(_zigzag()[0])), 0.0, "starts at the first centre")
	_near(line[line.size() - 1].distance_to(_centre(_zigzag()[-1])), 0.0, "ends at the last")
	for i in line.size() - 1:
		var gap := line[i].distance_to(line[i + 1])
		assert_true(gap > 0.0 and gap <= 1.5 * FeatureRibbonPlanner.SAMPLE_STEP, "gap %f" % gap)


func test_a_zigzag_of_hexes_becomes_a_smooth_line() -> void:
	for kind: FeatureRibbonPlanner.Kind in [KIND_ROAD, KIND_RIVER]:
		var grid := Fixtures.plains_grid(4)
		_link_path(grid, kind, _zigzag())
		var turn := _max_turn(_lines(grid, kind)[0])
		assert_true(turn < deg_to_rad(12.0), "kind %d: max turn %f deg" % [kind, rad_to_deg(turn)])


func test_a_sharp_hex_turn_is_rounded() -> void:
	# East, then north-west: the sides 120 degrees apart in the middle tile.
	var grid := Fixtures.plains_grid(3)
	var path: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(0, -1), Vector2i(-1, -1)]
	_link_path(grid, KIND_ROAD, path)
	var line := _lines(grid, KIND_ROAD)[0]
	assert_true(_max_turn(line) < deg_to_rad(20.0), "max turn %f" % rad_to_deg(_max_turn(line)))


func test_lines_stay_in_their_hexes_and_cross_only_linked_sides() -> void:
	for kind: FeatureRibbonPlanner.Kind in [KIND_ROAD, KIND_RIVER]:
		var grid := Fixtures.plains_grid(4)
		_link_path(grid, kind, _zigzag())
		var path: Array[Vector2i] = [
			Vector2i(0, 2), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, -1)
		]
		_link_path(grid, kind, path)
		for line in _lines(grid, kind):
			var previous := Vector2i(999, 999)
			for p in line:
				var tile := Hex.from_world(Vector3(p.x, 0.0, p.y), 1.0)
				if previous != Vector2i(999, 999) and tile != previous:
					assert_true(
						Hex.distance(tile, previous) == 1,
						"kind %d jumps from %s to %s" % [kind, previous, tile]
					)
					var dir := Hex.DIRECTIONS.find(tile - previous)
					assert_true(
						FeatureRibbonPlanner.links(grid, previous, kind) & (1 << dir) != 0,
						"kind %d crosses an unlinked side %s -> %s" % [kind, previous, tile]
					)
				assert_true(FeatureRibbonPlanner.links(grid, tile, kind) != 0, "in a linked tile")
				previous = tile


func test_geometry_is_deterministic_and_independent_of_the_grid_instance() -> void:
	var lines: Array = []
	var tris: Array = []
	for _i in 2:
		var grid := Fixtures.plains_grid(4)
		_link_path(grid, KIND_RIVER, _zigzag())
		lines.append(_lines(grid, KIND_RIVER))
		tris.append(FeatureRibbonPlanner.triangles(grid, KIND_RIVER))
	assert_true(lines[0] == lines[1], "same centrelines")
	assert_true(tris[0] == tris[1], "same triangles")


func test_rivers_meander_gently_and_vary_in_width() -> void:
	var road_grid := Fixtures.plains_grid(4)
	_link_path(road_grid, KIND_ROAD, _zigzag())
	var river_grid := Fixtures.plains_grid(4)
	_link_path(river_grid, KIND_RIVER, _zigzag())
	var road := _lines(road_grid, KIND_ROAD)[0]
	var river := _lines(river_grid, KIND_RIVER)[0]
	assert_eq(road.size(), river.size(), "same samples before the meander")
	var deviation := 0.0
	for i in road.size():
		deviation = maxf(deviation, road[i].distance_to(river[i]))
	assert_true(deviation > 0.02, "the river meanders (%f)" % deviation)
	assert_true(
		deviation <= FeatureRibbonPlanner.RIVER_MEANDER + EPSILON, "gently (%f)" % deviation
	)
	var widths := FeatureRibbonPlanner.half_widths(river_grid, KIND_RIVER)[0]
	var lo := INF
	var hi := 0.0
	for w in widths:
		lo = minf(lo, w)
		hi = maxf(hi, w)
	assert_true(hi - lo > 0.01, "width varies %f..%f" % [lo, hi])
	assert_true(hi <= FeatureRibbonPlanner.max_half_width(KIND_RIVER) + EPSILON)
	assert_true(widths[0] < 0.6 * hi, "narrow at the dead-end source")
	for w in FeatureRibbonPlanner.half_widths(road_grid, KIND_ROAD)[0]:
		_near(w, FeatureRibbonPlanner.ROAD_WIDTH / 2.0, "roads keep their width")


func test_a_junction_spoke_ends_on_the_through_line_with_a_disc() -> void:
	for kind: FeatureRibbonPlanner.Kind in [KIND_ROAD, KIND_RIVER]:
		var grid := Fixtures.plains_grid(3)
		_link(grid, kind, Vector2i(-1, 0), Vector2i(0, 0))
		_link(grid, kind, Vector2i(0, 0), Vector2i(1, 0))
		_link(grid, kind, Vector2i(0, 0), Vector2i(0, 1))  # the spoke, south-east
		var lines := _lines(grid, kind)
		assert_eq(lines.size(), 2, "kind %d: through line and spoke" % kind)
		var through: PackedVector2Array = (
			lines[0] if lines[0].size() > lines[1].size() else lines[1]
		)
		var spoke: PackedVector2Array = lines[1] if through == lines[0] else lines[0]
		var spoke_end := spoke[0]
		if _centre(Vector2i(0, 1)).distance_to(spoke[0]) < 0.5:
			spoke_end = spoke[spoke.size() - 1]
		var best := INF
		for i in through.size() - 1:
			best = minf(
				best,
				(
					Geometry2D
					. get_closest_point_to_segment(spoke_end, through[i], through[i + 1])
					. distance_to(spoke_end)
				)
			)
		assert_true(best < 1e-3, "kind %d: spoke ends on the through line (%f)" % [kind, best])
		if kind == KIND_ROAD:
			var has_disc := false
			for disc in FeatureRibbonPlanner.discs(grid, kind):
				has_disc = has_disc or Vector2(disc.x, disc.y).distance_to(spoke_end) < 1e-3
			assert_true(has_disc, "junction disc")


func test_strips_have_no_spikes_and_are_wound_clockwise() -> void:
	var grid := Fixtures.plains_grid(4)
	_link_path(grid, KIND_RIVER, _zigzag())
	var tris := FeatureRibbonPlanner.triangles(grid, KIND_RIVER)
	assert_eq(tris.size() % 3, 0)
	assert_true(tris.size() > 0)
	var line := _lines(grid, KIND_RIVER)[0]
	var reach := FeatureRibbonPlanner.max_half_width(KIND_RIVER) + EPSILON
	for i in range(0, tris.size(), 3):
		var cross := (tris[i + 1] - tris[i]).cross(tris[i + 2] - tris[i])
		assert_true(cross >= 0.0, "clockwise from above like the terrain")
	for p in tris:
		var best := INF
		for i in line.size() - 1:
			best = minf(
				best,
				Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1]).distance_to(p)
			)
		if best > reach:
			_fail("vertex %s is %f from the centreline" % [p, best])
			return


func test_no_links_no_lines_no_triangles() -> void:
	var grid := Fixtures.plains_grid(2)
	assert_eq(_lines(grid, KIND_ROAD).size(), 0)
	assert_eq(FeatureRibbonPlanner.triangles(grid, KIND_ROAD).size(), 0)
	assert_eq(FeatureRibbonPlanner.triangles(grid, KIND_RIVER).size(), 0)
	assert_true(FeatureRibbonPlanner.is_clear(grid, 0.0, 0.0))


func test_distance_and_clearance_follow_the_new_geometry() -> void:
	var grid := Fixtures.plains_grid(2)
	grid.set_road_links(Vector2i.ZERO, 1 << 0)
	grid.set_road_links(Vector2i(1, 0), 1 << 3)
	_near(FeatureRibbonPlanner.distance(grid, KIND_ROAD, 0.5, 0.2), 0.2)
	var limit := FeatureRibbonPlanner.ROAD_WIDTH / 2.0 + FeatureRibbonPlanner.CLEARANCE
	assert_false(FeatureRibbonPlanner.is_clear(grid, 1.2, limit - 0.01), "on the far half")
	assert_true(FeatureRibbonPlanner.is_clear(grid, 1.2, limit + 0.01))
	assert_true(FeatureRibbonPlanner.distance(grid, KIND_RIVER, 0.5, 0.0) == INF, "no river")
	# A curved river: every centreline point is not clear, a point well beside it is.
	var river := Fixtures.plains_grid(4)
	_link_path(river, KIND_RIVER, _zigzag())
	for p in _lines(river, KIND_RIVER)[0]:
		if FeatureRibbonPlanner.is_clear(river, p.x, p.y):
			_fail("centreline point %s counted as clear" % p)
			return
	assert_true(FeatureRibbonPlanner.is_clear(river, 0.0, -2.5), "far from the river")


# --- scatter and grass keep off the ribbons ---


func _road_grid() -> HexGrid:
	var grid := Fixtures.plains_grid(3)
	for c in grid.coords():
		grid.set_terrain(c, Terrain.Type.FOREST)
	for q in range(-3, 3):
		var a := Vector2i(q, 0)
		grid.set_road_links(a, grid.road_links(a) | (1 << 0))
		var b := Vector2i(q + 1, 0)
		grid.set_road_links(b, grid.road_links(b) | (1 << 3))
	grid.set_river_links(Vector2i(0, 2), 1 << 0)
	grid.set_river_links(Vector2i(1, 2), 1 << 3)
	return grid


func _assert_clear_of_ribbons(grid: HexGrid, items: Array, label: String) -> void:
	var clearance := FeatureRibbonPlanner.CLEARANCE - EPSILON
	for item: Dictionary in items:
		var p: Vector3 = item["position"]
		var d_road := FeatureRibbonPlanner.edge_distance(grid, KIND_ROAD, p.x, p.z)
		var d_river := FeatureRibbonPlanner.edge_distance(grid, KIND_RIVER, p.x, p.z)
		assert_true(d_road >= clearance, "%s %s on the road (%f)" % [label, p, d_road])
		assert_true(d_river >= clearance, "%s %s on the river (%f)" % [label, p, d_river])


func test_scatter_keeps_off_roads_and_rivers() -> void:
	var grid := _road_grid()
	var plan := ScatterPlanner.plan(grid, TerrainSurface.new(grid), 777)
	assert_true((plan["trees"] as Array).size() > 100, "a forest")
	for key: String in plan:
		_assert_clear_of_ribbons(grid, plan[key], key)


func test_grass_keeps_off_roads_and_rivers() -> void:
	var grid := _road_grid()
	for c in grid.coords():
		grid.set_terrain(c, Terrain.Type.PLAINS)
	var surface := TerrainSurface.new(grid)
	var count := 0
	for chunk: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var clumps := GrassPlanner.plan_chunk(chunk, grid, surface, 5, 1.0)
		count += clumps.size()
		_assert_clear_of_ribbons(grid, clumps, "grass")
		_assert_clear_of_ribbons(
			grid, GrassPlanner.plan_flowers(chunk, grid, surface, 5, 1.0), "flower"
		)
	assert_true(count > 1000, "grass grows beside the road")


func test_urban_tiles_get_no_trees_or_rocks() -> void:
	var grid := HexGrid.new()
	grid.set_terrain(Vector2i.ZERO, Terrain.Type.URBAN)
	for seed_value in 10:
		var plan := ScatterPlanner.plan(grid, TerrainSurface.new(grid), seed_value)
		assert_eq((plan["trees"] as Array).size(), 0)
		assert_eq((plan["rocks"] as Array).size(), 0)


func test_fields_and_marsh_have_less_or_equal_grass_than_plains() -> void:
	assert_eq(GrassPlanner.density_of(Terrain.Type.FIELDS), GrassPlanner.PLAINS_DENSITY * 0.6)
	assert_eq(GrassPlanner.density_of(Terrain.Type.URBAN), GrassPlanner.PLAINS_DENSITY * 0.3)
	assert_eq(GrassPlanner.density_of(Terrain.Type.MARSH), GrassPlanner.PLAINS_DENSITY)
	assert_eq(GrassPlanner.density_of(Terrain.Type.WATER), 0.0)


# --- MapView ---


func test_map_view_builds_one_ribbon_mesh_per_kind_only_with_links() -> void:
	var plain := Fixtures.plains_grid(2)
	var view := Fixtures.map_view(plain, {"foliage": false})
	assert_true(view.find_child("Roads", true, false) == null, "no links, no road mesh")
	assert_true(view.find_child("Rivers", true, false) == null, "no links, no river mesh")
	view.free()
	var linked := Fixtures.plains_grid(2)
	linked.set_road_links(Vector2i.ZERO, 1 << 0)
	linked.set_road_links(Vector2i(1, 0), 1 << 3)
	view = Fixtures.map_view(linked, {"foliage": false})
	var roads := view.find_child("Roads", true, false) as MeshInstance3D
	assert_true(roads != null, "road mesh")
	assert_true(view.find_child("Rivers", true, false) == null, "still no river mesh")
	assert_eq(roads.mesh.get_surface_count(), 1, "one draw call")
	view.free()
