class_name ResolveBattleCommand
extends OperationalCommand
## Closes the first pending contact battle with its result (TASK-094a, v0): removes it from the
## queue. No consequences yet (TASK-095). The result must belong to that battle.

const TYPE := "resolve_battle"

var result: BattleResult


func _init(p_result: BattleResult = null) -> void:
	result = p_result


func validate(state: OperationalState) -> String:
	if state.pending_battles.is_empty():
		return "no_pending_battle"
	var setup := state.pending_battles[0]
	if result == null or result.companies.size() != setup.companies.size():
		return "result_mismatch"
	for i in setup.companies.size():
		var planned := setup.companies[i]
		var reported := result.companies[i]
		if reported.ref != planned.ref or reported.strength_start != planned.strength:
			return "result_mismatch"
	return ""


func apply(state: OperationalState) -> Array[Dictionary]:
	var setup: BattleSetup = state.pending_battles.pop_front()
	var attacker_id: StringName = &""
	var defender_id: StringName = &""
	for company in setup.companies:
		if company.player == setup.attacker:
			attacker_id = _formation_of(company)
		else:
			defender_id = _formation_of(company)
	return [
		{
			"type": &"battle_resolved",
			"attacker_id": attacker_id,
			"defender_id": defender_id,
			"winner": result.winner,
			"reason": result.reason,
		}
	]


func to_dict() -> Dictionary:
	return {"type": TYPE, "result": result.to_dict() if result != null else {}}


## Formation id of a company ref "<formation id>/<n>".
static func _formation_of(company: BattleSetup.Company) -> StringName:
	return StringName(company.ref.rsplit("/", true, 1)[0])
