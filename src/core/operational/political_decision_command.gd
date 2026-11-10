class_name PoliticalDecisionCommand
extends OperationalCommand
## Base of the five political decisions (TASK-117, GDD "Political decisions"): the issuer is always
## `state.current_player`; every accepted decision costs one of `state.decisions_left`, first emits
## `political_decision_taken`, then its effects. Common rejections, in order: `battle_pending`,
## `no_decisions_left`; the rest is `_decision_problem` of the subclass. Side-agnostic: no rule asks
## which side the player is. Subclasses set `TYPE` through `type_id()`.


func validate(state: OperationalState) -> String:
	if not state.pending_battles.is_empty():
		return "battle_pending"
	if state.decisions_left < 1:
		return "no_decisions_left"
	return _decision_problem(state, state.current_player)


func apply(state: OperationalState) -> Array[Dictionary]:
	var player := state.current_player
	state.decisions_left -= 1
	var events: Array[Dictionary] = [
		{
			"type": &"political_decision_taken",
			"player": player,
			"decision": type_id(),
			"country": _country_id()
		}
	]
	events.append_array(_effects(state, player))
	return events


## The command's `TYPE` string (also the `decision` of the event).
func type_id() -> StringName:
	return &""


## "" when the decision is allowed, else the rejection code (after the common ones).
func _decision_problem(_state: OperationalState, _player: int) -> String:
	return ""


func _effects(_state: OperationalState, _player: int) -> Array[Dictionary]:
	return []


## The target country of the event (`&""` for none).
func _country_id() -> StringName:
	return &""


## Whether the player is still barred from escalating by an earlier Stand down.
static func is_standing_down(state: OperationalState, player: int) -> bool:
	return state.turn <= state.stand_down_until[player]
