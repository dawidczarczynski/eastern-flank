extends TestCase
## The nuclear attack (TASK-140, GDD "Escalation ladder"): NuclearStrikeCommand, the side flag
## may_use_nuclear and the end reason nuclear_use.

const Politics := preload("res://tests/unit/test_country_rules.gd")
const Collapse := preload("res://tests/unit/test_collapse.gd")


## Strip where player 1 (red) may use a nuclear weapon, at level 5, player 1 to move, in collapse
## (fielded 400, 200 left).
static func _state(nuclear_player := 1) -> OperationalState:
	var op := Politics._definition()
	op.sides[nuclear_player].may_use_nuclear = true
	var s := Politics._strip(op)
	s.escalation_level = s.ladder.top() - 1
	s.current_player = nuclear_player
	s.fielded_strength[nuclear_player] = 400
	s.formations.append(Collapse._company_formation(&"f", nuclear_player, 400, 200, 100))
	return s


static func _sim(s: OperationalState, rejected: Array[String]) -> OperationalSimulation:
	var sim := OperationalSimulation.new(s)
	sim.command_rejected.connect(
		func(_c: OperationalCommand, r: String) -> void: rejected.append(r)
	)
	return sim


func test_side_data_flag() -> void:
	assert_true(SideDefinition.find(&"russia").may_use_nuclear)
	assert_false(SideDefinition.find(&"nato").may_use_nuclear)
	assert_eq(Politics._strip().may_use_nuclear, [false, false] as Array[bool])
	assert_eq(_state().may_use_nuclear, [false, true] as Array[bool])


func test_nuclear_strike_ends_the_operation() -> void:
	var s := _state()
	s.pending_battles.clear()
	var rng_before := s.rng.state
	var command := NuclearStrikeCommand.new()
	assert_eq(command.validate(s), "")
	var events := command.apply(s)
	assert_eq(s.escalation_level, 6)
	assert_eq(s.escalation_caused, [0, 1])
	assert_eq(s.decisions_left, 0, "counts as the decision of the turn")
	assert_eq(s.result, {"winner": -1, "reason": &"nuclear_use", "by": 1})
	var types: Array = events.map(func(e: Dictionary) -> Variant: return e["type"])
	assert_eq(types, [&"political_decision_taken", &"escalation_changed", &"operation_ended"])
	assert_eq(events[0]["decision"], &"nuclear_strike")
	assert_eq(events[1]["level"], 6)
	assert_eq(events[1]["previous"], 5)
	assert_eq(events[1]["by"], 1)
	assert_eq(events[2]["reason"], &"nuclear_use")
	assert_eq(events[2]["by"], 1)
	assert_eq(events[2]["winner"], -1, "nobody wins")
	assert_eq(s.rng.state, rng_before, "no rng draws")


func test_nuclear_strike_mirrored() -> void:
	var s := _state(0)
	assert_eq(NuclearStrikeCommand.new().validate(s), "")
	NuclearStrikeCommand.new().apply(s)
	assert_eq(s.result, {"winner": -1, "reason": &"nuclear_use", "by": 0})


func test_pending_battles_dropped() -> void:
	var s := _state()
	s.pending_battles.append(BattleSetup.new())
	assert_eq(NuclearStrikeCommand.new().validate(s), "battle_pending")
	NuclearStrikeCommand.new().apply(s)
	assert_true(s.pending_battles.is_empty())
	var rejected: Array[String] = []
	var after := _sim(s, rejected)
	after.execute(EndOperationalTurnCommand.new())
	after.execute(NuclearStrikeCommand.new())
	assert_eq(rejected, ["operation_over", "operation_over"], "level 6 is final")


func test_rejections_in_order() -> void:
	var over := _state()
	over.result = {"winner": -1, "reason": &"nuclear_use", "by": 1}
	assert_eq(NuclearStrikeCommand.new().validate(over), "operation_over")
	var nato := _state()
	nato.current_player = 0
	nato.fielded_strength[0] = 400
	assert_eq(NuclearStrikeCommand.new().validate(nato), "not_nuclear_power", "always for NATO")
	nato.escalation_level = 1
	assert_eq(NuclearStrikeCommand.new().validate(nato), "not_nuclear_power")
	var low := _state()
	low.escalation_level = 4
	assert_eq(NuclearStrikeCommand.new().validate(low), "level_too_low")
	low.formations[0].companies[0].strength = 400
	assert_eq(NuclearStrikeCommand.new().validate(low), "level_too_low")
	var steady := _state()
	steady.formations[0].companies[0].strength = 204
	assert_eq(NuclearStrikeCommand.new().validate(steady), "no_collapse")


func test_common_decision_rules() -> void:
	var s := _state()
	s.decisions_left = 0
	assert_eq(NuclearStrikeCommand.new().validate(s), "no_decisions_left")
	var standing := _state()
	standing.stand_down_until[1] = standing.turn + 2
	assert_eq(NuclearStrikeCommand.new().validate(standing), "", "not blocked by standing down")
	var used := _state()
	var sim := OperationalSimulation.new(used)
	used.result = {}
	assert_true(sim.execute(EscalateCommand.new()) == false, "Escalate capped at 5")
	assert_eq(used.decisions_left, 1)


func test_codec_and_replay() -> void:
	var s := _state()
	var sim := OperationalSimulation.new(s)
	assert_true(sim.execute(NuclearStrikeCommand.new()))
	var d: Variant = JSON.parse_string(JSON.stringify(sim.history[0].to_dict()))
	var decoded := OperationalCommandCodec.from_dict(d as Dictionary)
	assert_true(decoded is NuclearStrikeCommand)
	var replay_state := _state()
	assert_true(OperationalSimulation.new(replay_state).execute(decoded))
	assert_eq(replay_state.snapshot(), s.snapshot())
