class_name StandDownCommand
extends PoliticalDecisionCommand
## Political decision *Stand down* (TASK-117): lowers the level by one and bars the player from the
## escalating decisions for `ladder.stand_down_cooldown_turns` turns. Rejections after the common
## ones: `at_floor`, `recent_escalation` (the player raised the level this or the previous round),
## `occupying` (a formation stands in a country the player breached or declared hostilities on).

const TYPE := "stand_down"


func type_id() -> StringName:
	return StringName(TYPE)


func _decision_problem(state: OperationalState, player: int) -> String:
	if state.escalation_level <= 0:
		return "at_floor"
	if state.last_raise_turn[player] >= state.turn - 1:
		return "recent_escalation"
	for formation in state.formations:
		if formation.owner_id != player:
			continue
		var country := state.get_country(state.country_at(formation.coord))
		if country != null and (country.breached_by[player] or country.declared_by[player]):
			return "occupying"
	return ""


func _effects(state: OperationalState, player: int) -> Array[Dictionary]:
	state.stand_down_until[player] = state.turn + state.ladder.stand_down_cooldown_turns
	return EscalationRules.lower(state, player, &"stand_down")


func to_dict() -> Dictionary:
	return {"type": TYPE}
