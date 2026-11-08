class_name SetPostureCommand
extends OperationalCommand
## Changes the posture of a formation of the current player (TASK-092d). A standing order is kept
## and re-planned when it executes (TASK-092e).

const TYPE := "set_posture"

var formation_id: StringName
var posture: StringName


func _init(p_formation_id: StringName = &"", p_posture: StringName = &"") -> void:
	formation_id = p_formation_id
	posture = p_posture


func validate(state: OperationalState) -> String:
	var reason := OperationalOrders.formation_problem(state, formation_id)
	if reason != "":
		return reason
	if OperationalPosture.find(posture) == null:
		return "unknown_posture"
	if state.get_formation(formation_id).posture == posture:
		return "same_posture"
	return ""


func apply(state: OperationalState) -> Array[Dictionary]:
	var formation := state.get_formation(formation_id)
	var previous := formation.posture
	formation.posture = posture
	return [
		{
			"type": &"formation_posture_changed",
			"formation_id": formation_id,
			"posture": posture,
			"previous": previous,
		}
	]


func to_dict() -> Dictionary:
	return {"type": TYPE, "formation_id": String(formation_id), "posture": String(posture)}
