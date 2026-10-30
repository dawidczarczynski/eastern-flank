# gdlint: disable=max-public-methods
extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")
const ABRAMS := preload("res://data/units/m1a2_sepv3.tres")
const T72B3 := preload("res://data/units/t72b3.tres")
const URAGAN := preload("res://data/units/bm27_uragan.tres")
const SQUAD := preload("res://data/units/pl_mech_infantry.tres")

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
	var attacks: Array[Dictionary] = []
	sim.event_emitted.connect(
		func(e: Dictionary) -> void:
			if e["type"] == &"unit_attacked" and not e["counter"]:
				attacks.append(e)
	)
	AiPlayer.new().take_turn(sim)
	assert_eq(attacks.size(), 1)
	assert_eq(attacks[0]["attacker_id"], ai_unit.id)
	assert_eq(attacks[0]["target_id"], human.id)
	assert_eq(human.hp, 10 - int(attacks[0]["damage"]))
	assert_true(ai_unit.has_attacked)
	assert_eq(sim.state.current_player, 0)


func test_ai_attacks_without_moving_when_already_adjacent() -> void:
	var state := GameState.new(Fixtures.plains_grid(4), 2, 1)
	var target := state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	var attacker := state.add_unit(1, Fixtures.sure_fighter(2), Vector2i(1, 0))
	var game := GameSimulation.new(state)
	game.execute(EndTurnCommand.new())
	AiPlayer.new().take_turn(game)
	assert_eq(attacker.coord, Vector2i(1, 0))
	assert_eq(target.hp, 8)


func test_ai_attacks_the_enemy_that_counters_less() -> void:
	var state := GameState.new(Fixtures.plains_grid(4), 2, 1)
	var healthy := state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	var wounded := state.add_unit(0, Fixtures.infantry(), Vector2i(1, -1))
	wounded.hp = 5
	state.add_unit(1, Fixtures.sure_fighter(2), Vector2i(1, 0))
	var game := GameSimulation.new(state)
	game.execute(EndTurnCommand.new())
	AiPlayer.new().take_turn(game)
	assert_eq(healthy.hp, 10)
	assert_eq(wounded.hp, 3)


func test_ai_breaks_hp_ties_by_lowest_unit_id() -> void:
	var state := GameState.new(Fixtures.plains_grid(4), 2, 1)
	var first := state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	var second := state.add_unit(0, Fixtures.infantry(), Vector2i(1, -1))
	state.add_unit(1, Fixtures.sure_fighter(2), Vector2i(1, 0))
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


func test_ai_ranged_unit_keeps_distance_and_shoots_without_counter() -> void:
	var state := GameState.new(Fixtures.plains_grid(5), 2, 1)
	var enemy := state.add_unit(0, Fixtures.fighter(4, 3), Vector2i(4, 0))
	var ranged := state.add_unit(1, Fixtures.fighter(5, 1, 6, 2), Vector2i(0, 0))
	var game := GameSimulation.new(state)
	game.execute(EndTurnCommand.new())
	var attacks: Array[Dictionary] = []
	game.event_emitted.connect(
		func(e: Dictionary) -> void:
			if e["type"] == &"unit_attacked":
				attacks.append(e)
	)
	AiPlayer.new().take_turn(game)
	assert_eq(Hex.distance(ranged.coord, enemy.coord), 2)
	assert_eq(attacks.size(), 1)
	assert_eq(attacks[0]["attacker_id"], ranged.id)
	assert_false(attacks[0]["counter"])
	assert_eq(enemy.hp, 10 - int(attacks[0]["damage"]))
	assert_eq(ranged.hp, 6)


func test_ai_ranged_unit_at_range_2_does_not_move() -> void:
	var state := GameState.new(Fixtures.plains_grid(5), 2, 1)
	var enemy := state.add_unit(0, Fixtures.fighter(4, 3), Vector2i(2, 0))
	var ranged := state.add_unit(1, Fixtures.fighter(5, 1, 6, 2), Vector2i(0, 0))
	var game := GameSimulation.new(state)
	game.execute(EndTurnCommand.new())
	var moved := [false]
	game.event_emitted.connect(
		func(e: Dictionary) -> void:
			if e["type"] == &"unit_moved":
				moved[0] = true
	)
	AiPlayer.new().take_turn(game)
	assert_false(moved[0])
	assert_eq(ranged.coord, Vector2i(0, 0))
	assert_true(enemy.hp < 10)


func test_ranged_destination_tie_prefers_inside_range_then_current_tile() -> void:
	var ai := AiPlayer.new()
	# Range 2: d=1 and d=3 both score 1; the tile inside range wins.
	assert_true(ai._is_better(1, 3, 2))
	assert_false(ai._is_better(3, 1, 2))
	# Equal distance never replaces the current best (current tile kept).
	assert_false(ai._is_better(1, 1, 2))
	assert_false(ai._is_better(3, 3, 2))


func test_ai_rocket_artillery_moves_away_from_adjacent_enemy_and_fires_uncountered() -> void:
	var state := GameState.new(Fixtures.plains_grid(6), 2, 1)
	var enemy := state.add_unit(0, SQUAD, Vector2i(1, 0))
	var artillery := state.add_unit(1, URAGAN, Vector2i(0, 0))
	var game := GameSimulation.new(state)
	game.execute(EndTurnCommand.new())
	AiPlayer.new().take_turn(game)
	assert_true(Hex.distance(artillery.coord, enemy.coord) > 1)
	assert_true(enemy.hp < enemy.definition.max_hp)
	assert_eq(artillery.hp, 6)


## AI (player 1) unit at (0, 0) with move 3, an enemy at (-3, 0) and objectives from `conditions`.
func _objective_game(
	hexes: Array[Vector2i], owners: Array[int], conditions: Array[VictoryCondition]
) -> GameSimulation:
	var state := GameState.new(Fixtures.plains_grid(5), 2, 1)
	human = state.add_unit(0, Fixtures.infantry(), Vector2i(-3, 0))
	ai_unit = state.add_unit(1, Fixtures.infantry(), Vector2i(0, 0))
	state.set_objectives(Fixtures.objectives(0, hexes, owners, conditions))
	var game := GameSimulation.new(state)
	game.execute(EndTurnCommand.new())
	return game


func test_ai_moves_to_an_objective_it_must_take() -> void:
	var hexes: Array[Vector2i] = [Vector2i(3, 0)]
	var game := _objective_game(
		hexes, [0], [Fixtures.condition(VictoryCondition.Kind.TAKE_HEXES, 1, hexes)]
	)
	AiPlayer.new().take_turn(game)
	assert_eq(ai_unit.coord, Vector2i(3, 0))
	assert_eq(game.state.objective_owners[Vector2i(3, 0)], 1)


func test_ai_retakes_a_lost_hold_objective() -> void:
	var hexes: Array[Vector2i] = [Vector2i(0, 3)]
	var game := _objective_game(
		hexes, [0], [Fixtures.condition(VictoryCondition.Kind.HOLD_HEXES, 1, hexes)]
	)
	AiPlayer.new().take_turn(game)
	assert_eq(ai_unit.coord, Vector2i(0, 3))
	assert_eq(game.state.objective_owners[Vector2i(0, 3)], 1)


func test_ai_prefers_the_enemy_when_it_is_nearer_than_the_objective() -> void:
	var hexes: Array[Vector2i] = [Vector2i(0, 4)]
	var game := _objective_game(
		hexes, [0], [Fixtures.condition(VictoryCondition.Kind.TAKE_HEXES, 1, hexes)]
	)
	AiPlayer.new().take_turn(game)
	assert_eq(Hex.distance(ai_unit.coord, human.coord), 1)


func test_ai_keeps_a_unit_on_its_objective_and_still_attacks() -> void:
	var hexes: Array[Vector2i] = [Vector2i(0, 0)]
	var game := _objective_game(
		hexes, [1], [Fixtures.condition(VictoryCondition.Kind.HOLD_HEXES, 1, hexes)]
	)
	AiPlayer.new().take_turn(game)
	assert_eq(ai_unit.coord, Vector2i(0, 0), "stays instead of closing in")
	game.execute(EndTurnCommand.new())
	human.coord = Vector2i(-1, 0)
	AiPlayer.new().take_turn(game)
	assert_eq(ai_unit.coord, Vector2i(0, 0))
	assert_true(human.hp < 10, "attacks from the objective")


func test_ai_ignores_objectives_without_a_take_or_hold_condition() -> void:
	var hexes: Array[Vector2i] = [Vector2i(3, 0)]
	var game := _objective_game(
		hexes, [0], [Fixtures.condition(VictoryCondition.Kind.TAKE_HEXES, 0, hexes)]
	)
	AiPlayer.new().take_turn(game)
	assert_eq(Hex.distance(ai_unit.coord, human.coord), 1)


# --- target choice by forecast (TASK-089a) ------------------------------------------------------


## Runs one AI turn (player 1) on `state`; returns the target id of its first attack (-1: none).
func _first_target(state: GameState) -> int:
	var game := GameSimulation.new(state)
	game.execute(EndTurnCommand.new())
	var targets: Array[int] = []
	game.event_emitted.connect(
		func(e: Dictionary) -> void:
			if e["type"] == &"unit_attacked" and not e["counter"]:
				targets.append(e["target_id"])
	)
	AiPlayer.new().take_turn(game)
	return targets[0] if not targets.is_empty() else -1


func test_ai_target_score_is_expected_damage_plus_kill_bonus_minus_counter() -> void:
	var state := GameState.new(Fixtures.plains_grid(4), 2, 1)
	var abrams := state.add_unit(1, ABRAMS, Vector2i(0, 0))
	var tank := state.add_unit(0, T72B3, Vector2i(1, 0))
	var mlrs := state.add_unit(0, URAGAN, Vector2i(0, 1))
	var on_tank := AttackCommand.forecast(state, abrams, tank)
	assert_true(
		is_equal_approx(
			AiPlayer.target_score(on_tank),
			(
				on_tank.expected_damage
				+ AiPlayer.KILL_BONUS * on_tank.kill_chance
				- on_tank.counter_expected
			)
		)
	)
	assert_true(
		(
			AiPlayer.target_score(AttackCommand.forecast(state, abrams, mlrs))
			> AiPlayer.target_score(on_tank)
		)
	)
	assert_eq(_first_target(state), mlrs.id)


func test_ai_prefers_a_better_attack_over_the_weakest_target() -> void:
	var state := GameState.new(Fixtures.plains_grid(4), 2, 1)
	state.add_unit(1, T72B3, Vector2i(0, 0))
	state.grid.set_terrain(Vector2i(1, 0), Terrain.Type.HILLS)
	var abrams := state.add_unit(0, ABRAMS, Vector2i(1, 0))
	abrams.hp = 6  # the weakest, but dug in on hills and hitting back hard
	var squad := state.add_unit(0, SQUAD, Vector2i(-1, 0))
	squad.hp = 7
	assert_eq(_first_target(state), squad.id)


## A range-2 AI striker at (0, 0) that cannot be countered there: every target scores the same
## when its HP exceeds the 3 sure hits.
func _tie_state() -> GameState:
	var state := GameState.new(Fixtures.plains_grid(4), 2, 1)
	state.add_unit(1, Fixtures.sure_fighter(3, 2, 2), Vector2i(0, 0))
	return state


func test_ai_score_ties_fall_back_to_lowest_hp() -> void:
	var state := _tie_state()
	state.add_unit(0, Fixtures.infantry(), Vector2i(2, 0))
	var weaker := state.add_unit(0, Fixtures.infantry(), Vector2i(0, 2))
	weaker.hp = 8
	assert_eq(_first_target(state), weaker.id)


func test_ai_score_and_hp_ties_fall_back_to_lowest_id() -> void:
	var state := _tie_state()
	var first := state.add_unit(0, Fixtures.infantry(), Vector2i(2, 0))
	state.add_unit(0, Fixtures.infantry(), Vector2i(0, 2))
	assert_eq(_first_target(state), first.id)
