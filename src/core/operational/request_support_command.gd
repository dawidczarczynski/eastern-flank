class_name RequestSupportCommand
extends PoliticalDecisionCommand
## Political decision *Request support* (TASK-121, GDD "Outside support"): asks a supporter for a
## package. Rejections after the common ones: `SupportRules.request_problem`. Effects: the package
## is marked requested with all its formations waiting, `support_requested`, then the escalation
## cost (cause `support_request`) unless the request is a response to the other side's.

const TYPE := "request_support"

var package_id: StringName


func _init(package: StringName = &"") -> void:
	package_id = package


func type_id() -> StringName:
	return StringName(TYPE)


func _decision_problem(state: OperationalState, player: int) -> String:
	return SupportRules.request_problem(state, player, package_id)


func _effects(state: OperationalState, player: int) -> Array[Dictionary]:
	var support := state.get_support(package_id)
	var package := support.definition
	var cost := 0 if SupportRules.is_response(state, package_id) else package.escalation_cost
	var responses := SupportRules.open_responses(state, package_id)
	support.requested_turn = state.turn
	support.waiting = package.formations.duplicate()
	var events: Array[Dictionary] = [
		{
			"type": &"support_requested",
			"package": package_id,
			"supporter": package.supporter.id,
			"player": player,
			"delivery_turn": state.turn + package.delay_turns,
			"responses": responses,
		}
	]
	if cost > 0:
		events.append_array(EscalationRules.raise(state, player, &"support_request", cost))
	return events


func to_dict() -> Dictionary:
	return {"type": TYPE, "package": String(package_id)}
