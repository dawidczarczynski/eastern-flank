class_name GameState
extends RefCounted
## Full match state. No dependency on the scene tree – fully testable headless.
## Changed only by commands (Command) executed in GameSimulation.

var grid: HexGrid
var units: Dictionary = {}  # int (unit id) -> Unit
var player_count: int
var current_player: int = 0
var turn: int = 1
## Id of the player who won the match; -1 while the game is still running and for a draw once it
## is over (see `is_over`).
var winner: int = -1
## Why the battle ended (BattleRules.REASON_*: &"eliminated", &"enemy_destroyed",
## &"objective_taken", &"turn_limit"); &"" while it runs (ADR 0016).
var end_reason: StringName = &""
var rng := RandomNumberGenerator.new()
## Faction id of each player (index = player id). Defaults to FactionRegistry.DEFAULT_IDS;
## the scenario assigns the match's factions. Static per match, so not part of snapshot().
var player_factions: Array[StringName] = []

## Display name of the operation (untranslated English, e.g. "Iron Shore"); "" = none. Set by
## the scenario, so a replay rebuilds it; static per match, so not part of snapshot().
var operation_name := ""

## Victory conditions and turn limit (set_objectives). Static per match – the scenario rebuilds
## it – so not part of snapshot(); defaults to BattleObjectives.default_objectives().
var objectives: BattleObjectives = BattleObjectives.default_objectives()
## Owner of each objective hex: Vector2i -> player id, -1 = neutral. Changed by BattleRules.capture;
## part of snapshot().
var objective_owners: Dictionary = {}
## Total HP of each player's living units when the battle started (record_starting_hp; index =
## player id), for DESTROY_SHARE. Static per match, so not part of snapshot().
var starting_hp: Array[int] = []

var _next_unit_id: int = 1


func _init(p_grid: HexGrid, p_player_count: int = 2, seed_value: int = 0) -> void:
	grid = p_grid
	player_count = p_player_count
	rng.seed = seed_value
	for player in player_count:
		var defaults := FactionRegistry.DEFAULT_IDS
		player_factions.append(defaults[player % defaults.size()])


## Whether the battle has ended (winner or draw).
func is_over() -> bool:
	return end_reason != &""


## Ends the battle: `p_winner` (-1 = draw) for `reason`. Called by BattleRules; tests use it to
## set up a finished battle.
func finish(p_winner: int, reason: StringName) -> void:
	winner = p_winner
	end_reason = reason


## Uses `p_objectives` for this battle; objective owners start at their initial owners.
func set_objectives(p_objectives: BattleObjectives) -> void:
	objectives = p_objectives
	objective_owners.clear()
	for i in p_objectives.hexes.size():
		objective_owners[p_objectives.hexes[i]] = p_objectives.initial_owners[i]


## Stores each player's current total HP of living units as `starting_hp`.
func record_starting_hp() -> void:
	starting_hp.clear()
	for player in player_count:
		var total := 0
		for unit in units_of(player):
			total += unit.hp
		starting_hp.append(total)


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
## Units are sorted by id and include dead ones; "objectives" = [[q, r, owner], ...] sorted by
## (q, r), [] without objective hexes. `rng_state` is `str(rng.state)`: the state is a
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
		"end_reason": String(end_reason),
		"rng_state": str(rng.state),
		"objectives": _objectives_snapshot(),
		"units": unit_list,
	}


func _objectives_snapshot() -> Array:
	var coords: Array = objective_owners.keys()
	coords.sort()
	var result: Array = []
	for c: Vector2i in coords:
		result.append([c.x, c.y, objective_owners[c]])
	return result


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
