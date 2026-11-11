extends TestCase
## AI firing positions with realistic weapon ranges (TASK-131a): stand off at the effective
## range, find line of sight, stay out of enemy reach when possible.

const Fixtures := preload("res://tests/fixtures.gd")
const T72B3 := preload("res://data/units/t72b3.tres")
const HOMAR := preload("res://data/units/homar_k.tres")
const SQUAD := preload("res://data/units/pl_mech_infantry.tres")
const RU_SQUAD := preload("res://data/units/ru_motor_rifle.tres")

var state: GameState
var sim: GameSimulation
var attacks: Array[Dictionary] = []


## An open 0 m plain of radius 15; player 0 is the AI.
func before_each() -> void:
	var grid := Fixtures.plains_grid(15)
	for c in grid.coords():
		grid.set_elevation(c, 0.0)
	state = GameState.new(grid, 2, 1)
	sim = GameSimulation.new(state)
	sim.event_emitted.connect(
		func(e: Dictionary) -> void:
			if e["type"] == &"unit_attacked" and not e["counter"]:
				attacks.append(e)
	)


func _forest(c: Vector2i) -> void:
	state.grid.set_terrain(c, Terrain.Type.FOREST)
	state.grid.set_elevation(c, 0.0)


## Hexes the unit can reach (and its own), at hex distance `d` from `target`, lowest (y, x) first.
func _reach_at(unit: Unit, target: Vector2i, d: int) -> Array[Vector2i]:
	var reach := state.grid.reachable(unit.coord, unit.moves_left, state.occupied())
	var result: Array[Vector2i] = []
	for c: Vector2i in reach.keys():
		if Hex.distance(c, target) == d:
			result.append(c)
	result.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return result


func test_tank_stops_at_its_effective_range_and_fires() -> void:
	var tank := state.add_unit(0, T72B3, Vector2i(-6, 0))
	var target := state.add_unit(1, SQUAD, Vector2i(6, 0))
	var expected := _reach_at(tank, target.coord, 8)[0]
	AiPlayer.new().take_turn(sim)
	assert_eq(tank.coord, expected)
	assert_eq(Hex.distance(tank.coord, target.coord), 8)
	assert_eq(attacks.size(), 1)
	assert_eq(attacks[0]["attacker_id"], tank.id)


func test_tank_already_at_a_good_range_stays() -> void:
	var tank := state.add_unit(0, T72B3, Vector2i(-2, 0))
	var target := state.add_unit(1, SQUAD, Vector2i(6, 0))
	AiPlayer.new().take_turn(sim)
	assert_eq(tank.coord, Vector2i(-2, 0))
	assert_eq(Hex.distance(tank.coord, target.coord), 8)
	assert_eq(attacks.size(), 1)


## A forest ring hides the target from every hex but the ring itself: the tank closes in by
## its full move and holds its fire.
func test_without_line_of_sight_the_tank_moves_toward_a_firing_hex() -> void:
	var target := state.add_unit(1, SQUAD, Vector2i(6, 0))
	for n in Hex.neighbors(target.coord):
		_forest(n)
	var tank := state.add_unit(0, T72B3, Vector2i(-6, 0))
	AiPlayer.new().take_turn(sim)
	assert_eq(attacks.size(), 0)
	assert_eq(Hex.distance(tank.coord, target.coord), 12 - T72B3.move_points)


func test_squad_closes_in_until_its_maximum_range() -> void:
	var squad := state.add_unit(0, SQUAD, Vector2i(0, 0))
	var target := state.add_unit(1, RU_SQUAD, Vector2i(6, 0))
	AiPlayer.new().take_turn(sim)
	assert_eq(Hex.distance(squad.coord, target.coord), 3)


## T-72B3 (max 12 hexes) 10 hexes away: the Homar-K (3 moves) can back off to 13 and still hit.
func test_homar_prefers_a_firing_hex_out_of_enemy_reach() -> void:
	var homar := state.add_unit(0, HOMAR, Vector2i(0, 0))
	var tank := state.add_unit(1, T72B3, Vector2i(10, 0))
	AiPlayer.new().take_turn(sim)
	assert_true(Hex.distance(homar.coord, tank.coord) > 12, str(homar.coord))
	assert_eq(attacks.size(), 1)


func test_homar_hidden_behind_a_forest_counts_as_out_of_reach() -> void:
	var homar := state.add_unit(0, HOMAR, Vector2i(0, 0))
	var tank := state.add_unit(1, T72B3, Vector2i(5, 0))
	for n in Hex.neighbors(homar.coord):
		_forest(n)
	AiPlayer.new().take_turn(sim)
	var problem := AttackCommand.fire_problem(state, T72B3, tank.coord, homar.coord)
	assert_eq(problem, "no_line_of_sight", str(homar.coord))
	assert_eq(attacks.size(), 1)


func test_homar_fires_even_when_no_hex_is_out_of_reach() -> void:
	var homar := state.add_unit(0, HOMAR, Vector2i(0, 0))
	state.add_unit(1, T72B3, Vector2i(5, 0))
	AiPlayer.new().take_turn(sim)
	assert_eq(attacks.size(), 1)
	assert_eq(attacks[0]["attacker_id"], homar.id)


## AI vs AI on the default battle, every event logged; 20 turns at most.
func _event_log(seed_value: int) -> Array[Dictionary]:
	var game := GameSimulation.new(Scenario.default_battle(seed_value))
	var events_log: Array[Dictionary] = []
	game.event_emitted.connect(func(e: Dictionary) -> void: events_log.append(e))
	var ai := AiPlayer.new()
	while not game.state.is_over() and game.state.turn <= 20:
		ai.take_turn(game)
	return events_log


func test_same_seed_gives_the_same_event_log_twice() -> void:
	var first := _event_log(5)
	assert_true(first.size() > 0)
	assert_eq(_event_log(5), first)
