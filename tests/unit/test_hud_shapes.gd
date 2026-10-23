extends TestCase


func test_chamfer_vertex_counts() -> void:
	var size := Vector2(100, 50)
	assert_eq(HudShapes.chamfer(size).size(), 4)
	assert_eq(HudShapes.chamfer(size, 10).size(), 5)
	assert_eq(HudShapes.chamfer(size, 10, 10).size(), 6)
	assert_eq(HudShapes.chamfer(size, 10, 10, 10).size(), 7)
	assert_eq(HudShapes.chamfer(size, 10, 10, 10, 10).size(), 8)


func test_chamfer_square_is_the_rect() -> void:
	var pts := HudShapes.chamfer(Vector2(100, 50))
	assert_eq(
		pts, PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 50), Vector2(0, 50)])
	)


func test_chamfer_top_right_and_bottom_left_matches_readme() -> void:
	# polygon(0 0, calc(100% - 12px) 0, 100% 12px, 100% 100%, 12px 100%, 0 calc(100% - 12px))
	var pts := HudShapes.chamfer(Vector2(200, 80), 0, 12, 0, 12)
	assert_eq(
		pts,
		PackedVector2Array(
			[
				Vector2(0, 0),
				Vector2(188, 0),
				Vector2(200, 12),
				Vector2(200, 80),
				Vector2(12, 80),
				Vector2(0, 68),
			]
		)
	)


func test_chamfer_top_left_cut() -> void:
	var pts := HudShapes.chamfer(Vector2(100, 50), 10)
	assert_eq(pts[0], Vector2(0, 10))
	assert_eq(pts[1], Vector2(10, 0))


func test_chamfer_is_limited_to_half_the_short_side() -> void:
	var pts := HudShapes.chamfer(Vector2(100, 20), 0, 0, 50, 0)
	assert_eq(pts[2], Vector2(100, 10))
	assert_eq(pts[3], Vector2(90, 20))


func test_chamfer_inset_is_offset_and_smaller() -> void:
	var inner := HudShapes.chamfer_inset(Vector2(100, 50), 1.0, 0, 12, 0, 12)
	var bounds := Rect2(inner[0], Vector2.ZERO)
	for p in inner:
		bounds = bounds.expand(p)
	assert_eq(bounds.position, Vector2(1, 1))
	assert_eq(bounds.end, Vector2(99, 49))


func test_trapezoid() -> void:
	assert_eq(
		HudShapes.trapezoid(Vector2(300, 80), 26),
		PackedVector2Array([Vector2(0, 0), Vector2(300, 0), Vector2(274, 80), Vector2(26, 80)])
	)


func test_hex_badge_40x36() -> void:
	var pts := HudShapes.hex_badge(Vector2(40, 36))
	assert_eq(pts.size(), 6)
	assert_eq(pts[0], Vector2(10, 0))
	assert_eq(pts[1], Vector2(30, 0))
	assert_eq(pts[2], Vector2(40, 18))
	assert_eq(pts[3], Vector2(30, 36))
	assert_eq(pts[4], Vector2(10, 36))
	assert_eq(pts[5], Vector2(0, 18))
	assert_eq(HudShapes.hex_badge(), pts)


func test_skewed_segment() -> void:
	assert_eq(
		HudShapes.skewed_segment(Vector2(20, 8)),
		PackedVector2Array([Vector2(3, 0), Vector2(20, 0), Vector2(17, 8), Vector2(0, 8)])
	)


func test_header_tab() -> void:
	assert_eq(
		HudShapes.header_tab(Vector2(80, 20)),
		PackedVector2Array([Vector2(0, 0), Vector2(70, 0), Vector2(80, 20), Vector2(0, 20)])
	)


func _assert_inside(polys: Array[PackedVector2Array], size: Vector2) -> void:
	var rect := Rect2(Vector2.ZERO, size).grow(0.001)
	for poly in polys:
		for p in poly:
			assert_true(rect.has_point(p), "%s outside %s" % [p, size])


func test_hatch_stays_inside_rect() -> void:
	for size: Vector2 in [Vector2(150, 3), Vector2(16, 40), Vector2(420, 8), Vector2(7, 7)]:
		_assert_inside(HudShapes.hatch_thin(size), size)
		_assert_inside(HudShapes.hatch_wide(size), size)


func test_hatch_stripe_count_and_coverage() -> void:
	var size := Vector2(60, 60)
	var stripes := HudShapes.hatch_thin(size)
	# x + y spans 0..120, one stripe every 6 * sqrt(2) = 8.49: 15 starts.
	assert_eq(stripes.size(), 15)
	var area := 0.0
	for poly in stripes:
		area += absf(_polygon_area(poly))
	# Roughly stripe / period of the rectangle (the corner stripes are partial).
	var ratio := area / (size.x * size.y)
	assert_true(ratio > 0.30 and ratio < 0.37, "coverage %s" % ratio)
	var wide := 0.0
	for poly in HudShapes.hatch_wide(size):
		wide += absf(_polygon_area(poly))
	assert_true(wide / (size.x * size.y) > 0.62, "wide coverage")


func test_hatch_degenerate_sizes_are_empty() -> void:
	assert_eq(HudShapes.hatch(Vector2.ZERO, 2, 6).size(), 0)
	assert_eq(HudShapes.hatch(Vector2(10, 10), 0, 6).size(), 0)


func _polygon_area(poly: PackedVector2Array) -> float:
	var sum := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		sum += a.x * b.y - b.x * a.y
	return sum * 0.5


func test_ruler_ticks() -> void:
	var pts := HudShapes.ruler_ticks()
	assert_eq(pts.size(), 122)  # 61 ticks, two points each
	assert_eq(pts[1].y, 8.0)  # tick 0 is tall
	assert_eq(pts[11].y, 5.0)  # tick 5
	assert_eq(pts[3].y, 3.0)  # tick 1
	assert_eq(pts[21].y, 8.0)  # tick 10
	assert_eq(pts[120].x, 300.5)  # last tick spans the 300 px ruler


func test_corner_bracket_arms() -> void:
	var tl := HudShapes.corner_bracket(0, Vector2(100, 60), 9.0, 1.0)
	assert_eq(tl, PackedVector2Array([Vector2(-1, 8), Vector2(-1, -1), Vector2(8, -1)]))
	var br := HudShapes.corner_bracket(2, Vector2(100, 60), 9.0)
	assert_eq(br, PackedVector2Array([Vector2(100, 51), Vector2(100, 60), Vector2(91, 60)]))


func test_enter_glyph_stays_inside_its_box() -> void:
	var size := Vector2(9, 8)
	var lines := HudShapes.enter_glyph(size)
	assert_eq(lines.size(), 2)
	for line in lines:
		assert_eq(line.size(), 3)
		for p in line:
			assert_true(Rect2(Vector2.ZERO, size).grow(0.01).has_point(p), "point %s" % str(p))
