class_name MuzzleFlash
extends Node3D
## The flash of a direct-fire gun (TASK-048): one FlashFx ball and, on HIGH graphics, one
## OmniLight3D, reused for every shot of the battle (shots play one at a time). Placed by fire(),
## then a pure function of the shot's age (pose) so the shot's tween can drive it.

const FLASH_COLOR := Color("ffd28a")
const LIGHT_COLOR := Color("ffb060")
const LIGHT_ENERGY := 4.0
const LIGHT_RANGE := 2.0
## Flash diameter in world units at the nominal model scale (times VisualScale.unit_model_scale()).
const BASE_SIZE := 0.2
const FLASH_TIME := 0.12
## Where warm_up() shows the flash for one frame (far below the map).
const WARM_UP_POSITION := Vector3(0.0, -50.0, 0.0)

var flash_size := BASE_SIZE

var _ball: FlashFx
var _light: OmniLight3D


## A flash added to `parent` and warmed up; the light only when `quality["fx_lights"]`.
static func create(parent: Node, quality: Dictionary) -> MuzzleFlash:
	var flash := MuzzleFlash.new().setup(quality.get("fx_lights", false))
	flash.name = "MuzzleFlash"
	parent.add_child(flash)
	flash.warm_up()
	return flash


## Builds the ball (and the light when `with_light`), hidden. Returns self.
func setup(with_light: bool) -> MuzzleFlash:
	flash_size = BASE_SIZE * VisualScale.unit_model_scale()
	_ball = FlashFx.new().setup(FLASH_COLOR, flash_size, FLASH_TIME)
	add_child(_ball)
	if with_light:
		_light = OmniLight3D.new()
		_light.name = "Light"
		_light.light_color = LIGHT_COLOR
		_light.omni_range = LIGHT_RANGE
		_light.shadow_enabled = false
		add_child(_light)
	pose(-1.0)
	return self


## Shows the flash (and light) for one frame far below the map, so the material and the light
## variant compile at battle start, not at the first shot. Outside the tree (headless tests, a
## stage not shown yet) there is nothing to render, so it does nothing.
func warm_up() -> void:
	if not is_inside_tree():
		return
	position = WARM_UP_POSITION
	pose(0.0)
	if _light != null:
		_light.light_energy = 0.01
	get_tree().process_frame.connect(pose.bind(-1.0), CONNECT_ONE_SHOT)


## Places the flash just in front of the muzzle at world `muzzle`, along the world bore direction.
func fire(muzzle: Vector3, bore_dir: Vector3) -> void:
	var at := muzzle + bore_dir.normalized() * flash_size * 0.5
	if is_inside_tree():
		global_position = at
	else:
		position = at


## Shows the flash `age` seconds after the shot (hidden before 0 and from FLASH_TIME on).
func pose(age: float) -> void:
	_ball.pose(age)
	if _light == null:
		return
	var live := age >= 0.0 and age < FLASH_TIME
	_light.visible = live
	_light.light_energy = LIGHT_ENERGY * (1.0 - age / FLASH_TIME) if live else 0.0
