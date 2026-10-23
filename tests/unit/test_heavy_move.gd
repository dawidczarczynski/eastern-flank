extends TestCase

const TOLERANCE := 0.001
const TILE := MoveAnimation.SECONDS_PER_TILE


func _near(actual: float, expected: float, message := "") -> void:
	assert_true(
		absf(actual - expected) < TOLERANCE, "%s got %f, expected %f" % [message, actual, expected]
	)


## East, then north-east-ish bend: (0,0) -> (1,0) -> (1,-1) (facing +X, then up the screen).
func _bend() -> PackedVector3Array:
	return PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, -1)])


func _straight() -> PackedVector3Array:
	return PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)])


func test_facing_the_way_means_no_pivot_and_one_run() -> void:
	var move := HeavyMove.plan(_straight(), 0.0)
	assert_eq((move["phases"] as Array).size(), 1)
	_near(move["duration"], 2.0 * TILE)


func test_a_wrong_heading_pivots_before_any_movement() -> void:
	var move := HeavyMove.plan(_straight(), PI)
	var phases: Array = move["phases"]
	assert_eq(phases.size(), 2)
	assert_eq(phases[0]["kind"], HeavyMove.PIVOT)
	var pivot_end: float = phases[0]["t1"]
	assert_true(pivot_end >= PI / HeavyMove.PIVOT_RATE - TOLERANCE, "a half turn takes its time")
	for i in 11:
		var pose := HeavyMove.pose(move, pivot_end * i / 10.0)
		_near(pose["path_time"], 0.0, "no travel while pivoting")
		assert_false(pose["driving"] and i < 10)
	_near(
		MoveAnimation.wrap_angle(HeavyMove.pose(move, pivot_end)["yaw"]),
		0.0,
		"facing the way at the end of the pivot"
	)
	_near(move["duration"], pivot_end + 2.0 * TILE)


func test_a_bend_stops_pivots_and_drives_off() -> void:
	var move := HeavyMove.plan(_bend(), 0.0)
	var phases: Array = move["phases"]
	assert_eq(phases.size(), 3)  # drive, pivot, drive
	assert_eq(phases[1]["kind"], HeavyMove.PIVOT)
	var at_bend := HeavyMove.pose(move, phases[0]["t1"])
	_near(at_bend["path_time"], TILE, "stopped on the corner tile")
	var mid_pivot := HeavyMove.pose(move, (phases[1]["t0"] + phases[1]["t1"]) / 2.0)
	_near(mid_pivot["path_time"], TILE, "no movement while turning")
	assert_false(mid_pivot["driving"])
	assert_true(absf(mid_pivot["turn_left"]) > 0.1)
	_near(HeavyMove.pose(move, move["duration"])["path_time"], 2.0 * TILE)


func test_the_yaw_is_a_run_heading_while_driving() -> void:
	var move := HeavyMove.plan(_bend(), 0.0)
	for i in 101:
		var pose := HeavyMove.pose(move, move["duration"] * i / 100.0)
		if pose["driving"]:
			var yaw: float = pose["yaw"]
			assert_true(
				absf(yaw) < TOLERANCE or absf(yaw - PI / 2.0) < TOLERANCE,
				"yaw %f is a run heading" % yaw
			)


func test_path_time_is_monotonic_and_starts_slowly() -> void:
	var move := HeavyMove.plan(_straight(), 0.0)
	var last := -1.0
	for i in 41:
		var p: float = HeavyMove.pose(move, move["duration"] * i / 40.0)["path_time"]
		assert_true(p >= last)
		last = p
	var light := MoveAnimation.path_time(0.3, move["duration"])
	assert_true(HeavyMove.pose(move, 0.3)["path_time"] < light, "heavier start than infantry")


func test_steered_heading_follows_the_path_without_lag() -> void:
	var pts := _bend()
	_near(MoveAnimation.steered_yaw(pts, TILE * 0.3), 0.0, "straight first part")
	_near(MoveAnimation.steered_yaw(pts, TILE * 1.7), PI / 2.0, "after the bend")
	var at_corner := MoveAnimation.steered_yaw(pts, TILE)
	assert_true(at_corner > 0.3 and at_corner < PI / 2.0 - 0.3, "mid-turn at the corner")
	_near(MoveAnimation.steered_yaw(pts, TILE * 2.0), PI / 2.0, "end keeps the last heading")
