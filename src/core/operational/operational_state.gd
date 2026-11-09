class_name OperationalState
extends RefCounted
## Full state of an operation (ADR 0015, TASK-092b). Changed only by OperationalCommands through
## OperationalSimulation. The human's side is not part of it (it lives in the session), so the
## state and its replay are identical whichever side the human plays.

var operation_id: StringName
## Display name of the operation (translation key; static, not in the snapshot).
var operation_name: String
## Id of the operation's map (ImportedMap); becomes BattleSetup.map_id (static, not in snapshot).
var map_id: StringName = &""
## Calendar date of turn 1 (YYYY-MM-DD, OperationalClock); static, not in the snapshot.
var start_date: String = ""
var grid: HexGrid
## Hexes around a formation that belong to its side in the front line (FrontLine; static, not in
## the snapshot).
var front_range: int = FrontLine.DEFAULT_RANGE
## Side id of each player (SideDefinition.id).
var player_sides: Array[StringName] = []
## Lead faction of each player's side (colours, HUD).
var player_factions: Array[StringName] = []
## Posture of formations that appear after the start (static, from the definition).
var initial_posture: StringName = &"defend"
var first_player: int = 0
var current_player: int = 0
var turn: int = 1
## In placement order – also the order in which orders execute (TASK-092e).
var formations: Array[Formation] = []
## Political state of the countries, in setup order (TASK-114).
var countries: Array[CountryState] = []
## Vector2i -> country id of every hex that belongs to a country (static, not in the snapshot).
var country_map: Dictionary = {}
## Seeded with the campaign seed; battle seeds are drawn from it (ADR 0015 §2).
var rng := RandomNumberGenerator.new()
## The escalation ladder (static, not in the snapshot; TASK-115).
var ladder: EscalationLadder = EscalationLadder.shipped()
## Shared escalation level, index into `ladder.levels` (TASK-115).
var escalation_level: int = 1
## The calm decay never goes below this (= the start level).
var escalation_floor: int = 1
## Per player: steps of escalation that player caused / de-escalation steps taken.
var escalation_caused: Array[int] = [0, 0]
var escalation_deescalated: Array[int] = [0, 0]
## Per player: turn of the player's latest raise, -1 = never.
var last_raise_turn: Array[int] = [-1, -1]
## Consecutive full rounds without a raise (calm decay).
var calm_rounds: int = 0
## A raise happened in the running round.
var raised_this_round: bool = false
## {} while the operation runs, else {winner: int, reason: StringName}.
var result: Dictionary = {}
## Contact battles waiting to be fought, FIFO (filled by EndOperationalTurnCommand, TASK-094a).
var pending_battles: Array[BattleSetup] = []


## The formation with this id; null if there is none.
func get_formation(formation_id: StringName) -> Formation:
	for f in formations:
		if f.id == formation_id:
			return f
	return null


## The country with this id; null if there is none.
func get_country(country_id: StringName) -> CountryState:
	for c in countries:
		if c.id == country_id:
			return c
	return null


## Id of the country the hex belongs to; &"" for water, no country or off the map.
func country_at(coord: Vector2i) -> StringName:
	return country_map.get(coord, &"")


## The formation standing on `coord`; null if the hex is empty.
func formation_at(coord: Vector2i) -> Formation:
	for f in formations:
		if f.coord == coord:
			return f
	return null


## JSON-compatible snapshot of the dynamic state (static data – definitions, map – is left out):
## {turn, current_player, rng_state, escalation, result,
## countries: [CountryState.snapshot() sorted by id],
## formations: [Formation.snapshot() sorted by id]}.
func snapshot() -> Dictionary:
	var sorted := formations.duplicate()
	sorted.sort_custom(_id_before)
	var entries: Array = []
	for f: Formation in sorted:
		entries.append(f.snapshot())
	var country_entries: Array = []
	var sorted_countries := countries.duplicate()
	sorted_countries.sort_custom(_country_id_before)
	for c: CountryState in sorted_countries:
		country_entries.append(c.snapshot())
	return {
		"countries": country_entries,
		"turn": turn,
		"current_player": current_player,
		"rng_state": str(rng.state),
		"formations": entries,
		"escalation":
		{
			"level": escalation_level,
			"caused": escalation_caused.duplicate(),
			"deescalated": escalation_deescalated.duplicate(),
			"last_raise_turn": last_raise_turn.duplicate(),
			"calm_rounds": calm_rounds,
			"raised_this_round": raised_this_round,
		},
		"result": result.duplicate(),
	}


static func _id_before(a: Formation, b: Formation) -> bool:
	return String(a.id) < String(b.id)


static func _country_id_before(a: CountryState, b: CountryState) -> bool:
	return String(a.id) < String(b.id)
