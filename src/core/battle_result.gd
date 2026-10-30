class_name BattleResult
extends RefCounted
## What a finished battle hands back to the operational layer – the only channel from a battle
## into the operation (ADR 0015).
## JSON form (`to_dict`): {"winner", "reason", "turns", "companies": [Company]}.
## `from_dict` returns null on anything malformed.


## Strength of one company at the start and the end of the battle (losses = start - end).
class Company:
	extends RefCounted
	var player: int
	var unit_type: StringName
	## BattleSetup.Company.ref ("" in scenario battles).
	var ref: String = ""
	var strength_start: int
	## 0 = destroyed.
	var strength_end: int

	func losses() -> int:
		return strength_start - strength_end

	func to_dict() -> Dictionary:
		return {
			"player": player,
			"unit_type": String(unit_type),
			"ref": ref,
			"strength_start": strength_start,
			"strength_end": strength_end,
		}

	static func from_dict(d: Variant) -> Company:
		if not d is Dictionary:
			return null
		var player_value: Variant = CommandCodec.to_int_or_null(d.get("player"))
		var start_value: Variant = CommandCodec.to_int_or_null(d.get("strength_start"))
		var end_value: Variant = CommandCodec.to_int_or_null(d.get("strength_end"))
		var type_value: Variant = d.get("unit_type")
		var ref_value: Variant = d.get("ref")
		if player_value == null or start_value == null or end_value == null:
			return null
		if not type_value is String or not ref_value is String:
			return null
		var company := Company.new()
		company.player = player_value
		company.unit_type = StringName(type_value)
		company.ref = ref_value
		company.strength_start = start_value
		company.strength_end = end_value
		return company


## Winning player; -1 = draw (or the battle is not over).
var winner: int = -1
## Why the battle ended (GameState.end_reason): &"eliminated", &"objective_taken",
## &"enemy_destroyed" or &"turn_limit"; &"" while the battle runs.
var reason: StringName = &""
## Turns played (GameState.turn when the battle ended).
var turns: int = 0
## One entry per BattleSetup company, in the same order.
var companies: Array[Company] = []


## Result of the battle `state` that `Scenario.from_setup(setup)` started: company i of the
## setup is unit id i + 1.
static func from_battle(setup: BattleSetup, state: GameState) -> BattleResult:
	var result := BattleResult.new()
	result.winner = state.winner
	result.reason = state.end_reason
	result.turns = state.turn
	for i in setup.companies.size():
		var planned := setup.companies[i]
		var unit := state.get_unit(i + 1)
		var company := Company.new()
		company.player = planned.player
		company.unit_type = planned.unit_type
		company.ref = planned.ref
		company.strength_start = planned.strength
		company.strength_end = maxi(unit.hp, 0) if unit != null else 0
		result.companies.append(company)
	return result


func to_dict() -> Dictionary:
	var company_list: Array[Dictionary] = []
	for company in companies:
		company_list.append(company.to_dict())
	return {
		"winner": winner,
		"reason": String(reason),
		"turns": turns,
		"companies": company_list,
	}


## null when a field is missing or has the wrong type (JSON floats are accepted when integral).
static func from_dict(d: Dictionary) -> BattleResult:
	var winner_value: Variant = CommandCodec.to_int_or_null(d.get("winner"))
	var turns_value: Variant = CommandCodec.to_int_or_null(d.get("turns"))
	var reason_value: Variant = d.get("reason")
	var company_list: Variant = d.get("companies")
	if winner_value == null or turns_value == null or not reason_value is String:
		return null
	if not company_list is Array:
		return null
	var result := BattleResult.new()
	result.winner = winner_value
	result.reason = StringName(reason_value)
	result.turns = turns_value
	for entry: Variant in company_list:
		var company := Company.from_dict(entry)
		if company == null:
			return null
		result.companies.append(company)
	return result
