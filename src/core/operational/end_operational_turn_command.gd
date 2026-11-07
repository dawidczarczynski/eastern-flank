class_name EndOperationalTurnCommand
extends OperationalCommand
## Ends the current player's move on the staff map (TASK-093b): the other player becomes current
## and `turn` rises when the move returns to `first_player` (both blocs move inside one 12 h
## turn). Rejected while a contact battle is waiting to be fought.

const TYPE := "end_operational_turn"


func validate(state: OperationalState) -> String:
	if not state.pending_battles.is_empty():
		return "battle_pending"
	return ""


func apply(state: OperationalState) -> Array[Dictionary]:
	var events: Array[Dictionary] = [
		{"type": &"operational_turn_ended", "player": state.current_player}
	]
	_switch_side(state)
	(
		events
		. append(
			{
				"type": &"operational_turn_started",
				"player": state.current_player,
				"turn": state.turn,
			}
		)
	)
	return events


func to_dict() -> Dictionary:
	return {"type": TYPE}


static func _switch_side(state: OperationalState) -> void:
	state.current_player = 1 - state.current_player
	if state.current_player == state.first_player:
		state.turn += 1
