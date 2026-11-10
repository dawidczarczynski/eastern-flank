class_name CountryRules
extends RefCounted
## Pure political rules of the operational layer (TASK-114, GDD "Countries and stances"): the
## player-relative relation of a country, who may enter / strike a hex, and the single place that
## changes a stance. No randomness.


## &"own", &"enemy", &"hostile", &"neutral" or &"none" (empty / unknown id) – seen from `player`.
static func relation(state: OperationalState, player: int, country_id: StringName) -> StringName:
	var country := state.get_country(country_id)
	if country == null:
		return &"none"
	if country.stance == CountryState.NEUTRAL:
		return &"neutral"
	if country.side == player:
		return &"own"
	return &"enemy" if country.stance == CountryState.BELLIGERENT else &"hostile"


## Whether `player` may enter the hex (route through it, stand on it).
static func may_enter(state: OperationalState, player: int, coord: Vector2i) -> bool:
	return may_enter_country(state, player, state.country_at(coord))


## Whether `player` may enter the hexes of a country (the same answer for every hex of it).
static func may_enter_country(state: OperationalState, player: int, country_id: StringName) -> bool:
	match relation(state, player, country_id):
		&"own", &"none":
			return true
		&"enemy":
			var country := state.get_country(country_id)
			return (
				not country.definition.sanctuary
				or country.breached_by[player]
				or state.escalation_level >= state.ladder.sanctuary_open_level
			)
	return false


## Whether `player` may strike a target on the hex: never own soil, otherwise as `may_enter`.
static func may_strike(state: OperationalState, player: int, coord: Vector2i) -> bool:
	if relation(state, player, state.country_at(coord)) == &"own":
		return false
	return may_enter(state, player, coord)


## The only place that changes a stance. Legal: neutral -> aligned / belligerent S; aligned S ->
## belligerent S; aligned S -> neutral. Anything else: push_error, no change, []. `cause` is a tag
## for the event, `by` the acting player or -1. casus_belli resets, the other flags stay. A country
## that becomes belligerent on its leaning side brings its contribution once (Reinforcements,
## TASK-118): the `formation_joined` / `formation_join_failed` events follow the stance event.
static func set_stance(
	state: OperationalState,
	country_id: StringName,
	stance: StringName,
	side: int,
	cause: StringName,
	by: int
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var country := state.get_country(country_id)
	if country == null:
		push_error("CountryRules: unknown country '%s'" % country_id)
		return events
	var error := transition_problem(country, stance, side)
	if error != "":
		push_error("CountryRules: %s" % error)
		return events
	var previous_stance := country.stance
	var previous_side := country.side
	country.stance = stance
	country.side = side
	country.casus_belli = [false, false]
	var event := {
		"type": &"country_stance_changed",
		"country": country_id,
		"stance": stance,
		"side": side,
		"previous_stance": previous_stance,
		"previous_side": previous_side,
		"cause": cause,
		"by": by,
	}
	events.append(event)
	if (
		stance == CountryState.BELLIGERENT
		and side == country.leaning
		and not country.contributed
		and not country.contribution.is_empty()
	):
		country.contributed = true
		var placed := Reinforcements.place(state, country.contribution, side, &"contribution")
		events.append_array(placed["events"])
	return events


## "" when the transition is legal, otherwise the reason (shown by the debug panel).
static func transition_problem(country: CountryState, stance: StringName, side: int) -> String:
	var label := String(country.id)
	if not CountryState.STANCES.has(stance):
		return "unknown stance '%s'" % stance
	if stance == CountryState.NEUTRAL:
		if side != -1:
			return "%s: a neutral country has no side" % label
		if country.stance != CountryState.ALIGNED:
			return "%s: only an aligned country can become neutral" % label
		return ""
	if side != 0 and side != 1:
		return "%s: side %d is not 0 or 1" % [label, side]
	match country.stance:
		CountryState.NEUTRAL:
			return ""
		CountryState.ALIGNED:
			if stance == CountryState.BELLIGERENT and side == country.side:
				return ""
			return "%s: an aligned country can only become belligerent on its own side" % label
	return "%s: a belligerent country stays at war" % label
