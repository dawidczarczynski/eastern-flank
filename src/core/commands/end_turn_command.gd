class_name EndTurnCommand
extends Command
## Ends the current player's turn. BattleRules.at_turn_end may end the battle first (take hexes,
## turn limit): then only turn_ended + game_over are emitted and the turn does not pass.


func to_dict() -> Dictionary:
	return {"type": "end_turn"}


func validate(state: GameState) -> String:
	if state.is_over():
		return "game_over"
	return ""


func apply(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = [{"type": &"turn_ended", "player": state.current_player}]
	events.append_array(BattleRules.at_turn_end(state))
	if state.is_over():
		return events
	state.current_player = (state.current_player + 1) % state.player_count
	if state.current_player == 0:
		state.turn += 1
	for unit in state.units_of(state.current_player):
		unit.moves_left = unit.definition.move_points
		unit.has_attacked = false
		unit.activated = false
	events.append({"type": &"turn_started", "player": state.current_player, "turn": state.turn})
	state.command_points = state.command_points_per_turn[state.current_player]
	if state.is_command_limited(state.current_player):
		(
			events
			. append(
				{
					"type": &"command_points_changed",
					"player": state.current_player,
					"remaining": state.command_points,
				}
			)
		)
	return events
