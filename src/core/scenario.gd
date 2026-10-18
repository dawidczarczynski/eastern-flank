class_name Scenario
extends RefCounted
## Battle setups built headless from a seed (shared by the game, replays and AI simulations).

const MAP_WIDTH := 12
const MAP_HEIGHT := 10
const INFANTRY := preload("res://data/units/infantry.tres")
const CAVALRY := preload("res://data/units/cavalry.tres")
const ARTILLERY := preload("res://data/units/rocket_artillery.tres")


## Default 2-player battle on a generated 12x10 map. Spawn tiles are forced to plains.
static func default_battle(seed_value: int) -> GameState:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grid := MapGenerator.generate(MAP_WIDTH, MAP_HEIGHT, rng)
	var state := GameState.new(grid, 2, seed_value)
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
		var coord := MapGenerator.offset_to_axial(spawn[2], spawn[3])
		MapGenerator.force_terrain(grid, coord, Terrain.Type.PLAINS)
		state.add_unit(spawn[0], spawn[1], coord)
	return state
