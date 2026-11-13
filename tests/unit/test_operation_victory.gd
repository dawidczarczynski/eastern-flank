extends TestCase
## Victory of an operation (TASK-107a): Gap status, scoring, the penalty and the endings.

const Data := preload("res://tests/unit/test_contribution_data.gd")
const Politics := preload("res://tests/unit/test_country_rules.gd")

const CHAIN: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]


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
## (0, 7) 5 for side 1, Grodno (0, 8) 5 for whoever holds it; the 4-hex chain on row 0.
static func _state() -> OperationalState:
	var s := OperationalState.new()
	var def := OperationDefinition.new()
	def.gap_chain = CHAIN.duplicate()
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
	return s


static func _hold(s: OperationalState, hex: Vector2i, side: int) -> void:
	s.hex_holders[hex] = side


static func _hold_chain(s: OperationalState, side: int, count: int = 4) -> void:
	for i in count:
		_hold(s, CHAIN[i], side)


# --- gap status ---


func test_gap_status() -> void:
	var s := _state()
	assert_eq(OperationVictory.gap_status(s, s.definition), OperationVictory.OPEN)
	_hold_chain(s, 1, 3)
	assert_eq(OperationVictory.gap_status(s, s.definition), OperationVictory.OPEN, "3 of 4")
	_hold_chain(s, 1)
	assert_eq(OperationVictory.gap_status(s, s.definition), OperationVictory.CLOSED)
	_hold(s, CHAIN[1], 0)
	assert_eq(OperationVictory.gap_status(s, s.definition), OperationVictory.OPEN, "NATO hex")
	_hold(s, CHAIN[1], -1)
	assert_eq(OperationVictory.gap_status(s, s.definition), OperationVictory.OPEN, "unheld hex")


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


func test_closed_gap_scores_for_side_one() -> void:
	var s := _state()
	_hold_chain(s, 1)
	var score := OperationVictory.score(s, s.definition)
	assert_eq(score[1]["total"], 10)
	assert_eq(score[0]["total"], 0, "no open-Gap points")


# --- endings ---


func test_closed_rounds_to_win() -> void:
	var s := _state()
	_hold_chain(s, 1)
	assert_eq(OperationVictory.end_round(s, 7), [] as Array[Dictionary])
	assert_eq(s.gap_closed_rounds, 1)
	var events := OperationVictory.end_round(s, 8)
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], &"operation_ended")
	assert_eq(events[0]["winner"], 1)
	assert_eq(events[0]["reason"], &"gap_closed")
	assert_eq(s.result["winner"], 1)
	assert_eq(events[0]["score"][1]["total"], 10)


func test_a_lost_chain_resets_the_counter() -> void:
	var s := _state()
	_hold_chain(s, 1)
	OperationVictory.end_round(s, 7)
	_hold(s, CHAIN[2], 0)
	assert_eq(OperationVictory.end_round(s, 8), [] as Array[Dictionary])
	assert_eq(s.gap_closed_rounds, 0)
	assert_eq(s.snapshot()["gap_closed_rounds"], 0)
	_hold(s, CHAIN[2], 1)
	assert_eq(OperationVictory.end_round(s, 9), [] as Array[Dictionary])
	assert_eq(s.gap_closed_rounds, 1)
	assert_eq(s.snapshot()["gap_closed_rounds"], 1)


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


func test_gap_closed_is_checked_before_the_round_limit() -> void:
	var s := _state()
	_hold_chain(s, 1)
	s.gap_closed_rounds = 1
	var events := OperationVictory.end_round(s, 30)
	assert_eq(events[0]["reason"], &"gap_closed")


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


func test_the_command_ends_the_operation_after_two_closed_rounds() -> void:
	var s := _closed_chain_state()
	var sim := OperationalSimulation.new(s)
	var types: Array = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: types.append(e["type"]))
	for i in 3:
		assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_true(s.result.is_empty(), "one full round and a half")
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(s.result["reason"], &"gap_closed")
	assert_eq(s.result["winner"], 1)
	assert_true(types.has(&"operation_ended"))
	assert_false(sim.execute(EndOperationalTurnCommand.new()))


## Strip operation (row 0: belarus q4-5, russia q6-7) whose 3-hex chain (5..7, 0) side 1 holds
## from the start with its own formations; side 0 stands on (0, 0).
static func _closed_chain_definition() -> OperationDefinition:
	var op := Politics._definition()
	op.first_player = 0
	op.formations = (
		[
			Data.placement(&"blue_1", 0, Vector2i(0, 0)),
			Data.placement(&"red_1", 1, Vector2i(5, 0)),
			Data.placement(&"red_2", 1, Vector2i(6, 0)),
			Data.placement(&"red_3", 1, Vector2i(7, 0)),
		]
		as Array[FormationPlacement]
	)
	op.gap_chain = [Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0)] as Array[Vector2i]
	return op


static func _grid_with_roads() -> HexGrid:
	var grid := Politics._grid()
	var east := Hex.DIRECTIONS.find(Vector2i(1, 0))
	var west := Hex.DIRECTIONS.find(Vector2i(-1, 0))
	for q in range(5, 8):
		grid.set_road_links(
			Vector2i(q, 0), (1 << east if q < 7 else 0) | (1 << west if q > 5 else 0)
		)
	return grid


static func _closed_chain_state() -> OperationalState:
	return Operation.from_definition(
		_closed_chain_definition(), 1, _grid_with_roads(), Politics._country_map()
	)


# --- campaign record ---


func test_a_gap_closed_record_replays_to_the_same_result() -> void:
	var def := _closed_chain_definition()
	var s := _closed_chain_state()
	var sim := OperationalSimulation.new(s)
	for i in 4:
		assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(s.result["reason"], &"gap_closed")
	var record := CampaignRecord.from_simulation(sim, 1, &"red", [])
	var copy := CampaignRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())))
	var replayed := Operation.from_definition(def, 1, _grid_with_roads(), Politics._country_map())
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
	assert_eq(def.closed_rounds_to_win, 2)
	assert_eq(def.draw_margin, 5)
	assert_true(def.gap_chain.size() >= 3)
	var map := ImportedMap.find(def.map_id)
	var grid := map.to_grid()
	for index in def.gap_chain.size():
		var hex := def.gap_chain[index]
		assert_true(grid.has_tile(hex) and grid.move_cost(hex) != Terrain.IMPASSABLE, "land")
		if index > 0:
			assert_true(grid.has_road(def.gap_chain[index - 1], hex), "road link at %d" % index)
	assert_eq(def.gap_chain[0], _place_hex(map, "Suwałki"))
	assert_eq(def.gap_chain[def.gap_chain.size() - 1], _place_hex(map, "Marijampolė"))
	var state := Operation.build(&"suwalki_gap", 1)
	assert_true(state != null, "the definition is valid")
	var points := {}
	for objective in def.objectives:
		assert_true(grid.has_tile(objective.hex_in(state)), "%s on the map" % objective.id)
		points[objective.id] = objective.points
	assert_eq(points, {&"chernyakhovsk": 5, &"bialystok": 5, &"vilnius": 5, &"grodno": 40})
	assert_eq(def.gap_open_points, 10)
	assert_eq(def.gap_closed_points, 10)
	assert_eq(def.escalation_penalty, 3)
	for goal in def.ai_goals:
		if goal.objective_id != &"":
			assert_true(state.get_objective(goal.objective_id) != null, goal.id)
			assert_true(goal.hex_in(state) != Vector2i.MAX)


func test_suwalki_start_holders() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	var def := state.definition
	assert_eq(HexControl.holder(state, def.gap_chain[0]), 0, "Suwałki starts Polish")
	assert_eq(OperationVictory.gap_status(state, def), OperationVictory.OPEN)
	assert_eq(HexControl.holder(state, Vector2i(-6, 19)), 1, "Kaliningrad")
	var score := OperationVictory.score(state, def)
	assert_eq(score[0]["total"], 10, "Gap open only")
	assert_eq(score[1]["total"], 40, "Grodno, held from the start")


static func _place_hex(map: ImportedMap, place_name: String) -> Vector2i:
	for i in map.place_count():
		var place := map.place_at(i)
		if place["name"] == place_name:
			var at: Vector2 = place["position"]
			return Hex.from_world(Vector3(at.x, 0.0, at.y), 1.0)
	return Vector2i.MAX
