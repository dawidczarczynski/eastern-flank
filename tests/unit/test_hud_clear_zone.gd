extends TestCase
## HUD clear zone maths (TASK-150): insets, pan clamp, panel side, ease shift.

const MAP := Rect2(0, 0, 2000, 1000)
const VIEW := Vector2(1000, 500)

const INSETS := Vector4(100, 50, 40, 20)  # top, bottom, left, right


func test_clear_rect_is_the_viewport_minus_the_insets() -> void:
	assert_eq(StaffMapCameraMath.clear_rect(VIEW, INSETS), Rect2(40, 100, 940, 350))


func test_clamp_lets_the_theatre_edge_reach_the_clear_zone_edge() -> void:
	# zoom 1: the clear zone's top-left corner may reach the map's top-left corner
	var p := StaffMapCameraMath.clamp_position(Vector2(-500, -500), 1.0, MAP, VIEW, INSETS)
	assert_eq(p + Vector2(40, 100) - VIEW * 0.5, Vector2.ZERO)
	# and the bottom-right corner of the clear zone the map's bottom-right corner
	p = StaffMapCameraMath.clamp_position(Vector2(9000, 9000), 1.0, MAP, VIEW, INSETS)
	assert_eq(p + Vector2(980, 450) - VIEW * 0.5, MAP.end)


func test_clamp_without_insets_is_unchanged() -> void:
	var a := StaffMapCameraMath.clamp_position(Vector2(-500, 5000), 1.0, MAP, VIEW)
	assert_eq(a, StaffMapCameraMath.clamp_position(Vector2(-500, 5000), 1.0, MAP, VIEW, Vector4()))


func test_clamp_centres_the_clear_zone_vertically_when_the_map_is_smaller() -> void:
	var p := StaffMapCameraMath.clamp_position(Vector2(10, 10), 0.25, MAP, VIEW, INSETS)
	var centre_y := 275.0  # centre of the clear zone on screen
	assert_eq(p.y + (centre_y - VIEW.y * 0.5) / 0.25, MAP.get_center().y)


func test_a_map_narrower_than_the_screen_stays_centred_whatever_docks() -> void:
	var docked := Vector4(100, 50, 400, 0)
	var a := StaffMapCameraMath.clamp_position(Vector2(10, 10), 0.25, MAP, VIEW, docked)
	var b := StaffMapCameraMath.clamp_position(Vector2(10, 10), 0.25, MAP, VIEW, INSETS)
	assert_eq(a.x, MAP.get_center().x)
	assert_eq(b.x, MAP.get_center().x)


func test_ground_insets_stretch_top_and_bottom_with_the_pitch() -> void:
	var g := StaffMapCameraMath.ground_insets(INSETS, 60.0)  # cos 60 = 0.5
	assert_true(absf(g.x - 200.0) < 0.001 and absf(g.y - 100.0) < 0.001)
	assert_eq(Vector2(g.z, g.w), Vector2(40, 20))


func test_panel_docks_opposite_the_counter() -> void:
	assert_true(StaffMapCameraMath.panel_on_left(1000.0, 1440.0, true))  # counter right of centre
	assert_false(StaffMapCameraMath.panel_on_left(400.0, 1440.0, true))
	assert_false(StaffMapCameraMath.panel_on_left(1000.0, 1440.0, false))  # left dock busy
	assert_false(StaffMapCameraMath.panel_on_left(720.0, 1440.0, true))  # exactly centre


func test_ease_shift_is_zero_inside_and_minimal_outside() -> void:
	var clear := Rect2(0, 100, 1000, 400)
	assert_eq(StaffMapCameraMath.ease_shift(Vector2(500, 300), clear, 40.0), Vector2.ZERO)
	assert_eq(StaffMapCameraMath.ease_shift(Vector2(500, 80), clear, 40.0), Vector2(0, 60))
	assert_eq(StaffMapCameraMath.ease_shift(Vector2(990, 520), clear, 40.0), Vector2(-30, -60))
