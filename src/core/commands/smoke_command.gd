class_name SmokeCommand
extends Command
## Order Smoke screen (TASK-081b): a tank lays smoke on a hex 1-2 hexes away. The hex blocks
## direct-fire line of sight through it until the start of the owner's next turn. Uses the
## unit's action slot and its movement (GDD "Unit orders").

var unit_id: int
var target: Vector2i


func _init(p_unit_id: int, p_target: Vector2i) -> void:
	unit_id = p_unit_id
	target = p_target


func to_dict() -> Dictionary:
	return {"type": "order_smoke", "unit_id": unit_id, "target": [target.x, target.y]}


func validate(state: GameState) -> String:
	var problem := unit_problem(state)
	if problem != "":
		return problem
	if not state.grid.has_tile(target):
		return "invalid_target"
	var unit := state.get_unit(unit_id)
	return OrderRules.range_problem(unit, OrderRules.SMOKE, Hex.distance(unit.coord, target))


## The common checks on the unit alone (target not looked at).
func unit_problem(state: GameState) -> String:
	return OrderRules.slot_problem(state, unit_id, OrderRules.SMOKE)


func apply(state: GameState) -> Array[Dictionary]:
	var unit := state.get_unit(unit_id)
	var has_smoke := state.smoke_hexes.any(func(s: Dictionary) -> bool: return s["coord"] == target)
	if not has_smoke:
		state.smoke_hexes.append({"coord": target, "owner": unit.owner_id})
	unit.has_attacked = true
	unit.slot_order = OrderRules.SMOKE
	unit.moves_left = 0
	var events: Array[Dictionary] = [
		{
			"type": &"unit_order_issued",
			"unit_id": unit_id,
			"order": OrderRules.SMOKE,
			"target": target,
		},
	]
	events.append_array(state.activate(unit))
	return events
