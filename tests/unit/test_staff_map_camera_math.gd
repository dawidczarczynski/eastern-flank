extends TestCase
## Staff map camera maths (TASK-093a).

const MAP := Rect2(0, 0, 2000, 1000)
const VIEW := Vector2(1000, 500)


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
