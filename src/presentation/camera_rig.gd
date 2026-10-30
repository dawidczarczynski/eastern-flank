class_name CameraRig
extends Node3D
## Strategy camera. WASD/arrows – pan, Q/E – rotate, wheel – zoom, LMB drag – grab pan,
## RMB drag – rotate. Tilt (a pitch offset on top of the distance curve, kept for the match):
## Ctrl+wheel (up = towards the horizon), R/F held (R = towards the horizon), vertical MMB drag
## (down = towards top-down), Home – smooth reset. All formulas live in CameraMath.
## TODO: move the keys to the Input Map (project.godot) once there's a settings screen.

## A LMB/RMB release that never became a drag (the owner decides what a click means).
signal clicked(screen_position: Vector2, button: MouseButton)

const TARGET_HEIGHT := 0.4
const DEFAULT_DISTANCE := 24.0
const CLAMP_MARGIN := 2.0
const KEY_PAN_SPEED := 0.9  # units/s per unit of distance
const KEY_ROTATE_SPEED := 1.2  # rad/s
const MOUSE_ROTATE_SPEED := 0.005  # rad/px
## Impact shake (TASK-075): a decaying offset of the camera node only. Largest offset (world
## units) at SHAKE_NEAR or closer, fading linearly to 0 at SHAKE_FAR; SHAKE_ENABLED switches it off.
const SHAKE_ENABLED := true
const SHAKE_MAX := 0.03
const SHAKE_NEAR := 6.0
const SHAKE_FAR := 25.0
const SHAKE_DECAY := 0.25  # seconds from SHAKE_MAX to 0

var _target := Vector2.ZERO  # XZ look-at point (the rig's position, y = 0)
var _yaw := 0.0
var _distance := DEFAULT_DISTANCE
var _bounds := Rect2()
var _has_bounds := false
var _press_button := MOUSE_BUTTON_NONE
var _press_position := Vector2.ZERO
var _dragging := false
var _pitch_offset := 0.0  # player tilt, radians (CameraMath.clamp_pitch_offset range)
var _resetting_tilt := false  # Home pressed: the offset is easing back to 0
var _tilt_dragging := false  # middle mouse held
## Callable(x: float, z: float) -> float: the drawn ground height; null = flat ground at 0.
var _ground_height := Callable()
var _shake := 0.0  # current shake amplitude (world units)
var _shake_clock := 0.0

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_apply()


## A release lost to focus change must not leave the rig stuck in a press.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_press_button = MOUSE_BUTTON_NONE
		_dragging = false
		_tilt_dragging = false


## The XZ point the camera looks at.
func target() -> Vector2:
	return _target


func distance() -> float:
	return _distance


## Player tilt offset in radians (0 = the automatic pitch curve).
func pitch_offset() -> float:
	return _pitch_offset


## Screenshot tool: sets the tilt offset directly (clamped).
func set_pitch_offset(offset: float) -> void:
	_pitch_offset = CameraMath.clamp_pitch_offset(offset)
	_resetting_tilt = false
	_apply()


## True while a pressed mouse button is being dragged (pan / rotate), not for plain clicks.
func is_dragging() -> bool:
	return _dragging


## Limits the target to the map rectangle (see CameraMath.map_bounds).
func set_bounds(rect: Rect2) -> void:
	_bounds = rect
	_has_bounds = true
	_apply()


## The camera keeps CameraMath.GROUND_CLEARANCE above the ground this query returns.
func set_ground_query(query: Callable) -> void:
	_ground_height = query
	_apply()


func set_target(target: Vector2) -> void:
	_target = target
	_apply()


## Places the camera in one go (screenshot tool); the distance is clamped like a zoom.
func set_view(target: Vector2, yaw: float, distance: float) -> void:
	_target = target
	_yaw = yaw
	_distance = clampf(distance, CameraMath.MIN_DISTANCE, CameraMath.MAX_DISTANCE)
	_apply()


## Shake amplitude of an impact `distance` world units from the camera.
static func shake_strength(distance: float) -> float:
	return SHAKE_MAX * clampf((SHAKE_FAR - distance) / (SHAKE_FAR - SHAKE_NEAR), 0.0, 1.0)


## Adds `strength` (shake_strength) to the shake; the sum never exceeds SHAKE_MAX.
func add_shake(strength: float) -> void:
	if SHAKE_ENABLED:
		_shake = minf(SHAKE_MAX, _shake + maxf(strength, 0.0))


## Current shake amplitude (0 at rest).
func shake() -> float:
	return _shake


func _process(delta: float) -> void:
	var changed := false
	if _shake > 0.0:
		_shake_clock += delta
		_shake = maxf(0.0, _shake - SHAKE_MAX / SHAKE_DECAY * delta)
		if _shake == 0.0:
			_shake_clock = 0.0
		changed = true
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if input != Vector2.ZERO:
		_target += CameraMath.key_pan(input, _yaw) * KEY_PAN_SPEED * _distance * delta
		changed = true

	var rotation_input := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		rotation_input += 1.0
	if Input.is_physical_key_pressed(KEY_E):
		rotation_input -= 1.0
	if rotation_input != 0.0:
		_yaw += rotation_input * KEY_ROTATE_SPEED * delta
		changed = true

	var tilt_input := 0.0  # + = towards the horizon
	if not (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT)):
		if Input.is_physical_key_pressed(KEY_R):
			tilt_input += 1.0
		if Input.is_physical_key_pressed(KEY_F):
			tilt_input -= 1.0
	if tilt_input != 0.0:
		_resetting_tilt = false
		_pitch_offset = CameraMath.tilt_toward_horizon(
			_pitch_offset, tilt_input * CameraMath.TILT_KEY_SPEED * delta
		)
		changed = true
	elif _resetting_tilt:
		_pitch_offset = CameraMath.reset_offset(_pitch_offset, delta)
		_resetting_tilt = _pitch_offset != 0.0
		changed = true
	if changed:
		_apply()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null:
		if key.pressed and not key.echo and key.keycode == KEY_HOME:
			_resetting_tilt = true
		return
	var button := event as InputEventMouseButton
	if button != null:
		_on_mouse_button(button)
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if _tilt_dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_tilt_dragging = false  # the release was eaten elsewhere (e.g. a HUD control)
	if _tilt_dragging:
		_resetting_tilt = false
		_pitch_offset = CameraMath.tilt_toward_horizon(
			_pitch_offset, -motion.relative.y * CameraMath.TILT_MOUSE_SPEED
		)
		_apply()
	elif _press_button != MOUSE_BUTTON_NONE:
		_on_mouse_motion(motion)


func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				var notches := event.factor if event.factor > 0.0 else 1.0
				if event.ctrl_pressed:  # Ctrl+wheel tilts instead of zooming; up = to the horizon
					if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
						notches = -notches
					_resetting_tilt = false
					_pitch_offset = CameraMath.tilt_step(_pitch_offset, notches)
				else:
					if event.button_index == MOUSE_BUTTON_WHEEL_UP:
						notches = -notches
					_distance = CameraMath.zoom(_distance, notches)
				_apply()
		MOUSE_BUTTON_MIDDLE:
			_tilt_dragging = event.pressed
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
			if event.pressed:
				# A held button whose release never arrived (e.g. eaten by a HUD control) is dropped.
				if (
					_press_button == MOUSE_BUTTON_NONE
					or not Input.is_mouse_button_pressed(_press_button)
				):
					_press_button = event.button_index
					_press_position = event.position
					_dragging = false
			elif event.button_index == _press_button:
				var was_drag := _dragging
				_press_button = MOUSE_BUTTON_NONE
				_dragging = false
				if not was_drag:
					clicked.emit(event.position, event.button_index)


func _on_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _dragging and CameraMath.is_drag(_press_position, event.position):
		_dragging = true
	if not _dragging:
		return
	if _press_button == MOUSE_BUTTON_LEFT:
		_target += CameraMath.pan_delta(event.relative, _yaw, _distance)
	else:
		_yaw -= event.relative.x * MOUSE_ROTATE_SPEED
	_apply()


func _apply() -> void:
	if _has_bounds:
		_target = CameraMath.clamp_target(_target, _bounds, CLAMP_MARGIN)
	position = Vector3(_target.x, 0.0, _target.y)
	if _camera == null:
		return
	var look_at_point := Vector3.UP * TARGET_HEIGHT
	_camera.position = look_at_point + _clear_offset(look_at_point)
	_camera.look_at(global_position + look_at_point, Vector3.UP)
	if _shake > 0.0:  # translation only: the rig target, the pitch and the aim stay untouched
		var t := _shake_clock
		_camera.position += (Vector3(sin(t * 91.0), sin(t * 77.0 + 1.3), cos(t * 63.0)) * _shake)


## Camera offset with the pitch raised where needed so the camera stays above the ground under it.
func _clear_offset(look_at_point: Vector3) -> Vector3:
	if not _ground_height.is_valid():
		return CameraMath.camera_offset(_yaw, _distance, 0.0, _pitch_offset)
	var pitch := CameraMath.clear_pitch(
		_ground_height, _target, _yaw, _distance, look_at_point.y, _pitch_offset
	)
	return CameraMath.camera_offset_at_pitch(_yaw, _distance, pitch)
