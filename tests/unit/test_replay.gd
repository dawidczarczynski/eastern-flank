extends TestCase

const SEED := 12345
const FIXTURE_PATH := "res://tests/fixtures/replays/default_battle_12345.json"
const REGENERATE := "tools/make_replay_fixture.sh"
const FACTIONS := '["poland", "russia"]'


## Simulation on seed 12345 after: move unit 1 by one tile, end_turn, end_turn.
func _three_command_sim() -> GameSimulation:
	var sim := GameSimulation.new(Scenario.default_battle(SEED))
	var unit := sim.state.get_unit(1)
	var reach := sim.state.grid.reachable(unit.coord, unit.moves_left, sim.state.occupied())
	var step := Vector2i.ZERO
	var found := false
	for c: Vector2i in reach.keys():
		if Hex.distance(unit.coord, c) == 1:
			step = c
			found = true
			break
	assert_true(found, "unit 1 has no free neighbour")
	assert_true(sim.execute(MoveUnitCommand.new(1, step)))
	assert_true(sim.execute(EndTurnCommand.new()))
	assert_true(sim.execute(EndTurnCommand.new()))
	return sim


func _record(commands: Array[Dictionary]) -> MatchRecord:
	var record := MatchRecord.new()
	record.seed = SEED
	record.commands = commands
	return record


func test_record_defaults() -> void:
	var record := MatchRecord.new()
	assert_eq(MatchRecord.VERSION, 2, "bumped by TASK-039a (ADR-0009)")
	assert_eq(record.version, MatchRecord.VERSION)
	assert_eq(record.scenario, "default_battle")
	assert_eq(record.commands.size(), 0)


func test_from_simulation_uses_history() -> void:
	var record := MatchRecord.from_simulation(_three_command_sim(), SEED)
	assert_eq(record.seed, SEED)
	assert_eq(record.commands.size(), 3)
	assert_eq(record.commands[0]["type"], "move")
	assert_eq(record.commands[1], {"type": "end_turn"})


func test_json_round_trip() -> void:
	var record := MatchRecord.from_simulation(_three_command_sim(), SEED)
	var loaded := MatchRecord.from_json(record.to_json())
	assert_true(loaded != null)
	assert_eq(loaded.version, MatchRecord.VERSION)
	assert_eq(loaded.scenario, "default_battle")
	assert_eq(loaded.seed, SEED)
	assert_eq(loaded.commands.size(), 3)


func test_from_json_rejects_invalid_json() -> void:
	assert_eq(MatchRecord.from_json("{not json"), null)
	assert_eq(MatchRecord.from_json("[1, 2]"), null)
	assert_eq(MatchRecord.from_json(""), null)


## An empty record of format `version`.
func _versioned(version: int) -> String:
	return (
		'{"version": %d, "scenario": "default_battle", "seed": 1, "factions": %s, "commands": []}'
		% [version, FACTIONS]
	)


func test_from_json_rejects_other_versions() -> void:
	assert_eq(MatchRecord.from_json(_versioned(3)), null)
	assert_eq(
		MatchRecord.from_json(
			'{"scenario": "default_battle", "seed": 1, "factions": %s, "commands": []}' % FACTIONS
		),
		null
	)


## Records from before TASK-039a (version 1: generic infantry / cavalry / rocket artillery)
## are rejected with a readable message instead of replaying into different units (ADR-0009).
func test_pre_039_record_is_rejected_with_a_readable_error() -> void:
	var text := _versioned(1)
	var result := MatchRecord.parse_json(text)
	assert_eq(result["record"], null)
	var message: String = result["error"]
	assert_true(message.contains("version 1"), message)
	assert_true(message.contains("unsupported"), message)
	assert_eq(MatchRecord.from_json(text), null)


func test_parse_json_reports_every_failure_readably() -> void:
	for bad in ["{not json", "[1]", '{"version": 2, "seed": 1}']:
		var result := MatchRecord.parse_json(bad)
		assert_eq(result["record"], null, bad)
		assert_false((result["error"] as String).is_empty(), bad)
	var ok := MatchRecord.parse_json(
		MatchRecord.from_simulation(_three_command_sim(), SEED).to_json()
	)
	assert_true(ok["record"] is MatchRecord)
	assert_eq(ok["error"], "")


func test_from_json_rejects_malformed_fields() -> void:
	var base := '{"version": 2, "scenario": "default_battle", "factions": %s, ' % FACTIONS
	var bad_seed := base + '"seed": 1.5, "commands": []}'
	var bad_commands := base + '"seed": 1, "commands": {}}'
	var bad_entry := base + '"seed": 1, "commands": [3]}'
	assert_eq(MatchRecord.from_json(bad_seed), null)
	assert_eq(MatchRecord.from_json(bad_commands), null)
	assert_eq(MatchRecord.from_json(bad_entry), null)


func test_replay_reproduces_original_snapshot() -> void:
	var sim := _three_command_sim()
	var record := MatchRecord.from_json(MatchRecord.from_simulation(sim, SEED).to_json())
	var result := Replay.run(record)
	assert_eq(result["ok"], true)
	var replayed: GameSimulation = result["simulation"]
	assert_eq(replayed.state.snapshot(), sim.state.snapshot())
	assert_eq(replayed.history.size(), 3)


func test_rejected_command_is_diverged_with_reason() -> void:
	var result := Replay.run(_record([{"type": "attack", "attacker_id": 99, "target_id": 1}]))
	assert_eq(result, {"ok": false, "error": "diverged", "index": 0, "reason": "unit_not_found"})


func test_undecodable_command_is_invalid_command_at_its_index() -> void:
	var commands: Array[Dictionary] = [{"type": "end_turn"}, {"type": "end_turn"}]
	commands.append({"type": "teleport"})
	var result := Replay.run(_record(commands))
	assert_eq(result["ok"], false)
	assert_eq(result["error"], "invalid_command")
	assert_eq(result["index"], 2)
	assert_eq(result["reason"], "")


func test_unknown_scenario() -> void:
	var record := _record([])
	record.scenario = "unknown"
	var result := Replay.run(record)
	assert_eq(result["ok"], false)
	assert_eq(result["error"], "unknown_scenario")


func test_two_replays_give_equal_snapshots() -> void:
	var record := MatchRecord.from_simulation(_three_command_sim(), SEED)
	var a: GameSimulation = Replay.run(record)["simulation"]
	var b: GameSimulation = Replay.run(record)["simulation"]
	assert_eq(a.state.snapshot(), b.state.snapshot())


func test_snapshot_contents() -> void:
	var state := Scenario.default_battle(SEED)
	state.get_unit(5).hp = 0
	var snap := state.snapshot()
	assert_eq(snap["turn"], 1)
	assert_eq(snap["current_player"], 0)
	assert_eq(snap["winner"], -1)
	assert_eq(snap["rng_state"], str(state.rng.state))
	var units: Array = snap["units"]
	assert_eq(units.size(), 9)
	for i in units.size():
		assert_eq(units[i]["id"], i + 1)
	var first := state.get_unit(1)
	var expected := {
		"id": 1,
		"owner": 0,
		"definition": "pl_mech_infantry",
		"coord": [first.coord.x, first.coord.y],
		"hp": first.hp,
		"moves_left": first.moves_left,
		"has_attacked": false,
		"activated": false,
	}
	assert_eq(units[0], expected)
	assert_eq(snap["command_points"], 0)
	assert_eq(units[4]["hp"], 0, "dead units stay in the snapshot")


func test_snapshot_survives_json_round_trip() -> void:
	var state := Scenario.default_battle(SEED)
	state.rng.randi()  # rng.state is a full 64-bit value now
	var snap := state.snapshot()
	var parsed: Variant = JSON.parse_string(JSON.stringify(snap))
	assert_eq(parsed["rng_state"], str(state.rng.state))
	assert_eq(MatchRecord.normalize(parsed), snap)


func test_regression_fixture_replays_to_expected_final_state() -> void:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	assert_true(file != null, "missing %s – run %s" % [FIXTURE_PATH, REGENERATE])
	if file == null:
		return
	var text := file.get_as_text()
	var record := MatchRecord.from_json(text)
	var fixture: Variant = JSON.parse_string(text)
	assert_true(record != null and fixture is Dictionary, "unreadable fixture")
	if record == null or not fixture is Dictionary:
		return
	var result := Replay.run(record)
	var hint := (
		"Game rules changed the outcome of the recorded AI match. If the change is intended, "
		+ "regenerate the fixture with %s and commit it." % REGENERATE
	)
	assert_eq(result["ok"], true, "replay failed: %s. %s" % [str(result), hint])
	if not result["ok"]:
		return
	var actual := (result["simulation"] as GameSimulation).state.snapshot()
	var expected: Variant = MatchRecord.normalize(fixture.get("expected_final"))
	assert_true(
		actual == expected,
		(
			"final snapshot differs from expected_final (%s). %s"
			% [_first_difference(expected, actual), hint]
		)
	)


## Path and values of the first difference between two snapshots (for readable failures).
func _first_difference(expected: Variant, actual: Variant, path: String = "") -> String:
	if expected is Dictionary and actual is Dictionary:
		return _dictionary_difference(expected, actual, path)
	if expected is Array and actual is Array:
		return _array_difference(expected, actual, path)
	if typeof(expected) != typeof(actual) or expected != actual:
		return "%s: expected %s, got %s" % [path, str(expected), str(actual)]
	return ""


func _dictionary_difference(expected: Dictionary, actual: Dictionary, path: String) -> String:
	for key: Variant in expected:
		if not actual.has(key):
			return "%s.%s missing" % [path, key]
		var diff := _first_difference(expected[key], actual[key], "%s.%s" % [path, key])
		if diff != "":
			return diff
	return "" if expected.size() == actual.size() else "%s has extra keys" % path


func _array_difference(expected: Array, actual: Array, path: String) -> String:
	for i in mini(expected.size(), actual.size()):
		var diff := _first_difference(expected[i], actual[i], "%s[%d]" % [path, i])
		if diff != "":
			return diff
	if expected.size() != actual.size():
		return "%s: %d items expected, got %d" % [path, expected.size(), actual.size()]
	return ""


func test_from_simulation_stores_the_scenario_name() -> void:
	var sim := GameSimulation.new(Scenario.objective_battle(SEED))
	sim.execute(EndTurnCommand.new())
	assert_eq(MatchRecord.from_simulation(sim, SEED).scenario, "default_battle")
	var record := MatchRecord.from_simulation(sim, SEED, "objective_battle")
	assert_eq(MatchRecord.from_json(record.to_json()).scenario, "objective_battle")


## A played AI-vs-AI objective match replays to the same state: objective owners and end state
## included.
func test_objective_match_survives_a_replay() -> void:
	var sim := GameSimulation.new(Scenario.objective_battle(SEED))
	var ai := AiPlayer.new()
	var captured := [0]
	sim.event_emitted.connect(
		func(e: Dictionary) -> void:
			if e["type"] == &"objective_captured":
				captured[0] += 1
	)
	while not sim.state.is_over() and sim.state.turn <= 30:
		ai.take_turn(sim)
	assert_true(sim.state.is_over(), "the turn limit ends it")
	var record := MatchRecord.from_json(
		MatchRecord.from_simulation(sim, SEED, "objective_battle").to_json()
	)
	var replay := Replay.run(record)
	assert_true(replay["ok"], str(replay))
	var replayed := (replay["simulation"] as GameSimulation).state
	assert_eq(replayed.snapshot(), sim.state.snapshot())
	assert_eq(replayed.end_reason, sim.state.end_reason)
	assert_eq((replayed.snapshot()["objectives"] as Array).size(), 2)
	assert_true(captured[0] > 0, "the AI captured an objective during the match")
