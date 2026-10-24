extends TestCase

const EPS := 0.0001


func _near(actual: float, expected: float) -> void:
	assert_true(absf(actual - expected) < EPS, "expected %s, got %s" % [expected, actual])


func test_wrap_yaw_stays_in_one_turn() -> void:
	_near(OrbitMath.wrap_yaw(0.5), 0.5)
	_near(OrbitMath.wrap_yaw(PI + 0.5), -PI + 0.5)
	_near(OrbitMath.wrap_yaw(-PI - 0.5), PI - 0.5)
	_near(OrbitMath.wrap_yaw(5.0 * TAU + 0.25), 0.25)


func test_pitch_is_clamped() -> void:
	_near(OrbitMath.clamp_pitch(-1.0), OrbitMath.PITCH_MIN)
	_near(OrbitMath.clamp_pitch(3.0), OrbitMath.PITCH_MAX)
	_near(OrbitMath.clamp_pitch(0.7), 0.7)


func test_drag_right_turns_yaw_and_drag_down_raises_the_camera() -> void:
	var state := OrbitMath.dragged(0.0, 0.3, Vector2(100.0, 0.0))
	assert_true(state["yaw"] < 0.0)
	_near(state["pitch"], 0.3)
	state = OrbitMath.dragged(0.0, 0.3, Vector2(0.0, 50.0))
	assert_true(state["pitch"] > 0.3)


func test_drag_wraps_yaw_and_clamps_pitch() -> void:
	var state := OrbitMath.dragged(-3.0, 0.3, Vector2(100.0, 5000.0))
	assert_true(state["yaw"] >= -PI and state["yaw"] < PI)
	_near(state["pitch"], OrbitMath.PITCH_MAX)
	state = OrbitMath.dragged(0.0, 0.3, Vector2(0.0, -5000.0))
	_near(state["pitch"], OrbitMath.PITCH_MIN)


func test_distance_limits_scale_with_the_model() -> void:
	var small := 0.3
	var big := 1.5
	assert_true(OrbitMath.min_distance(small) < OrbitMath.min_distance(big))
	assert_true(OrbitMath.max_distance(small) < OrbitMath.max_distance(big))
	for r in [small, big]:
		var fit := OrbitMath.fit_distance(r)
		assert_true(fit > OrbitMath.min_distance(r) and fit < OrbitMath.max_distance(r))
		# The fitting distance really shows the whole bounding sphere.
		assert_true(fit * sin(deg_to_rad(OrbitMath.FOV_DEGREES) * 0.5) > r)


func test_zoom_is_clamped_both_ways() -> void:
	var r := 0.8
	assert_true(OrbitMath.zoomed(2.0, 1.0, r) < 2.0)
	assert_true(OrbitMath.zoomed(2.0, -1.0, r) > 2.0)
	_near(OrbitMath.zoomed(2.0, 500.0, r), OrbitMath.min_distance(r))
	_near(OrbitMath.zoomed(2.0, -500.0, r), OrbitMath.max_distance(r))


func test_eye_is_at_the_distance_and_pitch() -> void:
	var target := Vector3(1.0, 2.0, 3.0)
	var eye := OrbitMath.eye(target, 0.7, 0.4, 5.0)
	_near(eye.distance_to(target), 5.0)
	_near((eye - target).y, 5.0 * sin(0.4))
	# yaw 0 puts the camera on +Z
	var front := OrbitMath.eye(Vector3.ZERO, 0.0, 0.0, 2.0)
	_near(front.z, 2.0)
	_near(front.x, 0.0)


func test_default_state_fits_the_radius() -> void:
	var state := OrbitMath.default_state(0.6)
	_near(state["distance"], OrbitMath.fit_distance(0.6))
	_near(state["yaw"], OrbitMath.DEFAULT_YAW)
	_near(state["pitch"], OrbitMath.DEFAULT_PITCH)


func test_radius_is_half_the_box_diagonal_with_a_floor() -> void:
	_near(OrbitMath.radius(AABB(Vector3.ZERO, Vector3(3.0, 4.0, 0.0))), 2.5)
	_near(OrbitMath.radius(AABB()), OrbitMath.MIN_RADIUS)


func test_visible_bounds_skips_hidden_parts() -> void:
	var root := Node3D.new()
	var shown := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	shown.mesh = box
	root.add_child(shown)
	var hidden := MeshInstance3D.new()
	hidden.mesh = box
	hidden.position = Vector3(10.0, 0.0, 0.0)
	hidden.visible = false
	root.add_child(hidden)
	var bounds := OrbitMath.visible_bounds(root)
	_near(bounds.size.x, 1.0)
	root.free()
