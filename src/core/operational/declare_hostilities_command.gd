class_name DeclareHostilitiesCommand
extends PoliticalDecisionCommand
## Political decision *Declare hostilities* (TASK-117): a neutral or opposing aligned country
## becomes belligerent against the declarer. Free with a casus belli, else it raises the level by
## `ladder.declaration_escalation`. Rejections after the common ones: `unknown_country`,
## `own_country`, `already_at_war`, `standing_down`, `level_cap` (the level would pass
## `ladder.cap()`, TASK-140).

const TYPE := "declare_hostilities"

var country_id: StringName


func _init(p_country_id: StringName = &"") -> void:
	country_id = p_country_id


func type_id() -> StringName:
	return StringName(TYPE)


func _decision_problem(state: OperationalState, player: int) -> String:
	if state.get_country(country_id) == null:
		return "unknown_country"
	match CountryRules.relation(state, player, country_id):
		&"own":
			return "own_country"
		&"enemy":
			return "already_at_war"
	if is_standing_down(state, player):
		return "standing_down"
	if state.escalation_level + cost(state, player, country_id) > state.ladder.cap():
		return "level_cap"
	return ""


## Escalation steps declaring on the country costs `player` (0 with a casus belli).
static func cost(state: OperationalState, player: int, target: StringName) -> int:
	var country := state.get_country(target)
	if country != null and country.casus_belli[player]:
		return 0
	return state.ladder.declaration_escalation


func _effects(state: OperationalState, player: int) -> Array[Dictionary]:
	var steps := cost(state, player, country_id)
	var events := CountryRules.set_stance(
		state, country_id, CountryState.BELLIGERENT, 1 - player, &"declared", player
	)
	state.get_country(country_id).declared_by[player] = true
	if steps > 0:
		events.append_array(EscalationRules.raise(state, player, &"declaration", steps))
	return events


func _country_id() -> StringName:
	return country_id


func to_dict() -> Dictionary:
	return {"type": TYPE, "country": String(country_id)}
