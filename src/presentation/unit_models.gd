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
const M1A2_SEPV3 := &"m1a2_sepv3"
## Models driven by vehicle locomotion (wheel spin, hull rocking, slope tilt) instead of a march.
const VEHICLES: Array[StringName] = [CAVALRY, ROCKET_ARTILLERY, M1A2_SEPV3]
## Soldiers in a squad model (Soldier0..4) and wheel pivots a vehicle may have (Wheel0..19).
const SQUAD_SIZE := 5
const MAX_WHEELS := 20
## Elevation (rad) of a turntable launcher's pod while firing.
const LAUNCHER_ELEVATION := 0.7
## Hydraulic actuators a launcher may have (Actuator0.., see pose_launcher).
const MAX_ACTUATORS := 4
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


## Whether the model's launcher turns and elevates ("Launcher" turntable with the "Pod" on it);
## fixed launchers have the "Pod" directly on the model.
static func has_launcher(model: Node3D) -> bool:
	return _model_of(model).get_node_or_null("Launcher") is Node3D


## The pod holding the "Mouth*" tube ends, on the turntable or fixed on the model; null if none.
static func launcher_pod(model: Node3D) -> Node3D:
	var m := _model_of(model)
	var pod := m.get_node_or_null("Launcher/Pod") as Node3D
	return pod if pod != null else m.get_node_or_null("Pod") as Node3D


## Turntable angle (Launcher rotation.y) that points the tube ends, which face the rear when
## stowed, towards the facing yaw `target_yaw` of a unit whose body has yaw `facing_yaw`;
## wrapped to the shorter turn.
static func launcher_traverse(facing_yaw: float, target_yaw: float) -> float:
	return wrapf(target_yaw - facing_yaw - PI, -PI, PI)


## Turntable launcher pose: "Launcher" turns by `traverse` about its Y, its "Pod" turns up by
## `elevation` about the hinge (the Pod's local Z, from its built pose kept in the "rest" meta).
## Each "Actuator<i>" (cylinder, at its anchor on the turntable) and "ActuatorRod<i>" (piston)
## are aimed along their local Y at each other between the anchor and the Pod's
## "ActuatorMount<i>". No-op for models without a launcher; (0, 0) is the stowed pose.
static func pose_launcher(model: Node3D, traverse: float, elevation: float) -> void:
	var m := _model_of(model)
	var launcher := m.get_node_or_null("Launcher") as Node3D
	var pod := launcher_pod(m)
	if launcher == null or pod == null:
		return
	launcher.basis = Basis(Vector3.UP, traverse)
	var rest: Transform3D = pod.get_meta(&"rest", pod.transform)
	if not pod.has_meta(&"rest"):
		pod.set_meta(&"rest", rest)
	pod.transform = rest * Transform3D(Basis(Vector3.BACK, elevation), Vector3.ZERO)
	for i in MAX_ACTUATORS:
		var barrel := launcher.get_node_or_null("Actuator%d" % i) as Node3D
		var rod := launcher.get_node_or_null("ActuatorRod%d" % i) as Node3D
		var mount := pod.get_node_or_null("ActuatorMount%d" % i) as Node3D
		if barrel == null or rod == null or mount == null:
			continue
		var top := pod.transform * mount.position
		barrel.basis = _along(top - barrel.position)
		rod.position = top
		rod.basis = _along(barrel.position - top)


## Rotation whose Y axis points along `direction`; the hinge axis (Z) stays as close to the
## launcher's Z as possible.
static func _along(direction: Vector3) -> Basis:
	var y := direction.normalized()
	var x := y.cross(Vector3.BACK).normalized()
	return Basis(x, y, x.cross(y))


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
