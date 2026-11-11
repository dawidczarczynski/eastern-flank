class_name NuclearStrikeCommand
extends PoliticalDecisionCommand
## Political decision *Use nuclear weapon* (TASK-140, GDD "Escalation ladder"): the last resort –
## takes the level from `ladder.cap()` to the top and ends the operation with reason `nuclear_use`;
## nobody wins (EscalationRules.nuclear_use). Rejections, in order: `operation_over`,
## `not_nuclear_power` (the side's `may_use_nuclear` is false), `level_too_low` (level below
## the cap), `no_collapse` (CollapseRules.in_collapse), then the common ones (`battle_pending`,
## `no_decisions_left`). Not blocked by standing down. Counts as the turn's decision.

const TYPE := "nuclear_strike"


func type_id() -> StringName:
	return StringName(TYPE)


func validate(state: OperationalState) -> String:
	if not state.result.is_empty():
		return "operation_over"
	var player := state.current_player
	if not state.may_use_nuclear[player]:
		return "not_nuclear_power"
	if state.escalation_level < state.ladder.cap():
		return "level_too_low"
	if not CollapseRules.in_collapse(state, player):
		return "no_collapse"
	return super.validate(state)


func _effects(state: OperationalState, player: int) -> Array[Dictionary]:
	return EscalationRules.nuclear_use(state, player)


func to_dict() -> Dictionary:
	return {"type": TYPE}
