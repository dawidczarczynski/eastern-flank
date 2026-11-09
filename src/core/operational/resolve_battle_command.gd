class_name ResolveBattleCommand
extends OperationalCommand
## Closes the first pending contact battle with its result (TASK-094a): removes it from the
## queue and applies the consequences (BattleConsequences, TASK-095). The result must belong to
## that battle (`result_mismatch`); an `auto` result must equal
## `AutoResolve.resolve` of it (`auto_mismatch`, TASK-120).

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
	# An auto result is a pure function of the pending setup (TASK-120): recompute it. A played
	# result cannot be checked here (the tactical commands live in the campaign record).
	if result.resolution == BattleResult.AUTO:
		var expected := AutoResolve.resolve(setup)
		if expected == null or expected.to_dict() != result.to_dict():
			return "auto_mismatch"
	return ""


func apply(state: OperationalState) -> Array[Dictionary]:
	var setup: BattleSetup = state.pending_battles.pop_front()
	var ids := ContactBattle.formation_ids(setup)
	var events: Array[Dictionary] = [
		{
			"type": &"battle_resolved",
			"attacker_id": ids[0],
			"defender_id": ids[1],
			"winner": result.winner,
			"reason": result.reason,
		}
	]
	events.append_array(BattleConsequences.apply(state, setup, result))
	return events


func to_dict() -> Dictionary:
	return {"type": TYPE, "result": result.to_dict() if result != null else {}}
