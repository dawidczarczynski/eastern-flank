class_name OperationalState
extends RefCounted
## Full state of an operation (ADR 0015, TASK-092b). Changed only by OperationalCommands through
## OperationalSimulation. The human's side is not part of it (it lives in the session), so the
## state and its replay are identical whichever side the human plays.

var operation_id: StringName
## Display name of the operation (translation key; static, not in the snapshot).
var operation_name: String
var grid: HexGrid
## Side id of each player (SideDefinition.id).
var player_sides: Array[StringName] = []
## Lead faction of each player's side (colours, HUD).
var player_factions: Array[StringName] = []
var first_player: int = 0
var current_player: int = 0
var turn: int = 1
## In placement order – also the order in which orders execute (TASK-092e).
var formations: Array[Formation] = []
## Seeded with the campaign seed; battle seeds are drawn from it (ADR 0015 §2).
var rng := RandomNumberGenerator.new()
## Contact battles waiting to be fought, FIFO (filled by TASK-094).
var pending_battles: Array[BattleSetup] = []


## The formation with this id; null if there is none.
func get_formation(formation_id: StringName) -> Formation:
	for f in formations:
		if f.id == formation_id:
			return f
	return null


## The formation standing on `coord`; null if the hex is empty.
func formation_at(coord: Vector2i) -> Formation:
	for f in formations:
		if f.coord == coord:
			return f
	return null


## JSON-compatible snapshot of the dynamic state (static data – definitions, map – is left out):
## {turn, current_player, rng_state, formations: [Formation.snapshot() sorted by id]}.
func snapshot() -> Dictionary:
	var sorted := formations.duplicate()
	sorted.sort_custom(_id_before)
	var entries: Array = []
	for f: Formation in sorted:
		entries.append(f.snapshot())
	return {
		"turn": turn,
		"current_player": current_player,
		"rng_state": str(rng.state),
		"formations": entries,
	}


static func _id_before(a: Formation, b: Formation) -> bool:
	return String(a.id) < String(b.id)
