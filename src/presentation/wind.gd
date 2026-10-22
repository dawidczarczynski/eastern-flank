class_name Wind
extends RefCounted
## Global wind shader parameters (TASK-057), shared by grass and later trees / undergrowth
## (assets/shaders/wind.gdshaderinc). Registered at runtime, not in project.godot.

const DIRECTION := Vector2(0.8, 0.6)
const STRENGTH := 0.6
const SPEED := 1.2
## Largest sway offset of a vertex (world units): wind.gdshaderinc scales by this 0.012.
const MAX_OFFSET := 0.012

static var _strength := 0.0
static var _added: Dictionary = {}


## Registers the three global parameters (once) and sets them; strength 0 when `enabled` is false.
static func setup(enabled: bool) -> void:
	_strength = STRENGTH if enabled else 0.0
	_add(&"wind_direction", RenderingServer.GLOBAL_VAR_TYPE_VEC2, DIRECTION.normalized())
	_add(&"wind_strength", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, STRENGTH if enabled else 0.0)
	_add(&"wind_speed", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, SPEED)


## The strength last set (the RenderingServer keeps no globals under the headless dummy renderer).
static func strength() -> float:
	return _strength


static func _add(param: StringName, type_id: int, value: Variant) -> void:
	# global_shader_parameter_get_list() is editor-only, so remember what was added.
	if _added.has(param):
		RenderingServer.global_shader_parameter_set(param, value)
	else:
		RenderingServer.global_shader_parameter_add(param, type_id, value)
		_added[param] = true
