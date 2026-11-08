extends TestCase
## StaffMapLayers clipping to the straight map edges (TASK-093a), split from
## test_staff_map_layers.gd. Hand-made grids, no scene.


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
	var clipped := StaffMapLayers.clip_polygons(
		StaffMapLayers.fills(grid)[Terrain.Type.PLAINS], rect
	)
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
