extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var sim: GameSimulation
var human: Unit
var ai_unit: Unit


func before_each() -> void:
	var state := GameState.new(Fixtures.plains_grid(4), 2, 1)
	human = state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	ai_unit = state.add_unit(1, Fixtures.infantry(), Vector2i(3, 0))
	sim = GameSimulation.new(state)
	sim.execute(EndTurnCommand.new())  # AI turn


func test_ai_approaches_nearest_enemy() -> void:
	AiPlayer.new().take_turn(sim)
	assert_eq(Hex.distance(ai_unit.coord, human.coord), 1)


func test_ai_ends_its_turn() -> void:
	AiPlayer.new().take_turn(sim)
	assert_eq(sim.state.current_player, 0)


func test_ai_attacks_after_moving_next_to_enemy() -> void:
	AiPlayer.new().take_turn(sim)
	assert_eq(human.hp, 8)
	assert_true(ai_unit.has_attacked)
	assert_eq(sim.state.current_player, 0)


func test_ai_attacks_without_moving_when_already_adjacent() -> void:
	var state := GameState.new(Fixtures.plains_grid(4), 2, 1)
	var target := state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	var attacker := state.add_unit(1, Fixtures.infantry(), Vector2i(1, 0))
	var game := GameSimulation.new(state)
	game.execute(EndTurnCommand.new())
	AiPlayer.new().take_turn(game)
	assert_eq(attacker.coord, Vector2i(1, 0))
	assert_eq(target.hp, 8)


func test_ai_attacks_weakest_adjacent_enemy() -> void:
	var state := GameState.new(Fixtures.plains_grid(4), 2, 1)
	var healthy := state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	var wounded := state.add_unit(0, Fixtures.infantry(), Vector2i(1, -1))
	wounded.hp = 5
	state.add_unit(1, Fixtures.infantry(), Vector2i(1, 0))
	var game := GameSimulation.new(state)
	game.execute(EndTurnCommand.new())
	AiPlayer.new().take_turn(game)
	assert_eq(healthy.hp, 10)
	assert_eq(wounded.hp, 3)


func test_ai_breaks_hp_ties_by_lowest_unit_id() -> void:
	var state := GameState.new(Fixtures.plains_grid(4), 2, 1)
	var first := state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	var second := state.add_unit(0, Fixtures.infantry(), Vector2i(1, -1))
	state.add_unit(1, Fixtures.infantry(), Vector2i(1, 0))
	var game := GameSimulation.new(state)
	game.execute(EndTurnCommand.new())
	AiPlayer.new().take_turn(game)
	assert_eq(first.hp, 8)
	assert_eq(second.hp, 10)


func test_ai_stops_after_winning() -> void:
	var state := GameState.new(Fixtures.plains_grid(4), 2, 1)
	var victim := state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	victim.hp = 1
	state.add_unit(1, Fixtures.infantry(), Vector2i(1, 0))
	state.add_unit(1, Fixtures.infantry(), Vector2i(2, 0))
	var game := GameSimulation.new(state)
	game.execute(EndTurnCommand.new())
	var rejections: Array[String] = []
	game.command_rejected.connect(
		func(_c: Command, reason: String) -> void: rejections.append(reason)
	)
	AiPlayer.new().take_turn(game)
	assert_eq(state.winner, 1)
	assert_eq(state.current_player, 1)
	assert_eq(rejections.size(), 0)
