class_name CameraRig
extends Node3D
## Strategy camera. WASD/arrows – pan, Q/E – rotate, mouse wheel – zoom.
## TODO: move the keys to the Input Map (project.godot) once there's a settings screen.

@export var pan_speed := 10.0
@export var rotate_speed := 1.5
@export var zoom_step := 1.5
@export var min_distance := 6.0
@export var max_distance := 30.0

var _distance := 14.0

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_update_camera()


func _process(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if input != Vector2.ZERO:
		var direction := transform.basis * Vector3(input.x, 0.0, input.y)
		direction.y = 0.0
		position += direction.normalized() * pan_speed * delta * (_distance / 14.0)

	var rotation_input := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		rotation_input += 1.0
	if Input.is_physical_key_pressed(KEY_E):
		rotation_input -= 1.0
	rotation.y += rotation_input * rotate_speed * delta


func _unhandled_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed:
		return
	if mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
		_distance = clampf(_distance - zoom_step, min_distance, max_distance)
		_update_camera()
	elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_distance = clampf(_distance + zoom_step, min_distance, max_distance)
		_update_camera()


func _update_camera() -> void:
	_camera.position = Vector3(0.0, _distance * 0.8, _distance * 0.6)
	_camera.look_at(global_position, Vector3.UP)
