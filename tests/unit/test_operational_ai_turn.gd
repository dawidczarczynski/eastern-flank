extends TestCase
## OperationalAiTurn and the operational AI-vs-AI run (TASK-102c).


func _sim(seed_value := 1) -> OperationalSimulation:
	return OperationalSimulation.new(Operation.build(&"suwalki_gap", seed_value))


func test_play_executes_the_plan_and_ends_the_turn() -> void:
	var sim := _sim()
	var player := sim.state.current_player
	var out := OperationalAiTurn.play(sim, player)
	var commands: Array[OperationalCommand] = out["commands"]
	assert_true(commands.size() >= 2)
	assert_true(commands[-1] is EndOperationalTurnCommand)
	assert_true(out["ended"])
	assert_eq(sim.state.current_player, 1 - player)
	assert_false((out["results"] as Array[bool]).has(false))


func test_nothing_happens_out_of_turn() -> void:
	var sim := _sim()
	var other := 1 - sim.state.current_player
	var out := OperationalAiTurn.play(sim, other)
	assert_eq((out["commands"] as Array).size(), 0)
	assert_eq(sim.history.size(), 0)


func test_bounded_by_max_commands_plus_the_end() -> void:
	var sim := _sim()
	var profile := AiProfile.shipped().duplicate() as AiProfile
	profile.max_commands = 1
	var out := OperationalAiTurn.play(sim, sim.state.current_player, profile)
	assert_true((out["commands"] as Array).size() <= 2)
	assert_true(out["ended"])


class RejectFirst:
	extends OperationalSimulation
	var calls := 0

	func execute(command: OperationalCommand) -> bool:
		calls += 1
		if calls == 1:
			return false
		return super.execute(command)


func test_a_rejected_command_is_skipped_and_the_turn_still_ends() -> void:
	var sim := RejectFirst.new(Operation.build(&"suwalki_gap", 1))
	var out := OperationalAiTurn.play(sim, sim.state.current_player)
	var results: Array[bool] = out["results"]
	assert_false(results[0])
	assert_true(results.size() >= 2)
	assert_true(out["ended"])
	assert_eq(sim.calls, results.size(), "nothing retried")


func test_two_ais_play_ten_rounds_deterministically() -> void:
	var a := MatchRunner.play_operational(_sim(3), 10)
	var b := MatchRunner.play_operational(_sim(3), 10)
	assert_eq(a["rejected"], 0)
	assert_false(a["stalled"])
	assert_true(a["commands"] > 20)
	assert_eq(a["hash"], b["hash"])


func test_runner_with_the_ai_as_player_0_or_1_only() -> void:
	for side in [0, 1]:
		var sim := _sim(5)
		var ai_sides: Array[int] = [side]
		var r := MatchRunner.play_operational(sim, 5, ai_sides)
		assert_eq(r["rejected"], 0)
		# The human's side never moves: the run stops when it is its turn.
		assert_true(r["stalled"])
		assert_eq(sim.state.current_player, 1 - side)


func test_human_battle_is_left_untouched() -> void:
	var sim := _sim()
	var setup := BattleSetup.new()
	setup.attacker = 0
	sim.state.pending_battles.append(setup)
	var ai_sides: Array[int] = [1]
	var r := MatchRunner.play_operational(sim, 5, ai_sides)
	assert_eq(sim.state.pending_battles.size(), 1)
	assert_true(r["stalled"])
	assert_eq(r["battles"], 0)
