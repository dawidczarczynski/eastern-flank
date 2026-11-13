class_name Operation
extends RefCounted
## Builds an OperationalState from an OperationDefinition (TASK-092b). Takes no human-side
## parameter: the operation is the same whichever side the human plays.

## Operations shipped in data/operations/.
const NAMES: Array[StringName] = [&"suwalki_gap"]


## The operation data/operations/<operation_id>.tres on its imported map; null with push_error
## when it is unknown or invalid.
static func build(operation_id: StringName, seed_value: int) -> OperationalState:
	if not NAMES.has(operation_id):
		push_error("Operation: unknown operation '%s'" % operation_id)
		return null
	var definition := OperationDefinition.find(operation_id)
	if definition == null:
		push_error("Operation: cannot load operation '%s'" % operation_id)
		return null
	return from_definition(definition, seed_value)


## A state from the given data; `grid` = null loads the definition's map
## (ImportedMap.find(map_id).to_grid()). Null with push_error when the data is invalid.
static func from_definition(
	definition: OperationDefinition,
	seed_value: int,
	grid: HexGrid = null,
	country_map: Dictionary = {}
) -> OperationalState:
	if grid == null:
		var map := ImportedMap.find(definition.map_id)
		if map == null:
			push_error("Operation '%s': unknown map '%s'" % [definition.id, definition.map_id])
			return null
		grid = map.to_grid()
		if grid == null:
			return null
		if country_map.is_empty():
			country_map = _map_countries(map)
			if country_map.has(&"error"):
				push_error("Operation '%s': %s" % [definition.id, country_map[&"error"]])
				return null
	var error := _problem(definition, grid, country_map)
	if error != "":
		push_error("Operation '%s': %s" % [definition.id, error])
		return null
	var state := OperationalState.new()
	state.operation_id = definition.id
	state.operation_name = definition.display_name
	state.map_id = definition.map_id
	state.start_date = definition.start_date
	state.front_range = definition.front_range
	state.initial_posture = definition.initial_posture
	state.grid = grid
	for index in definition.sides.size():
		var side: SideDefinition = definition.sides[index]
		state.player_sides.append(side.id)
		state.player_factions.append(side.lead_faction)
		state.may_use_nuclear[index] = side.may_use_nuclear
	state.first_player = definition.first_player
	state.current_player = definition.first_player
	state.turn = 1
	state.escalation_level = definition.initial_escalation
	state.escalation_floor = definition.initial_escalation
	state.decisions_left = state.ladder.decisions_per_turn
	state.rng.seed = seed_value
	state.country_map = country_map
	for setup in definition.countries:
		state.countries.append(CountryState.from_setup(setup))
	for placement in definition.formations:
		var formation := Formation.from_placement(placement, definition.initial_posture)
		state.formations.append(formation)
		state.fielded_strength[formation.owner_id] += formation.max_strength()
	_add_strikes(state, definition)
	state.ai_goals = definition.ai_goals.duplicate()
	state.definition = definition
	HexControl.setup(state)
	return state


static func _add_strikes(state: OperationalState, definition: OperationDefinition) -> void:
	state.strike_means = StrikeMeansDefinition.shipped()
	state.air_defence_types = AirDefenceDefinition.shipped()
	for placement in definition.installations:
		state.installations.append(Installation.from_placement(placement))
	for player in 2:
		if player < definition.strike_stock.size():
			state.strike_stock[player] = _copy_counts(definition.strike_stock[player])
		if player < definition.strike_resupply.size():
			state.strike_resupply[player] = _copy_counts(definition.strike_resupply[player])
	state.strikes_per_turn = definition.strikes_per_turn
	state.strikes_left = definition.strikes_per_turn
	state.suppression_rounds = definition.suppression_rounds
	state.repair_per_round = definition.repair_per_round


static func _copy_counts(source: Dictionary) -> Dictionary:
	var result := {}
	for key: Variant in source:
		result[StringName(key)] = int(source[key])
	return result


## "" when the definition is consistent with itself, the map and the faction rosters.
static func _problem(
	definition: OperationDefinition, grid: HexGrid, country_map: Dictionary
) -> String:
	var ladder := EscalationLadder.shipped()
	if definition.initial_escalation < 0 or definition.initial_escalation > ladder.top() - 1:
		return (
			"initial_escalation %d outside 0 .. %d"
			% [definition.initial_escalation, ladder.top() - 1]
		)
	var sides_error := _sides_problem(definition)
	if sides_error != "":
		return sides_error
	if OperationalPosture.find(definition.initial_posture) == null:
		return "unknown initial posture '%s'" % definition.initial_posture
	var countries_error := _countries_problem(definition, country_map)
	if countries_error != "":
		return countries_error
	var ids := {}
	var occupied := {}
	for placement in definition.formations:
		if placement == null:
			return "empty placement"
		var error := _placement_problem(definition, grid, placement)
		if error != "":
			return "formation '%s': %s" % [placement.id, error]
		if ids.has(placement.id):
			return "duplicate formation id '%s'" % placement.id
		ids[placement.id] = true
		if occupied.has(placement.coord):
			var other: StringName = occupied[placement.coord]
			return "'%s' and '%s' on one tile %s" % [other, placement.id, placement.coord]
		occupied[placement.coord] = placement.id
	var closed_error := _closed_placement_problem(definition, country_map)
	if closed_error != "":
		return closed_error
	var strike_error := _strikes_problem(definition, grid)
	if strike_error != "":
		return strike_error
	var victory_error := _victory_problem(definition, grid)
	if victory_error != "":
		return victory_error
	var goals_error := _goals_problem(definition, grid)
	if goals_error != "":
		return goals_error
	return _contributions_problem(definition, grid, country_map, ids)


## Coord -> country id of every hex of `map` that belongs to a country (what `from_definition`
## builds itself when it loads the grid); {} for a map without countries. For callers that pass
## their own `grid` (the staff map shares one grid with its view).
static func map_countries(map: ImportedMap) -> Dictionary:
	var result := _map_countries(map)
	return {} if result.has(&"error") else result


## country id of every hex of the map; a dictionary with the key &"error" when an ISO code of the
## map has no CountryDefinition.
static func _map_countries(map: ImportedMap) -> Dictionary:
	var result := {}
	var by_iso := {}
	for code in map.countries:
		var country := CountryDefinition.find_by_iso(code)
		if country == null:
			return {&"error": "map country '%s' has no CountryDefinition" % code}
		by_iso[code] = country.id
	for row in map.height:
		for col in map.width:
			var coord := MapGenerator.offset_to_axial(col, row)
			var code := map.country_at(coord)
			if code != "":
				result[coord] = by_iso[code]
	return result


static func _countries_problem(definition: OperationDefinition, country_map: Dictionary) -> String:
	var seen := {}
	for setup in definition.countries:
		if setup == null or setup.country == null:
			return "empty country setup"
		var id := setup.country.id
		if seen.has(id):
			return "duplicate country '%s'" % id
		seen[id] = true
		if not CountryState.STANCES.has(setup.stance):
			return "country '%s': unknown stance '%s'" % [id, setup.stance]
		if setup.leaning < -1 or setup.leaning > 1:
			return "country '%s': leaning %d outside -1 .. 1" % [id, setup.leaning]
		if setup.stance == CountryState.NEUTRAL and setup.side != -1:
			return "country '%s': neutral with side %d" % [id, setup.side]
		if setup.stance != CountryState.NEUTRAL and setup.side != 0 and setup.side != 1:
			return "country '%s': %s with side %d" % [id, setup.stance, setup.side]
	for country_id: StringName in country_map.values():
		if not seen.has(country_id):
			return "country '%s' on the map has no setup" % country_id
	return ""


## Contributions (TASK-118): each placement is valid like a start one, belongs to the country's
## leaning side, lies on its soil and has an id unused anywhere in the operation.
static func _contributions_problem(
	definition: OperationDefinition, grid: HexGrid, country_map: Dictionary, ids: Dictionary
) -> String:
	for setup in definition.countries:
		var label := "country '%s'" % setup.country.id
		if not setup.contribution.is_empty() and setup.leaning == -1:
			return "%s: a contribution without a leaning" % label
		for placement in setup.contribution:
			if placement == null:
				return "%s: empty contribution placement" % label
			var error := _contribution_problem(definition, grid, country_map, setup, placement)
			if error == "" and ids.has(placement.id):
				error = "duplicate formation id '%s'" % placement.id
			if error != "":
				return "%s: contribution '%s': %s" % [label, placement.id, error]
			ids[placement.id] = true
	return ""


static func _contribution_problem(
	definition: OperationDefinition,
	grid: HexGrid,
	country_map: Dictionary,
	setup: CountrySetup,
	placement: FormationPlacement
) -> String:
	if placement.player != setup.leaning:
		return "player %d is not the leaning side %d" % [placement.player, setup.leaning]
	var error := _placement_problem(definition, grid, placement)
	if error != "":
		return error
	if country_map.get(placement.coord, &"") != setup.country.id:
		return "%s is not in the country" % placement.coord
	return ""


## A formation may not start on a hex that is closed to its player.
static func _closed_placement_problem(
	definition: OperationDefinition, country_map: Dictionary
) -> String:
	if definition.countries.is_empty():
		return ""
	var probe := OperationalState.new()
	probe.country_map = country_map
	for setup in definition.countries:
		probe.countries.append(CountryState.from_setup(setup))
	for placement in definition.formations:
		if not CountryRules.may_enter(probe, placement.player, placement.coord):
			return "formation '%s' starts on a closed hex %s" % [placement.id, placement.coord]
	return ""


## AI goals (TASK-102a): a known player and role, a positive weight, a unique id and an existing
## installation or a hex of the map.
static func _goals_problem(definition: OperationDefinition, grid: HexGrid) -> String:
	var ids := {}
	for goal in definition.ai_goals:
		if goal == null:
			return "empty AI goal"
		var label := "AI goal '%s'" % goal.id
		if ids.has(goal.id):
			return "duplicate AI goal id '%s'" % goal.id
		ids[goal.id] = true
		if goal.player != 0 and goal.player != 1:
			return "%s: player %d" % [label, goal.player]
		if not AiGoal.ROLES.has(goal.role):
			return "%s: unknown role '%s'" % [label, goal.role]
		if goal.weight < 1:
			return "%s: weight %d must be positive" % [label, goal.weight]
		if goal.objective_id != &"":
			if not definition.objectives.any(
				func(o: OperationObjective) -> bool: return o.id == goal.objective_id
			):
				return "%s: unknown objective '%s'" % [label, goal.objective_id]
		elif goal.installation_id != &"":
			var found := false
			for placement in definition.installations:
				found = found or placement.id == goal.installation_id
			if not found:
				return "%s: unknown installation '%s'" % [label, goal.installation_id]
		elif not grid.has_tile(goal.coord):
			return "%s: hex %s is not on the map" % [label, goal.coord]
	return ""


## Victory data (TASK-107a): objectives on the map with positive points, the Gap chain (3+ land
## road hexes, consecutive ones neighbours), round limit, rounds to win, draw margin.
static func _victory_problem(definition: OperationDefinition, grid: HexGrid) -> String:
	if definition.round_limit < 1:
		return "round_limit %d must be at least 1" % definition.round_limit
	if definition.closed_rounds_to_win < 1:
		return "closed_rounds_to_win %d must be at least 1" % definition.closed_rounds_to_win
	if definition.draw_margin < 0 or definition.escalation_penalty < 0:
		return "draw_margin / escalation_penalty must not be negative"
	var ids := {}
	for objective in definition.objectives:
		if objective == null:
			return "empty objective"
		var label := "objective '%s'" % objective.id
		if ids.has(objective.id):
			return "duplicate objective id '%s'" % objective.id
		ids[objective.id] = true
		if objective.points < 1:
			return "%s: points %d must be positive" % [label, objective.points]
		if not OperationObjective.HOLDER_RULES.has(objective.holder_rule):
			return "%s: unknown holder_rule '%s'" % [label, objective.holder_rule]
		if objective.holder_rule == OperationObjective.OWN_SIDE and objective.side not in [0, 1]:
			return "%s: own_side needs side 0 or 1" % label
		if objective.installation_id != &"":
			var found := definition.installations.any(
				func(p: InstallationPlacement) -> bool: return p.id == objective.installation_id
			)
			if not found:
				return "%s: unknown installation '%s'" % [label, objective.installation_id]
		elif not grid.has_tile(objective.coord):
			return "%s: hex %s is not on the map" % [label, objective.coord]
	return _chain_problem(definition.gap_chain, grid)


static func _chain_problem(chain: Array[Vector2i], grid: HexGrid) -> String:
	if chain.is_empty():
		return ""
	if chain.size() < 3:
		return "gap_chain needs at least 3 hexes"
	for index in chain.size():
		var hex := chain[index]
		if not grid.has_tile(hex) or grid.move_cost(hex) == Terrain.IMPASSABLE:
			return "gap_chain hex %s is not a land hex of the map" % hex
		if index > 0 and not grid.has_road(chain[index - 1], hex):
			return "gap_chain hexes %s and %s have no road link" % [chain[index - 1], hex]
	return ""


## Installations, strike stock / resupply and the strike numbers (TASK-097a).
static func _strikes_problem(definition: OperationDefinition, grid: HexGrid) -> String:
	if definition.strikes_per_turn < 1:
		return "strikes_per_turn %d must be at least 1" % definition.strikes_per_turn
	if definition.repair_per_round < 0:
		return "repair_per_round %d is negative" % definition.repair_per_round
	if definition.suppression_rounds < 1:
		return "suppression_rounds %d must be at least 1" % definition.suppression_rounds
	var counts_error := _counts_problem(definition.strike_stock, definition.strike_resupply)
	if counts_error != "":
		return counts_error
	var ids := {}
	var occupied := {}
	for placement in definition.installations:
		if placement == null:
			return "empty installation"
		var error := _installation_problem(definition, grid, placement)
		if error != "":
			return "installation '%s': %s" % [placement.id, error]
		if ids.has(placement.id):
			return "duplicate installation id '%s'" % placement.id
		ids[placement.id] = true
		if occupied.has(placement.coord):
			var other: StringName = occupied[placement.coord]
			return "'%s' and '%s' on one tile %s" % [other, placement.id, placement.coord]
		occupied[placement.coord] = placement.id
	return ""


static func _counts_problem(stock: Array[Dictionary], resupply: Array[Dictionary]) -> String:
	for entries: Array[Dictionary] in [stock, resupply]:
		if entries.size() != 0 and entries.size() != 2:
			return "strike stock / resupply needs 0 or 2 entries, has %d" % entries.size()
		for player in entries.size():
			var entry := entries[player]
			for key: Variant in entry:
				if not StrikeMeansDefinition.SHIPPED.has(StringName(key)):
					return "unknown strike means '%s'" % key
				if not entry[key] is int or int(entry[key]) < 0:
					return "strike count of '%s' is not a non-negative int" % key
				if not StrikeMeansDefinition.find(StringName(key)).usable_by(player):
					return (
						"strike means '%s' belongs to the other side of player %d" % [key, player]
					)
	return ""


static func _installation_problem(
	definition: OperationDefinition, grid: HexGrid, placement: InstallationPlacement
) -> String:
	if not Installation.CLASSES.has(placement.class_id):
		return "unknown class '%s'" % placement.class_id
	if placement.owner < 0 or placement.owner >= definition.sides.size():
		return "owner %d out of range" % placement.owner
	var ad_error := _ad_type_problem(placement)
	if ad_error != "":
		return ad_error
	if not grid.has_tile(placement.coord):
		return "off the map at %s" % placement.coord
	if grid.move_cost(placement.coord) == Terrain.IMPASSABLE:
		return "impassable tile %s" % placement.coord
	return ""


## An air-defence site needs a shipped type, any other class none (TASK-098a).
static func _ad_type_problem(placement: InstallationPlacement) -> String:
	if placement.class_id != &"air_defence":
		return "" if placement.ad_type == &"" else "ad_type on a '%s'" % placement.class_id
	if not AirDefenceDefinition.SHIPPED.has(placement.ad_type):
		return "unknown ad_type '%s'" % placement.ad_type
	return ""


static func _sides_problem(definition: OperationDefinition) -> String:
	if definition.sides.size() != 2:
		return "%d sides, expected 2" % definition.sides.size()
	if definition.first_player < 0 or definition.first_player > 1:
		return "first_player %d is not 0 or 1" % definition.first_player
	var owner := {}
	for index in definition.sides.size():
		var side: SideDefinition = definition.sides[index]
		if side == null:
			return "empty side"
		if not side.factions.has(side.lead_faction):
			return "side '%s' lacks its lead faction '%s'" % [side.id, side.lead_faction]
		for faction in side.factions:
			if owner.has(faction) and owner[faction] != index:
				return "faction '%s' in both sides" % faction
			owner[faction] = index
	return ""


static func _placement_problem(
	definition: OperationDefinition, grid: HexGrid, placement: FormationPlacement
) -> String:
	if placement.player < 0 or placement.player >= definition.sides.size():
		return "player %d out of range" % placement.player
	var type := placement.definition
	if type == null:
		return "no formation type"
	if not grid.has_tile(placement.coord):
		return "off the map at %s" % placement.coord
	if grid.move_cost(placement.coord) == Terrain.IMPASSABLE:
		return "impassable tile %s" % placement.coord
	var side := definition.sides[placement.player]
	if not side.factions.has(type.faction):
		return "faction '%s' is not on side '%s'" % [type.faction, side.id]
	var faction := FactionRegistry.get_faction(type.faction)
	if faction == null:
		return "unknown faction '%s'" % type.faction
	if type.companies.is_empty():
		return "no companies"
	for unit in type.companies:
		if not faction.has_unit(unit):
			var unit_id: StringName = unit.id if unit != null else &""
			return "company '%s' not in the roster of '%s'" % [unit_id, type.faction]
	return ""
