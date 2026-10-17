extends TestCase

const EPS := 0.001


func _near(actual: float, expected: float) -> void:
	assert_true(absf(actual - expected) < EPS, "expected %s, got %s" % [expected, actual])


func _near_v2(actual: Vector2, expected: Vector2) -> void:
	assert_true(actual.distance_to(expected) < EPS, "expected %s, got %s" % [expected, actual])


func test_pitch_for_distance() -> void:
	_near(CameraMath.pitch_for_distance(8.0), 0.82)
	_near(CameraMath.pitch_for_distance(45.0), 1.12)
	_near(CameraMath.pitch_for_distance(24.0), 0.94973)


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
