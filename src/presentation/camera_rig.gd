class_name CameraRig
extends Node3D
## Strategy camera. WASD/arrows – pan, Q/E – rotate, wheel – zoom, LMB drag – grab pan,
## RMB drag – rotate. All formulas live in CameraMath.
## TODO: move the keys to the Input Map (project.godot) once there's a settings screen.

## A LMB/RMB release that never became a drag (the owner decides what a click means).
signal clicked(screen_position: Vector2, button: MouseButton)

const TARGET_HEIGHT := 0.4
const DEFAULT_DISTANCE := 24.0
const CLAMP_MARGIN := 2.0
const KEY_PAN_SPEED := 0.9  # units/s per unit of distance
const KEY_ROTATE_SPEED := 1.2  # rad/s
const MOUSE_ROTATE_SPEED := 0.005  # rad/px

var _target := Vector2.ZERO  # XZ look-at point (the rig's position, y = 0)
var _yaw := 0.0
var _distance := DEFAULT_DISTANCE
var _bounds := Rect2()
var _has_bounds := false
var _press_button := MOUSE_BUTTON_NONE
var _press_position := Vector2.ZERO
var _dragging := false

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_apply()


## A release lost to focus change must not leave the rig stuck in a press.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_press_button = MOUSE_BUTTON_NONE
		_dragging = false


## True while a pressed mouse button is being dragged (pan / rotate), not for plain clicks.
func is_dragging() -> bool:
	return _dragging


## Limits the target to the map rectangle (see CameraMath.map_bounds).
func set_bounds(rect: Rect2) -> void:
	_bounds = rect
	_has_bounds = true
	_apply()


func set_target(target: Vector2) -> void:
	_target = target
	_apply()


func _process(delta: float) -> void:
	var changed := false
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
	if changed:
		_apply()


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		_on_mouse_button(button)
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _press_button != MOUSE_BUTTON_NONE:
		_on_mouse_motion(motion)


func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				var notches := event.factor if event.factor > 0.0 else 1.0
				if event.button_index == MOUSE_BUTTON_WHEEL_UP:
					notches = -notches
				_distance = CameraMath.zoom(_distance, notches)
				_apply()
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
	_camera.position = look_at_point + CameraMath.camera_offset(_yaw, _distance)
	_camera.look_at(global_position + look_at_point, Vector3.UP)
