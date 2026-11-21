class_name WaterPlane
extends RefCounted
## The translucent water plane of a MapView (TASK-056; moved out of MapView by TASK-135): one
## plane at TerrainSurface.WATER_SURFACE over the terrain mesh plus MARGIN, the water shader with
## the look's water colours and a procedural ripple normal map.

## The water plane is this much larger than the terrain mesh.
const MARGIN := 80.0
## Water shader (TASK-056): colours, depths, ripple speeds and normal scale are its defaults.
const SHADER := preload("res://assets/shaders/water.gdshader")
## Water normal texture parameters.
const NORMAL_PERIODS: Array[int] = [4, 8, 16, 32]
const NORMAL_SEED := 303
const NORMAL_STRENGTH := 5.0

static var _normal: ImageTexture


## The ripple normal map (`size` texels), made once.
static func normal_texture(size: int) -> ImageTexture:
	if _normal == null:
		var heights := DetailTexture.height_map(size, NORMAL_PERIODS, NORMAL_SEED)
		_normal = ImageTexture.create_from_image(
			DetailTexture.normal_image(heights, size, NORMAL_STRENGTH)
		)
	return _normal


## The water plane over `rect` (the terrain mesh); `normal_size` is the normal map's size.
static func build(rect: Rect2, normal_size: int) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = rect.size + Vector2.ONE * MARGIN
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"normal_map", normal_texture(normal_size))
	var look_water := LookPreset.water_params()
	for key: String in look_water:
		material.set_shader_parameter(StringName(key), look_water[key])
	plane.material = material
	var instance := MeshInstance3D.new()
	instance.name = "Water"
	instance.mesh = plane
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var center := rect.get_center()
	instance.position = Vector3(center.x, TerrainSurface.WATER_SURFACE, center.y)
	return instance
