class_name CloudShadows
extends RefCounted
## Global shader parameters of the moving cloud shadows (TASK-201b): a tileable noise texture and
## the strength / scale / speed / drift of assets/shaders/cloud_shadow.gdshaderinc. Registered at
## runtime, not in project.godot. The strength is a look value (LookPreset.clouds(): 0 outside the
## `true` VisualScale preset) and 0 on LOW (`enabled` false).

const NOISE_SIZE := 128
## Value-noise lattice cells per octave: broad patches with some ragged edge.
const NOISE_PERIODS: Array[int] = [3, 6, 12]
const NOISE_SEED := 2011

static var _strength := 0.0
static var _added: Dictionary = {}
static var _texture: ImageTexture


## The tileable cloud noise as an 8-bit grey image (row-major wrap-around lattice noise).
static func noise_image() -> Image:
	var heights := DetailTexture.height_map(NOISE_SIZE, NOISE_PERIODS, NOISE_SEED)
	var bytes := PackedByteArray()
	bytes.resize(heights.size())
	for i in heights.size():
		bytes[i] = int(clampf(heights[i], 0.0, 1.0) * 255.0 + 0.5)
	return Image.create_from_data(NOISE_SIZE, NOISE_SIZE, false, Image.FORMAT_R8, bytes)


## Registers the global parameters (once) and sets them from the active look; strength 0 when
## `enabled` is false.
static func setup(enabled: bool) -> void:
	var values := LookPreset.clouds()
	_strength = float(values["strength"]) if enabled else 0.0
	if _texture == null:
		_texture = ImageTexture.create_from_image(noise_image())
	var drift := Wind.DIRECTION.normalized()
	# A cloud ~2 km up casts its shadow this far away from the sun's side of the sky.
	var sun := LookPreset.sun()
	var elevation := deg_to_rad(float(sun["elevation_deg"]))
	var azimuth := deg_to_rad(float(sun["azimuth_deg"]))
	var away := Vector2(-sin(azimuth), cos(azimuth)) * (1.0 / maxf(tan(elevation), 0.2))
	_add(&"cloud_noise", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, _texture)
	_add(&"cloud_shadow_strength", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, _strength)
	_add(
		&"cloud_scale", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, MapScale.to_units(values["scale_m"])
	)
	_add(
		&"cloud_speed", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, MapScale.to_units(values["speed_m"])
	)
	_add(&"cloud_drift", RenderingServer.GLOBAL_VAR_TYPE_VEC2, drift)
	_add(
		&"cloud_sun_offset",
		RenderingServer.GLOBAL_VAR_TYPE_VEC2,
		away * MapScale.to_units(values["height_m"])
	)


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
