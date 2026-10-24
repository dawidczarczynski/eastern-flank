class_name CatalogAnimations
extends RefCounted
## Which animations the unit catalog offers for a model (TASK-084): a table from the mechanisms
## the model declares (`UnitModels.mechanisms`, ADR 0014) to animation ids, so each unit shows only
## what it has. Adding a mechanism (gun_recoil) = a row in TABLE and a handler in
## CatalogStage. Pure: no nodes besides reading the model's metadata.

const DRIVE := &"drive"
const MARCH := &"march"
const KNEEL := &"kneel"
const DEPLOY := &"deploy"
const RAISE := &"raise"
const TRAVERSE := &"traverse"
const FIRE := &"fire"
## Offered for every unit, whatever it declares.
const HIT := &"hit"
const DEATH := &"death"

## Mechanism id -> the animations it enables.
const TABLE := {
	"wheels": [DRIVE],
	"squad_march": [MARCH, KNEEL],
	"stabilisers": [DEPLOY],
	"blast_shields": [DEPLOY],
	"launcher": [RAISE, TRAVERSE, FIRE],
	"turret_traverse": [TRAVERSE],
}
## Button order.
const ORDER: Array[StringName] = [DRIVE, MARCH, KNEEL, DEPLOY, RAISE, TRAVERSE, FIRE]
const COMMON: Array[StringName] = [HIT, DEATH]
## Translation keys of the button texts.
const LABELS := {
	DRIVE: "Drive",
	MARCH: "March",
	KNEEL: "Kneel / stand",
	DEPLOY: "Deploy",
	RAISE: "Raise launcher",
	TRAVERSE: "Traverse",
	FIRE: "Fire",
	HIT: "Hit",
	DEATH: "Death",
}
## Fraction of the traverse range (or of the quarter turn for a full traverse) the Traverse and
## Fire animations turn the launcher to.
const TRAVERSE_FRACTION := 0.8
const FULL_TRAVERSE_ANGLE := PI / 3.0


## Animation ids for the model, in ORDER. A model without metadata gets none.
static func for_model(model: Node3D) -> Array[StringName]:
	var found := {}
	var declared := UnitModels.mechanisms(model)
	for mechanism: String in TABLE:
		if declared.has(mechanism):
			for id: StringName in TABLE[mechanism]:
				found[id] = true
	if found.has(FIRE) and not UnitModels.has_launcher(model):
		found.erase(RAISE)
		found.erase(TRAVERSE)
		found.erase(FIRE)
	var result: Array[StringName] = []
	for id in ORDER:
		if found.has(id):
			result.append(id)
	return result


## Translation key of an animation's button text.
static func label(id: StringName) -> String:
	return LABELS.get(id, String(id))


## Angle (rad, relative to the stowed direction) the launcher traverses to in the Traverse and Fire
## animations: inside the model's traverse range, away from the stowed direction.
static func traverse_angle(model: Node3D) -> float:
	var params := (
		UnitModels.turret_params(model)
		if UnitModels.has_turret(model)
		else UnitModels.launcher_params(model)
	)
	var range_deg: Variant = params["traverse_deg"]
	if not range_deg is Array:
		return FULL_TRAVERSE_ANGLE
	var lo := float((range_deg as Array)[0])
	var hi := float((range_deg as Array)[1])
	return deg_to_rad(hi if absf(hi) >= absf(lo) else lo) * TRAVERSE_FRACTION
