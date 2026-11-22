extends TestCase
## Unit markers (TASK-111): the fixed-pixel UnitLabel with a class icon, anchored 18 px above the
## unit's ground point, with the overlap shift and the marker click.

const Fixtures := preload("res://tests/fixtures.gd")
const CLASSES_PATH := "res://docs/design/units/classes.json"
const VIEWPORT_SIZE := Vector2i(1280, 720)

var _hud: Control


func before_each() -> void:
	_hud = Control.new()


func after_each() -> void:
	_hud.free()


func _class_ids() -> Array[StringName]:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CLASSES_PATH))
	var ids: Array[StringName] = []
	for entry: Dictionary in parsed:
		ids.append(StringName(entry["id"]))
	return ids


func test_every_design_class_has_its_own_icon_glyph() -> void:
	var ids := _class_ids()
	assert_true(ids.size() >= 10, "classes.json read")
	var box := Rect2(Vector2.ZERO, UnitClassIcon.SIZE).grow(0.01)
	var seen := {}
	for id in ids:
		assert_true(UnitClassIcon.has_glyph(id), "%s has a glyph" % id)
		var lines := HudShapes.class_glyph(id, UnitClassIcon.SIZE)
		var dots := HudShapes.class_glyph_dots(id, UnitClassIcon.SIZE)
		assert_true(lines.size() + dots.size() > 0, "%s draws something" % id)
		for line in lines:
			assert_true(line.size() >= 2, "%s polyline" % id)
			for p in line:
				assert_true(box.has_point(p), "%s point %s inside the icon" % [id, p])
		for p in dots:
			assert_true(box.has_point(p), "%s dot %s inside the icon" % [id, p])
		seen[str(lines) + str(dots)] = id
	# mech_infantry and ifv share the APP-6 mechanised infantry symbol; every other class differs.
	assert_eq(seen.size(), ids.size() - 1, "distinct glyphs")


func test_unknown_class_has_no_glyph_but_an_icon() -> void:
	assert_false(UnitClassIcon.has_glyph(&"no_such_class"))
	assert_eq(HudShapes.class_glyph(&"no_such_class", UnitClassIcon.SIZE).size(), 0)


func test_icon_is_15_by_11_px() -> void:
	assert_eq(UnitClassIcon.SIZE, Vector2(15, 11))
	var label := UnitLabel.new()
	_hud.add_child(label)
	label.setup("TNK", Color.RED, 8, 8, &"tank")
	assert_eq(label.class_icon().custom_minimum_size, Vector2(15, 11))
	assert_eq(label.class_icon().unit_class, &"tank")


## A camera `distance` from `target` at the curve's pitch, outside a scene tree: the screen point of
## `point` by the camera's own projection (Camera3D.unproject_position needs a viewport in a tree).
func _project(target: Vector3, distance: float, point: Vector3) -> Vector2:
	var eye := target + CameraMath.camera_offset(0.4, distance)
	var view := Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye).affine_inverse()
	var projection := Projection.create_perspective(40.0, 16.0 / 9.0, 0.01, 220.0)
	var clip := projection * Vector4((view * point).x, (view * point).y, (view * point).z, 1.0)
	var ndc := Vector2(clip.x, clip.y) / clip.w
	return Vector2((ndc.x + 1.0) * 0.5 * 1280.0, (1.0 - ndc.y) * 0.5 * 720.0)


func test_marker_pixel_size_does_not_depend_on_the_camera_distance() -> void:
	var label := UnitLabel.new()
	_hud.add_child(label)
	label.setup("TNK", Color.RED, 5, 8, &"tank")
	var sizes: Array[Vector2] = []
	for d: float in [0.4, 24.0, 46.0]:
		label.place_at(_project(Vector3.ZERO, d, Vector3(0.3, 0, 0.2)))
		assert_true(label.visible, "visible at %s" % d)
		sizes.append(label.size)
	assert_true(sizes[0].x > UnitClassIcon.SIZE.x and sizes[0].y >= UnitClassIcon.SIZE.y)
	assert_eq(sizes[1], sizes[0])
	assert_eq(sizes[2], sizes[0])


func _unit_view(coord: Vector2i, world: Vector3) -> UnitView:
	var state := GameState.new(Fixtures.plains_grid(3), 2, 1)
	var unit := state.add_unit(0, Fixtures.generic_tank(), coord)
	var view := UnitView.new()
	view.setup(unit, state.faction_of(0), world, _hud, Callable())
	return view


func _bottom_centre(label: UnitLabel) -> Vector2:
	return label.position + Vector2(label.size.x / 2.0, label.size.y)


func test_marker_sits_18_px_above_the_ground_point_at_any_model_scale() -> void:
	assert_eq(UnitLabel.ANCHOR_OFFSET, 18.0)
	var ground := Vector3(1.5, 0.3, -0.75)
	var view := _unit_view(Vector2i(1, 0), ground)
	for d: float in [0.4, 24.0]:
		for model_scale: float in [1.0, 4.0]:
			view.get_node("Body").scale = Vector3.ONE * model_scale  # the model's AABB grows
			var screen := _project(ground, d, view.ground_point())
			view.label().place_at(screen)
			var expected := screen - Vector2(0, 18)
			var got := _bottom_centre(view.label())
			assert_true(
				got.distance_to(expected) <= 0.71, "d %s scale %s: %s" % [d, model_scale, got]
			)
			assert_eq(view.ground_point(), ground, "the anchor is the ground point")
	view.free()


func test_marker_rect_is_the_label_above_the_anchor() -> void:
	var label := UnitLabel.new()
	_hud.add_child(label)
	label.setup("TNK", Color.RED, 8, 8, &"tank")
	var rect := label.rect_at(UnitLabel.anchor(Vector2(400, 300)))
	assert_eq(rect.end.y, 282.0)
	assert_eq(rect.get_center().x, 400.0)
	label.shift = 17.0
	label.place_at(Vector2(400, 300))
	assert_true(absf(label.position.y - (rect.position.y - 17.0)) <= 0.5, "shift moves it up")


func test_marker_is_hidden_without_a_camera() -> void:
	var view := _unit_view(Vector2i(0, 0), Vector3.ZERO)
	view.refresh_label()
	assert_false(view.label().visible)
	assert_eq(view.marker_rect(), Rect2())
	assert_false(view.marker_hit(Vector2.ZERO))
	view.free()


func test_distance_to_camera() -> void:
	var view := _unit_view(Vector2i(0, 0), Vector3(2, 0, 0))
	assert_true(absf(view.distance_from(Vector3(2, 3, 4)) - 5.0) < 0.001)
	assert_eq(view.distance_to_camera(), INF, "no camera")
	assert_true(CameraMath.draws_group(view.distance_from(Vector3(2, 1, 2))))
	assert_false(CameraMath.draws_group(view.distance_from(Vector3(2, 3, 4))))
	view.free()


func test_overlapping_markers_shift_the_farther_one_up_by_its_height() -> void:
	var near := Rect2(100, 100, 60, 17)
	var far := Rect2(130, 108, 60, 17)
	var shifts := UnitLabel.overlap_shifts([far, near] as Array[Rect2], [30.0, 10.0])
	assert_eq(shifts, PackedFloat32Array([17.0, 0.0]))


func test_no_shift_without_overlap() -> void:
	var a := Rect2(100, 100, 60, 17)
	var b := Rect2(161, 100, 60, 17)
	var c := Rect2(100, 118, 60, 17)
	var shifts := UnitLabel.overlap_shifts([a, b, c] as Array[Rect2], [10.0, 20.0, 30.0])
	assert_eq(shifts, PackedFloat32Array([0.0, 0.0, 0.0]))


func test_at_most_one_shift_step() -> void:
	# Three markers on top of each other: the two farther ones move up once each, never twice.
	var r := Rect2(100, 100, 60, 17)
	var shifts := UnitLabel.overlap_shifts([r, r, r] as Array[Rect2], [30.0, 10.0, 20.0])
	assert_eq(shifts, PackedFloat32Array([17.0, 0.0, 17.0]))


func test_marker_click_picks_the_closest_marker_under_the_point() -> void:
	var near := Rect2(100, 100, 60, 17)
	var far := Rect2(130, 108, 60, 17)
	var rects: Array[Rect2] = [far, near]
	var depths: Array[float] = [30.0, 10.0]
	assert_eq(UnitLabel.pick(rects, depths, Vector2(140, 110)), 1, "both: the closer")
	assert_eq(UnitLabel.pick(rects, depths, Vector2(185, 120)), 0, "only the far one")
	assert_eq(UnitLabel.pick(rects, depths, Vector2(10, 10)), -1, "none")


func test_marker_click_hits_the_drawn_marker() -> void:
	var view := _unit_view(Vector2i(1, 0), Vector3(1.5, 0, 0))
	var label := view.label()
	label.place_at(Vector2(640, 360))
	var inside := label.position + label.size * 0.5
	assert_true(view.marker_hit(inside))
	assert_false(view.marker_hit(label.position - Vector2(5, 5)))
	view.free()


func test_a_shifted_marker_blocks_the_farther_ones() -> void:
	# b moves up off a; c (farther, overlapping b's new place only) moves up too.
	var a := Rect2(100, 100, 60, 17)
	var b := Rect2(120, 105, 60, 17)
	var c := Rect2(190, 90, 60, 17)
	var shifts := UnitLabel.overlap_shifts([a, b, c] as Array[Rect2], [10.0, 20.0, 30.0])
	assert_eq(shifts, PackedFloat32Array([0.0, 17.0, 0.0]), "c is clear of b's new place")
	var d := Rect2(170, 90, 60, 17)
	shifts = UnitLabel.overlap_shifts([a, b, d] as Array[Rect2], [10.0, 20.0, 30.0])
	assert_eq(shifts, PackedFloat32Array([0.0, 17.0, 17.0]), "d overlaps b's new place")
