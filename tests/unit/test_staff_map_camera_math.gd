extends TestCase
## Staff map camera maths (TASK-093a).

const MAP := Rect2(0, 0, 2000, 1000)
const VIEW := Vector2(1000, 500)
const UNIT := 20.0


func test_min_zoom_fits_the_whole_map() -> void:
	assert_eq(StaffMapCameraMath.min_zoom(MAP, VIEW), 0.5)
	assert_eq(StaffMapCameraMath.min_zoom(MAP, Vector2(1000, 100)), 0.1)


func test_max_zoom_shows_about_ten_hexes_and_is_not_below_min() -> void:
	var z := StaffMapCameraMath.max_zoom(Vector2(1280, 720), 20.0, 0.38)
	assert_true(absf(z - 2.4) < 0.001)
	assert_eq(StaffMapCameraMath.max_zoom(Vector2(100, 100), 20.0, 5.0), 5.0)


func test_clamp_keeps_the_view_inside_the_map() -> void:
	var p := StaffMapCameraMath.clamp_position(Vector2(-500, 5000), 1.0, MAP, VIEW)
	assert_eq(p, Vector2(500, 750))
	p = StaffMapCameraMath.clamp_position(Vector2(5000, -5000), 1.0, MAP, VIEW)
	assert_eq(p, Vector2(1500, 250))


func test_clamp_centres_when_the_map_is_smaller_than_the_view() -> void:
	var p := StaffMapCameraMath.clamp_position(Vector2(10, 10), 0.25, MAP, VIEW)
	assert_eq(p, Vector2(1000, 500))


func test_zoom_about_cursor_keeps_the_world_point_fixed() -> void:
	var cursor := Vector2(800, 100)
	var before := Vector2(700, 400) + (cursor - VIEW * 0.5) / 1.0
	var moved := StaffMapCameraMath.zoom_about(Vector2(700, 400), 1.0, 2.0, cursor, VIEW)
	var after := moved + (cursor - VIEW * 0.5) / 2.0
	assert_true(before.distance_to(after) < 0.001)


func test_zoom_by_is_clamped() -> void:
	assert_eq(StaffMapCameraMath.zoom_by(1.0, 100.0, 0.5, 2.0), 2.0)
	assert_eq(StaffMapCameraMath.zoom_by(1.0, -100.0, 0.5, 2.0), 0.5)
	assert_true(StaffMapCameraMath.zoom_by(1.0, 1.0, 0.5, 2.0) > 1.0)


# --- TASK-125: the tilted orthographic camera ---


func test_pitch_zero_ground_viewport_and_cursor_are_the_screen() -> void:
	assert_eq(StaffMapCameraMath.ground_viewport(VIEW, 0.0), VIEW)
	assert_eq(StaffMapCameraMath.ground_cursor(Vector2(800, 100), VIEW, 0.0), Vector2(800, 100))
	assert_eq(StaffMapCameraMath.drag_delta(Vector2(10, -20), 2.0, 0.0), Vector2(-5, 10))


func test_pitch_zero_reproduces_the_v0_camera() -> void:
	# v0: the world pixel under the cursor is position + (cursor - viewport / 2) / zoom.
	var position := Vector2(700, 400)
	var zoom := 1.5
	var cursor := Vector2(800, 100)
	var expected := position + (cursor - VIEW * 0.5) / zoom
	var target := Vector3(position.x, 0.0, position.y) / UNIT
	var hit := StaffMapCameraMath.plane_point(cursor, VIEW, target, zoom * UNIT, 0.0)
	assert_true((hit * UNIT).distance_to(expected) < 0.001, str(hit * UNIT))
	var screen := StaffMapCameraMath.project(
		Vector3(hit.x, 3.0, hit.y), VIEW, target, zoom * UNIT, 0.0
	)
	assert_true(screen.distance_to(cursor) < 0.001, "height does not move a point when flat")
	# Same limits as v0 when flat.
	var ground := StaffMapCameraMath.ground_viewport(VIEW, 0.0)
	assert_eq(StaffMapCameraMath.min_zoom(MAP, ground), 0.5)


func test_tilt_foreshortens_the_ground_by_cos_pitch() -> void:
	var ground := StaffMapCameraMath.ground_viewport(VIEW, 60.0)
	assert_true(absf(ground.y - 1000.0) < 0.01)
	assert_true(absf(StaffMapCameraMath.min_zoom(MAP, ground) - 0.5) < 0.0001)
	assert_true(StaffMapCameraMath.min_zoom(Rect2(0, 0, 100, 1000), ground) > 0.49)
	var drag := StaffMapCameraMath.drag_delta(Vector2(0, 10), 1.0, 60.0)
	assert_true(absf(drag.y + 20.0) < 0.01)


func test_clamp_with_tilt_uses_the_ground_viewport() -> void:
	var ground := StaffMapCameraMath.ground_viewport(VIEW, 60.0)  # 1000 x 1000 ground pixels
	var p := StaffMapCameraMath.clamp_position(Vector2(-500, -500), 1.0, MAP, ground)
	assert_eq(p.x, 500.0)
	assert_true(absf(p.y - 500.0) < 0.01)  # the map's 1000 px depth fits exactly: centred


func test_plane_point_and_project_agree_at_every_pitch() -> void:
	var target := Vector3(30, 0, 20)
	for pitch in [0.0, 20.0, 35.0, 50.0]:
		for cursor in [Vector2(0, 0), Vector2(1000, 500), Vector2(321, 77)]:
			var hit := StaffMapCameraMath.plane_point(cursor, VIEW, target, 40.0, pitch)
			var back := StaffMapCameraMath.project(
				Vector3(hit.x, 0.0, hit.y), VIEW, target, 40.0, pitch
			)
			assert_true(back.distance_to(cursor) < 0.01, "%s %s" % [pitch, cursor])
		var centre := StaffMapCameraMath.plane_point(VIEW * 0.5, VIEW, target, 40.0, pitch)
		assert_true(centre.distance_to(Vector2(30, 20)) < 0.001)


func test_camera_transform_matches_the_ray() -> void:
	var target := Vector3(5, 0, 7)
	var xf := StaffMapCameraMath.camera_transform(target, 35.0)
	var ray := StaffMapCameraMath.screen_ray(VIEW * 0.5, VIEW, target, 40.0, 35.0)
	assert_true(xf.origin.distance_to(ray["origin"]) < 0.001)
	var forward := -xf.basis.z
	assert_true(forward.y < 0.0 and forward.z < 0.0, "looks down and north")
	assert_true(absf(xf.basis.x.dot(Vector3.RIGHT) - 1.0) < 0.0001, "no yaw")


func test_cursor_centred_zoom_with_tilt_keeps_the_ground_point() -> void:
	var pitch := 35.0
	var position := Vector2(700, 400)
	var cursor := Vector2(800, 100)
	var target := Vector3(position.x, 0.0, position.y) / UNIT
	var before := StaffMapCameraMath.plane_point(cursor, VIEW, target, 1.0 * UNIT, pitch)
	var moved := StaffMapCameraMath.zoom_about(
		position,
		1.0,
		2.0,
		StaffMapCameraMath.ground_cursor(cursor, VIEW, pitch),
		StaffMapCameraMath.ground_viewport(VIEW, pitch)
	)
	var target_after := Vector3(moved.x, 0.0, moved.y) / UNIT
	var after := StaffMapCameraMath.plane_point(cursor, VIEW, target_after, 2.0 * UNIT, pitch)
	assert_true(before.distance_to(after) < 0.0001, "%s vs %s" % [before, after])


func test_pitch_clamp_and_toggle() -> void:
	assert_eq(StaffMapCameraMath.clamp_pitch(-10.0), 0.0)
	assert_eq(StaffMapCameraMath.clamp_pitch(80.0), 50.0)
	assert_eq(StaffMapCameraMath.toggle_pitch(35.0, 35.0), 0.0)
	assert_eq(StaffMapCameraMath.toggle_pitch(0.0, 42.0), 42.0)
	assert_eq(StaffMapCameraMath.toggle_pitch(0.0, 0.0), StaffMapCameraMath.PITCH_DEFAULT)


func test_zoom_level_thresholds_with_hysteresis() -> void:
	var t := Vector2(5.0, 9.0)
	assert_eq(StaffMapCameraMath.zoom_level(3.0, 0, t, 0.1), 0)
	assert_eq(StaffMapCameraMath.zoom_level(5.2, 0, t, 0.1), 0, "inside the band: stays")
	assert_eq(StaffMapCameraMath.zoom_level(5.6, 0, t, 0.1), 1)
	assert_eq(StaffMapCameraMath.zoom_level(4.8, 1, t, 0.1), 1, "inside the band: stays")
	assert_eq(StaffMapCameraMath.zoom_level(4.4, 1, t, 0.1), 0)
	assert_eq(StaffMapCameraMath.zoom_level(20.0, 0, t, 0.1), 2)
	assert_eq(StaffMapCameraMath.zoom_level(1.0, 2, t, 0.1), 0)
