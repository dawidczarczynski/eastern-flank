class_name MoveUnitCommand
extends Command

var unit_id: int
var target: Vector2i


func _init(p_unit_id: int, p_target: Vector2i) -> void:
	unit_id = p_unit_id
	target = p_target


func validate(state: GameState) -> String:
	if state.winner != -1:
		return "game_over"
	var unit := state.get_unit(unit_id)
	if unit == null or not unit.is_alive():
		return "unit_not_found"
	if unit.owner_id != state.current_player:
		return "not_your_unit"
	if target == unit.coord or not _reach(state, unit).has(target):
		return "unreachable"
	return ""


func apply(state: GameState) -> Array[Dictionary]:
	var unit := state.get_unit(unit_id)
	var from := unit.coord
	unit.moves_left -= _reach(state, unit)[target]
	unit.coord = target
	var events: Array[Dictionary] = [
		{"type": &"unit_moved", "unit_id": unit_id, "from": from, "to": target},
	]
	return events


func _reach(state: GameState, unit: Unit) -> Dictionary:
	return state.grid.reachable(unit.coord, unit.moves_left, state.occupied())
