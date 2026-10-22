extends TestCase

var _rig: CameraRig


func before_each() -> void:
	_rig = CameraRig.new()


func after_each() -> void:
	_rig.free()


func _wheel(button: MouseButton, ctrl: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.ctrl_pressed = ctrl
	_rig._unhandled_input(event)


func test_ctrl_wheel_tilts_without_zooming() -> void:
	var distance := _rig.distance()
	_wheel(MOUSE_BUTTON_WHEEL_UP, true)
	assert_true(_rig.pitch_offset() < 0.0, "wheel up tilts to the horizon")
	assert_eq(_rig.distance(), distance)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN, true)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN, true)
	assert_true(_rig.pitch_offset() > 0.0, "wheel down tilts to top-down")
	assert_eq(_rig.distance(), distance)


func test_plain_wheel_zooms_without_tilting() -> void:
	var distance := _rig.distance()
	_wheel(MOUSE_BUTTON_WHEEL_UP, false)
	assert_true(_rig.distance() < distance, "wheel up zooms in")
	assert_eq(_rig.pitch_offset(), 0.0)


func test_tilt_is_clamped() -> void:
	for i in 50:
		_wheel(MOUSE_BUTTON_WHEEL_UP, true)
	assert_eq(_rig.pitch_offset(), -CameraMath.PITCH_OFFSET_LIMIT)


func test_home_resets_the_offset_smoothly() -> void:
	for i in 4:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN, true)
	var start := _rig.pitch_offset()
	var key := InputEventKey.new()
	key.keycode = KEY_HOME
	key.pressed = true
	_rig._unhandled_input(key)
	_rig._process(0.02)
	assert_true(_rig.pitch_offset() > 0.0 and _rig.pitch_offset() < start, "easing, not a jump")
	for i in 20:
		_rig._process(0.02)
	assert_eq(_rig.pitch_offset(), 0.0)


func _elevation() -> float:
	var offset := _rig._clear_offset(Vector3.UP * CameraRig.TARGET_HEIGHT)
	return asin(offset.y / offset.length())


func test_negative_offset_lowers_the_camera_with_a_ground_query() -> void:
	_rig.set_ground_query(func(_x: float, _z: float) -> float: return 0.0)
	_rig.set_view(Vector2.ZERO, 0.0, 12.0)
	var base := _elevation()
	_rig.set_pitch_offset(-0.3)
	assert_true(_elevation() < base - 0.2, "lower than %s: %s" % [base, _elevation()])
	_rig.set_pitch_offset(0.3)
	assert_true(_elevation() > base + 0.2, "higher")


func test_home_is_cancelled_by_other_tilt_input() -> void:
	for i in 4:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN, true)
	_home(false)
	_rig._process(0.02)
	var mid := _rig.pitch_offset()
	_wheel(MOUSE_BUTTON_WHEEL_UP, true)
	var after_wheel := _rig.pitch_offset()
	_rig._process(0.1)
	assert_eq(_rig.pitch_offset(), after_wheel, "no further easing")
	assert_true(after_wheel < mid)


func test_home_echo_is_ignored() -> void:
	_wheel(MOUSE_BUTTON_WHEEL_DOWN, true)
	var before := _rig.pitch_offset()
	_home(true)
	_rig._process(0.05)
	assert_eq(_rig.pitch_offset(), before)


func test_middle_drag_stops_when_the_release_was_lost() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	_rig._unhandled_input(press)
	# The real Input state says the middle button is not held, so the motion must not tilt.
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(0, 20)
	_rig._unhandled_input(motion)
	assert_eq(_rig.pitch_offset(), 0.0)


func _home(echo: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_HOME
	key.pressed = true
	key.echo = echo
	_rig._unhandled_input(key)
