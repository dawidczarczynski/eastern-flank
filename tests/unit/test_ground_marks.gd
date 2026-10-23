extends TestCase

const PATH := [
	Vector3(0, 0, 0), Vector3(1.5, 0.1, 0), Vector3(2.5, 0.2, 1.7), Vector3(2.5, 0.2, 3.4)
]


func _path() -> PackedVector3Array:
	return PackedVector3Array(PATH)


func test_tank_path_gives_one_track_per_segment() -> void:
	var marks := GroundMarks.track_segments(_path(), &"tank")
	assert_eq(marks.size(), 3)
	for i in 3:
		var from: Vector3 = PATH[i]
		var to: Vector3 = PATH[i + 1]
		var mark := marks[i]
		assert_eq(mark["kind"], GroundMarks.KIND_TRACK)
		assert_true((mark["center"] as Vector3).is_equal_approx((from + to) * 0.5), "midpoint")
		var expected_yaw := atan2(-(to.z - from.z), to.x - from.x)
		assert_true(absf(wrapf(mark["yaw"] - expected_yaw, -PI, PI)) < 0.01, "yaw along segment")
		var flat := Vector2(to.x - from.x, to.z - from.z).length()
		assert_true(absf(mark["length"] - flat) < 0.0001, "length")
		assert_eq(mark["width"], 0.42)
		assert_eq(mark["segment"], i)


func test_mlrs_leaves_narrower_tyre_marks_and_infantry_nothing() -> void:
	var tyres := GroundMarks.track_segments(_path(), &"mlrs")
	assert_eq(tyres.size(), 3)
	assert_eq(tyres[0]["width"], 0.34)
	assert_eq(tyres[0]["kind"], GroundMarks.KIND_TYRE)
	assert_eq(GroundMarks.track_segments(_path(), &"infantry").size(), 0)


func test_track_width_follows_the_unit_scale() -> void:
	var marks := GroundMarks.track_segments(_path(), &"tank", 1.1)
	assert_true(absf(marks[0]["width"] - 0.42 * 1.1 / 1.3) < 0.0001)


func test_track_pitch_follows_the_slope() -> void:
	var marks := GroundMarks.track_segments(_path(), &"tank")
	assert_true(marks[0]["pitch"] > 0.0, "rising segment tilts up")


func test_short_paths_give_nothing() -> void:
	assert_eq(GroundMarks.track_segments(PackedVector3Array(), &"tank").size(), 0)
	assert_eq(GroundMarks.track_segments(PackedVector3Array([Vector3.ZERO]), &"tank").size(), 0)


func test_indirect_fire_leaves_two_or_three_craters_near_the_target() -> void:
	var centre := Vector3(4, 0.5, 2)
	for event_index in 40:
		var marks := GroundMarks.craters(event_index, centre, 5, 3, false)
		assert_true(marks.size() >= 2 and marks.size() <= 3, "2-3 craters")
		for mark in marks:
			assert_eq(mark["kind"], GroundMarks.KIND_CRATER)
			var offset: Vector3 = mark["center"] - centre
			assert_true(Vector2(offset.x, offset.z).length() <= 0.35, "within 0.35")
			var radius: float = mark["length"] * 0.5
			assert_true(radius >= 0.10 - 0.0001 and radius <= 0.16 + 0.0001, "radius")
		var scorch := GroundMarks.impact_scorch(event_index, centre, 5, 3, false)
		assert_eq(scorch.size(), 1)
		assert_true(absf(scorch[0]["length"] * 0.5 - 0.25) < 0.0001, "scorch radius")


func test_direct_fire_and_counters_leave_nothing() -> void:
	var centre := Vector3.ZERO
	assert_eq(GroundMarks.craters(1, centre, 5, 1, false).size(), 0, "distance 1")
	assert_eq(GroundMarks.craters(1, centre, 1, 3, false).size(), 0, "range 1")
	assert_eq(GroundMarks.craters(1, centre, 5, 3, true).size(), 0, "counter")
	assert_eq(GroundMarks.impact_scorch(1, centre, 5, 1, false).size(), 0)


func test_craters_are_deterministic_per_event_index() -> void:
	var centre := Vector3(1, 0, 1)
	assert_eq(
		GroundMarks.craters(7, centre, 5, 3, false), GroundMarks.craters(7, centre, 5, 3, false)
	)
	var differs := false
	for i in range(8, 20):
		if (
			GroundMarks.craters(i, centre, 5, 3, false)
			!= GroundMarks.craters(7, centre, 5, 3, false)
		):
			differs = true
	assert_true(differs, "other events differ")


func test_death_scorch_radius() -> void:
	var mark := GroundMarks.death_scorch(3, Vector3(2, 0, 2))
	assert_eq(mark["kind"], GroundMarks.KIND_SCORCH)
	assert_true(absf(mark["length"] * 0.5 - 0.35) < 0.0001)


func test_wreck_burnt_ground_is_wider_than_a_tile_patch() -> void:
	var mark := GroundMarks.wreck_burnt(3, Vector3(2, 0, 2))
	assert_eq(mark["kind"], GroundMarks.KIND_BURNT)
	assert_true(mark["length"] * 0.5 > GroundMarks.DEATH_SCORCH_RADIUS * 1.5)
	assert_eq(mark, GroundMarks.wreck_burnt(3, Vector3(2, 0, 2)), "deterministic")


func _reveal_path() -> PackedVector3Array:
	return PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(2, 0, 2)])


func test_reveal_starts_empty_and_follows_the_unit() -> void:
	var spt := MoveAnimation.SECONDS_PER_TILE
	var start := GroundMarks.reveal_fractions(_reveal_path(), 0.0)
	assert_eq(start.size(), 2)
	assert_eq(start[0], 0.0)
	assert_eq(start[1], 0.0)
	# Unit at 1.0 into the first 2.0 long segment: head at 1.0 - offset.
	var mid := GroundMarks.reveal_fractions(_reveal_path(), spt * 0.5)
	assert_true(absf(mid[0] - (1.0 - GroundMarks.TRACK_REAR_OFFSET) / 2.0) < 0.001)
	assert_eq(mid[1], 0.0)


func test_reveal_crosses_into_the_next_segment_and_completes() -> void:
	var spt := MoveAnimation.SECONDS_PER_TILE
	var second := GroundMarks.reveal_fractions(_reveal_path(), spt * 1.5)
	assert_eq(second[0], 1.0)
	assert_true(absf(second[1] - (1.0 - GroundMarks.TRACK_REAR_OFFSET) / 2.0) < 0.001)
	var end := GroundMarks.reveal_fractions(_reveal_path(), spt * 2.0)
	assert_eq(end[0], 1.0)
	assert_eq(end[1], 1.0, "the whole path is revealed when the unit has arrived")


func test_reveal_is_monotonic_and_matches_the_unit_profile() -> void:
	var duration := MoveAnimation.duration(_reveal_path())
	var previous := 0.0
	for step in 21:
		var pt := MoveAnimation.path_time(duration * step / 20.0, duration)
		var f := GroundMarks.reveal_fractions(_reveal_path(), pt)
		var covered := f[0] * 2.0 + f[1] * 2.0
		assert_true(covered >= previous - 0.0001, "never shrinks")
		previous = covered


func test_reveal_zero_length_segments_count_as_revealed() -> void:
	var points := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3(1, 0, 0)])
	assert_eq(GroundMarks.reveal_fractions(points, 0.0)[0], 1.0)
	assert_eq(GroundMarks.reveal_fractions(PackedVector3Array(), 0.0).size(), 0)


func test_pool_evicts_the_oldest_track_first() -> void:
	var pool := GroundMarks.Pool.new(4)
	assert_eq(pool.add(&"track", "t1").size(), 0)
	pool.add(&"track", "t2")
	pool.add(&"crater", "c1")
	pool.add(&"track", "t3")
	var evicted := pool.add(&"crater", "c2")
	assert_eq(evicted, ["t1"])
	assert_eq(pool.size(), 4)


func test_pool_evicts_craters_then_scorch() -> void:
	var pool := GroundMarks.Pool.new(3)
	pool.add(&"scorch", "s1")
	pool.add(&"crater", "c1")
	pool.add(&"scorch", "s2")
	assert_eq(pool.add(&"tyre", "y1"), ["c1"], "no track yet: the crater goes before scorch")
	assert_eq(pool.add(&"scorch", "s3"), ["y1"], "a tyre mark counts as a track")
	assert_eq(pool.add(&"scorch", "s4"), ["s1"], "only scorch left: the oldest goes")


func test_pool_with_zero_capacity_rejects_everything() -> void:
	var pool := GroundMarks.Pool.new(0)
	assert_eq(pool.add(&"track", "t"), ["t"])
	assert_eq(pool.size(), 0)
