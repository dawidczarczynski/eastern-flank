extends TestCase
## Faction ids in MatchRecord and Replay (TASK-038, ADR-0007).

const SEED := 12345


## Simulation on seed 12345 after: end_turn, end_turn.
func _two_turn_sim() -> GameSimulation:
	var sim := GameSimulation.new(Scenario.default_battle(SEED))
	assert_true(sim.execute(EndTurnCommand.new()))
	assert_true(sim.execute(EndTurnCommand.new()))
	return sim


func _record(commands: Array[Dictionary]) -> MatchRecord:
	var record := MatchRecord.new()
	record.seed = SEED
	record.commands = commands
	return record


func test_record_defaults_to_the_default_factions() -> void:
	assert_eq(MatchRecord.new().factions, [&"poland", &"russia"] as Array[StringName])


func test_from_simulation_takes_factions_from_the_state() -> void:
	var sim := GameSimulation.new(Scenario.default_battle(SEED, [&"russia", &"poland"]))
	var record := MatchRecord.from_simulation(sim, SEED)
	assert_eq(record.factions, [&"russia", &"poland"] as Array[StringName])


func test_factions_round_trip_through_json() -> void:
	var sim := GameSimulation.new(Scenario.default_battle(SEED, [&"russia", &"poland"]))
	var record := MatchRecord.from_simulation(sim, SEED)
	assert_eq(record.to_dict()["factions"], ["russia", "poland"])
	var loaded := MatchRecord.from_json(record.to_json())
	assert_true(loaded != null)
	if loaded == null:
		return
	assert_eq(loaded.factions, [&"russia", &"poland"] as Array[StringName])
	var replayed: GameSimulation = Replay.run(loaded)["simulation"]
	assert_eq(replayed.state.player_factions, [&"russia", &"poland"] as Array[StringName])


func test_record_without_factions_loads_the_default_pair_and_replays_identically() -> void:
	var sim := _two_turn_sim()
	var d := MatchRecord.from_simulation(sim, SEED).to_dict()
	d.erase("factions")
	var loaded := MatchRecord.from_json(JSON.stringify(d))
	assert_true(loaded != null, "a record without factions still loads")
	if loaded == null:
		return
	assert_eq(loaded.factions, [&"poland", &"russia"] as Array[StringName])
	var result := Replay.run(loaded)
	assert_eq(result["ok"], true)
	var replayed: GameSimulation = result["simulation"]
	assert_eq(replayed.state.player_factions, [&"poland", &"russia"] as Array[StringName])
	assert_eq(replayed.state.snapshot(), sim.state.snapshot())


func test_from_json_rejects_malformed_factions() -> void:
	var base := '{"version": 1, "scenario": "default_battle", "seed": 1, "commands": [], '
	assert_eq(MatchRecord.from_json(base + '"factions": "poland"}'), null)
	assert_eq(MatchRecord.from_json(base + '"factions": ["poland", 3]}'), null)


func test_unknown_faction_fails_the_replay() -> void:
	var record := _record([])
	record.factions = [&"poland", &"atlantis"]
	var result := Replay.run(record)
	assert_eq(result, {"ok": false, "error": "invalid_factions", "index": -1, "reason": ""})


func test_wrong_faction_count_fails_the_replay() -> void:
	var record := _record([])
	record.factions = [&"poland"]
	assert_eq(Replay.run(record)["error"], "invalid_factions")
