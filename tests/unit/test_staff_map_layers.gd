extends TestCase
## StaffMapLayers (TASK-093a): hexes -> smoothed fill polygons, joined road / river polylines,
## hillshade, grid lines. Hand-made grids, no scene.

const Fixtures := preload("res://tests/fixtures.gd")


func _area(poly: PackedVector2Array) -> float:
	var sum := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5


func _total_area(polys: Array) -> float:
	var sum := 0.0
	for poly: PackedVector2Array in polys:
		sum += _area(poly)
	return sum


func _link(grid: HexGrid, a: Vector2i, b: Vector2i, river := false) -> void:
	var dir := Hex.DIRECTIONS.find(b - a)
	var back := (dir + 3) % 6
	if river:
		grid.set_river_links(a, grid.river_links(a) | (1 << dir))
		grid.set_river_links(b, grid.river_links(b) | (1 << back))
	else:
		grid.set_road_links(a, grid.road_links(a) | (1 << dir))
		grid.set_road_links(b, grid.road_links(b) | (1 << back))


func test_uniform_grid_has_only_one_class_covering_the_lattice() -> void:
	var grid := Fixtures.plains_grid(2)
	var fills := StaffMapLayers.fills(grid)
	assert_eq(fills.keys(), [Terrain.Type.PLAINS])
	assert_true(_total_area(fills[Terrain.Type.PLAINS]) > 10.0)


func test_a_lake_hex_gives_a_water_polygon_in_its_neighbourhood() -> void:
	var grid := Fixtures.plains_grid(3)
	grid.set_terrain(Vector2i.ZERO, Terrain.Type.WATER)
	var fills := StaffMapLayers.fills(grid)
	assert_true(fills.has(Terrain.Type.WATER))
	var water: Array = fills[Terrain.Type.WATER]
	assert_true(water.size() > 0)
	var centre := Hex.to_world(Vector2i.ZERO, 1.0)
	var centre2 := Vector2(centre.x, centre.z)
	var near := false
	for poly: PackedVector2Array in water:
		for p in poly:
			assert_true(p.distance_to(centre2) < 1.8, "water stays around the lake hex")
		near = near or Geometry2D.is_point_in_polygon(centre2, poly)
	assert_true(near, "the lake centre lies inside a water polygon")


func test_fills_conserve_the_area_of_the_lattice() -> void:
	var grid := Fixtures.plains_grid(3)
	var plain_area := _total_area(StaffMapLayers.fills(grid)[Terrain.Type.PLAINS])
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	grid.set_terrain(Vector2i(-1, 1), Terrain.Type.WATER)
	var total := 0.0
	var fills := StaffMapLayers.fills(grid)
	for terrain: int in fills:
		total += _total_area(fills[terrain])
	assert_true(absf(total - plain_area) < 0.001, "%s vs %s" % [total, plain_area])


func test_fills_are_deterministic() -> void:
	var grid := Fixtures.plains_grid(3)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	grid.set_terrain(Vector2i(0, 1), Terrain.Type.MARSH)
	assert_eq(StaffMapLayers.fills(grid), StaffMapLayers.fills(grid))


func test_road_chain_is_one_polyline() -> void:
	var grid := Fixtures.plains_grid(3)
	_link(grid, Vector2i(-2, 0), Vector2i(-1, 0))
	_link(grid, Vector2i(-1, 0), Vector2i(0, 0))
	_link(grid, Vector2i(0, 0), Vector2i(1, 0))
	var lines := StaffMapLayers.roads(grid, 0)
	assert_eq(lines.size(), 1)
	assert_eq(lines[0].size(), 4)


func test_two_separate_rivers_do_not_merge() -> void:
	var grid := Fixtures.plains_grid(3)
	_link(grid, Vector2i(-2, 0), Vector2i(-1, 0), true)
	_link(grid, Vector2i(-2, 2), Vector2i(-1, 2), true)  # not linked to the first one
	var lines := StaffMapLayers.rivers(grid, 0)
	assert_eq(lines.size(), 2)


func test_a_junction_splits_the_lines() -> void:
	var grid := Fixtures.plains_grid(3)
	_link(grid, Vector2i(-1, 0), Vector2i(0, 0))
	_link(grid, Vector2i(0, 0), Vector2i(1, 0))
	_link(grid, Vector2i(0, 0), Vector2i(0, 1))
	assert_eq(StaffMapLayers.roads(grid, 0).size(), 3)


func test_a_link_off_the_map_ends_at_the_hex_edge() -> void:
	var grid := Fixtures.plains_grid(1)
	grid.set_road_links(Vector2i(1, 0), 1)  # towards (2, 0): not on the map
	var lines := StaffMapLayers.roads(grid, 0)
	assert_eq(lines.size(), 1)
	var edge := Hex.to_world(Vector2i(1, 0), 1.0).x + Hex.SQRT3 * 0.5
	assert_true(absf(lines[0][1].x - edge) < 0.001)


func test_smoothing_keeps_the_end_points_and_adds_points() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 2)])
	var smooth := StaffMapLayers.smooth(line, 2)
	assert_eq(smooth[0], line[0])
	assert_eq(smooth[smooth.size() - 1], line[2])
	assert_true(smooth.size() > line.size())


func test_lines_are_deterministic() -> void:
	var grid := Fixtures.plains_grid(3)
	_link(grid, Vector2i(-1, 0), Vector2i(0, 0))
	_link(grid, Vector2i(0, 0), Vector2i(1, 0))
	_link(grid, Vector2i(0, 0), Vector2i(0, 1))
	assert_eq(StaffMapLayers.roads(grid), StaffMapLayers.roads(grid))


func test_hatch_segments_lie_inside_the_polygon() -> void:
	var square := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var segments := StaffMapLayers.hatch([square], 0.25)
	assert_true(segments.size() >= 6 and segments.size() % 2 == 0)
	for p in segments:
		assert_true(p.x >= -0.001 and p.x <= 1.001 and p.y >= -0.001 and p.y <= 1.001)


func test_hillshade_is_zero_on_flat_ground_and_signed_on_a_slope() -> void:
	var grid := Fixtures.plains_grid(2)
	for c in grid.coords():
		grid.set_elevation_m(c, 100.0)
	assert_eq(StaffMapLayers.shade_at(grid, Vector2i.ZERO), 0.0)
	# Ground rising to the south-east faces the light from the north-west: lit; falling: shaded.
	for c in grid.coords():
		grid.set_elevation_m(c, 100.0 + 30.0 * (c.x + c.y * 0.5))
	var rising_east := StaffMapLayers.shade_at(grid, Vector2i.ZERO)
	for c in grid.coords():
		grid.set_elevation_m(c, 100.0 - 30.0 * (c.x + c.y * 0.5))
	var falling_east := StaffMapLayers.shade_at(grid, Vector2i.ZERO)
	assert_true(rising_east > 0.0 and falling_east < 0.0)
	assert_eq(rising_east, -falling_east)


func test_hillshade_mesh_has_a_value_per_vertex() -> void:
	var grid := Fixtures.plains_grid(2)
	var shade := StaffMapLayers.hillshade(grid)
	assert_true(shade["vertices"].size() > 0)
	assert_eq(shade["vertices"].size(), shade["values"].size())
	assert_eq(shade["vertices"].size() % 3, 0)


func test_grid_lines_draw_each_shared_edge_once() -> void:
	var grid := Fixtures.plains_grid(0)
	assert_eq(StaffMapLayers.grid_lines(grid).size(), 12)  # one hex: 6 edges
	grid = Fixtures.plains_grid(1)  # 7 hexes: 7 * 6 - 12 shared edges counted twice = 30
	assert_eq(StaffMapLayers.grid_lines(grid).size(), 60)


func test_bounds_and_hex_lookup() -> void:
	var grid := Fixtures.plains_grid(2)
	var rect := StaffMapLayers.bounds(grid)
	assert_true(rect.has_point(Vector2.ZERO))
	var c := Vector2i(1, 1)
	var w := Hex.to_world(c, 1.0)
	assert_eq(StaffMapLayers.hex_at(Vector2(w.x + 0.1, w.z - 0.1)), c)


func test_ribbons_make_two_triangles_per_segment_around_the_line() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 2)])
	var mesh := StaffMapLayers.ribbons([line], 0.5)
	assert_eq(mesh.size(), 12)
	for p in mesh:
		assert_true(p.x >= -0.251 and p.x <= 2.251 and p.y >= -0.251 and p.y <= 2.251)
	assert_true(mesh.has(Vector2(0, 0) + Vector2(0, 0.25)) or mesh.has(Vector2(-0.25, 0.25)))


# --- TASK-125: strokes, class borders, sea ---


func test_a_through_road_is_one_stroke_and_the_side_road_ends_at_it() -> void:
	var grid := Fixtures.plains_grid(4)
	for q in range(-3, 3):
		_link(grid, Vector2i(q, 0), Vector2i(q + 1, 0))
	_link(grid, Vector2i(0, 0), Vector2i(0, 1))
	_link(grid, Vector2i(0, 1), Vector2i(0, 2))
	var strokes := StaffMapLayers.strokes(grid, false, 0)
	assert_eq(strokes.size(), 2)
	var lengths: Array = strokes.map(func(s: Dictionary) -> float: return s["steps"])
	lengths.sort()
	assert_true(absf(lengths[0] - 2.0) < 0.001, str(lengths))
	assert_true(absf(lengths[1] - 6.0) < 0.001, str(lengths))


func test_strokes_cover_every_link_once_and_are_deterministic() -> void:
	var grid := Fixtures.plains_grid(3)
	_link(grid, Vector2i(0, 0), Vector2i(1, 0))
	_link(grid, Vector2i(1, 0), Vector2i(1, 1))
	_link(grid, Vector2i(1, 1), Vector2i(0, 1))
	_link(grid, Vector2i(0, 1), Vector2i(0, 0))  # a loop
	_link(grid, Vector2i(-1, 0), Vector2i(-2, 0), true)
	var roads := StaffMapLayers.strokes(grid, false, 0)
	var total := 0.0
	for s in roads:
		total += s["steps"]
	assert_true(absf(total - 4.0) < 0.001)
	assert_eq(StaffMapLayers.strokes(grid, false, 2), StaffMapLayers.strokes(grid, false, 2))
	assert_eq(StaffMapLayers.strokes(grid, true, 0).size(), 1)


func test_borders_separate_the_classes_and_skip_uniform_ground() -> void:
	var grid := Fixtures.plains_grid(2)
	assert_eq(StaffMapLayers.borders(grid).size(), 0)
	grid.set_terrain(Vector2i.ZERO, Terrain.Type.FOREST)
	var borders := StaffMapLayers.borders(grid)
	var forest: PackedVector2Array = borders[Terrain.Type.FOREST]
	assert_eq(forest.size(), 12, "six triangles around the hex, one cut each")
	assert_eq(borders[Terrain.Type.PLAINS].size(), 12)
	for p in forest:
		assert_true(absf(p.length() - Hex.SQRT3 * 0.5) < 0.001, "cuts run through edge midpoints")


func test_sea_is_low_water_connected_to_the_map_edge() -> void:
	var grid := Fixtures.plains_grid(3)
	for c in grid.coords():
		grid.set_elevation_m(c, 50.0)
	for c in [Vector2i(3, 0), Vector2i(2, 0)]:  # edge water, sea level
		grid.set_terrain(c, Terrain.Type.WATER)
		grid.set_elevation_m(c, 0.0)
	grid.set_terrain(Vector2i(-1, 0), Terrain.Type.WATER)  # inland lake
	grid.set_elevation_m(Vector2i(-1, 0), 0.0)
	var sea := StaffMapLayers.sea_tiles(grid, 5.0)
	assert_true(sea.has(Vector2i(3, 0)) and sea.has(Vector2i(2, 0)))
	assert_false(sea.has(Vector2i(-1, 0)))
	var fills := StaffMapLayers.fills(grid, {Vector2i(3, 0): StaffMapPalette.SEA})
	assert_true(fills.has(StaffMapPalette.SEA))


func _offset_grid(cols: int, rows: int) -> HexGrid:
	var grid := HexGrid.new()
	for r in rows:
		for col in cols:
			grid.set_terrain(Vector2i(col - (r >> 1), r), Terrain.Type.PLAINS)
	return grid


func test_straight_rect_clips_fills_to_a_straight_left_and_right_edge() -> void:
	var grid := _offset_grid(6, 8)
	var rect := StaffMapLayers.straight_rect(grid)
	var full := StaffMapLayers.bounds(grid)
	assert_true(rect.size.x < full.size.x, "trimmed by the half-hex zigzag")
	var clipped := StaffMapLayers.clip_polygons(StaffMapLayers.fills(grid)[Terrain.Type.PLAINS], rect)
	assert_true(clipped.size() > 0)
	for poly: PackedVector2Array in clipped:
		for p in poly:
			assert_true(p.x >= rect.position.x - 0.001 and p.x <= rect.end.x + 0.001)


func test_clip_segments_cuts_at_the_rectangle() -> void:
	var rect := Rect2(0, 0, 10, 10)
	var out := StaffMapLayers.clip_segments(
		PackedVector2Array([Vector2(-5, 5), Vector2(5, 5), Vector2(20, 20), Vector2(30, 30)]), rect
	)
	assert_eq(out.size(), 2)
	assert_true(out[0].is_equal_approx(Vector2(0, 5)))
	assert_true(out[1].is_equal_approx(Vector2(5, 5)))


func test_clip_polyline_splits_at_the_rectangle() -> void:
	var rect := Rect2(0, 0, 10, 10)
	var line := PackedVector2Array([Vector2(-5, 5), Vector2(5, 5), Vector2(5, 20), Vector2(8, 5)])
	var pieces := StaffMapLayers.clip_polyline(line, rect)
	assert_eq(pieces.size(), 2)
	assert_true(pieces[0][0].is_equal_approx(Vector2(0, 5)))


func test_clipped_fill_covers_the_whole_straight_edge() -> void:
	var grid := _offset_grid(6, 8)
	var rect := StaffMapLayers.straight_rect(grid)
	var polys := StaffMapLayers.clip_polygons(StaffMapLayers.fills(grid)[Terrain.Type.PLAINS], rect)
	var missed := 0
	for i in 40:
		var p := Vector2(rect.position.x + 0.02, rect.position.y + rect.size.y * (i + 0.5) / 40.0)
		var hit := false
		for poly: PackedVector2Array in polys:
			hit = hit or Geometry2D.is_point_in_polygon(p, poly)
		if not hit:
			missed += 1
	assert_eq(missed, 0)
