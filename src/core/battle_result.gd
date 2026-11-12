class_name BattleResult
extends RefCounted
## What a finished battle hands back to the operational layer – the only channel from a battle
## into the operation (ADR 0015).
## JSON form (`to_dict`): {"winner", "reason", "turns", "resolution", "field_holder", "retreat",
## "companies": [Company]}.
## `from_dict` returns null on anything malformed.

const PLAYED := &"played"
const AUTO := &"auto"
## The player left the battle unfinished and the rest was auto-resolved from the state reached
## (AutoResolve.resolve_from); the commands played so far are in the campaign record.
const CONCLUDED := &"concluded"


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
## &"played" (a tactical battle was fought), &"auto" (AutoResolve, TASK-120) or &"concluded"
## (left halfway, the rest auto-resolved). The consequences
## (TASK-095) never read it.
var resolution: StringName = &"played"
## Player who holds the field afterwards: the winner, on a draw the defender, -1 without an
## attacker (`settle`).
var field_holder: int = -1
## Player whose formation retreats: the loser when it has a company left, else -1 (`settle`).
var retreat: int = -1
## One entry per BattleSetup company, in the same order.
var companies: Array[Company] = []


## Result of the battle `state` that `Scenario.from_setup(setup)` started: company i of the
## setup is unit id i + 1.
static func from_battle(setup: BattleSetup, state: GameState) -> BattleResult:
	var result := BattleResult.new()
	result.winner = state.winner
	result.reason = state.end_reason
	result.turns = state.turn
	result.resolution = PLAYED
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
	result.settle(setup)
	return result


## Fills `field_holder` and `retreat` from `winner`, the companies' `strength_end` and the
## setup's attacker – the one place the rule exists, for played and auto-resolved battles.
func settle(setup: BattleSetup) -> void:
	if winner >= 0:
		field_holder = winner
	elif setup.attacker >= 0:
		field_holder = 1 - setup.attacker
	else:
		field_holder = -1
	retreat = -1
	if winner < 0:
		return
	var loser := 1 - winner
	for company in companies:
		if company.player == loser and company.strength_end > 0:
			retreat = loser
			return


func to_dict() -> Dictionary:
	var company_list: Array[Dictionary] = []
	for company in companies:
		company_list.append(company.to_dict())
	return {
		"winner": winner,
		"reason": String(reason),
		"turns": turns,
		"resolution": String(resolution),
		"field_holder": field_holder,
		"retreat": retreat,
		"companies": company_list,
	}


## null when a field is missing or has the wrong type (JSON floats are accepted when integral).
static func from_dict(d: Dictionary) -> BattleResult:
	var winner_value: Variant = CommandCodec.to_int_or_null(d.get("winner"))
	var turns_value: Variant = CommandCodec.to_int_or_null(d.get("turns"))
	var holder_value: Variant = CommandCodec.to_int_or_null(d.get("field_holder"))
	var retreat_value: Variant = CommandCodec.to_int_or_null(d.get("retreat"))
	var reason_value: Variant = d.get("reason")
	var resolution_value: Variant = d.get("resolution")
	var company_list: Variant = d.get("companies")
	if winner_value == null or turns_value == null or not reason_value is String:
		return null
	if holder_value == null or retreat_value == null or not resolution_value is String:
		return null
	if not [PLAYED, AUTO, CONCLUDED].has(StringName(resolution_value as String)):
		return null
	if not company_list is Array:
		return null
	var result := BattleResult.new()
	result.winner = winner_value
	result.reason = StringName(reason_value)
	result.turns = turns_value
	result.resolution = StringName(resolution_value as String)
	result.field_holder = holder_value
	result.retreat = retreat_value
	for entry: Variant in company_list:
		var company := Company.from_dict(entry)
		if company == null:
			return null
		result.companies.append(company)
	return result
