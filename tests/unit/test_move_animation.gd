extends TestCase

const TOLERANCE := 0.001


func _near(actual: float, expected: float) -> void:
	assert_true(absf(actual - expected) < TOLERANCE, "got %f, expected %f" % [actual, expected])


func _near_v(actual: Vector3, expected: Vector3) -> void:
	assert_true(
		actual.distance_to(expected) < TOLERANCE, "got %s, expected %s" % [actual, expected]
	)


func _poly() -> PackedVector3Array:
	return PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 2)])


func test_facing_yaw_cardinal_directions() -> void:
	_near(MoveAnimation.facing_yaw(Vector3.ZERO, Vector3(1, 0, 0)), 0.0)
	_near(MoveAnimation.facing_yaw(Vector3.ZERO, Vector3(0, 0, -1)), PI / 2.0)
	_near(MoveAnimation.facing_yaw(Vector3.ZERO, Vector3(0, 0, 1)), -PI / 2.0)
	_near(absf(MoveAnimation.facing_yaw(Vector3.ZERO, Vector3(-1, 0, 0))), PI)


func test_facing_yaw_uses_difference() -> void:
	_near(MoveAnimation.facing_yaw(Vector3(5, 3, 5), Vector3(6, 0, 5)), 0.0)


func test_turn_towards_takes_shortest_arc() -> void:
	_near(MoveAnimation.turn_towards(3.0, -3.0, 1.0), 3.0 + (TAU - 6.0))


func test_turn_towards_partial_step() -> void:
	_near(MoveAnimation.turn_towards(0.0, 1.0, 0.05), 0.7)


func test_turn_towards_full_step_reaches_target() -> void:
	_near(MoveAnimation.turn_towards(0.0, 1.0, 1.0), 1.0)


func test_sample_first_segment_midpoint() -> void:
	_near_v(MoveAnimation.sample(_poly(), 0.13), Vector3(0.5, 0, 0))


func test_sample_second_segment_midpoint() -> void:
	_near_v(MoveAnimation.sample(_poly(), 0.39), Vector3(1, 0, 1))


func test_sample_clamps_to_last_point() -> void:
	_near_v(MoveAnimation.sample(_poly(), 10.0), Vector3(1, 0, 2))


func test_sample_before_start_is_first_point() -> void:
	_near_v(MoveAnimation.sample(_poly(), -1.0), Vector3.ZERO)


func test_sample_single_point() -> void:
	var points := PackedVector3Array([Vector3(2, 1, 3)])
	_near_v(MoveAnimation.sample(points, 0.5), Vector3(2, 1, 3))


func test_sample_empty_is_zero() -> void:
	_near_v(MoveAnimation.sample(PackedVector3Array(), 0.5), Vector3.ZERO)


func test_segment_target_is_end_of_current_segment() -> void:
	_near_v(MoveAnimation.segment_target(_poly(), 0.13), Vector3(1, 0, 0))
	_near_v(MoveAnimation.segment_target(_poly(), 0.39), Vector3(1, 0, 2))
	_near_v(MoveAnimation.segment_target(_poly(), 10.0), Vector3(1, 0, 2))


func test_segment_target_single_point() -> void:
	var points := PackedVector3Array([Vector3(2, 1, 3)])
	_near_v(MoveAnimation.segment_target(points, 0.0), Vector3(2, 1, 3))


func test_segment_index() -> void:
	assert_eq(MoveAnimation.segment_index(_poly(), 0.0), 0)
	assert_eq(MoveAnimation.segment_index(_poly(), 0.13), 0)
	assert_eq(MoveAnimation.segment_index(_poly(), 0.39), 1)
	assert_eq(MoveAnimation.segment_index(_poly(), 10.0), 1)


func test_duration_is_seconds_per_segment() -> void:
	_near(MoveAnimation.duration(_poly()), 0.52)
	_near(MoveAnimation.duration(PackedVector3Array([Vector3.ZERO])), 0.0)
