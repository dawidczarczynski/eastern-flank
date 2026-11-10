class_name DemandNeutralityCommand
extends PoliticalDecisionCommand
## Political decision *Demand neutrality* (TASK-117): an ultimatum that makes a country aligned
## with the other side neutral. No escalation, not blocked by standing down. Rejections after the
## common ones: `unknown_country`, `not_hostile`, `refuses_ultimatum`
## (CountrySetup.accepts_ultimatum false), `level_too_high` (level above
## `ladder.demand_neutrality_max_level`), `troops_present` (a formation of the other player stands
## in the country).

const TYPE := "demand_neutrality"

var country_id: StringName


func _init(p_country_id: StringName = &"") -> void:
	country_id = p_country_id


func type_id() -> StringName:
	return StringName(TYPE)


func _decision_problem(state: OperationalState, player: int) -> String:
	var country := state.get_country(country_id)
	if country == null:
		return "unknown_country"
	if CountryRules.relation(state, player, country_id) != &"hostile":
		return "not_hostile"
	if not country.accepts_ultimatum:
		return "refuses_ultimatum"
	if state.escalation_level > state.ladder.demand_neutrality_max_level:
		return "level_too_high"
	for formation in state.formations:
		if formation.owner_id != player and state.country_at(formation.coord) == country_id:
			return "troops_present"
	return ""


func _effects(state: OperationalState, player: int) -> Array[Dictionary]:
	return CountryRules.set_stance(
		state, country_id, CountryState.NEUTRAL, -1, &"neutrality_demanded", player
	)


func _country_id() -> StringName:
	return country_id


func to_dict() -> Dictionary:
	return {"type": TYPE, "country": String(country_id)}
