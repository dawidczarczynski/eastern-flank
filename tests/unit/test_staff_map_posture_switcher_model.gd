extends TestCase
## The posture strip model (TASK-158): segments, active posture, flip side, enabled flag, click
## meaning and texts. No scene.

const M := preload("res://src/presentation/operational/staff_map_posture_switcher_model.gd")


func test_three_segments_in_posture_order_with_move_percent_from_data() -> void:
	var segs := M.segments(&"advance")
	assert_eq(segs.size(), 3)
	assert_eq(segs[0]["posture"], &"march")
	assert_eq(segs[1]["posture"], &"advance")
	assert_eq(segs[2]["posture"], &"defend")
	assert_eq(segs[0]["move_percent"], OperationalPosture.find(&"march").move_percent)
	assert_eq(segs[2]["move_percent"], OperationalPosture.find(&"defend").move_percent)
	assert_false(segs[0]["active"])
	assert_true(segs[1]["active"])
	assert_eq(segs[2]["key"], 3)


func test_armed_posture_wins_over_the_formations_own() -> void:
	assert_eq(M.active_posture(&"defend", &""), &"defend")
	assert_eq(M.active_posture(&"defend", &"march"), &"march")


func test_caption_and_tooltip_use_name_and_percent() -> void:
	var percent := OperationalPosture.find(&"march").move_percent
	assert_eq(M.caption(&"march"), "MARCH · %d %%" % percent)
	var tip := M.tooltip(&"march")
	assert_eq(tip["title"], M.caption(&"march"))
	assert_true(String(tip["effect"]).length() > 0)
	assert_true(String(tip["key"]).contains("1"))


func test_enabled_only_for_own_on_the_viewers_turn_without_blockers() -> void:
	assert_true(M.enabled(true, true, false, false, false))
	assert_false(M.enabled(false, true, false, false, false))
	assert_false(M.enabled(true, false, false, false, false))
	assert_false(M.enabled(true, true, true, false, false))
	assert_false(M.enabled(true, true, false, true, false))
	assert_false(M.enabled(true, true, false, false, true))


func test_strip_flips_above_when_the_order_leaves_downwards() -> void:
	assert_false(M.flip_above(300.0, false, 0.0, 900.0))
	assert_false(M.flip_above(300.0, true, 100.0, 900.0))
	assert_true(M.flip_above(300.0, true, 500.0, 900.0))


func test_strip_flips_above_without_room_below() -> void:
	assert_true(M.flip_above(880.0, false, 0.0, 900.0))


func test_strip_rect_is_below_or_above_the_tile() -> void:
	var below := M.strip_rect(false)
	assert_eq(below.size, Vector2(156, 34))
	assert_eq(below.position.y, 38.0)
	var above := M.strip_rect(true)
	assert_eq(above.end.y, -38.0)
	assert_eq(above.get_center().x, 0.0)


func test_segment_at_maps_x_to_the_segment() -> void:
	assert_eq(M.segment_at(Vector2(-70, 50), false), 0)
	assert_eq(M.segment_at(Vector2(0, 50), false), 1)
	assert_eq(M.segment_at(Vector2(70, 50), false), 2)
	assert_eq(M.segment_at(Vector2(0, 10), false), -1)
	assert_eq(M.segment_at(Vector2(0, -50), true), 1)


func test_click_with_an_order_sets_the_posture_unless_it_is_the_same() -> void:
	assert_eq(M.click_action(true, &"march", &"", &"defend"), M.SET)
	assert_eq(M.click_action(true, &"march", &"", &"march"), M.NONE)


func test_click_without_an_order_arms_and_a_second_click_drops_it() -> void:
	assert_eq(M.click_action(false, &"march", &"", &"defend"), M.ARM)
	assert_eq(M.click_action(false, &"march", &"defend", &"defend"), M.DISARM)
	assert_eq(M.click_action(false, &"march", &"defend", &"advance"), M.ARM)
