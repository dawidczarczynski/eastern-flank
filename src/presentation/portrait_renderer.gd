class_name PortraitRenderer
extends Node
## Lit 3D portraits of the unit models for the hover card (TASK-034). One SubViewport with its own
## World3D renders each (unit definition, owner) pair once, one pair per frame, and the result is
## kept as an ImageTexture. portrait() hands out the cached texture at once: it shows the plain
## background until its render has finished (is_ready()).

const SIZE := Vector2i(640, 340)
const BACKGROUND := Color("#3a3f35")
const GROUND_COLOR := Color("#6b7150")
const GROUND_RADIUS := 5.0
const SUN_COLOR := Color("#fff0d8")
const SUN_POSITION := Vector3(1.2, 2.4, 1.6)
const FOG_BEGIN := 2.2
const FOG_END := 6.0
const FOV := 24.0
const CAMERA_OFFSET := Vector3(0.82, 0.4, 1.02)
const LOOK_DROP := 0.02
const MODEL_YAW := -0.6
## Share of the battle environment's ambient energy.
const AMBIENT_SHARE := 0.7
const BATTLE_AMBIENT := 0.65
const AMBIENT_COLOR := Color(0.675, 0.72, 0.745)
const TONEMAP_EXPOSURE := 1.3
const TONEMAP_WHITE := 6.0

var _quality: Dictionary = {}
var _textures: Dictionary = {}  # key -> ImageTexture
var _ready_keys: Dictionary = {}  # key -> true once rendered
var _queue: Array[Dictionary] = []
var _rendering := false
var _viewport: SubViewport
var _sun: DirectionalLight3D
var _stage: Node3D
var _camera: Camera3D


## Camera for a model whose bounding box is `aabb` (model-space, facing the viewer's right).
static func camera_transform(aabb: AABB) -> Transform3D:
	var size := aabb.size.length()
	var center := aabb.get_center()
	var position := center + size * CAMERA_OFFSET
	var target := center - Vector3(0.0, LOOK_DROP, 0.0)
	return Transform3D(Basis.looking_at(target - position, Vector3.UP), position)


## Cache key of a (unit definition id, owner) pair.
static func key_of(definition_id: StringName, owner_id: int) -> String:
	return "%s:%d" % [definition_id, owner_id]


## Bounding box of the visible meshes below `node` (in `node`'s own local space).
static func visible_aabb(node: Node3D, to_root: Transform3D = Transform3D.IDENTITY) -> AABB:
	var result := AABB()
	var has := false
	for child in node.get_children():
		var spatial := child as Node3D
		if spatial == null or not spatial.visible:
			continue
		var transform_to_root := to_root * spatial.transform
		var box := AABB()
		var has_box := false
		var instance := spatial as MeshInstance3D
		if instance != null and instance.mesh != null:
			box = transform_to_root * instance.get_aabb()
			has_box = true
		var inner := visible_aabb(spatial, transform_to_root)
		if inner.size != Vector3.ZERO:
			box = box.merge(inner) if has_box else inner
			has_box = true
		if has_box:
			result = result.merge(box) if has else box
			has = true
	return result


## `quality`: GraphicsQuality.features of the running battle.
func setup(quality: Dictionary) -> void:
	_quality = quality
	name = "PortraitRenderer"
	_build_viewport()
	_start_next()  # portraits requested before setup


## The texture of the pair, created and queued for rendering on first request; the same object
## for repeated requests. Needs a faction for the camouflage (null = neutral grey).
func portrait(definition_id: StringName, owner_id: int, faction: FactionDefinition) -> Texture2D:
	var key := key_of(definition_id, owner_id)
	if _textures.has(key):
		return _textures[key]
	var blank := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGB8)
	blank.fill(BACKGROUND)
	var texture := ImageTexture.create_from_image(blank)
	_textures[key] = texture
	_queue.append({"key": key, "id": definition_id, "owner": owner_id, "faction": faction})
	_start_next()
	return texture


## Whether the portrait of the pair has been rendered.
func is_ready(definition_id: StringName, owner_id: int) -> bool:
	return _ready_keys.has(key_of(definition_id, owner_id))


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = _quality.get("msaa_3d", Viewport.MSAA_DISABLED)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT_COLOR
	environment.ambient_light_energy = BATTLE_AMBIENT * AMBIENT_SHARE
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = TONEMAP_EXPOSURE
	environment.tonemap_white = TONEMAP_WHITE
	environment.fog_enabled = true
	environment.fog_light_color = BACKGROUND
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = FOG_BEGIN
	environment.fog_depth_end = FOG_END
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)

	_sun = DirectionalLight3D.new()
	_sun.light_color = SUN_COLOR
	_sun.shadow_enabled = _quality.get("shadows", true)
	_sun.transform = Transform3D(Basis.looking_at(-SUN_POSITION, Vector3.UP), SUN_POSITION)
	_viewport.add_child(_sun)

	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = GROUND_RADIUS
	disc.bottom_radius = GROUND_RADIUS
	disc.height = 0.02
	disc.radial_segments = 48
	disc.rings = 1
	ground.mesh = disc
	ground.position.y = -0.01
	var material := StandardMaterial3D.new()
	material.albedo_color = GROUND_COLOR
	material.roughness = 1.0
	ground.material_override = material
	_viewport.add_child(ground)

	_stage = Node3D.new()
	_viewport.add_child(_stage)
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.current = true
	_viewport.add_child(_camera)
	add_child(_viewport)


func _start_next() -> void:
	if _rendering or _queue.is_empty() or _viewport == null or not is_inside_tree():
		return
	_rendering = true
	_render_next.call_deferred()


func _render_next() -> void:
	while not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		await _render(job)
	_rendering = false


func _render(job: Dictionary) -> void:
	var model := UnitModels.build(job["id"], 0, job["faction"] as FactionDefinition)
	_stage.add_child(model)  # facing yaw 0: the model looks along +X
	_camera.transform = camera_transform(visible_aabb(model))
	model.rotation.y = MODEL_YAW
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	_stage.remove_child(model)
	model.queue_free()
	if image == null or image.is_empty() or image.get_size() != SIZE:
		push_warning("PortraitRenderer: no image for '%s'" % job["key"])
		return
	image.convert(Image.FORMAT_RGB8)
	(_textures[job["key"]] as ImageTexture).update(image)
	_ready_keys[job["key"]] = true
