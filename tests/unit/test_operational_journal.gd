extends TestCase
## OperationalJournal (TASK-148a): per-side view of one history, folded strikes, codec, replay.

const Contact := preload("res://tests/unit/test_contact.gd")
const Decisions := preload("res://tests/unit/test_political_decisions.gd")
const Strikes := preload("res://tests/unit/test_strikes.gd")


## Contact state: "f" (player 0) ordered to (6, 0), "e" (player 1) on (4, 1); plays to the contact.
func _contact_run() -> OperationalSimulation:
	var state := Contact._state()
	state.rng.seed = 7
	var sim := OperationalSimulation.new(state)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(6, 0), &"advance")))
	for i in 3:
		assert_true(sim.execute(EndOperationalTurnCommand.new()))
	return sim


func _resolve(sim: OperationalSimulation) -> void:
	var setup := sim.state.pending_battles[0]
	assert_true(sim.execute(ResolveBattleCommand.new(Contact.new()._result_for(setup, 0))))


func _strike_run() -> OperationalSimulation:
	var state := Strikes._state()
	state.escalation_level = 2
	state.strike_stock[0][&"sure"] = 6
	var sim := OperationalSimulation.new(state)
	assert_true(sim.execute(StrikeCommand.new(&"sure", &"a1", 2)))
	return sim


func _kinds(entries: Array[OperationalJournal.Entry]) -> Array:
	return entries.map(func(e: OperationalJournal.Entry) -> Variant: return e.kind)


func test_starts_empty_and_snapshot_has_the_journal() -> void:
	var s := Contact._state()
	assert_eq(s.journal.entries.size(), 0)
	assert_eq((s.snapshot()["journal"] as Array).size(), 0)


func test_order_and_posture_entries_belong_to_the_owner() -> void:
	var s := Contact._state()
	var sim := OperationalSimulation.new(s)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(6, 0), &"advance")))
	assert_true(sim.execute(SetPostureCommand.new(&"f", &"defend")))
	assert_true(sim.execute(CancelOrderCommand.new(&"f")))
	assert_eq(_kinds(s.journal.entries), [&"order_issued", &"posture_changed", &"order_cancelled"])
	assert_eq(s.journal.entries_for(0).size(), 3)
	assert_eq(s.journal.entries_for(1).size(), 0)
	var first := s.journal.entries[0]
	assert_eq(first.category, &"move")
	assert_eq(first.actor, 0)
	assert_eq(first.turn, s.turn)
	assert_true(first.has_coord)
	assert_eq(first.coord, Vector2i(6, 0))


func test_contact_is_seen_by_both_and_far_moves_only_by_the_mover() -> void:
	var sim := _contact_run()
	var s := sim.state
	var kinds0 := _kinds(s.journal.entries_for(0))
	var kinds1 := _kinds(s.journal.entries_for(1))
	assert_true(kinds0.has(&"formation_halted"), "halt in contact seen by the mover")
	assert_true(kinds1.has(&"formation_halted"), "halt in contact seen by the enemy")
	assert_true(kinds0.has(&"battle_pending") and kinds1.has(&"battle_pending"))
	assert_true(kinds0.has(&"formation_moved"))
	assert_false(kinds1.has(&"formation_moved"), "a move elsewhere is not shown to the enemy")
	assert_false(kinds0.has(&"operational_turn_ended"), "turn markers are not written")


func test_battle_entries_are_seen_by_both() -> void:
	var sim := _contact_run()
	_resolve(sim)
	for side in 2:
		var kinds := _kinds(sim.state.journal.entries_for(side))
		assert_true(kinds.has(&"battle_resolved"), "side %d" % side)
		assert_true(kinds.has(&"battle_consequences"), "side %d" % side)
	var resolved: OperationalJournal.Entry = null
	for e in sim.state.journal.entries:
		if e.kind == &"battle_resolved":
			resolved = e
	assert_eq(resolved.category, &"battle")
	assert_eq(resolved.args["winner"], 0)
	assert_eq(resolved.args["reason"], "turn_limit")


func test_a_strike_is_one_entry_with_its_effects_folded_in() -> void:
	var sim := _strike_run()
	var strikes := sim.state.journal.entries.filter(
		func(e: OperationalJournal.Entry) -> bool: return e.category == &"strike"
	)
	assert_eq(strikes.size(), 1)
	var e: OperationalJournal.Entry = strikes[0]
	assert_eq(e.kind, &"strike")
	assert_eq(e.actor, 0)
	assert_true(e.has_coord)
	assert_eq(e.args["means"], "sure")
	assert_eq(e.args["count"], 2)
	assert_eq(e.args["class_id"], "airfield")
	assert_eq(e.args["hits"], 2)
	assert_eq(e.args["intercepted"], 0)
	assert_true(e.args.has("damage"))
	assert_eq(e.args["target_destroyed"], false)
	assert_eq(e.args["before"], 100)
	assert_true(int(e.args["after"]) < int(e.args["before"]))
	assert_eq(sim.state.journal.entries_for(0).size(), sim.state.journal.entries_for(1).size())
	for side in 2:
		assert_true(_kinds(sim.state.journal.entries_for(side)).has(&"strike"))


func test_political_entries_are_bare_effects() -> void:
	var a := _escalate_journal(0)
	var b := _escalate_journal(1)
	assert_true(a.size() >= 2)
	assert_eq(a, b, "who decided is not stored")
	var s := Decisions._setup()
	OperationalSimulation.new(s).execute(EscalateCommand.new())
	for e in s.journal.entries:
		assert_eq(e.category, &"politics")
		assert_eq(e.actor, -1)
		assert_eq(e.involved.size(), 0)
	assert_eq(_kinds(s.journal.entries_for(1)), [&"decision", &"level_changed"])


func _escalate_journal(first_player: int) -> Array:
	var s := Decisions._setup()
	s.current_player = first_player
	OperationalSimulation.new(s).execute(EscalateCommand.new())
	return s.journal.entries.map(
		func(e: OperationalJournal.Entry) -> Dictionary: return e.to_dict()
	)


func test_other_events_and_rejected_commands_append_nothing() -> void:
	var s := Contact._state()
	var j := s.journal
	for type in [
		&"operational_turn_started",
		&"operational_turn_ended",
		&"strike_stock_changed",
		&"formation_readiness_changed",
		&"installation_changed",
		&"installation_suppressed",
		&"unit_moved",
	]:
		j.on_event(s, {"type": type, "id": &"x", "cause": &"repair"})
	assert_eq(j.entries.size(), 0)
	var sim := OperationalSimulation.new(s)
	assert_false(sim.execute(CancelOrderCommand.new(&"f")))
	assert_eq(j.entries.size(), 0)


func test_perspective_strike_battle_and_remote_move() -> void:
	var s := Contact._state()
	var j := s.journal
	j.on_event(
		s,
		{
			"type": &"strike_launched",
			"player": 0,
			"means": &"sure",
			"count": 1,
			"target": &"a1",
			"coord": Vector2i(6, 0)
		}
	)
	j.on_event(s, {"type": &"strike_resolved", "player": 0, "hits": 1, "intercepted": 0})
	j.on_event(
		s,
		{
			"type": &"battle_pending",
			"attacker_id": &"f",
			"defender_id": &"e",
			"at": Vector2i(1, 0),
			"index": 0
		}
	)
	# A side-1 move far from side 0, then a side-1 halt next to side 0's formation.
	(
		j
		. on_event(
			s,
			{
				"type": &"formation_moved",
				"formation_id": &"e",
				"from": Vector2i(9, 1),
				"to": Vector2i(8, 1),
				"path": [Vector2i(8, 1)],
				"cost": 1,
			}
		)
	)
	s.formations[1].coord = Vector2i(1, 0)
	j.on_event(s, {"type": &"formation_halted", "formation_id": &"e", "at": Vector2i(1, 0)})
	assert_eq(_kinds(j.entries_for(0)), [&"strike", &"battle_pending", &"formation_halted"])
	assert_eq(
		_kinds(j.entries_for(1)),
		[&"strike", &"battle_pending", &"formation_moved", &"formation_halted"]
	)


func test_json_round_trip_and_strictness() -> void:
	var sim := _contact_run()
	_resolve(sim)
	var d := sim.state.journal.to_dict()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(d))
	var back := OperationalJournal.from_dict(parsed)
	assert_true(back != null)
	assert_eq(back.to_dict(), d)
	var first: Dictionary = (d["entries"] as Array)[0]
	var bad := first.duplicate()
	bad.erase("turn")
	assert_true(OperationalJournal.Entry.from_dict(bad) == null)
	bad = first.duplicate()
	bad["kind"] = "nonsense"
	assert_true(OperationalJournal.Entry.from_dict(bad) == null)
	bad = first.duplicate()
	bad["category"] = 3
	assert_true(OperationalJournal.Entry.from_dict(bad) == null)
	bad = first.duplicate()
	bad["coord"] = [1]
	assert_true(OperationalJournal.Entry.from_dict(bad) == null)
	assert_true(OperationalJournal.from_dict({"entries": [bad]}) == null)
	assert_true(OperationalJournal.from_dict("x") == null)


func test_missing_journal_loads_empty() -> void:
	assert_eq(OperationalJournal.from_dict(null).entries.size(), 0)
	assert_eq(OperationalJournal.from_dict({}).entries.size(), 0)


func test_same_commands_give_equal_journals_and_reading_keeps_the_rng() -> void:
	var dicts: Array[Dictionary] = []
	var rngs: Array[int] = []
	for _run in 2:
		var sim := _contact_run()
		_resolve(sim)
		sim.state.journal.entries_for(0)
		sim.state.journal.to_dict()
		dicts.append(sim.state.journal.to_dict())
		rngs.append(sim.state.rng.state)
	assert_true(dicts[0]["entries"].size() >= 6)
	assert_eq(dicts[0], dicts[1])
	assert_eq(rngs[0], rngs[1])
	var s := Contact._state()
	var before := s.rng.state
	OperationalSimulation.new(s).execute(IssueOrderCommand.new(&"f", Vector2i(6, 0), &"advance"))
	assert_eq(s.rng.state, before)


func test_strike_replay_gives_an_equal_journal() -> void:
	var dicts: Array[Dictionary] = []
	for _run in 2:
		dicts.append(_strike_run().state.journal.to_dict())
	assert_eq(dicts[0], dicts[1])
