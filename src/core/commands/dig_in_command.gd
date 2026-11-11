class_name DigInCommand
extends Command
## Order Dig in (TASK-081a): the unit entrenches – +2 defence until it moves. Uses the unit's
## action slot of the turn and its movement (GDD "Unit orders").

var unit_id: int


func _init(p_unit_id: int) -> void:
	unit_id = p_unit_id


func to_dict() -> Dictionary:
	return {"type": "order_dig_in", "unit_id": unit_id}


func validate(state: GameState) -> String:
	if state.is_over():
		return "game_over"
	var unit := state.get_unit(unit_id)
	if unit == null or not unit.is_alive():
		return "unit_not_found"
	if unit.owner_id != state.current_player:
		return "not_your_unit"
	if not state.can_activate(unit):
		return "no_command_points"
	return _order_problem(unit)


## Rules of the order itself, once the unit exists and may act.
func _order_problem(unit: Unit) -> String:
	if not OrderRules.orders_for(unit).has(OrderRules.DIG_IN):
		return "order_not_available"
	if unit.has_attacked or unit.slot_order != &"":
		return "already_acted"
	if unit.dug:
		return "already_dug"
	return ""


func apply(state: GameState) -> Array[Dictionary]:
	var unit := state.get_unit(unit_id)
	unit.dug = true
	unit.has_attacked = true
	unit.slot_order = OrderRules.DIG_IN
	unit.moves_left = 0
	var events: Array[Dictionary] = [
		{
			"type": &"unit_order_issued",
			"unit_id": unit_id,
			"order": OrderRules.DIG_IN,
			"target": unit.coord,
		},
	]
	events.append_array(state.activate(unit))
	return events
