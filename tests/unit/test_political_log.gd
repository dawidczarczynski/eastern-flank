extends TestCase
## PoliticalLog (TASK-119a): one entry per event, effects only, cap, codec, replay determinism.

const Decisions := preload("res://tests/unit/test_political_decisions.gd")


static func _log_after(first_player: int) -> Array:
	var s := Decisions._setup()
	s.current_player = first_player
	var sim := OperationalSimulation.new(s)
	sim.execute(EscalateCommand.new())
	return s.political_log.entries.map(
		func(e: PoliticalLog.Entry) -> Dictionary: return e.to_dict()
	)


func _state() -> OperationalState:
	return Decisions._setup()


func test_starts_empty_and_snapshot_has_the_log() -> void:
	var s := _state()
	assert_eq(s.political_log.size(), 0)
	assert_eq((s.snapshot()["political_log"] as Array).size(), 0)


func test_escalate_logs_decision_then_level() -> void:
	var s := _state()
	var sim := OperationalSimulation.new(s)
	assert_true(sim.execute(EscalateCommand.new()))
	var kinds := s.political_log.entries.map(func(e: PoliticalLog.Entry) -> Variant: return e.kind)
	assert_eq(kinds, [&"decision", &"level_changed"])
	var level := s.political_log.entries[1]
	assert_eq(level.level_before, 1)
	assert_eq(level.level_after, 2)
	assert_eq(level.cause, &"decision")
	assert_eq(level.side, -1)
	assert_eq(s.political_log.entries[0].cause, &"escalate")
	assert_eq(s.political_log.entries[0].turn, s.turn)


func test_rejected_command_appends_nothing() -> void:
	var s := _state()
	s.decisions_left = 0
	var sim := OperationalSimulation.new(s)
	assert_false(sim.execute(EscalateCommand.new()))
	assert_eq(s.political_log.size(), 0)


func test_entries_do_not_name_the_deciding_side() -> void:
	var a := _log_after(0)
	var b := _log_after(1)
	assert_eq(a.size(), b.size())
	for i in a.size():
		assert_eq(a[i], b[i])


func test_stance_breach_and_contribution_events() -> void:
	var s := _state()
	var log := s.political_log
	(
		log
		. on_event(
			s,
			{
				"type": &"country_stance_changed",
				"country": &"lithuania",
				"stance": &"aligned",
				"side": 0,
				"previous_stance": &"neutral",
				"previous_side": -1,
				"cause": &"escalation",
				"by": 1,
			}
		)
	)
	log.on_event(s, {"type": &"sanctuary_breached", "country": &"belarus", "player": 0})
	(
		log
		. on_event(
			s,
			{
				"type": &"formation_joined",
				"formation_id": &"lt_1",
				"player": 0,
				"country": &"lithuania",
				"source": &"contribution",
			}
		)
	)
	log.on_event(s, {"type": &"formation_joined", "player": 0, "source": &"package"})
	log.on_event(s, {"type": &"unit_moved"})
	assert_eq(log.size(), 3)
	var stance := log.entries[0]
	assert_eq(stance.kind, &"stance_changed")
	assert_eq(stance.side, 0)
	assert_eq(stance.stance_before, &"neutral")
	assert_eq(stance.stance_after, &"aligned")
	assert_eq(stance.cause, &"escalation")
	assert_eq(log.entries[1].side, -1)
	assert_eq(log.entries[1].country, &"belarus")
	assert_eq(log.entries[2].side, 0)
	assert_eq(log.entries[2].args["formation_id"], "lt_1")


func test_cap_drops_the_oldest() -> void:
	var s := _state()
	for i in 61:
		s.turn = i
		s.political_log.on_event(s, {"type": &"sanctuary_breached", "country": &"belarus"})
	assert_eq(s.political_log.size(), 60)
	assert_eq(s.political_log.entries[0].turn, 1)
	assert_eq(s.political_log.entries[59].turn, 60)


func test_json_round_trip_and_strictness() -> void:
	var s := _state()
	var sim := OperationalSimulation.new(s)
	sim.execute(EscalateCommand.new())
	var d := s.political_log.to_dict()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(d))
	var back := PoliticalLog.from_dict(parsed)
	assert_true(back != null)
	assert_eq(back.to_dict(), d)
	var bad: Dictionary = (d["entries"][0] as Dictionary).duplicate()
	bad.erase("turn")
	assert_true(PoliticalLog.Entry.from_dict(bad) == null)
	bad = (d["entries"][0] as Dictionary).duplicate()
	bad["kind"] = "nonsense"
	assert_true(PoliticalLog.Entry.from_dict(bad) == null)
	bad = (d["entries"][0] as Dictionary).duplicate()
	bad["key"] = 5
	assert_true(PoliticalLog.Entry.from_dict(bad) == null)


func test_missing_log_is_empty_and_long_log_keeps_the_last_60() -> void:
	assert_eq(PoliticalLog.from_dict({}).size(), 0)
	assert_eq(PoliticalLog.from_dict(null).size(), 0)
	var s := _state()
	var entries: Array = []
	for i in 70:
		s.turn = i
		s.political_log.on_event(s, {"type": &"sanctuary_breached", "country": &"belarus"})
	for e in s.political_log.entries:
		entries.append(e.to_dict())
	var long_dict := {"entries": entries + entries}
	var loaded := PoliticalLog.from_dict(long_dict)
	assert_eq(loaded.size(), 60)


func test_reading_the_log_does_not_touch_the_rng() -> void:
	var a := _state()
	var b := _state()
	OperationalSimulation.new(a).execute(EscalateCommand.new())
	OperationalSimulation.new(b).execute(EscalateCommand.new())
	b.political_log.to_dict()
	assert_eq(a.rng.state, b.rng.state)
	assert_eq(a.political_log.to_dict(), b.political_log.to_dict())


func test_same_commands_give_equal_logs() -> void:
	var logs: Array[Dictionary] = []
	for _run in 2:
		var s := _state()
		var sim := OperationalSimulation.new(s)
		sim.execute(EscalateCommand.new())
		s.pending_battles.clear()
		sim.execute(EndOperationalTurnCommand.new())
		sim.execute(StandDownCommand.new())
		logs.append(s.political_log.to_dict())
	assert_true(logs[0]["entries"].size() >= 3)
	assert_eq(logs[0], logs[1])
