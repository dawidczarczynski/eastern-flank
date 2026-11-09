class_name IssueOrderCommand
extends OperationalCommand
## Gives a formation of the current player an order (TASK-092d): go to `destination` in
## `posture` (an enemy-held destination is an attack order, only for a posture that does not avoid
## contact). Replaces any earlier order; the formation does not move now (TASK-092e executes
## orders at the end of the turn).

const TYPE := "issue_order"

var formation_id: StringName
var destination: Vector2i
var posture: StringName


func _init(
	p_formation_id: StringName = &"", p_destination := Vector2i.ZERO, p_posture: StringName = &""
) -> void:
	formation_id = p_formation_id
	destination = p_destination
	posture = p_posture


func validate(state: OperationalState) -> String:
	var reason := OperationalOrders.formation_problem(state, formation_id)
	if reason != "":
		return reason
	var data := OperationalPosture.find(posture)
	if data == null:
		return "unknown_posture"
	var formation := state.get_formation(formation_id)
	if (
		destination == formation.coord
		or not state.grid.has_tile(destination)
		or state.grid.move_cost(destination) == Terrain.IMPASSABLE
	):
		return "invalid_destination"
	reason = _target_problem(state, formation, data)
	if reason != "":
		return reason
	if OperationalRoutes.plan(state, formation, destination, data.avoids_contact).is_empty():
		return "no_route"
	return ""


## What is wrong with the destination hex's occupant: an own formation, or an enemy for a posture
## that avoids contact.
func _target_problem(
	state: OperationalState, formation: Formation, data: OperationalPosture
) -> String:
	var holder := state.formation_at(destination)
	if holder == null:
		return ""
	if holder.owner_id == formation.owner_id:
		return "occupied"
	return "enemy_destination" if data.avoids_contact else ""


func apply(state: OperationalState) -> Array[Dictionary]:
	var formation := state.get_formation(formation_id)
	var data := OperationalPosture.find(posture)
	formation.posture = posture
	formation.order = FormationOrder.new(destination)
	var forecast := OperationalRoutes.forecast(
		state,
		formation,
		destination,
		OperationalOrders.budget(formation, data),
		data.avoids_contact
	)
	return [
		{
			"type": &"formation_order_issued",
			"formation_id": formation_id,
			"destination": destination,
			"posture": posture,
			"forecast": forecast,
		}
	]


func to_dict() -> Dictionary:
	return {
		"type": TYPE,
		"formation_id": String(formation_id),
		"destination": [destination.x, destination.y],
		"posture": String(posture),
	}
