extends TestCase
## The pure flight geometry and timing of a strike trace (TASK-141b).

const FROM := Vector2(0, 400)
const TO := Vector2(500, 400)


func test_apex_height_follows_the_arc() -> void:
	var flat := StaffMapStrikeFlight.point(FROM, TO, 0.5, 0.02)
	var high := StaffMapStrikeFlight.point(FROM, TO, 0.5, 0.40)
	assert_true(absf((400.0 - flat.y) - 10.0) < 0.01, "0.02 of 500 px = 10 px: %s" % flat)
	assert_true(absf((400.0 - high.y) - 200.0) < 0.01, "0.40 of 500 px = 200 px: %s" % high)
	assert_true(absf(high.x - 250.0) < 0.01, "apex over the middle")
	assert_eq(StaffMapStrikeFlight.point(FROM, TO, 0.0, 0.4), FROM)
	assert_eq(StaffMapStrikeFlight.point(FROM, TO, 1.0, 0.4), TO)


func test_apex_is_capped() -> void:
	assert_eq(StaffMapStrikeFlight.apex(5000.0, 0.4), StaffMapStrikeFlight.MAX_APEX_PX)
	assert_eq(StaffMapStrikeFlight.apex(100.0, 0.4, 1.0), 40.0)


func test_wobble_leaves_the_ends_and_moves_the_middle() -> void:
	var clean := StaffMapStrikeFlight.point(FROM, TO, 0.4, 0.02)
	var wobbly := StaffMapStrikeFlight.point(FROM, TO, 0.4, 0.02, 1.0, 0.0, 1.0, 3)
	assert_true(clean.distance_to(wobbly) > 0.5, "wobble displaces the path")
	assert_eq(StaffMapStrikeFlight.point(FROM, TO, 0.0, 0.02, 1.0, 0.0, 1.0, 3), FROM)
	assert_true(
		StaffMapStrikeFlight.point(FROM, TO, 1.0, 0.02, 1.0, 0.0, 1.0, 3).distance_to(TO) < 0.01
	)
	assert_true(clean.distance_to(wobbly) <= StaffMapStrikeFlight.WOBBLE_PX + 0.01)


func test_points_grow_with_progress() -> void:
	assert_eq(StaffMapStrikeFlight.points(FROM, TO, 24, 0.0, 0.1).size(), 1)
	assert_eq(StaffMapStrikeFlight.points(FROM, TO, 24, 0.5, 0.1).size(), 13)
	var full := StaffMapStrikeFlight.points(FROM, TO, 24, 1.0, 0.1)
	assert_eq(full.size(), 25)
	assert_eq(full[24], TO)


func test_stagger_offsets() -> void:
	assert_eq(StaffMapStrikeFlight.stagger(0), 0.0)
	assert_true(absf(StaffMapStrikeFlight.stagger(1) - 0.25) < 0.0001)
	assert_true(absf(StaffMapStrikeFlight.stagger(5) - 1.25) < 0.0001)


func test_drawn_indices_cap_at_six_and_spread() -> void:
	assert_eq(StaffMapStrikeFlight.drawn_indices(0), [] as Array[int])
	assert_eq(StaffMapStrikeFlight.drawn_indices(4), [0, 1, 2, 3] as Array[int])
	assert_eq(StaffMapStrikeFlight.drawn_indices(6), [0, 1, 2, 3, 4, 5] as Array[int])
	var many := StaffMapStrikeFlight.drawn_indices(16)
	assert_eq(many.size(), 6)
	assert_eq(many[0], 0)
	assert_true(many[5] >= 12 and many[5] < 16, "spread over the salvo: %s" % str(many))
	assert_eq(StaffMapStrikeFlight.hidden_count(16), 10)
	assert_eq(StaffMapStrikeFlight.hidden_count(4), 0)


func test_stop_point_of_an_intercepted_missile() -> void:
	var stop := StaffMapStrikeFlight.stop_point(FROM, TO)
	assert_true(absf(stop.x - 360.0) < 0.01, "72 % of the way: %s" % stop)
	assert_eq(StaffMapStrikeFlight.stop_point(FROM, TO, Vector2(300, 380)), Vector2(300, 380))


func test_heading_points_along_the_flight() -> void:
	var start := StaffMapStrikeFlight.heading(FROM, TO, 0.1, 0.4)
	var end := StaffMapStrikeFlight.heading(FROM, TO, 0.95, 0.4)
	assert_true(start.y < 0.0 and start.x > 0.0, "climbs at the start")
	assert_true(end.y > 0.0 and end.x > 0.0, "dives at the end")
