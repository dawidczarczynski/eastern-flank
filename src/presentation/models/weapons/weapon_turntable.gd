class_name WeaponTurntable
extends SubViewportContainer
## Turntable of one strike weapon model (TASK-144) for the strike panel's model card
## (docs/design/operational_map/README.md "Strike panel": 388 x 140 px): its own 3D world with one
## camera and one directional light (no shadows), the model spinning once per SPIN_SECONDS, seen
## from TILT_DEG above the horizon and fitted to the viewport. The SubViewport renders only while
## the card is visible (UPDATE_WHEN_VISIBLE) and the spin stops with it.
## Usage: `var turntable := WeaponTurntable.new(); card.add_child(turntable);
## turntable.show_weapon(&"jassm_er")` -> false when the weapon has no model (show the glyph).

const DEFAULT_SIZE := Vector2i(388, 140)
const SPIN_SECONDS := 12.0
const TILT_DEG := 18.0
const FOV_DEG := 30.0
## Share of the viewport the spinning model may fill (each direction).
const FILL := 0.9
## Starting yaw: three-quarter view of the nose.
const START_YAW_DEG := -35.0
const LIGHT_ROTATION_DEG := Vector3(-50.0, -30.0, 0.0)

var viewport: SubViewport
var camera: Camera3D
var light: DirectionalLight3D
## Spins around Y; holds the fitted model.
var spinner: Node3D
var model: Node3D
var weapon_id: StringName = &""


func _init() -> void:
	stretch = true
	custom_minimum_size = DEFAULT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.size = DEFAULT_SIZE
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.positional_shadow_atlas_size = 0
	add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.68, 0.72, 0.75)
	environment.ambient_light_energy = 0.55
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	light = DirectionalLight3D.new()
	light.shadow_enabled = false
	light.light_energy = 1.2
	light.rotation_degrees = LIGHT_ROTATION_DEG
	viewport.add_child(light)
	spinner = Node3D.new()
	spinner.name = "Spinner"
	spinner.rotation_degrees.y = START_YAW_DEG
	viewport.add_child(spinner)
	camera = Camera3D.new()
	camera.fov = FOV_DEG
	camera.current = true
	viewport.add_child(camera)
	_place_camera(1.0)


## Shows the weapon's model; false (and an empty turntable) when it has none.
func show_weapon(means_id: StringName) -> bool:
	if means_id == weapon_id and model != null:
		return true
	weapon_id = means_id
	if model != null:
		model.queue_free()
		model = null
	model = WeaponModels.build(means_id)
	if model == null:
		return false
	spinner.add_child(model)
	_fit()
	return true


func _process(delta: float) -> void:
	if is_visible_in_tree():
		spin(delta)


## Turns the model by `delta` seconds of the spin (one turn per SPIN_SECONDS).
func spin(delta: float) -> void:
	if model != null:
		spinner.rotation.y = wrapf(spinner.rotation.y + TAU * delta / SPIN_SECONDS, -PI, PI)


## Centres the model on the spin axis and moves the camera so that the model fits the viewport at
## every yaw (its horizontal circle and its height, seen from TILT_DEG).
func _fit() -> void:
	var box := _aabb(model, Transform3D.IDENTITY)
	var centre := box.get_center()
	model.position = -centre
	var half := box.size / 2.0
	var radius := Vector2(half.x, half.z).length()
	var tilt := deg_to_rad(TILT_DEG)
	var half_height := radius * sin(tilt) + half.y * cos(tilt)
	var aspect := float(viewport.size.x) / maxf(1.0, float(viewport.size.y))
	var tan_v := tan(deg_to_rad(FOV_DEG) / 2.0) * FILL
	var tan_h := tan_v * aspect
	# The near half of the spin circle comes closer to the camera: a part of the radius as margin.
	var distance := maxf(radius / tan_h, half_height / tan_v) + radius * 0.35
	_place_camera(distance)


func _place_camera(distance: float) -> void:
	var tilt := deg_to_rad(TILT_DEG)
	var eye := Vector3(0.0, sin(tilt), cos(tilt)) * distance
	camera.transform = Transform3D(Basis.IDENTITY, eye).looking_at(Vector3.ZERO, Vector3.UP)
	camera.near = maxf(0.01, distance * 0.05)
	camera.far = distance * 4.0


## Bounds of the meshes below `node` in its parent's space (local transforms only, so it works
## before the tree has processed the new nodes).
static func _aabb(node: Node3D, to_parent: Transform3D) -> AABB:
	var result := AABB()
	var has := false
	var transform := to_parent * node.transform
	var instance := node as MeshInstance3D
	if instance != null and instance.mesh != null:
		result = transform * instance.get_aabb()
		has = true
	for child in node.get_children():
		if child is Node3D:
			var inner := _aabb(child as Node3D, transform)
			if inner.size != Vector3.ZERO:
				result = result.merge(inner) if has else inner
				has = true
	return result
