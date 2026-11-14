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
## Per player: the side may use a nuclear weapon (SideDefinition.may_use_nuclear, TASK-140; static,
## not in the snapshot).
var may_use_nuclear: Array[bool] = [false, false]
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
## Per player: the side's first urban strike has raised the level; later ones add nothing
## (TASK-140, never cleared).
var urban_escalated: Array[bool] = [false, false]
## Per player: the sum of max_strength() of every formation that has entered play for the player
## (start, joined allies, arrived support); destroyed formations stay in it (TASK-140,
## CollapseRules).
var fielded_strength: Array[int] = [0, 0]
## Political decisions the current player may still take this turn (TASK-117); reset when the
## turn passes on.
var decisions_left: int = 1
## Per player: the escalating decisions are rejected while `turn` <= this (after Stand down).
var stand_down_until: Array[int] = [0, 0]
## Outside-support packages in setup order (TASK-121).
var support: Array[SupportState] = []
## Fixed installations of both sides, in setup order (TASK-097a).
var installations: Array[Installation] = []
## Per player: {means id: count} (TASK-097a; changed only through StrikeRules.add_stock).
var strike_stock: Array[Dictionary] = [{}, {}]
## Strikes the current player may still launch this turn; reset when the turn passes on.
var strikes_left: int = 2
## Orders (IssueOrderCommand) the current player has issued this turn; reset when the turn passes
## on. The limit is `orders_per_turn` (C2 integrity).
var orders_issued: int = 0
## Means by id (static, not in the snapshot; the shipped ones, tests may add more).
var strike_means: Dictionary = {}
## Per player: {means id: count} gained at each round boundary (static).
var strike_resupply: Array[Dictionary] = [{}, {}]
## Air-defence types by id (static, not in the snapshot; the shipped ones, tests may add more).
var air_defence_types: Dictionary = {}
## Strikes per own turn, rounds a hit silences an air-defence site, repair per round (static).
var strikes_per_turn: int = 2
var suppression_rounds: int = 2
var repair_per_round: int = 5
## Objectives of the operational AI, both sides (static, not in the snapshot; TASK-102a).
var ai_goals: Array[AiGoal] = []
## The operation's data (victory objectives, Gap chain, round limit; static, not in the snapshot).
## Null in hand-made states: then no victory rule applies (OperationVictory.end_round does nothing).
var definition: OperationDefinition = null
## Holder (0 / 1) of each hex at the start (static, HexControl.setup); hexes absent are unheld.
var hex_initial: Dictionary = {}
## Vector2i -> holder of the hexes whose holder changed since the start (HexControl).
var hex_holders: Dictionary = {}
## Consecutive finished rounds that ended with side 1 holding the whole Gap chain.
var gap_closed_rounds: int = 0
## {} while the operation runs, else {winner: int (-1 = nobody), reason: StringName, by: int}
## (`by` = the side that caused it, -1 when none; the score is in the `operation_ended` event and
## OperationVictory.score).
var result: Dictionary = {}
## Contact battles waiting to be fought, FIFO (filled by EndOperationalTurnCommand, TASK-094a).
var pending_battles: Array[BattleSetup] = []
## Short history of political changes, effects only (TASK-119a); filled by OperationalSimulation.
var political_log := PoliticalLog.new()
## Per-side journal of everything that happened (TASK-148a); filled by OperationalSimulation.
var journal := OperationalJournal.new()


## Orders `player` may issue per turn, from the current integrity of their command posts.
func orders_per_turn(player: int) -> int:
	return BattleConditionsRules.orders_per_turn(installations, player)


## Orders the current player may still issue this turn.
func orders_left() -> int:
	return maxi(0, orders_per_turn(current_player) - orders_issued)


## The formation with this id; null if there is none.
func get_formation(formation_id: StringName) -> Formation:
	for f in formations:
		if f.id == formation_id:
			return f
	return null


## The victory objective with this id; null if there is none (or no definition).
func get_objective(objective_id: StringName) -> OperationObjective:
	if definition == null:
		return null
	for o in definition.objectives:
		if o.id == objective_id:
			return o
	return null


## The support package with this id; null if there is none.
func get_support(package_id: StringName) -> SupportState:
	for s in support:
		if s.id == package_id:
			return s
	return null


## The installation with this id; null if there is none.
func get_installation(installation_id: StringName) -> Installation:
	for i in installations:
		if i.id == installation_id:
			return i
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
## formations: [Formation.snapshot() sorted by id],
## installations: [Installation.snapshot() sorted by id],
## support: [SupportState.snapshot() sorted by id], strike_stock, strikes_left,
## fielded_strength, hex_holders, gap_closed_rounds, orders_issued (only when above 0)}.
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
	var installation_entries: Array = []
	var sorted_installations := installations.duplicate()
	sorted_installations.sort_custom(_installation_id_before)
	for i: Installation in sorted_installations:
		installation_entries.append(i.snapshot())
	var support_entries: Array = []
	var sorted_support := support.duplicate()
	sorted_support.sort_custom(_support_id_before)
	for s: SupportState in sorted_support:
		support_entries.append(s.snapshot())
	var snapshot := {
		"countries": country_entries,
		"support": support_entries,
		"installations": installation_entries,
		"strike_stock": [_stock_snapshot(0), _stock_snapshot(1)],
		"strikes_left": strikes_left,
		"decisions_left": decisions_left,
		"stand_down_until": stand_down_until.duplicate(),
		"turn": turn,
		"current_player": current_player,
		"rng_state": str(rng.state),
		"formations": entries,
		"fielded_strength": fielded_strength.duplicate(),
		"escalation":
		{
			"level": escalation_level,
			"caused": escalation_caused.duplicate(),
			"deescalated": escalation_deescalated.duplicate(),
			"last_raise_turn": last_raise_turn.duplicate(),
			"calm_rounds": calm_rounds,
			"raised_this_round": raised_this_round,
			"urban_escalated": urban_escalated.duplicate(),
		},
		"result": result.duplicate(),
		"hex_holders": _holders_snapshot(),
		"gap_closed_rounds": gap_closed_rounds,
		"political_log": political_log.to_dict()["entries"],
		"journal": journal.to_dict()["entries"],
	}
	if orders_issued > 0:  # only when used: older snapshots stay unchanged
		snapshot["orders_issued"] = orders_issued
	return snapshot


## [[q, r, holder], ...] of the changed hexes, sorted.
func _holders_snapshot() -> Array:
	var coords: Array = hex_holders.keys()
	coords.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	return coords.map(func(c: Vector2i) -> Array: return [c.x, c.y, hex_holders[c]])


static func _id_before(a: Formation, b: Formation) -> bool:
	return String(a.id) < String(b.id)


static func _country_id_before(a: CountryState, b: CountryState) -> bool:
	return String(a.id) < String(b.id)


static func _support_id_before(a: SupportState, b: SupportState) -> bool:
	return String(a.id) < String(b.id)


static func _installation_id_before(a: Installation, b: Installation) -> bool:
	return String(a.id) < String(b.id)


## One player's stock with String keys in sorted order.
func _stock_snapshot(player: int) -> Dictionary:
	var keys: Array = strike_stock[player].keys().map(func(k: Variant) -> String: return String(k))
	keys.sort()
	var result := {}
	for key: String in keys:
		result[key] = strike_stock[player][StringName(key)]
	return result
