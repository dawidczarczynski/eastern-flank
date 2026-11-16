extends TestCase
## The posture glyph polygons (TASK-158): pure geometry shared by badge and switcher.


func _bounds(posture: StringName) -> Rect2:
	var pts := PackedVector2Array()
	for line in StaffMapPostureGlyphs.strokes(posture):
		pts.append_array(line)
	for poly in StaffMapPostureGlyphs.fills(posture):
		pts.append_array(poly)
	var rect := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		rect = rect.expand(p)
	return rect


func test_every_posture_has_a_glyph_inside_the_design_box() -> void:
	var box := Rect2(-6, -6, 12, 12)
	for posture in OperationalPosture.NAMES:
		assert_false(StaffMapPostureGlyphs.strokes(posture).is_empty(), String(posture))
		assert_true(box.encloses(_bounds(posture)), String(posture))


func test_unknown_posture_has_no_glyph() -> void:
	assert_true(StaffMapPostureGlyphs.strokes(&"nope").is_empty())
	assert_true(StaffMapPostureGlyphs.fills(&"nope").is_empty())


func test_march_is_a_double_chevron() -> void:
	var lines := StaffMapPostureGlyphs.strokes(&"march")
	assert_eq(lines.size(), 2)
	assert_eq(lines[0].size(), 3)
	assert_true(StaffMapPostureGlyphs.fills(&"march").is_empty())


func test_advance_is_a_shaft_with_a_filled_head() -> void:
	assert_eq(StaffMapPostureGlyphs.strokes(&"advance").size(), 1)
	var heads := StaffMapPostureGlyphs.fills(&"advance")
	assert_eq(heads.size(), 1)
	assert_eq(heads[0].size(), 3)


func test_defend_is_an_arc_over_a_bar() -> void:
	var lines := StaffMapPostureGlyphs.strokes(&"defend")
	assert_eq(lines.size(), 2)
	assert_true(lines[0].size() > 4)  # the arc
	assert_eq(lines[1].size(), 2)  # the bar
	assert_true(lines[0][4].y < lines[1][0].y)  # the arc crown is above the bar
