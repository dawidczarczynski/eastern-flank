class_name EscalateCommand
extends PoliticalDecisionCommand
## Political decision *Escalate* (TASK-117): authorise wider strikes – raises the level by
## `ladder.decision_escalation`. Rejections after the common ones: `standing_down`, `threshold`.

const TYPE := "escalate"


func type_id() -> StringName:
	return StringName(TYPE)


func _decision_problem(state: OperationalState, player: int) -> String:
	if is_standing_down(state, player):
		return "standing_down"
	if state.escalation_level + state.ladder.decision_escalation >= state.ladder.top():
		return "threshold"
	return ""


func _effects(state: OperationalState, player: int) -> Array[Dictionary]:
	return EscalationRules.raise(state, player, &"decision", state.ladder.decision_escalation)


func to_dict() -> Dictionary:
	return {"type": TYPE}
