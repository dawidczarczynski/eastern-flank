class_name GameState
extends RefCounted
## Full match state. No dependency on the scene tree – fully testable headless.
## Changed only by commands (Command) executed in GameSimulation.

var grid: HexGrid
var units: Dictionary = {}  # int (unit id) -> Unit
var player_count: int
var current_player: int = 0
var turn: int = 1
## Id of the player who won the match; -1 while the game is still running.
var winner: int = -1
var rng := RandomNumberGenerator.new()
## Faction id of each player (index = player id). Defaults to FactionRegistry.DEFAULT_IDS;
## the scenario assigns the match's factions. Static per match, so not part of snapshot().
var player_factions: Array[StringName] = []

## Display name of the operation (untranslated English, e.g. "Iron Shore"); "" = none. Set by
## the scenario, so a replay rebuilds it; static per match, so not part of snapshot().
var operation_name := ""

var _next_unit_id: int = 1


func _init(p_grid: HexGrid, p_player_count: int = 2, seed_value: int = 0) -> void:
	grid = p_grid
	player_count = p_player_count
	rng.seed = seed_value
	for player in player_count:
		var defaults := FactionRegistry.DEFAULT_IDS
		player_factions.append(defaults[player % defaults.size()])


## The faction of `player_id`; null for an unknown player or faction id.
func faction_of(player_id: int) -> FactionDefinition:
	if player_id < 0 or player_id >= player_factions.size():
		return null
	return FactionRegistry.get_faction(player_factions[player_id])


func add_unit(owner_id: int, definition: UnitDefinition, coord: Vector2i) -> Unit:
	var unit := Unit.new(_next_unit_id, owner_id, definition, coord)
	units[unit.id] = unit
	_next_unit_id += 1
	return unit


func get_unit(unit_id: int) -> Unit:
	return units.get(unit_id)


func unit_at(c: Vector2i) -> Unit:
	for u: Unit in units.values():
		if u.coord == c and u.is_alive():
			return u
	return null


func units_of(player_id: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for u: Unit in units.values():
		if u.owner_id == player_id and u.is_alive():
			result.append(u)
	return result


## Tiles occupied by living units: Vector2i -> true.
func occupied() -> Dictionary:
	var result := {}
	for u: Unit in units.values():
		if u.is_alive():
			result[u.coord] = true
	return result


## Comparable, JSON-compatible description of the state (replay checks, regression fixtures).
## Units are sorted by id and include dead ones. `rng_state` is `str(rng.state)`: the state is a
## full 64-bit integer that a JSON number (a double) cannot hold exactly.
func snapshot() -> Dictionary:
	var ids: Array = units.keys()
	ids.sort()
	var unit_list: Array[Dictionary] = []
	for id: int in ids:
		unit_list.append(_unit_snapshot(units[id]))
	return {
		"turn": turn,
		"current_player": current_player,
		"winner": winner,
		"rng_state": str(rng.state),
		"units": unit_list,
	}


func _unit_snapshot(u: Unit) -> Dictionary:
	return {
		"id": u.id,
		"owner": u.owner_id,
		"definition": String(u.definition.id),
		"coord": [u.coord.x, u.coord.y],
		"hp": u.hp,
		"moves_left": u.moves_left,
		"has_attacked": u.has_attacked,
	}
