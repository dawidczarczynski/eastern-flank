class_name InvokeAllianceCommand
extends PoliticalDecisionCommand
## Political decision *Invoke alliance* (TASK-117): an aligned ally of the player enters the war
## and the level rises by `ladder.alliance_escalation`. The same command for both sides (the view
## names it per side, SideDefinition.alliance_decision_name). Rejections after the common ones:
## `unknown_country`, `not_your_ally`, `already_at_war`, `standing_down`, `level_cap` (the level
## would pass `ladder.cap()`, TASK-140).

const TYPE := "invoke_alliance"

var country_id: StringName


func _init(p_country_id: StringName = &"") -> void:
	country_id = p_country_id


func type_id() -> StringName:
	return StringName(TYPE)


func _decision_problem(state: OperationalState, player: int) -> String:
	var country := state.get_country(country_id)
	if country == null:
		return "unknown_country"
	if CountryRules.relation(state, player, country_id) != &"own":
		return "not_your_ally"
	if country.stance != CountryState.ALIGNED:
		return "already_at_war"
	if is_standing_down(state, player):
		return "standing_down"
	if state.escalation_level + state.ladder.alliance_escalation > state.ladder.cap():
		return "level_cap"
	return ""


func _effects(state: OperationalState, player: int) -> Array[Dictionary]:
	var events := CountryRules.set_stance(
		state, country_id, CountryState.BELLIGERENT, player, &"invoked", player
	)
	events.append_array(
		EscalationRules.raise(state, player, &"alliance", state.ladder.alliance_escalation)
	)
	return events


func _country_id() -> StringName:
	return country_id


func to_dict() -> Dictionary:
	return {"type": TYPE, "country": String(country_id)}
