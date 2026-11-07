extends TestCase
## Operational turns (TASK-093b): EndOperationalTurnCommand, its codec form and OperationalClock.


static func _state(first_player := 1) -> OperationalState:
	var state := OperationalState.new()
	state.first_player = first_player
	state.current_player = first_player
	return state


func test_turn_order_and_events() -> void:
	var sim := OperationalSimulation.new(_state(1))
	var events: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(sim.state.turn, 1)
	assert_eq(sim.state.current_player, 0)
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(sim.state.turn, 2)
	assert_eq(sim.state.current_player, 1)
	var types: Array = []
	for e in events:
		types.append(e["type"])
	assert_eq(
		types,
		[
			&"operational_turn_ended",
			&"operational_turn_started",
			&"operational_turn_ended",
			&"operational_turn_started",
		]
	)
	assert_eq(events[0]["player"], 1)
	assert_eq(events[1]["player"], 0)
	assert_eq(events[1]["turn"], 1)
	assert_eq(events[2]["player"], 0)
	assert_eq(events[3]["player"], 1)
	assert_eq(events[3]["turn"], 2)


func test_first_player_zero_increments_on_player_zero() -> void:
	var sim := OperationalSimulation.new(_state(0))
	sim.execute(EndOperationalTurnCommand.new())
	assert_eq(sim.state.turn, 1)
	sim.execute(EndOperationalTurnCommand.new())
	assert_eq(sim.state.turn, 2)
	assert_eq(sim.state.current_player, 0)


func test_rejected_while_battle_pending() -> void:
	var state := _state()
	state.pending_battles.append(BattleSetup.new())
	var sim := OperationalSimulation.new(state)
	var reasons: Array[String] = []
	sim.command_rejected.connect(func(_c: OperationalCommand, r: String) -> void: reasons.append(r))
	assert_false(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(reasons, ["battle_pending"] as Array[String])
	assert_eq(state.turn, 1)
	assert_eq(state.current_player, 1)


func test_codec_round_trip() -> void:
	var d := EndOperationalTurnCommand.new().to_dict()
	assert_eq(d, {"type": "end_operational_turn"})
	var back := OperationalCommandCodec.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_true(back is EndOperationalTurnCommand)


func test_codec_rejects_other_types() -> void:
	assert_true(OperationalCommandCodec.from_dict({"type": "end_turn"}) == null)
	assert_true(OperationalCommandCodec.from_dict({"type": "nope"}) == null)
	assert_true(OperationalCommandCodec.from_dict({}) == null)


func test_clock_day_and_night() -> void:
	assert_true(OperationalClock.is_day(1))
	assert_false(OperationalClock.is_day(2))
	assert_true(OperationalClock.is_day(3))
	assert_eq(OperationalClock.time_of_day(1), "06:00–18:00")
	assert_eq(OperationalClock.time_of_day(2), "18:00–06:00")


func test_clock_date() -> void:
	assert_eq(OperationalClock.date(1, "2027-06-14"), "2027-06-14")
	assert_eq(OperationalClock.date(2, "2027-06-14"), "2027-06-14", "night starts the same day")
	assert_eq(OperationalClock.date(3, "2027-06-14"), "2027-06-15")
	assert_eq(OperationalClock.date(61, "2027-06-14"), "2027-07-14")
	assert_eq(OperationalClock.date(1, ""), "", "no start date, no date")
	assert_eq(OperationalClock.date(1, "garbage"), "")
