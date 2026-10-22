extends TestCase

const EPS := 0.001


func _near(actual: float, expected: float) -> void:
	assert_true(absf(actual - expected) < EPS, "expected %s, got %s" % [expected, actual])


func _near_v2(actual: Vector2, expected: Vector2) -> void:
	assert_true(actual.distance_to(expected) < EPS, "expected %s, got %s" % [expected, actual])


func test_pitch_for_distance_control_points() -> void:
	_near(CameraMath.pitch_for_distance(7.0), 0.30)
	_near(CameraMath.pitch_for_distance(24.0), 0.56)
	_near(CameraMath.pitch_for_distance(46.0), 1.05)
	_near(CameraMath.pitch_for_distance(15.5), 0.43)


func test_pitch_for_distance_is_clamped_outside_the_zoom_range() -> void:
	_near(CameraMath.pitch_for_distance(2.0), 0.30)
	_near(CameraMath.pitch_for_distance(100.0), 1.05)


func test_pitch_for_distance_is_monotonic() -> void:
	var previous := CameraMath.pitch_for_distance(7.0)
	var d := 7.25
	while d <= 46.0:
		var p := CameraMath.pitch_for_distance(d)
		assert_true(p > previous, "pitch must grow with distance (d %s)" % d)
		previous = p
		d += 0.25


func test_horizon_is_in_frame_when_zoomed_in() -> void:
	# The horizon sits at the camera pitch below the view centre; it is visible when the pitch
	# is less than half the vertical FOV (40 degrees in the battle scene).
	assert_true(CameraMath.pitch_for_distance(7.0) < deg_to_rad(40.0) / 2.0)


func test_min_pitch_for_ground() -> void:
	# Camera height = target height + sin(pitch) * d must reach ground + clearance.
	var p := CameraMath.min_pitch_for_ground(2.0, 0.4, 10.0)
	_near(0.4 + sin(p) * 10.0, 2.0 + CameraMath.GROUND_CLEARANCE)
	# Low ground needs (almost) no extra pitch; never negative.
	assert_true(CameraMath.min_pitch_for_ground(-20.0, 0.4, 10.0) >= 0.0)
	# Impossible clearance: straight down at most.
	_near(CameraMath.min_pitch_for_ground(50.0, 0.4, 7.0), PI / 2.0)


func test_camera_stays_above_ground_at_every_distance() -> void:
	var ground := 2.0
	var d := CameraMath.MIN_DISTANCE
	while d <= CameraMath.MAX_DISTANCE:
		var offset := CameraMath.camera_offset(
			0.3, d, CameraMath.min_pitch_for_ground(ground, 0.4, d)
		)
		assert_true(0.4 + offset.y >= 3.5 - EPS, "camera height at d %s: %s" % [d, 0.4 + offset.y])
		_near(offset.length(), d)
		d += 0.5


func test_camera_offset_default_yaw() -> void:
	var p := CameraMath.pitch_for_distance(24.0)
	var offset := CameraMath.camera_offset(0.0, 24.0)
	_near(offset.x, 0.0)
	_near(offset.y, sin(p) * 24.0)
	_near(offset.z, cos(p) * 24.0)


func test_camera_offset_length_equals_distance() -> void:
	for yaw: float in [0.0, 1.0, PI]:
		for d: float in [7.0, 24.0, 46.0]:
			_near(CameraMath.camera_offset(yaw, d).length(), d)


func test_camera_offset_quarter_turn() -> void:
	var offset := CameraMath.camera_offset(PI / 2.0, 24.0)
	_near(offset.z, 0.0)
	assert_true(offset.x > 0.0)


func test_zoom() -> void:
	_near(CameraMath.zoom(24.0, 1.0), 26.88)
	_near(CameraMath.zoom(24.0, -1.0), 21.12)
	_near(CameraMath.zoom(45.0, 1.0), 46.0)
	_near(CameraMath.zoom(7.5, -1.0), 7.0)
	_near(CameraMath.zoom(24.0, 0.0), 24.0)


func test_pan_delta() -> void:
	_near_v2(CameraMath.pan_delta(Vector2(100, 0), 0.0, 24.0), Vector2(-3.84, 0))
	_near_v2(CameraMath.pan_delta(Vector2(0, 100), 0.0, 24.0), Vector2(0, -3.84))
	_near_v2(CameraMath.pan_delta(Vector2(100, 0), PI / 2.0, 24.0), Vector2(0, 3.84))


func test_key_pan_direction() -> void:
	_near_v2(CameraMath.key_pan(Vector2(0, 1), 0.0), Vector2(0, -1))  # W: away from the camera
	_near_v2(CameraMath.key_pan(Vector2(1, 0), 0.0), Vector2(1, 0))  # D: camera right
	_near_v2(CameraMath.key_pan(Vector2(1, 0), PI / 2.0), Vector2(0, -1))
	_near(CameraMath.key_pan(Vector2(1, 1), 0.7).length(), 1.0)
	_near_v2(CameraMath.key_pan(Vector2.ZERO, 0.0), Vector2.ZERO)


func test_is_drag() -> void:
	assert_false(CameraMath.is_drag(Vector2(0, 0), Vector2(4, 0)))
	assert_true(CameraMath.is_drag(Vector2(0, 0), Vector2(3, 3)))
	assert_false(CameraMath.is_drag(Vector2(10, 10), Vector2(10, 14)))


func test_map_bounds() -> void:
	var centers: Array[Vector3] = [Vector3(0, 0, 0), Vector3(10, 0, 6)]
	var rect := CameraMath.map_bounds(centers, 1.0)
	_near(rect.position.x, -0.866)
	_near(rect.position.y, -1.0)
	_near(rect.size.x, 11.732)
	_near(rect.size.y, 8.0)


func test_clamp_target() -> void:
	var bounds := Rect2(0, 0, 20, 14)
	_near_v2(CameraMath.clamp_target(Vector2(-5, 30), bounds, 2.0), Vector2(2, 12))
	_near_v2(CameraMath.clamp_target(Vector2(9, 9), bounds, 2.0), Vector2(9, 9))
	_near_v2(CameraMath.clamp_target(Vector2(9, 9), Rect2(0, 0, 3, 3), 2.0), Vector2(1.5, 1.5))


func test_clear_pitch_keeps_camera_above_steep_ground() -> void:
	# A steep ridge: ground rises 1.2 per unit towards +z, the camera sits on the +z side.
	var ridge := func(_x: float, z: float) -> float: return maxf(0.0, z * 1.2)
	for d: float in [7.0, 15.0, 24.0, 46.0]:
		var pitch := CameraMath.clear_pitch(ridge, Vector2.ZERO, 0.0, d, 0.4)
		var offset := CameraMath.camera_offset(0.0, d, pitch)
		var ground: float = ridge.call(offset.x, offset.z)
		assert_true(0.4 + offset.y >= ground + CameraMath.GROUND_CLEARANCE - 0.001, "d %s" % d)


func test_clear_pitch_is_the_curve_on_flat_ground() -> void:
	var flat := func(_x: float, _z: float) -> float: return 0.0
	_near(CameraMath.clear_pitch(flat, Vector2.ZERO, 0.0, 24.0, 0.4), 0.56)
