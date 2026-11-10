class_name EscalationRules
extends RefCounted
## Pure escalation rules of the operational layer (TASK-115, GDD "Escalation ladder"): raising and
## lowering the shared level with attribution, allies joining, the threshold that ends the
## operation, calm decay, the sanctuary breach and the rules of engagement for strikes. All state
## changes go through here. No randomness.


## Raises the level by `steps` (capped at the top), attributed to player `by`. Allies join when the
## level reaches `allies_join_level`; reaching the top ends the operation: the other player wins.
## Events: `escalation_changed`, the stance changes, then `operation_ended`.
static func raise(
	state: OperationalState, by: int, cause: StringName, steps: int = 1
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if by != 0 and by != 1:
		push_error("EscalationRules.raise: player %d is not 0 or 1" % by)
		return events
	var ladder := state.ladder
	var previous := state.escalation_level
	var level := mini(previous + steps, ladder.top())
	if steps <= 0 or level == previous:
		return events
	state.escalation_level = level
	state.escalation_caused[by] += level - previous
	state.last_raise_turn[by] = state.turn
	state.raised_this_round = true
	events.append(
		{
			"type": &"escalation_changed",
			"level": level,
			"previous": previous,
			"by": by,
			"cause": cause
		}
	)
	if previous < ladder.allies_join_level and level >= ladder.allies_join_level:
		_join_allies(state, events)
	if level == ladder.top() and state.result.is_empty():
		state.result = {"winner": 1 - by, "reason": &"escalation_threshold"}
		state.pending_battles.clear()
		(
			events
			. append(
				{
					"type": &"operation_ended",
					"winner": 1 - by,
					"reason": &"escalation_threshold",
					"by": by,
				}
			)
		)
	return events


## Lowers the level by one (callers own the floor); attributed to `by` when >= 0 (-1 = nobody).
static func lower(state: OperationalState, by: int, cause: StringName) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state.escalation_level <= 0:
		return events
	var previous := state.escalation_level
	state.escalation_level -= 1
	if by == 0 or by == 1:
		state.escalation_deescalated[by] += 1
	(
		events
		. append(
			{
				"type": &"escalation_changed",
				"level": state.escalation_level,
				"previous": previous,
				"by": by,
				"cause": cause,
			}
		)
	)
	return events


## Calm decay at the round boundary (called when play returns to the first player).
static func end_round(state: OperationalState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	state.calm_rounds = 0 if state.raised_this_round else state.calm_rounds + 1
	var calm_over := state.calm_rounds >= state.ladder.calm_rounds
	if calm_over and state.escalation_level > state.escalation_floor:
		events = lower(state, -1, &"calm")
		state.calm_rounds = 0
	state.raised_this_round = false
	return events


## An enemy sanctuary entered / struck for the first time by `player`: marks the breach, emits
## `sanctuary_breached` and raises the level. [] for anything else.
static func breach(
	state: OperationalState,
	player: int,
	country_id: StringName,
	at: Vector2i,
	formation_id: StringName
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not _would_breach(state, player, country_id):
		return events
	state.get_country(country_id).breached_by[player] = true
	(
		events
		. append(
			{
				"type": &"sanctuary_breached",
				"country": country_id,
				"player": player,
				"at": at,
				"formation_id": formation_id,
			}
		)
	)
	events.append_array(
		raise(state, player, &"sanctuary_breach", state.ladder.sanctuary_breach_escalation)
	)
	return events


## The incidents of a formation that has just entered `steps` (in order, the first from `from`):
## for each entered hex the first breach of an enemy sanctuary (`breach`), then the casus belli of
## a step out of an aligned country into an enemy one (`casus_belli_gained`). Stops once the
## operation has ended. Draws nothing (TASK-116).
static func on_steps(
	state: OperationalState, formation: Formation, steps: Array[Vector2i], from: Vector2i
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var player := formation.owner_id
	var previous := from
	for hex in steps:
		events.append_array(breach(state, player, state.country_at(hex), hex, formation.id))
		if not state.result.is_empty():
			break
		var launch := _launch_country(state, player, previous, hex)
		if launch != null and not launch.casus_belli[1 - player]:
			launch.casus_belli[1 - player] = true
			(
				events
				. append(
					{
						"type": &"casus_belli_gained",
						"country": launch.id,
						"player": 1 - player,
						"formation_id": formation.id,
						"at": hex,
					}
				)
			)
		previous = hex
	return events


## The incidents the `route` of `formation` would cause, in order, assuming nothing else changes
## (pure): `{type: &"sanctuary_breach", country, at, steps, ends_operation}` – the first entry of
## a not yet breached enemy sanctuary; `ends_operation` when the level plus all steps so far reach
## the top – and `{type: &"casus_belli", country, for_player, at}` – a step out of an aligned
## country into an enemy one whose flag is not set yet.
static func route_incidents(
	state: OperationalState, formation: Formation, route: Array[Vector2i]
) -> Array[Dictionary]:
	var incidents: Array[Dictionary] = []
	var player := formation.owner_id
	var breached := {}
	var flagged := {}
	var level := state.escalation_level
	var previous := formation.coord
	for hex in route:
		var country_id := state.country_at(hex)
		if not breached.has(country_id) and _would_breach(state, player, country_id):
			breached[country_id] = true
			var steps := state.ladder.sanctuary_breach_escalation
			level += steps
			(
				incidents
				. append(
					{
						"type": &"sanctuary_breach",
						"country": country_id,
						"at": hex,
						"steps": steps,
						"ends_operation": level >= state.ladder.top(),
					}
				)
			)
		var launch := _launch_country(state, player, previous, hex)
		if launch != null and not launch.casus_belli[1 - player] and not flagged.has(launch.id):
			flagged[launch.id] = true
			(
				incidents
				. append(
					{
						"type": &"casus_belli",
						"country": launch.id,
						"for_player": 1 - player,
						"at": hex,
					}
				)
			)
		previous = hex
	return incidents


## The country `player` launches from with this step: aligned with the player at `from` while
## `to` lies in a country enemy to the player; else null.
static func _launch_country(
	state: OperationalState, player: int, from: Vector2i, to: Vector2i
) -> CountryState:
	var country := state.get_country(state.country_at(from))
	if (
		country == null
		or country.stance != CountryState.ALIGNED
		or country.side != player
		or CountryRules.relation(state, player, state.country_at(to)) != &"enemy"
	):
		return null
	return country


## "" when `player` may strike a `target_class` target on `coord`, else why not: `own_soil`,
## `closed_country` or `roe_class`.
static func strike_allowed(
	state: OperationalState, player: int, coord: Vector2i, target_class: StringName
) -> String:
	if CountryRules.relation(state, player, state.country_at(coord)) == &"own":
		return "own_soil"
	if not CountryRules.may_strike(state, player, coord):
		return "closed_country"
	if not state.ladder.strike_classes_at(state.escalation_level).has(target_class):
		return "roe_class"
	return ""


## Steps a strike on `coord` by `player` would cause (breach + urban).
static func strike_escalation(state: OperationalState, player: int, coord: Vector2i) -> int:
	var steps := 0
	if _would_breach(state, player, state.country_at(coord)):
		steps += state.ladder.sanctuary_breach_escalation
	if _is_urban(state, coord):
		steps += state.ladder.urban_strike_escalation
	return steps


## Applies the escalation of a resolved strike: `breach`, then `raise` for an urban hex.
static func on_strike(state: OperationalState, player: int, coord: Vector2i) -> Array[Dictionary]:
	var events := breach(state, player, state.country_at(coord), coord, &"")
	if _is_urban(state, coord) and state.result.is_empty():
		events.append_array(
			raise(state, player, &"urban_strike", state.ladder.urban_strike_escalation)
		)
	return events


static func _is_urban(state: OperationalState, coord: Vector2i) -> bool:
	return state.grid.get_terrain(coord) == Terrain.Type.URBAN


## Whether a hit by `player` on this country would be a first breach of an enemy sanctuary.
static func _would_breach(state: OperationalState, player: int, country_id: StringName) -> bool:
	var country := state.get_country(country_id)
	return (
		country != null
		and country.definition.sanctuary
		and CountryRules.relation(state, player, country_id) == &"enemy"
		and not country.breached_by[player]
	)


static func _join_allies(state: OperationalState, events: Array[Dictionary]) -> void:
	for country in state.countries:
		if country.stance == CountryState.ALIGNED:
			events.append_array(
				CountryRules.set_stance(
					state, country.id, CountryState.BELLIGERENT, country.side, &"ladder", -1
				)
			)
		elif country.stance == CountryState.NEUTRAL and country.leaning >= 0:
			events.append_array(
				CountryRules.set_stance(
					state, country.id, CountryState.ALIGNED, country.leaning, &"ladder", -1
				)
			)
