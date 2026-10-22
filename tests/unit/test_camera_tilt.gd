extends TestCase

const EPS := 0.001


func _near(actual: float, expected: float) -> void:
	assert_true(absf(actual - expected) < EPS, "expected %s, got %s" % [expected, actual])


func test_pitch_with_offset_zero_is_the_curve() -> void:
	for d in [7.0, 15.5, 24.0, 46.0]:
		_near(CameraMath.pitch_with_offset(d, 0.0), CameraMath.pitch_for_distance(d))


func test_pitch_with_offset_shifts_the_curve() -> void:
	_near(CameraMath.pitch_with_offset(24.0, 0.2), 0.76)
	_near(CameraMath.pitch_with_offset(24.0, -0.2), 0.36)


func test_pitch_offset_is_clamped() -> void:
	_near(CameraMath.pitch_with_offset(24.0, 5.0), 0.56 + 0.35)
	_near(CameraMath.pitch_with_offset(24.0, -5.0), 0.56 - 0.35)
	_near(CameraMath.clamp_pitch_offset(9.0), 0.35)
	_near(CameraMath.clamp_pitch_offset(-9.0), -0.35)


func test_pitch_result_is_clamped() -> void:
	_near(CameraMath.pitch_with_offset(7.0, -0.35), 0.14)
	# The offset limit keeps the far end below straight down: 1.05 + 0.35.
	_near(CameraMath.pitch_with_offset(46.0, 0.35), 1.4)
	assert_true(CameraMath.pitch_with_offset(46.0, 0.35) <= CameraMath.PITCH_MAX)


func test_tilt_step_direction_and_clamp() -> void:
	assert_true(CameraMath.tilt_step(0.0, 1.0) < 0.0, "wheel up tilts to the horizon")
	assert_true(CameraMath.tilt_step(0.0, -1.0) > 0.0, "wheel down tilts to top-down")
	_near(CameraMath.tilt_step(0.0, 2.0), -2.0 * CameraMath.TILT_STEP)
	_near(CameraMath.tilt_step(-0.34, 5.0), -0.35)
	_near(CameraMath.tilt_step(0.34, -5.0), 0.35)


func test_reset_offset_moves_to_zero_without_overshoot() -> void:
	_near(CameraMath.reset_offset(0.2, 0.01), 0.2 - 0.35 / 0.3 * 0.01)
	_near(CameraMath.reset_offset(-0.2, 0.01), -0.2 + 0.35 / 0.3 * 0.01)
	_near(CameraMath.reset_offset(0.05, 1.0), 0.0)
	_near(CameraMath.reset_offset(0.0, 0.1), 0.0)


func test_reset_takes_about_the_reset_time_from_the_limit() -> void:
	var offset := -CameraMath.PITCH_OFFSET_LIMIT
	var t := 0.0
	while offset != 0.0:
		offset = CameraMath.reset_offset(offset, 0.01)
		t += 0.01
	assert_true(absf(t - CameraMath.TILT_RESET_SECONDS) < 0.03, "took %s s" % t)


func test_camera_offset_uses_the_pitch_offset() -> void:
	var offset := CameraMath.camera_offset(0.0, 7.0, 0.0, -0.35)
	_near(offset.y, 7.0 * sin(0.14))


func test_clear_pitch_applies_on_top_of_the_offset() -> void:
	var flat := func(_x: float, _z: float) -> float: return 0.0
	_near(CameraMath.clear_pitch(flat, Vector2.ZERO, 0.0, 24.0, 0.4, 0.2), 0.76)
	# Camera at d 7 with the lowest tilt would be at 0.4 + 7 * sin(0.14) < 1.5 over a 0.8 hill.
	var hill := func(_x: float, _z: float) -> float: return 0.8
	var pitch := CameraMath.clear_pitch(hill, Vector2.ZERO, 0.0, 7.0, 0.4, -0.35)
	assert_true(
		0.4 + 7.0 * sin(pitch) >= 0.8 + CameraMath.GROUND_CLEARANCE - 0.001, "pitch %s" % pitch
	)
