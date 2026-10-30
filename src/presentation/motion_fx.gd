class_name MotionFx
extends RefCounted
## The dust and exhaust emitters of one driving vehicle (TASK-064). They sit on the model's root
## (so they follow the hull's heading), emit into world space and so leave a cloud that hangs
## behind the vehicle and thins out on its own. UnitView calls begin() / update() / end() while
## a move plays; the numbers come from MotionEffects. Emission strength is `amount_ratio`.
## The puffs are ParticleFx.puff_emitter ones (drag towards the wind drift, sun-lit soft puffs);
## a puff keeps the colour it was born with, so the cloud's colour changes along the way.

const DUST_LIFETIME := 2.4
const DUST_MAX := 40
## Puff size at birth and at the end of its life (world units, tank at the reference scale):
## small puffs kicked up behind the tracks / wheels that grow into a low, narrow trail.
const DUST_SIZE_START := 0.05
const DUST_SIZE_END := 0.38
const DUST_ALPHA := 0.5
const EXHAUST_LIFETIME := 2.0
const EXHAUST_MAX := 120
const EXHAUST_SIZE_START := 0.03
const EXHAUST_SIZE_END := 0.26
## Exhaust colour: dark puffs at full engine load (the pull-away blast), thin grey when cruising.
const EXHAUST_BLACK := Color("1c1b19", 0.75)
const EXHAUST_GREY := Color("77756f", 0.3)
## Opacity over a puff's life (it multiplies the tint).
const DUST_RAMP := [
	0.0,
	Color(1, 1, 1, 0.0),
	0.08,
	Color(1, 1, 1, 1.0),
	0.4,
	Color(1, 1, 1, 0.65),
	1.0,
	Color(1, 1, 1, 0.0)
]
const EXHAUST_RAMP := [
	0.0,
	Color(1, 1, 1, 0.0),
	0.04,
	Color(1, 1, 1, 1.0),
	0.3,
	Color(1, 1, 1, 0.6),
	1.0,
	Color(1, 1, 1, 0.0)
]
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
		"amount": DUST_MAX,
		"lifetime": DUST_LIFETIME,
		"drag": 1.8,
		"rise": 0.08,
		"wind": wind_push,
		"size_start": DUST_SIZE_START * size_factor,
		"size_end": DUST_SIZE_END * size_factor,
		"grow": 2.0,
		"ramp": DUST_RAMP,
		"look": "vehicle_dust",
		"direction": Vector3(-1.0, 0.8, 0.0),
		"spread": 35.0,
		"speed": Vector2(0.15, 0.45),
		"jitter": 0.03 * size_factor,
		"size": Vector2(0.8, 1.2),
		"life": Vector2(0.7, 1.0),
		"tint": Color(MotionEffects.DUST_PLAINS, DUST_ALPHA),
	}
	var feet := bounds.position.y
	for side in [["Dust_L", -1.0], ["Dust_R", 1.0]]:
		var anchor := model.get_node_or_null(side[0] as String) as Node3D
		var local := Vector3(rear, feet, side[1] * side_offset)
		var at := model.transform * anchor.position if anchor != null else local * model_scale
		var dust := ParticleFx.puff_emitter(dust_config)
		dust.name = side[0]
		dust.position = at
		root.add_child(dust)
		_dust.append(dust)
	var exhaust_config := {
		"amount": EXHAUST_MAX,
		"lifetime": EXHAUST_LIFETIME,
		"drag": 2.2,
		"rise": 0.3,
		"wind": wind_push,
		"size_start": EXHAUST_SIZE_START * size_factor,
		"size_end": EXHAUST_SIZE_END * size_factor,
		"grow": 2.0,
		"ramp": EXHAUST_RAMP,
		"look": "vehicle_exhaust",
		"direction": Vector3(-0.6, 1.0, 0.0),
		"spread": 12.0,
		"speed": Vector2(0.5, 1.1),
		"jitter": 0.01 * size_factor,
		"size": Vector2(0.8, 1.2),
		"life": Vector2(0.7, 1.0),
		"tint": EXHAUST_GREY,
	}
	_exhaust = ParticleFx.puff_emitter(exhaust_config)
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
			ParticleFx.set_puff_tint(dust, Color(tint, DUST_ALPHA))
		_tint = tint
	var dust_rate := MotionEffects.dust_rate(unit_class, speed) * _dust_factor
	var dust_ratio := 0.0
	if tint.a > 0.0:
		dust_ratio = dust_rate / float(_dust.size()) * DUST_LIFETIME / DUST_MAX
	for dust in _dust:
		dust.amount_ratio = clampf(dust_ratio, 0.0, 1.0)
	var engine_load := MotionEffects.exhaust_load(since_start, heading_error, speed)
	ParticleFx.set_puff_tint(_exhaust, EXHAUST_GREY.lerp(EXHAUST_BLACK, engine_load * engine_load))
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
