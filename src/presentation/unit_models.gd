class_name UnitModels
extends RefCounted
## Registry of the unit miniatures: loads src/presentation/models/<unit_id>.gd (one file per
## unit, `static func build(faction) -> Node3D`), wraps the result in a root with facing and
## scale, and poses squads / vehicles. No mesh-building code here (see ModelParts).
## Models face +X and stand on y = 0 of their root.

const MODEL_SCALE := 1.3
## 1 model unit = 10 m before MODEL_SCALE.
const METERS_PER_UNIT := 10.0
const MODEL_PATH := "res://src/presentation/models/%s.gd"
const INFANTRY := &"infantry"
const CAVALRY := &"cavalry"
const ROCKET_ARTILLERY := &"rocket_artillery"
## Models driven by vehicle locomotion (wheel spin, hull rocking, slope tilt) instead of a march.
const VEHICLES: Array[StringName] = [CAVALRY, ROCKET_ARTILLERY]
## Soldiers in a squad model (Soldier0..4) and wheel pivots a vehicle may have (Wheel0..11).
const SQUAD_SIZE := 5
const MAX_WHEELS := 12
## Temporary stand-ins until TASK-039a adds the real unit definitions (then delete this and
## model_id): "<unit id>:<faction id>" -> model file id.
const MODEL_STAND_INS := {&"rocket_artillery:poland": &"homar_k"}


## Yaw of a model root: player 0 faces east (+X), player 1 faces west.
static func facing_yaw(owner_id: int) -> float:
	return 0.0 if owner_id == 0 else PI


static func is_vehicle(definition_id: StringName) -> bool:
	return definition_id in VEHICLES


## Model file id for a unit of a faction: its own id unless MODEL_STAND_INS maps it.
static func model_id(definition_id: StringName, faction: FactionDefinition) -> StringName:
	var faction_id: StringName = faction.id if faction != null else &""
	return MODEL_STAND_INS.get(StringName("%s:%s" % [definition_id, faction_id]), definition_id)


## `faction` colours the model (null = neutral grey); `owner_id` only sets the facing.
static func build(definition_id: StringName, owner_id: int, faction: FactionDefinition) -> Node3D:
	var root := Node3D.new()
	root.rotation.y = facing_yaw(owner_id)
	var model := _build_model(definition_id, faction)
	model.name = "Model"
	model.scale = Vector3.ONE * MODEL_SCALE
	root.add_child(model)
	return root


## Whether a model file exists for the unit id.
static func has_model(definition_id: StringName) -> bool:
	return ResourceLoader.exists(MODEL_PATH % definition_id)


## The unit's own model (cached per unit and faction), or the magenta placeholder when there is
## no model file yet, so new units are playable before they are modelled.
static func _build_model(definition_id: StringName, faction: FactionDefinition) -> Node3D:
	if has_model(definition_id):
		var script := load(MODEL_PATH % definition_id) as GDScript
		if script != null:
			var faction_id: StringName = faction.id if faction != null else &""
			var model := ModelParts.cached(
				"%s:%s" % [definition_id, faction_id], Callable(script, "build").bind(faction)
			)
			if model != null:
				return model
	push_warning("UnitModels: no model for '%s', using a placeholder box" % definition_id)
	return ModelParts.placeholder()


## Root may be the built root or its "Model" child.
static func _model_of(node: Node3D) -> Node3D:
	var inner := node.get_node_or_null("Model") as Node3D
	return inner if inner != null else node


## Poses a squad: `moving` makes kneelers stand; at env 0 / not moving every Rig is exactly
## the identity transform.
static func pose_infantry(model: Node3D, distance: float, env: float, moving: bool) -> void:
	var m := _model_of(model)
	for i in SQUAD_SIZE:
		var rig := m.get_node_or_null("Soldier%d/Rig" % i) as Node3D
		if rig == null:
			continue
		var kneel := rig.get_node_or_null("Kneel") as Node3D
		if kneel != null:
			kneel.visible = not moving
			(rig.get_node("Stand") as Node3D).visible = moving
		if not moving or env <= 0.0:
			rig.transform = Transform3D.IDENTITY
			continue
		var phase := Locomotion.step_phase(i)
		rig.position = Vector3(0.0, Locomotion.step_bob(distance, phase) * env, 0.0)
		rig.rotation = Vector3(
			Locomotion.step_sway(distance, phase) * env, 0.0, Locomotion.LEAN * env
		)


## Spins the wheels to the accumulated `wheel_distance` and sets the hull's pitch/roll to the
## slope `tilt` (x pitch, y roll) plus the env-scaled rocking.
static func pose_tank(model: Node3D, wheel_distance: float, env: float, tilt: Vector2) -> void:
	var m := _model_of(model)
	var angle := Locomotion.wheel_angle(wheel_distance)
	for i in MAX_WHEELS:
		var pivot := m.get_node_or_null("Wheel%d" % i) as Node3D
		if pivot != null:
			pivot.rotation.z = angle
	var pitch := tilt.x
	var roll := tilt.y
	if env > 0.0:
		var bob := Locomotion.hull_bob(wheel_distance)
		pitch += bob.x * env
		roll += bob.y * env
	m.rotation = Vector3(roll, 0.0, pitch)
