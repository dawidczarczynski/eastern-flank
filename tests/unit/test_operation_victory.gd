# gdlint: disable=max-public-methods
extends TestCase
## Victory of an operation (TASK-107a, TASK-177): NATO's link and Russia's corridor as
## connectivity conditions, scoring, the penalty and the endings.

const Fixtures := preload("res://tests/fixtures.gd")
const Data := preload("res://tests/unit/test_contribution_data.gd")
const Politics := preload("res://tests/unit/test_country_rules.gd")

## Hand-made board (see `_state`): axial q 2..9, r 0..6 of plains; column q 2 is Russia, column
## q 9 Belarus (both held by side 1 from the start); NATO's link joins (5, 0) with (5, 6).
const NATO_FROM := Vector2i(5, 0)
const NATO_TO := Vector2i(5, 6)
## A straight corridor across row 3: it also cuts NATO's link.
const WALL: Array[Vector2i] = [
	Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3), Vector2i(7, 3), Vector2i(8, 3)
]
## A winding, non-straight corridor from (2, 1) Russia to (9, 1) Belarus.
const CORRIDOR: Array[Vector2i] = [
	Vector2i(3, 1),
	Vector2i(4, 1),
	Vector2i(4, 2),
	Vector2i(4, 3),
	Vector2i(4, 4),
	Vector2i(5, 4),
	Vector2i(6, 3),
	Vector2i(6, 2),
	Vector2i(7, 1),
	Vector2i(8, 1),
]


static func _objective(
	id: StringName, coord: Vector2i, side: int, points: int, rule: StringName
) -> OperationObjective:
	var o := OperationObjective.new()
	o.id = id
	o.coord = coord
	o.side = side
	o.points = points
	o.holder_rule = rule
	return o


## Hand-made state: Chernyakhovsk (0, 5) 5 for side 0, Bialystok (0, 6) 5 for side 1, Vilnius
## (0, 7) 5 for side 1, Grodno (0, 8) 5 for whoever holds it (all off the board); NATO's link
## NATO_FROM - NATO_TO and the corridor Russia - Belarus on the board described above.
static func _state() -> OperationalState:
	var s := OperationalState.new()
	var def := OperationDefinition.new()
	def.nato_link_from = NATO_FROM
	def.nato_link_to = NATO_TO
	def.corridor_from_country = &"russia"
	def.corridor_to_country = &"belarus"
	def.objectives = (
		[
			_objective(&"chernyakhovsk", Vector2i(0, 5), 0, 5, OperationObjective.OWN_SIDE),
			_objective(&"bialystok", Vector2i(0, 6), 1, 5, OperationObjective.OWN_SIDE),
			_objective(&"vilnius", Vector2i(0, 7), 1, 5, OperationObjective.OWN_SIDE),
			_objective(&"grodno", Vector2i(0, 8), -1, 5, OperationObjective.ANY),
		]
		as Array[OperationObjective]
	)
	s.definition = def
	s.grid = HexGrid.new()
	for q in range(2, 10):
		for r in range(0, 7):
			s.grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
		s.country_map[Vector2i(2, q - 2)] = &"russia"
		s.country_map[Vector2i(9, q - 2)] = &"belarus"
	for hex: Vector2i in s.country_map:
		s.hex_initial[hex] = 1
	return s


static func _hold(s: OperationalState, hex: Vector2i, side: int) -> void:
	s.hex_holders[hex] = side


static func _hold_all(s: OperationalState, hexes: Array[Vector2i], side: int) -> void:
	for hex in hexes:
		_hold(s, hex, side)


## Holds the first `count` corridor hexes (all by default) for `side`.
static func _hold_corridor(s: OperationalState, side: int, count: int = -1) -> void:
	if count < 0:
		count = CORRIDOR.size()
	for i in count:
		_hold(s, CORRIDOR[i], side)


# --- connection status ---


func test_the_board_routes_are_neighbour_chains() -> void:
	for route: Array[Vector2i] in [WALL, CORRIDOR]:
		for i in range(1, route.size()):
			assert_eq(Hex.distance(route[i - 1], route[i]), 1, "%s" % route[i])


func test_corridor_closed_by_a_winding_route() -> void:
	var s := _state()
	var def := s.definition
	assert_eq(OperationVictory.corridor_status(s, def), OperationVictory.OPEN, "nothing held")
	_hold_corridor(s, 1)
	assert_eq(OperationVictory.corridor_status(s, def), OperationVictory.CLOSED)
	var route := OperationVictory.corridor_route(s, def)
	assert_eq(s.country_at(route[0]), &"russia")
	assert_eq(s.country_at(route[-1]), &"belarus")
	for hex in route:
		assert_eq(HexControl.holder(s, hex), 1)


func test_one_gap_in_the_corridor_opens_it() -> void:
	var s := _state()
	var def := s.definition
	_hold_corridor(s, 1)
	_hold(s, CORRIDOR[5], 0)
	assert_eq(OperationVictory.corridor_status(s, def), OperationVictory.OPEN, "NATO hex")
	_hold(s, CORRIDOR[5], -1)
	assert_eq(OperationVictory.corridor_status(s, def), OperationVictory.OPEN, "unheld hex")
	assert_eq(OperationVictory.corridor_route(s, def), [] as Array[Vector2i])
	_hold(s, Vector2i(5, 3), 1)
	assert_eq(
		OperationVictory.corridor_status(s, def), OperationVictory.CLOSED, "a detour by (5, 3)"
	)


func test_corridor_needs_side_one_country_ends() -> void:
	var s := _state()
	var def := s.definition
	_hold_corridor(s, 1)
	for r in 7:
		_hold(s, Vector2i(2, r), 0)
	assert_eq(OperationVictory.corridor_status(s, def), OperationVictory.OPEN, "Russia lost")
	def.corridor_to_country = &""
	assert_eq(OperationVictory.corridor_status(s, def), OperationVictory.OPEN, "no objective")


func test_gap_link_open_and_cut() -> void:
	var s := _state()
	var def := s.definition
	assert_eq(OperationVictory.gap_status(s, def), OperationVictory.OPEN, "neutral hexes allowed")
	assert_eq(OperationVictory.gap_route(s, def)[0], NATO_FROM)
	assert_eq(OperationVictory.gap_route(s, def)[-1], NATO_TO)
	_hold(s, Vector2i(5, 3), 1)
	assert_eq(OperationVictory.gap_status(s, def), OperationVictory.OPEN, "a detour exists")
	_hold_all(s, WALL.slice(0, WALL.size() - 1), 1)
	assert_eq(OperationVictory.gap_status(s, def), OperationVictory.OPEN, "detour by (8, 3)")
	_hold(s, WALL[-1], 1)
	assert_eq(OperationVictory.gap_status(s, def), OperationVictory.CUT, "every route blocked")
	_hold(s, WALL[2], 0)
	assert_eq(OperationVictory.gap_status(s, def), OperationVictory.OPEN, "NATO broke through")
	_hold(s, NATO_TO, 1)
	assert_eq(OperationVictory.gap_status(s, def), OperationVictory.CUT, "an end held by Russia")
	def.nato_link_to = Vector2i.MAX
	assert_eq(OperationVictory.gap_status(s, def), OperationVictory.OPEN, "no objective")


func test_water_is_not_walkable() -> void:
	var s := _state()
	var def := s.definition
	for hex in WALL:
		if hex != Vector2i(6, 3):
			s.grid.set_terrain(hex, Terrain.Type.WATER)
	assert_eq(OperationVictory.gap_status(s, def), OperationVictory.OPEN, "through (6, 3)")
	_hold(s, Vector2i(6, 3), 1)
	assert_eq(OperationVictory.gap_status(s, def), OperationVictory.CUT, "water does not help")
	_hold_all(s, WALL, 1)
	assert_eq(
		OperationVictory.corridor_status(s, def), OperationVictory.OPEN, "no corridor over water"
	)


func test_land_route_ignores_holders() -> void:
	var s := _state()
	var def := s.definition
	_hold_all(s, WALL, 1)
	var gap := OperationVictory.land_route(s, def, true)
	assert_eq([gap[0], gap[-1]], [NATO_FROM, NATO_TO])
	assert_eq(gap.size(), 7)
	var corridor := OperationVictory.land_route(s, def, false)
	assert_eq(corridor.size(), 8, "straight across the board")
	assert_eq(OperationVictory.country_hexes(s, &"belarus").size(), 7)


# --- score ---


func test_score_breakdown() -> void:
	var s := _state()
	_hold(s, Vector2i(0, 5), 0)
	_hold(s, Vector2i(0, 8), 0)
	s.escalation_caused = [2, 0]
	var score := OperationVictory.score(s, s.definition)
	var nato: Dictionary = score[0]
	assert_eq(nato["total"], 14, "5 + 10 + 5 - 6")
	assert_eq(nato["escalation_penalty"], -6)
	var ids: Array = nato["lines"].map(func(l: Dictionary) -> Variant: return l["id"])
	assert_eq(ids, [&"chernyakhovsk", &"grodno", &"gap_open"])
	assert_eq(nato["lines"][2]["points"], 10)
	assert_eq(score[1]["total"], 0)
	assert_eq(score[1]["lines"], [] as Array[Dictionary])


func test_escalation_penalty_is_net_and_never_positive() -> void:
	var s := _state()
	s.escalation_caused = [3, 1]
	s.escalation_deescalated = [1, 3]
	assert_eq(OperationVictory.penalty(s, s.definition, 0), -6)
	assert_eq(OperationVictory.penalty(s, s.definition, 1), 0)


func test_grodno_belongs_to_its_holder_only() -> void:
	var s := _state()
	var score := OperationVictory.score(s, s.definition)
	assert_false(score[0]["lines"].any(func(l: Dictionary) -> bool: return l["id"] == &"grodno"))
	assert_false(score[1]["lines"].any(func(l: Dictionary) -> bool: return l["id"] == &"grodno"))
	_hold(s, Vector2i(0, 8), 1)
	score = OperationVictory.score(s, s.definition)
	assert_true(score[1]["lines"].any(func(l: Dictionary) -> bool: return l["id"] == &"grodno"))
	assert_false(score[0]["lines"].any(func(l: Dictionary) -> bool: return l["id"] == &"grodno"))


func test_closed_corridor_scores_for_side_one() -> void:
	var s := _state()
	_hold_corridor(s, 1)
	var score := OperationVictory.score(s, s.definition)
	assert_eq(score[1]["lines"], [{"id": &"corridor", "points": s.definition.corridor_points}])
	assert_eq(score[1]["total"], s.definition.corridor_points)
	assert_eq(score[0]["total"], 0, "a corridor across the board cuts NATO's link")


func test_cut_gap_link_scores_nothing_and_no_gap_closed_line() -> void:
	var s := _state()
	_hold(s, NATO_TO, 1)
	var score := OperationVictory.score(s, s.definition)
	assert_eq(score[0]["total"], 0, "the link is cut")
	assert_eq(score[1]["total"], 0, "the corridor is open")
	for side in 2:
		for line: Dictionary in score[side]["lines"]:
			assert_true(line["id"] != &"gap_closed")


func test_open_road_and_open_corridor_lines() -> void:
	var s := _state()
	var def := s.definition
	var score := OperationVictory.score(s, def)
	assert_eq(score[0]["lines"], [{"id": &"gap_open", "points": def.gap_open_points}])
	assert_eq(score[1]["lines"], [] as Array[Dictionary])


# --- endings ---


## The events without the `corridor_counter` notices (TASK-165; see test_objective_events).
static func _without_counter(events: Array[Dictionary]) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.get("kind") != &"corridor_counter")


func test_closed_rounds_to_win() -> void:
	var s := _state()
	var need := s.definition.closed_rounds_to_win
	assert_eq(need, 5, "the default")
	_hold_corridor(s, 1)
	for round_number in range(7, 7 + need - 1):
		assert_eq(
			_without_counter(OperationVictory.end_round(s, round_number)), [] as Array[Dictionary]
		)
		assert_eq(s.corridor_closed_rounds, round_number - 6)
	var events := _without_counter(OperationVictory.end_round(s, 7 + need - 1))
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], &"operation_ended")
	assert_eq(events[0]["winner"], 1)
	assert_eq(events[0]["by"], 1)
	assert_eq(events.back()["reason"], &"corridor_closed")
	assert_eq(s.result["winner"], 1)
	assert_eq(events[0]["score"][1]["total"], s.definition.corridor_points)


func test_held_one_round_short_then_lost_does_not_end() -> void:
	var s := _state()
	var need := s.definition.closed_rounds_to_win
	_hold_corridor(s, 1)
	for round_number in need - 1:
		OperationVictory.end_round(s, 7 + round_number)
	assert_eq(s.corridor_closed_rounds, need - 1)
	assert_true(s.result.is_empty())
	_hold(s, CORRIDOR[2], 0)
	assert_eq(_without_counter(OperationVictory.end_round(s, 7 + need)), [] as Array[Dictionary])
	assert_eq(s.corridor_closed_rounds, 0)
	assert_true(s.result.is_empty())


func test_corridor_closed_late_with_a_short_counter_is_only_scored() -> void:
	var s := _state()
	_hold_corridor(s, 1)
	s.corridor_closed_rounds = s.definition.closed_rounds_to_win - 2
	var events := OperationVictory.end_round(s, s.definition.round_limit)
	assert_eq(events.back()["reason"], &"round_limit")
	assert_eq(events.back()["by"], -1)
	assert_eq(events.back()["score"][1]["total"], s.definition.corridor_points)


func test_a_cut_gap_link_never_moves_the_counter_nor_wins() -> void:
	var s := _state()
	_hold(s, NATO_TO, 1)
	for round_number in s.definition.closed_rounds_to_win + 1:
		assert_eq(OperationVictory.end_round(s, 7 + round_number), [] as Array[Dictionary])
		assert_eq(s.corridor_closed_rounds, 0)
	assert_true(s.result.is_empty(), "a cut link is no instant win")
	_hold_corridor(s, 1)
	OperationVictory.end_round(s, 20)
	_hold(s, NATO_TO, 0)
	OperationVictory.end_round(s, 21)
	assert_eq(s.corridor_closed_rounds, 2, "retaking the link's end changes nothing")


func test_a_lost_chain_resets_the_counter() -> void:
	var s := _state()
	_hold_corridor(s, 1)
	OperationVictory.end_round(s, 7)
	_hold(s, CORRIDOR[2], 0)
	assert_eq(_without_counter(OperationVictory.end_round(s, 8)), [] as Array[Dictionary])
	assert_eq(s.corridor_closed_rounds, 0)
	assert_eq(s.snapshot()["corridor_closed_rounds"], 0)
	_hold(s, CORRIDOR[2], 1)
	assert_eq(_without_counter(OperationVictory.end_round(s, 9)), [] as Array[Dictionary])
	assert_eq(s.corridor_closed_rounds, 1)
	assert_eq(s.snapshot()["corridor_closed_rounds"], 1)


func _totals(nato: int, russia: int) -> Dictionary:
	return {0: {"total": nato}, 1: {"total": russia}}


func test_winner_of_the_totals_and_the_draw_margin() -> void:
	var def := OperationDefinition.new()
	assert_eq(OperationVictory.winner_of(_totals(20, 14), def), 0)
	assert_eq(OperationVictory.winner_of(_totals(18, 14), def), -1, "difference 4")
	assert_eq(OperationVictory.winner_of(_totals(19, 14), def), 0, "difference exactly 5")
	assert_eq(OperationVictory.winner_of(_totals(14, 19), def), 1)
	assert_eq(OperationVictory.winner_of(_totals(14, 14), def), -1, "equal")
	def.draw_margin = 0
	assert_eq(OperationVictory.winner_of(_totals(14, 14), def), -1, "equal without a margin")


func test_round_limit_ends_with_the_higher_score() -> void:
	var s := _state()
	_hold(s, Vector2i(0, 5), 0)
	_hold(s, Vector2i(0, 8), 0)
	_hold(s, Vector2i(0, 6), 1)  # NATO 20, Russia 5
	var events := OperationVictory.end_round(s, 30)
	assert_eq(events[0]["reason"], &"round_limit")
	assert_eq(events[0]["winner"], 0)
	assert_eq(events[0]["score"][0]["total"], 20)
	assert_eq(events[0]["score"][1]["total"], 5)
	assert_eq(s.result["reason"], &"round_limit")


func test_round_limit_inside_the_margin_is_a_draw() -> void:
	var s := _state()
	_hold(s, Vector2i(0, 6), 1)
	_hold(s, Vector2i(0, 7), 1)  # NATO 10 (gap), Russia 10
	var events := OperationVictory.end_round(s, 30)
	assert_eq(events[0]["winner"], -1)
	assert_eq(s.result["winner"], -1)


func test_corridor_closed_is_checked_before_the_round_limit() -> void:
	var s := _state()
	_hold_corridor(s, 1)
	s.corridor_closed_rounds = s.definition.closed_rounds_to_win - 1
	var events := OperationVictory.end_round(s, s.definition.round_limit)
	assert_eq(events.back()["reason"], &"corridor_closed")


func test_no_ending_before_the_limit_and_nothing_after_it_ended() -> void:
	var s := _state()
	assert_eq(OperationVictory.end_round(s, 29), [] as Array[Dictionary])
	s.result = {"winner": -1, "reason": &"nuclear_use", "by": 1}
	assert_eq(OperationVictory.end_round(s, 30), [] as Array[Dictionary])
	assert_eq(s.result["reason"], &"nuclear_use")


func test_a_state_without_a_definition_never_ends_by_victory() -> void:
	var s := OperationalState.new()
	assert_eq(OperationVictory.end_round(s, 99), [] as Array[Dictionary])


func test_nuclear_use_carries_the_score_and_blocks_commands() -> void:
	var s := _state()
	var events := EscalationRules.nuclear_use(s, 1)
	var ended := events[1]
	assert_eq(ended["type"], &"operation_ended")
	assert_eq(ended["winner"], -1)
	assert_eq(ended["reason"], &"nuclear_use")
	assert_true(ended["score"].has(0) and ended["score"].has(1))
	var sim := OperationalSimulation.new(s)
	var reasons: Array[String] = []
	sim.command_rejected.connect(func(_c: OperationalCommand, r: String) -> void: reasons.append(r))
	assert_false(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(reasons, ["operation_over"] as Array[String])


# --- through the end-of-turn command ---


func test_the_command_ends_the_operation_after_the_closed_rounds() -> void:
	var s := _closed_chain_state()
	var sim := OperationalSimulation.new(s)
	var types: Array = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: types.append(e["type"]))
	for i in 3:
		assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_true(s.result.is_empty(), "one full round and a half")
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(s.result["reason"], &"corridor_closed")
	assert_eq(s.result["winner"], 1)
	assert_true(types.has(&"operation_ended"))
	assert_false(sim.execute(EndOperationalTurnCommand.new()))


## Strip operation (rows 0-1: poland q0-1, lithuania q2-3, belarus q4-5, russia q6-7): Russia and
## Belarus are neighbours held by side 1 from the start, so the corridor is closed at once; side 1
## also stands on (5..7, 0), side 0 on (0, 0); NATO's link joins (0, 0) with (3, 1).
static func _closed_chain_definition() -> OperationDefinition:
	var op := Politics._definition()
	op.first_player = 0
	op.closed_rounds_to_win = 2
	op.formations = (
		[
			Data.placement(&"blue_1", 0, Vector2i(0, 0)),
			Data.placement(&"red_1", 1, Vector2i(5, 0)),
			Data.placement(&"red_2", 1, Vector2i(6, 0)),
			Data.placement(&"red_3", 1, Vector2i(7, 0)),
		]
		as Array[FormationPlacement]
	)
	op.nato_link_from = Vector2i(0, 0)
	op.nato_link_to = Vector2i(3, 1)
	op.corridor_from_country = &"russia"
	op.corridor_to_country = &"belarus"
	return op


static func _closed_chain_state() -> OperationalState:
	return Operation.from_definition(
		_closed_chain_definition(), 1, Politics._grid(), Politics._country_map()
	)


# --- campaign record ---


func test_a_corridor_closed_record_replays_to_the_same_result() -> void:
	var def := _closed_chain_definition()
	var s := _closed_chain_state()
	Operation.give_initiative(s, s.player_sides.find(&"red"))
	var sim := OperationalSimulation.new(s)
	for i in 4:
		assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(s.result["reason"], &"corridor_closed")
	var record := CampaignRecord.from_simulation(sim, 1, &"red", [])
	var copy := CampaignRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())))
	var replayed := Operation.from_definition(def, 1, Politics._grid(), Politics._country_map())
	var outcome := copy.replay_on(replayed)
	assert_true(outcome["ok"], str(outcome))
	assert_eq(replayed.snapshot(), s.snapshot())
	assert_eq(replayed.result, s.result)
	assert_eq(OperationVictory.score(replayed, def), OperationVictory.score(s, def), "same score")


func test_determinism_of_two_runs() -> void:
	var a := _closed_chain_state()
	var b := _closed_chain_state()
	for state in [a, b]:
		var sim := OperationalSimulation.new(state as OperationalState)
		for i in 4:
			sim.execute(EndOperationalTurnCommand.new())
	assert_eq(a.snapshot(), b.snapshot())


# --- the shipped data ---


func test_suwalki_data() -> void:
	var def := OperationDefinition.find(&"suwalki_gap")
	assert_eq(def.round_limit, 30)
	assert_eq(def.closed_rounds_to_win, 5)
	assert_eq(def.draw_margin, 5)
	var map := ImportedMap.find(def.map_id)
	var grid := map.to_grid()
	assert_eq(def.nato_link_from, _place_hex(map, "Suwałki"))
	assert_eq(def.nato_link_to, _place_hex(map, "Kaunas"))
	for hex in [def.nato_link_from, def.nato_link_to]:
		assert_true(grid.has_tile(hex) and grid.move_cost(hex) != Terrain.IMPASSABLE, "land")
	assert_eq([def.corridor_from_country, def.corridor_to_country], [&"russia", &"belarus"])
	var state := Operation.build(&"suwalki_gap", 1)
	assert_true(state != null, "the definition is valid")
	var points := {}
	for objective in def.objectives:
		assert_true(grid.has_tile(objective.hex_in(state)), "%s on the map" % objective.id)
		points[objective.id] = objective.points
	assert_eq(points, {&"chernyakhovsk": 5, &"bialystok": 5, &"vilnius": 5, &"grodno": 10})
	assert_eq(def.gap_open_points, 10)
	assert_eq(def.corridor_points, 10)
	assert_eq(def.escalation_penalty, 3)
	for goal in def.ai_goals:
		if goal.objective_id != &"":
			assert_true(state.get_objective(goal.objective_id) != null, goal.id)
			assert_true(goal.hex_in(state) != Vector2i.MAX)


func test_suwalki_start_holders() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	var def := state.definition
	assert_eq(HexControl.holder(state, def.nato_link_from), 0, "Suwałki starts Polish")
	assert_eq(OperationVictory.gap_status(state, def), OperationVictory.OPEN)
	assert_eq(OperationVictory.corridor_status(state, def), OperationVictory.OPEN)
	assert_eq(HexControl.holder(state, Vector2i(-6, 19)), 1, "Kaliningrad")
	var score := OperationVictory.score(state, def)
	assert_eq(score[0]["total"], 10, "Gap open only")
	assert_eq(score[1]["total"], 10, "Grodno, held from the start")


func test_suwalki_land_routes() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	var def := state.definition
	var corridor := OperationVictory.land_route(state, def, false)
	assert_true(corridor.size() > 2, "Kaliningrad and Belarus are joined by land")
	assert_eq(state.country_at(corridor[0]), &"russia")
	assert_eq(state.country_at(corridor[-1]), &"belarus")
	var gap := OperationVictory.land_route(state, def, true)
	assert_eq([gap[0], gap[-1]], [def.nato_link_from, def.nato_link_to])


## Russia closes the corridor along its shortest land route: NATO's link is cut too.
func test_suwalki_corridor_closes_by_any_held_route() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	var def := state.definition
	for hex in OperationVictory.land_route(state, def, false):
		state.hex_holders[hex] = 1
	assert_eq(OperationVictory.corridor_status(state, def), OperationVictory.CLOSED)
	assert_eq(OperationVictory.gap_status(state, def), OperationVictory.CUT)


func test_corridor_ai_goals_sit_on_shortest_routes() -> void:
	var def := OperationDefinition.find(&"suwalki_gap")
	var state := Operation.build(&"suwalki_gap", 1)
	var expected := {
		&"ru_take_corridor_choke": [1, AiGoal.TAKE, Vector2i(24, 29), 7],
		&"ru_take_corridor_mid": [1, AiGoal.TAKE, Vector2i(24, 33), 5],
		&"ru_take_corridor_end": [1, AiGoal.TAKE, Vector2i(24, 37), 4],
		&"nato_hold_corridor_choke": [0, AiGoal.HOLD, Vector2i(24, 29), 12],
		&"nato_hold_corridor_mid": [0, AiGoal.HOLD, Vector2i(29, 22), 10],
	}
	var corridor_steps := OperationVictory.land_route(state, def, false).size() - 1
	var gap_steps := OperationVictory.land_route(state, def, true).size() - 1
	var russia := OperationVictory.country_hexes(state, &"russia")
	var belarus := OperationVictory.country_hexes(state, &"belarus")
	var found := 0
	for goal in def.ai_goals:
		if not expected.has(goal.id):
			continue
		found += 1
		var want: Array = expected[goal.id]
		var hex := goal.hex_in(state)
		assert_eq([goal.player, goal.role, hex, goal.weight], want, goal.id)
		assert_true(state.grid.move_cost(hex) != Terrain.IMPASSABLE, "%s on land" % goal.id)
		# On a shortest route: the straight distances to both ends add up to its length.
		var through_corridor := _nearest(hex, russia) + _nearest(hex, belarus) == corridor_steps
		var through_gap := (
			Hex.distance(hex, def.nato_link_from) + Hex.distance(hex, def.nato_link_to) == gap_steps
		)
		assert_true(through_corridor if goal.player == 1 else through_gap, goal.id)
	assert_eq(found, expected.size())


static func _nearest(hex: Vector2i, hexes: Array[Vector2i]) -> int:
	var best := 1 << 30
	for other in hexes:
		best = mini(best, Hex.distance(hex, other))
	return best


# --- link validation ---


func _links_valid(edit: Callable, grid: HexGrid = null) -> bool:
	var op := _closed_chain_definition()
	edit.call(op)
	var used := Politics._grid() if grid == null else grid
	return Operation.from_definition(op, 1, used, Politics._country_map()) != null


func test_link_validation() -> void:
	assert_true(_links_valid(func(_op: OperationDefinition) -> void: pass), "the strip")
	var none := func(op: OperationDefinition) -> void:
		op.nato_link_from = Vector2i.MAX
		op.nato_link_to = Vector2i.MAX
		op.corridor_from_country = &""
		op.corridor_to_country = &""
	assert_true(_links_valid(none), "no connection objectives")
	var half := func(op: OperationDefinition) -> void: op.nato_link_to = Vector2i.MAX
	assert_false(_links_valid(half), "one link end")
	var off := func(op: OperationDefinition) -> void: op.nato_link_to = Vector2i(9, 0)
	assert_false(_links_valid(off), "off the map")
	var same := func(op: OperationDefinition) -> void: op.nato_link_to = op.nato_link_from
	assert_false(_links_valid(same), "the same hex")
	var water := Politics._grid()
	water.set_terrain(Vector2i(3, 1), Terrain.Type.WATER)
	assert_false(_links_valid(func(_op: OperationDefinition) -> void: pass, water), "water")
	var one := func(op: OperationDefinition) -> void: op.corridor_to_country = &""
	assert_false(_links_valid(one), "one corridor country")
	var twice := func(op: OperationDefinition) -> void: op.corridor_to_country = &"russia"
	assert_false(_links_valid(twice), "the same country")
	var unknown := func(op: OperationDefinition) -> void: op.corridor_to_country = &"latvia"
	assert_false(_links_valid(unknown), "not a country of the operation")


static func _place_hex(map: ImportedMap, place_name: String) -> Vector2i:
	for i in map.place_count():
		var place := map.place_at(i)
		if place["name"] == place_name:
			var at: Vector2 = place["position"]
			return Hex.from_world(Vector3(at.x, 0.0, at.y), 1.0)
	return Vector2i.MAX


# --- annihilation (TASK-164) ---


static func _annihilation_state(count_0: int, count_1: int) -> OperationalState:
	var s := _state()
	s.fielded_strength = [3, 3]
	for i in count_0:
		s.formations.append(Fixtures.formation(StringName("a%d" % i), 0))
	for i in count_1:
		s.formations.append(Fixtures.formation(StringName("b%d" % i), 1))
	return s


static func _package(
	side: int, requested_turn: int, waiting_count: int, withdrawn := false
) -> SupportState:
	var package := SupportPackage.new()
	package.id = StringName("pkg_%d" % side)
	package.side = side
	var support := SupportState.from_package(package)
	support.requested_turn = requested_turn
	support.withdrawn = withdrawn
	for i in waiting_count:
		support.waiting.append(FormationPlacement.new())
	return support


func test_annihilation_side_one_wiped() -> void:
	var s := _annihilation_state(1, 0)
	var events := OperationVictory.annihilation(s)
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], &"operation_ended")
	assert_eq(events[0]["winner"], 0)
	assert_eq(events[0]["by"], 0)
	assert_eq(events[0]["reason"], &"annihilation")
	assert_true(events[0]["score"].has(0) and events[0]["score"].has(1))
	assert_eq(s.result, {"winner": 0, "reason": &"annihilation", "by": 0})


func test_annihilation_side_zero_wiped_and_both_wiped() -> void:
	var s := _annihilation_state(0, 2)
	var events := OperationVictory.annihilation(s)
	assert_eq(events[0]["winner"], 1)
	assert_eq(events[0]["by"], 1)
	var both := _annihilation_state(0, 0)
	events = OperationVictory.annihilation(both)
	assert_eq(events[0]["winner"], -1)
	assert_eq(events[0]["by"], -1)
	assert_eq(events[0]["reason"], &"annihilation")


func test_annihilation_needs_both_sides_dead_to_be_a_draw_not_one() -> void:
	var s := _annihilation_state(1, 1)
	assert_eq(OperationVictory.annihilation(s), [] as Array[Dictionary])
	assert_true(s.result.is_empty())


func test_annihilation_pending_support_keeps_a_side_in_the_game() -> void:
	var s := _annihilation_state(1, 0)
	s.support.append(_package(1, 3, 2))
	assert_eq(OperationVictory.annihilation(s), [] as Array[Dictionary])
	s.support[0].withdrawn = true
	assert_eq(OperationVictory.annihilation(s).size(), 1, "withdrawn")
	var empty := _annihilation_state(1, 0)
	empty.support.append(_package(1, 3, 0))
	assert_eq(OperationVictory.annihilation(empty).size(), 1, "nothing waiting")


func test_annihilation_ignores_unrequested_and_enemy_support() -> void:
	var s := _annihilation_state(1, 0)
	s.support.append(_package(1, -1, 2))
	s.support.append(_package(0, 3, 2))
	assert_eq(OperationVictory.annihilation(s).size(), 1)


func test_annihilation_never_fielded_or_no_definition() -> void:
	var s := _annihilation_state(1, 0)
	s.fielded_strength = [3, 0]
	assert_eq(OperationVictory.annihilation(s), [] as Array[Dictionary])
	var bare := OperationalState.new()
	bare.fielded_strength = [3, 3]
	assert_eq(OperationVictory.annihilation(bare), [] as Array[Dictionary])


func test_annihilation_does_nothing_after_the_end() -> void:
	var s := _annihilation_state(1, 0)
	s.result = {"winner": -1, "reason": &"nuclear_use", "by": 1}
	assert_eq(OperationVictory.annihilation(s), [] as Array[Dictionary])
	assert_eq(s.result["reason"], &"nuclear_use")


func test_end_round_checks_annihilation_before_corridor_closed_and_ignores_score() -> void:
	var s := _annihilation_state(1, 0)
	_hold_corridor(s, 1)
	s.corridor_closed_rounds = s.definition.closed_rounds_to_win - 1
	var events := OperationVictory.end_round(s, 5)
	assert_eq(events[0]["reason"], &"annihilation")
	assert_eq(events[0]["winner"], 0)
	var low := _annihilation_state(0, 1)
	_hold(low, Vector2i(0, 5), 0)
	_hold(low, Vector2i(0, 8), 0)
	events = OperationVictory.end_round(low, 5)
	assert_eq(events[0]["winner"], 1, "side 0 has the higher score but no formations")
