extends TestCase


func test_six_segments_with_four_points_each() -> void:
	assert_eq(RadialRingGeometry.SLOT_COUNT, 6)
	for slot in RadialRingGeometry.SLOT_COUNT:
		assert_eq(RadialRingGeometry.segment(slot).size(), 4)


func test_label_centre_hits_its_own_slot() -> void:
	for slot in RadialRingGeometry.SLOT_COUNT:
		assert_eq(RadialRingGeometry.slot_at(RadialRingGeometry.label_center(slot)), slot)


func test_slots_run_clockwise_from_north_east() -> void:
	assert_eq(RadialRingGeometry.slot_at(Vector2(60, -100)), 0)  # NE
	assert_eq(RadialRingGeometry.slot_at(Vector2(110, 0)), 1)  # E
	assert_eq(RadialRingGeometry.slot_at(Vector2(-110, 0)), 4)  # W


func test_gaps_between_segments_hit_nothing() -> void:
	assert_eq(RadialRingGeometry.slot_at(Vector2(0, -120)), -1)  # between 6 and 1
	assert_eq(RadialRingGeometry.slot_at(Vector2(0, 120)), -1)  # between 3 and 4
	var between_1_and_2 := Vector2(72.7, -42.0).lerp(Vector2(138.6, -80.0), 0.5)
	assert_eq(RadialRingGeometry.slot_at(between_1_and_2), -1)


func test_inside_the_hole_and_outside_the_ring_hit_nothing() -> void:
	assert_eq(RadialRingGeometry.slot_at(Vector2.ZERO), -1)
	assert_eq(RadialRingGeometry.slot_at(Vector2(0, -80)), -1)  # r < 84
	assert_eq(RadialRingGeometry.slot_at(Vector2(60, 0)), -1)
	assert_eq(RadialRingGeometry.slot_at(Vector2(170, 0)), -1)  # r > 160
	assert_eq(RadialRingGeometry.slot_at(Vector2(0, -165)), -1)


func test_inner_hex_is_pointy_top() -> void:
	var hex := RadialRingGeometry.inner_hex()
	assert_eq(hex.size(), 6)
	assert_true(hex[0].is_equal_approx(Vector2(0, -75)))
	assert_true(hex[1].is_equal_approx(Vector2(64.951904, -37.5)))


func test_tick_ring_has_long_ticks_every_30_degrees() -> void:
	var ticks := RadialRingGeometry.ticks()
	assert_eq(ticks.size(), 72 * 2)
	assert_true(ticks[0].is_equal_approx(Vector2(168, 0)))
	assert_true(ticks[1].is_equal_approx(Vector2(178, 0)))  # 0 deg: long
	assert_true(is_equal_approx(ticks[3].length(), 172.0))  # 5 deg: short
	assert_true(is_equal_approx(ticks[13].length(), 178.0))  # 30 deg: long


func test_key_numbers_sit_on_the_slot_direction() -> void:
	assert_true(RadialRingGeometry.key_position(1).is_equal_approx(Vector2(190, 0)))
	var ne := RadialRingGeometry.key_position(0)
	assert_true(is_equal_approx(ne.length(), 190.0))
	assert_true(is_equal_approx(ne.angle(), RadialRingGeometry.label_center(0).angle()))


func test_centre_is_clamped_inside_the_viewport() -> void:
	var viewport := Vector2(1280, 720)
	assert_eq(RadialRingGeometry.clamp_center(Vector2(640, 360), viewport), Vector2(640, 360))
	assert_eq(RadialRingGeometry.clamp_center(Vector2(-50, 900), viewport), Vector2(200, 520))
	assert_eq(RadialRingGeometry.clamp_center(Vector2(1270, 10), viewport), Vector2(1080, 200))


func test_card_sits_right_of_the_ring_and_flips_near_the_edge() -> void:
	var viewport := Vector2(1280, 720)
	var card := Vector2(272, 300)
	var right := RadialRingGeometry.card_position(Vector2(400, 360), viewport, card)
	assert_eq(right, Vector2(606, 210))
	var left := RadialRingGeometry.card_position(Vector2(1000, 360), viewport, card)
	assert_eq(left, Vector2(1000 - 206 - 272, 210))
	var low := RadialRingGeometry.card_position(Vector2(400, 700), viewport, card)
	assert_eq(low.y, 720.0 - 300.0 - RadialRingGeometry.EDGE)


func test_target_tag_sits_below_right_of_the_cursor_and_flips_near_the_edges() -> void:
	var viewport := Vector2(1280, 720)
	var tag := Vector2(150, 60)
	assert_eq(TargetTag.placement(Vector2(400, 300), viewport, tag), Vector2(422, 318))
	# Near the right / bottom edge it flips to the left of / above the cursor.
	assert_eq(TargetTag.placement(Vector2(1200, 300), viewport, tag), Vector2(1028, 318))
	assert_eq(TargetTag.placement(Vector2(400, 700), viewport, tag), Vector2(422, 622))
	# Never off the top-left.
	assert_eq(TargetTag.placement(Vector2(0, 0), Vector2(100, 50), tag), Vector2(8, 8))
