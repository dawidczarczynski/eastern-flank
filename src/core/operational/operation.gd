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
	definition: OperationDefinition, seed_value: int, grid: HexGrid = null
) -> OperationalState:
	if grid == null:
		var map := ImportedMap.find(definition.map_id)
		if map == null:
			push_error("Operation '%s': unknown map '%s'" % [definition.id, definition.map_id])
			return null
		grid = map.to_grid()
		if grid == null:
			return null
	var error := _problem(definition, grid)
	if error != "":
		push_error("Operation '%s': %s" % [definition.id, error])
		return null
	var state := OperationalState.new()
	state.operation_id = definition.id
	state.operation_name = definition.display_name
	state.grid = grid
	for side in definition.sides:
		state.player_sides.append(side.id)
		state.player_factions.append(side.lead_faction)
	state.first_player = definition.first_player
	state.current_player = definition.first_player
	state.turn = 1
	state.rng.seed = seed_value
	for placement in definition.formations:
		state.formations.append(Formation.from_placement(placement))
	return state


## "" when the definition is consistent with itself, the map and the faction rosters.
static func _problem(definition: OperationDefinition, grid: HexGrid) -> String:
	var sides_error := _sides_problem(definition)
	if sides_error != "":
		return sides_error
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
