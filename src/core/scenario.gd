class_name Scenario
extends RefCounted
## Battle setups built headless from a seed (shared by the game, replays and AI simulations).

const MAP_WIDTH := 12
const MAP_HEIGHT := 10
const INFANTRY := preload("res://data/units/infantry.tres")
const CAVALRY := preload("res://data/units/cavalry.tres")
const ARTILLERY := preload("res://data/units/rocket_artillery.tres")


## Default 2-player battle on a generated 12x10 map. Spawn tiles are forced to plains.
## `factions` = faction id of player 0 and player 1 (FactionRegistry). Factions don't change the
## map, spawns or unit ids – only which roster each player's units must come from: a unit whose
## definition is not in its owner's roster is skipped with push_error.
static func default_battle(
	seed_value: int, factions: Array[StringName] = FactionRegistry.DEFAULT_IDS
) -> GameState:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grid := MapGenerator.generate(MAP_WIDTH, MAP_HEIGHT, rng)
	var state := GameState.new(grid, 2, seed_value)
	state.player_factions = factions.duplicate()
	for player in state.player_count:
		if state.faction_of(player) == null:
			push_error("Scenario: player %d has an unknown faction" % player)
	# [owner, definition, column, row]
	var spawns: Array = [
		[0, INFANTRY, 1, 3],
		[0, CAVALRY, 1, 5],
		[0, INFANTRY, 1, 7],
		[0, ARTILLERY, 0, 5],
		[1, INFANTRY, MAP_WIDTH - 2, 2],
		[1, CAVALRY, MAP_WIDTH - 2, 4],
		[1, INFANTRY, MAP_WIDTH - 2, 6],
		[1, ARTILLERY, MAP_WIDTH - 1, 4],
	]
	for spawn: Array in spawns:
		var owner_id: int = spawn[0]
		var definition: UnitDefinition = spawn[1]
		var coord := MapGenerator.offset_to_axial(spawn[2], spawn[3])
		MapGenerator.force_terrain(grid, coord, Terrain.Type.PLAINS)
		if not can_spawn(state, owner_id, definition):
			push_error(
				"Scenario: '%s' is not in player %d's roster – skipped" % [definition.id, owner_id]
			)
			continue
		state.add_unit(owner_id, definition, coord)
	return state


## True when `definition` is in the roster of `player_id`'s faction.
static func can_spawn(state: GameState, player_id: int, definition: UnitDefinition) -> bool:
	var faction := state.faction_of(player_id)
	return faction != null and faction.has_unit(definition)
