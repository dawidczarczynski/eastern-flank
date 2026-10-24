class_name FlashFx
extends MeshInstance3D
## A short, bright flash (TASK-074): an additive, unshaded ball that expands and fades over `life`
## seconds. Mesh only – no light, no particles – and a pure function of its age (pose(age)), so a
## time-driven effect can scrub it. Shared by rocket launches and impacts (RocketVolley), and meant
## for direct-fire muzzle flashes (TASK-048) and the richer salvo effects (TASK-075).
## The caller places it (position in its parent's space).

## Size at age 0 as a fraction of the full size.
const START_SCALE := 0.4

static var _ball: SphereMesh

var life := 0.1
var size := 0.3
var _color := Color.WHITE
var _material: StandardMaterial3D


## Colour (its alpha is ignored), full diameter in world units, lifetime in seconds. Returns self.
func setup(color: Color, flash_size: float, flash_life: float) -> FlashFx:
	_color = Color(color, 1.0)
	size = flash_size
	life = maxf(flash_life, 0.001)
	mesh = _shared_ball()
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = _color
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
	return self


## Shows the flash `age` seconds after it started (hidden before 0 and from `life` on).
func pose(age: float) -> void:
	var v := age / life
	visible = v >= 0.0 and v < 1.0
	if not visible:
		return
	scale = Vector3.ONE * size * lerpf(START_SCALE, 1.0, v)
	var fade := 1.0 - v
	_material.albedo_color = Color(_color.r * fade, _color.g * fade, _color.b * fade, fade)


static func _shared_ball() -> SphereMesh:
	if _ball == null:
		_ball = SphereMesh.new()
		_ball.radius = 0.5
		_ball.height = 1.0
		_ball.radial_segments = 10
		_ball.rings = 5
	return _ball
