class_name EndTurnCommand
extends Command


func validate(state: GameState) -> String:
	if state.winner != -1:
		return "game_over"
	return ""


func apply(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = [{"type": &"turn_ended", "player": state.current_player}]
	state.current_player = (state.current_player + 1) % state.player_count
	if state.current_player == 0:
		state.turn += 1
	for unit in state.units_of(state.current_player):
		unit.moves_left = unit.definition.move_points
		unit.has_attacked = false
	events.append({"type": &"turn_started", "player": state.current_player, "turn": state.turn})
	return events
