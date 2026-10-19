class_name Scenario
extends RefCounted
## Battle setups built headless from a seed (shared by the game, replays and AI simulations).

const MAP_WIDTH := 12
const MAP_HEIGHT := 10
## Spawn slots per player, as offset [column, rows in fill order]: units with attack range 1 take
## the front slots, the others the back slots.
const FRONT_SLOTS := [[1, [3, 5, 7, 1, 9]], [MAP_WIDTH - 2, [2, 4, 6, 8, 0]]]
const BACK_SLOTS := [[0, [5, 3, 7]], [MAP_WIDTH - 1, [4, 2, 6]]]


## Default 2-player battle on a generated 12x10 map. Spawn tiles are forced to plains.
## `factions` = faction id of player 0 and player 1 (FactionRegistry). Each player spawns their
## faction's `default_force` in list order (unit ids follow it); factions don't change the map.
## A unit not in its owner's roster, or one beyond the free slots, is skipped with push_error.
static func default_battle(
	seed_value: int, factions: Array[StringName] = FactionRegistry.DEFAULT_IDS
) -> GameState:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grid := MapGenerator.generate(MAP_WIDTH, MAP_HEIGHT, rng)
	var state := GameState.new(grid, 2, seed_value)
	state.player_factions = factions.duplicate()
	for player in state.player_count:
		var faction := state.faction_of(player)
		if faction == null:
			push_error("Scenario: player %d has an unknown faction" % player)
			continue
		var used := {true: 0, false: 0}  # front? -> slots taken
		for definition: UnitDefinition in faction.default_force:
			var front := definition.attack_range == 1
			var slots: Array = (FRONT_SLOTS if front else BACK_SLOTS)[player]
			var rows: Array = slots[1]
			if used[front] >= rows.size():
				push_error("Scenario: no free slot for '%s' of player %d" % [definition.id, player])
				continue
			var coord := MapGenerator.offset_to_axial(slots[0], rows[used[front]])
			used[front] += 1
			MapGenerator.force_terrain(grid, coord, Terrain.Type.PLAINS)
			if not can_spawn(state, player, definition):
				push_error(
					(
						"Scenario: '%s' is not in player %d's roster – skipped"
						% [definition.id, player]
					)
				)
				continue
			state.add_unit(player, definition, coord)
	return state


## True when `definition` is in the roster of `player_id`'s faction.
static func can_spawn(state: GameState, player_id: int, definition: UnitDefinition) -> bool:
	var faction := state.faction_of(player_id)
	return faction != null and faction.has_unit(definition)
