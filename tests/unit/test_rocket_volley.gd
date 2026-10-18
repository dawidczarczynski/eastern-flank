extends TestCase

const TOL := 0.0001


func test_arc_endpoints() -> void:
	var from := Vector3(0, 1, 0)
	var to := Vector3(4, 0.5, 3)
	assert_true(RocketVolley.arc_point(from, to, 2.0, 0.0).distance_to(from) < TOL)
	assert_true(RocketVolley.arc_point(from, to, 2.0, 1.0).distance_to(to) < TOL)
	assert_true(RocketVolley.arc_point(from, to, 2.0, 5.0).distance_to(to) < TOL, "t is clamped")


func test_arc_apex_is_above_both_ends() -> void:
	var from := Vector3(0, 1, 0)
	var to := Vector3(4, 1.0, 0)
	var mid := RocketVolley.arc_point(from, to, 2.0, 0.5)
	assert_true(absf(mid.y - (1.0 + 2.0)) < TOL, "apex is the chord midpoint + apex height")
	assert_true(mid.y > from.y + 1.0 and mid.y > to.y + 1.0)
	var best := 0.0
	for i in 21:
		best = maxf(best, RocketVolley.arc_point(from, to, 2.0, i / 20.0).y)
	assert_true(absf(best - mid.y) < TOL, "the middle is the highest point")


func test_arc_moves_straight_in_xz() -> void:
	var p := RocketVolley.arc_point(Vector3.ZERO, Vector3(4, 0, 2), 1.0, 0.25)
	assert_true(absf(p.x - 1.0) < TOL and absf(p.z - 0.5) < TOL)


func test_apex_height_grows_with_distance_and_is_capped() -> void:
	assert_true(RocketVolley.apex_height(5.0) > RocketVolley.apex_height(1.0))
	assert_true(RocketVolley.apex_height(100.0) <= RocketVolley.APEX_MAX + TOL)


func test_progress_staggers_launches() -> void:
	assert_true(absf(RocketVolley.progress(RocketVolley.GAP, 1)) < TOL)
	assert_true(RocketVolley.progress(0.0, 2) < 0.0)
	assert_true(RocketVolley.progress(RocketVolley.FLIGHT, 0) >= 1.0 - TOL)


func test_total_duration_covers_last_rocket_and_impact() -> void:
	var expected := (
		(RocketVolley.ROCKET_COUNT - 1) * RocketVolley.GAP
		+ RocketVolley.FLIGHT
		+ RocketVolley.IMPACT_TIME
	)
	assert_true(absf(RocketVolley.total_duration() - expected) < TOL)
	assert_true(RocketVolley.last_impact_time() < RocketVolley.total_duration())
