extends TestCase
## Command points in scenarios, replays and the AI (TASK-091); the rules are in test_command_points.

const Fixtures := preload("res://tests/fixtures.gd")


func test_command_points_scenario_has_two_points_for_both_players() -> void:
	var game := Scenario.command_points_battle(12345)
	assert_eq(game.command_points_per_turn, [2, 2] as Array[int])
	assert_eq(game.command_points, 2)
	assert_eq(Scenario.NAMES.has("command_points_battle"), true)
	assert_eq(
		Scenario.build("command_points_battle", 5, FactionRegistry.DEFAULT_IDS).command_points, 2
	)


func test_command_points_scenario_is_the_default_battle_with_conditions() -> void:
	var setup := Scenario.command_points_battle_setup(7)
	var plain := Scenario.default_battle_setup(7).to_dict()
	var dict := setup.to_dict()
	assert_eq((dict["conditions"] as Array)[0]["command_points"], 2)
	dict.erase("conditions")
	plain.erase("conditions")
	assert_eq(dict, plain)


func test_from_setup_reads_command_points_and_default_is_unlimited() -> void:
	assert_eq(Scenario.default_battle(3).command_points_per_turn, [0, 0] as Array[int])
	var setup := Scenario.default_battle_setup(3)
	setup.conditions[1].command_points = 4
	var game := Scenario.from_setup(setup)
	assert_eq(game.command_points_per_turn, [0, 4] as Array[int])
	assert_eq(game.command_points, 0)


func test_from_setup_rejects_negative_command_points() -> void:
	var setup := Scenario.default_battle_setup(3)
	setup.conditions[0].command_points = -1
	assert_true(Scenario.from_setup(setup) == null)


func test_ai_with_one_point_activates_its_best_unit_not_the_first_id() -> void:
	var game := GameState.new(Fixtures.plains_grid(4), 2, 1)
	var target := game.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	var walker := game.add_unit(1, Fixtures.infantry(), Vector2i(4, 0))  # lower id, only moves
	var striker := game.add_unit(1, Fixtures.infantry(), Vector2i(1, 0))  # adjacent: attacks
	game.set_command_points_per_turn([0, 1] as Array[int])
	var play := GameSimulation.new(game)
	play.execute(EndTurnCommand.new())
	AiPlayer.new().take_turn(play)
	assert_true(striker.activated)
	assert_true(striker.has_attacked)
	assert_false(walker.activated)
	assert_eq(walker.coord, Vector2i(4, 0))
	assert_true(target.hp < 10)
	assert_eq(game.current_player, 0, "the AI still ends its turn")


func test_ai_prefers_a_kill_and_spends_no_more_than_it_has() -> void:
	var game := GameState.new(Fixtures.plains_grid(4), 2, 1)
	var wounded := game.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	wounded.hp = 2
	var healthy := game.add_unit(0, Fixtures.infantry(), Vector2i(0, 2))
	var first := game.add_unit(1, Fixtures.infantry(), Vector2i(0, 3))  # hits the healthy unit
	var killer := game.add_unit(1, Fixtures.sure_fighter(10), Vector2i(1, 0))  # kills the wounded one
	game.set_command_points_per_turn([0, 1] as Array[int])
	var play := GameSimulation.new(game)
	play.execute(EndTurnCommand.new())
	AiPlayer.new().take_turn(play)
	assert_false(wounded.is_alive())
	assert_eq(healthy.hp, 10)
	assert_true(killer.activated)
	assert_false(first.activated)


func test_command_points_match_survives_a_replay() -> void:
	var game := Scenario.command_points_battle(12345)
	var played := GameSimulation.new(game)
	var ai := AiPlayer.new()
	while not game.is_over() and game.turn <= 30:
		ai.take_turn(played)
	assert_true(played.history.size() > 0)
	var record := MatchRecord.from_json(
		MatchRecord.from_simulation(played, 12345, "command_points_battle").to_json()
	)
	var replay := Replay.run(record)
	assert_true(replay["ok"], str(replay))
	var replayed := (replay["simulation"] as GameSimulation).state
	assert_eq(replayed.snapshot(), game.snapshot())
	assert_eq(replayed.command_points_per_turn, [2, 2] as Array[int])
