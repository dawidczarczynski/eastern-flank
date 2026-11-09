extends TestCase
## Auto-resolve in the operation (TASK-120): the `auto_mismatch` check of ResolveBattleCommand and
## auto entries of a CampaignRecord.

const Fixtures := preload("res://tests/fixtures.gd")


func _contact_state() -> OperationalState:
	var state := Operation.build(&"suwalki_gap", 1)
	assert_false(Fixtures.theatre_contact(state).is_empty())
	return state


func test_resolve_command_checks_auto_results() -> void:
	var state := _contact_state()
	var sim := OperationalSimulation.new(state)
	var good := AutoResolve.resolve(state.pending_battles[0])
	var tampered := BattleResult.from_dict(good.to_dict())
	tampered.companies[0].strength_end = maxi(good.companies[0].strength_end - 1, 0)
	if tampered.companies[0].strength_end == good.companies[0].strength_end:
		tampered.companies[0].strength_end += 1
	assert_eq(ResolveBattleCommand.new(tampered).validate(state), "auto_mismatch")
	assert_eq(ResolveBattleCommand.new(good).validate(state), "")
	var played := BattleResult.from_dict(tampered.to_dict())
	played.resolution = &"played"
	assert_eq(
		ResolveBattleCommand.new(played).validate(state), "", "a played result is not recomputed"
	)
	assert_true(sim.execute(ResolveBattleCommand.new(good)))
	assert_eq(state.pending_battles.size(), 0)


func _end_turns_until_contact(sim: OperationalSimulation) -> void:
	for i in 8:
		if not sim.state.pending_battles.is_empty():
			return
		assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_false(sim.state.pending_battles.is_empty(), "a contact happened")


func test_record_with_played_and_auto_battle() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	var sim := OperationalSimulation.new(state)
	assert_true(sim.execute(IssueOrderCommand.new(&"ru_mr_4", Vector2i(16, 52), &"advance")))
	_end_turns_until_contact(sim)
	var prepared := ContactBattle.prepare(state)
	var battle := GameSimulation.new(Scenario.from_setup(prepared))
	assert_true(MatchRunner.run(battle, 40))
	var played_result := BattleResult.from_battle(prepared, battle.state)
	var played_entry := CampaignRecord.Battle.played(
		prepared, BattleReplay.command_dicts(battle.history), played_result
	)
	assert_true(sim.execute(ResolveBattleCommand.new(played_result)))
	_end_turns_until_contact(sim)
	var pending := state.pending_battles[0]
	var auto_result := AutoResolve.resolve(pending)
	var auto_entry := CampaignRecord.Battle.auto(pending, auto_result)
	assert_true(sim.execute(ResolveBattleCommand.new(auto_result)))
	var record := CampaignRecord.from_simulation(
		sim, 1, &"russia", [played_entry, auto_entry] as Array[CampaignRecord.Battle]
	)
	var loaded := CampaignRecord.from_json(record.to_json())
	assert_true(loaded != null)
	assert_eq(loaded.battles[1].resolution, &"auto")
	assert_eq(loaded.battles[1].commands.size(), 0)
	var replay := loaded.replay(true)
	assert_true(replay["ok"], "verifies: %s" % [replay])
	# TASK-095: the consequences of a played and an auto battle replay to the same state
	assert_eq((replay["simulation"] as OperationalSimulation).state.snapshot(), state.snapshot())
	assert_eq(loaded.replay(false)["simulation"].state.snapshot(), state.snapshot())
	var tampered := record.to_dict()
	tampered["battles"][1]["result"]["companies"][0]["strength_end"] += 1
	for command: Dictionary in tampered["commands"]:
		if command["type"] == "resolve_battle" and command["result"]["resolution"] == "auto":
			command["result"]["companies"][0]["strength_end"] += 1
	var failure := CampaignRecord.from_dict(tampered).replay(true)
	assert_false(failure["ok"])
	assert_eq(failure["error"], "battle_diverged")
