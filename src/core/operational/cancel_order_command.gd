class_name CancelOrderCommand
extends OperationalCommand
## Removes the standing order of a formation of the current player (TASK-092d); its posture stays.

const TYPE := "cancel_order"

var formation_id: StringName


func _init(p_formation_id: StringName = &"") -> void:
	formation_id = p_formation_id


func validate(state: OperationalState) -> String:
	var reason := OperationalOrders.formation_problem(state, formation_id)
	if reason != "":
		return reason
	if state.get_formation(formation_id).order == null:
		return "no_order"
	return ""


func apply(state: OperationalState) -> Array[Dictionary]:
	state.get_formation(formation_id).order = null
	return [{"type": &"formation_order_cancelled", "formation_id": formation_id}]


func to_dict() -> Dictionary:
	return {"type": TYPE, "formation_id": String(formation_id)}
