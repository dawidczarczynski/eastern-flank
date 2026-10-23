class_name MotionFx
extends RefCounted
## The dust and exhaust emitters of one driving vehicle (TASK-064). They sit on the model's root
## (so they follow the hull's heading), emit into world space and so leave a cloud that hangs
## behind the vehicle and thins out on its own. UnitView calls begin() / update() / end() while
## a move plays; the numbers come from MotionEffects. Emission strength is `amount_ratio`.

const DUST_LIFETIME := 2.4
const DUST_MAX := 40
const DUST_SIZE_START := 0.12
const DUST_SIZE_END := 0.5
const DUST_ALPHA := 0.35
const EXHAUST_LIFETIME := 2.4
const EXHAUST_MAX := 150
const EXHAUST_SIZE_START := 0.07
const EXHAUST_SIZE_END := 0.3
const EXHAUST_ALPHA := 0.85
## Exhaust colour: black at full engine load (the pull-away blast), thin grey when cruising.
const EXHAUST_BLACK := Color("141412")
const EXHAUST_GREY := Color("6a6a66", 0.4)
## Sizes are specified at the `current` unit scale preset.
const REFERENCE_UNIT_SCALE := 1.3
## Fallback placement from the model bounds: rear of the hull, wheels / tracks at ±40 % width,
## the engine deck at 60 % of the height.
const DUST_SIDE := 0.4
const EXHAUST_HEIGHT := 0.6

var unit_class: StringName
var _dust: Array[GPUParticles3D] = []
var _exhaust: GPUParticles3D
var _tint := Color(0, 0, 0, 0)
var _dust_factor := 1.0


## Builds the emitters under `root` (the model root, facing +X); `model` is the "Model" child
## whose `Exhaust` / `Dust_L` / `Dust_R` anchors are used when present. `wind` is the world
## drift direction (XZ) of the clouds, ZERO without wind.
func setup(root: Node3D, model: Node3D, unit_class_id: StringName, wind := Vector2.ZERO) -> void:
	unit_class = unit_class_id
	var bounds := model_bounds(model)
	var model_scale := model.scale.x
	var size_factor := (
		VisualScale.unit_model_scale()
		/ REFERENCE_UNIT_SCALE
		* MotionEffects.cloud_size(unit_class_id)
	)
	var rear := bounds.position.x
	var side_offset := bounds.size.z * DUST_SIDE
	var wind_push := Vector3(wind.x, 0.0, wind.y) * 0.1
	var dust_config := {
		"lifetime": DUST_LIFETIME,
		"max_particles": DUST_MAX,
		"direction": Vector3(-0.3, 1.0, 0.0),
		"spread": 40.0,
		"velocity_min": 0.05,
		"velocity_max": 0.25,
		"gravity": Vector3(0.0, 0.12, 0.0) + wind_push,
		"damping": 0.6,
		"size_start": DUST_SIZE_START * size_factor,
		"size_end": DUST_SIZE_END * size_factor,
		"alpha": DUST_ALPHA,
		"tint": MotionEffects.DUST_PLAINS,
	}
	var feet := bounds.position.y
	for side in [["Dust_L", -1.0], ["Dust_R", 1.0]]:
		var anchor := model.get_node_or_null(side[0] as String) as Node3D
		var local := Vector3(rear, feet, side[1] * side_offset)
		var at := model.transform * anchor.position if anchor != null else local * model_scale
		var dust := ParticleFx.emitter(dust_config)
		dust.name = side[0]
		dust.position = at
		root.add_child(dust)
		_dust.append(dust)
	var exhaust_config := {
		"lifetime": EXHAUST_LIFETIME,
		"max_particles": EXHAUST_MAX,
		"direction": Vector3(-0.6, 1.0, 0.0),
		"spread": 10.0,
		"velocity_min": 0.4,
		"velocity_max": 1.1,
		"gravity": Vector3(0.0, 0.08, 0.0) + wind_push,
		"damping": 2.2,
		"size_start": EXHAUST_SIZE_START * size_factor,
		"size_end": EXHAUST_SIZE_END * size_factor,
		"alpha": EXHAUST_ALPHA,
		"tint": EXHAUST_GREY,
	}
	_exhaust = ParticleFx.emitter(exhaust_config)
	_exhaust.name = "Exhaust"
	var exhaust_anchor := model.get_node_or_null("Exhaust") as Node3D
	if exhaust_anchor != null:
		_exhaust.position = model.transform * exhaust_anchor.position
	else:
		var y := bounds.position.y + bounds.size.y * EXHAUST_HEIGHT
		_exhaust.position = Vector3(rear, y, 0.0) * model_scale
	root.add_child(_exhaust)


func dust_emitters() -> Array[GPUParticles3D]:
	return _dust


func exhaust_emitter() -> GPUParticles3D:
	return _exhaust


## A move starts: the emitters switch on (their strength follows update()).
func begin() -> void:
	for dust in _dust:
		dust.emitting = true
	_exhaust.emitting = true


## One animation step: `since_start` seconds into the move, ground `speed`, `heading_error`
## (radians the hull still has to turn), and the ground under the vehicle. Particles already in
## the air are not touched, so the cloud lingers.
func update(
	since_start: float,
	speed: float,
	heading_error: float,
	terrain: int,
	weights := PackedFloat32Array()
) -> void:
	var tint := MotionEffects.dust_color(terrain, weights)
	_dust_factor = MotionEffects.dust_rate_factor(terrain, weights)
	if tint.a > 0.0 and tint != _tint:
		for dust in _dust:
			ParticleFx.set_tint(dust, tint)
		_tint = tint
	var dust_rate := MotionEffects.dust_rate(unit_class, speed) * _dust_factor
	var dust_ratio := 0.0
	if tint.a > 0.0:
		dust_ratio = dust_rate / float(_dust.size()) * DUST_LIFETIME / DUST_MAX
	for dust in _dust:
		dust.amount_ratio = clampf(dust_ratio, 0.0, 1.0)
	var engine_load := MotionEffects.exhaust_load(since_start, heading_error, speed)
	ParticleFx.set_tint(_exhaust, EXHAUST_GREY.lerp(EXHAUST_BLACK, engine_load * engine_load))
	var exhaust_rate := MotionEffects.exhaust_rate(unit_class, engine_load)
	_exhaust.amount_ratio = clampf(exhaust_rate * EXHAUST_LIFETIME / EXHAUST_MAX, 0.0, 1.0)


## The move is over: no new particles, those emitted finish their life.
func end() -> void:
	for dust in _dust:
		dust.emitting = false
		dust.amount_ratio = 0.0
	_exhaust.emitting = false
	_exhaust.amount_ratio = 0.0


## Bounds of all meshes below `node` in the space of `node` (its own transform excluded).
static func model_bounds(node: Node3D) -> AABB:
	var box := AABB()
	var found := false
	var stack: Array = [[node, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var current: Node3D = item[0]
		var to_model: Transform3D = item[1]
		var instance := current as MeshInstance3D
		if instance != null and instance.mesh != null:
			var part := to_model * instance.mesh.get_aabb()
			box = part if not found else box.merge(part)
			found = true
		for child in current.get_children():
			var child3d := child as Node3D
			if child3d != null:
				stack.append([child3d, to_model * child3d.transform])
	return box
