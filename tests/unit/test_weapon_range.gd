# gdlint: disable=max-public-methods
extends TestCase
## Realistic weapon range (TASK-131a): minimum / maximum range, line of sight of direct fire,
## hit chance falling with distance, counterattack reach and the forecast.

const Fixtures := preload("res://tests/fixtures.gd")
const ABRAMS := preload("res://data/units/m1a2_sepv3.tres")
const T72B3 := preload("res://data/units/t72b3.tres")
const HOMAR := preload("res://data/units/homar_k.tres")
const SQUAD := preload("res://data/units/pl_mech_infantry.tres")
const RU_SQUAD := preload("res://data/units/ru_motor_rifle.tres")

var state: GameState
var sim: GameSimulation
var events: Array[Dictionary] = []
var rejections: Array[String] = []


## An open 0 m plain of radius 15 (every range up to 14 hexes fits along the q axis).
func before_each() -> void:
	var grid := Fixtures.plains_grid(15)
	for c in grid.coords():
		grid.set_elevation(c, 0.0)
	state = GameState.new(grid, 2, 1)
	sim = GameSimulation.new(state)
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	sim.command_rejected.connect(
		func(_c: Command, reason: String) -> void: rejections.append(reason)
	)


## A player-0 `attacker` at (0, 0) and a player-1 `target` `distance` hexes east; returns both.
func _pair(attacker: UnitDefinition, target: UnitDefinition, distance: int) -> Array[Unit]:
	var a := state.add_unit(0, attacker, Vector2i(0, 0))
	var t := state.add_unit(1, target, Vector2i(distance, 0))
	return [a, t]


func _validate(pair: Array[Unit]) -> String:
	return AttackCommand.new(pair[0].id, pair[1].id).validate(state)


func _forest(c: Vector2i) -> void:
	state.grid.set_terrain(c, Terrain.Type.FOREST)
	state.grid.set_elevation(c, 0.0)


func _counters() -> int:
	var n := 0
	for e in events:
		if e["type"] == &"unit_attacked" and e["counter"]:
			n += 1
	return n


# --- range ---


func test_t72_hits_at_8_full_at_12_half_and_not_at_13() -> void:
	var at8 := _pair(T72B3, SQUAD, 8)
	assert_eq(_validate(at8), "")
	var base := AttackCommand.compute_damage(state, at8[0], at8[1])  # 6 - 3 = 3
	assert_eq(AttackCommand.hit_on(state, at8[0], at8[1]), base)
	assert_eq(AttackCommand.forecast(state, at8[0], at8[1]).range_factor, 1.0)
	at8[1].coord = Vector2i(12, 0)
	assert_eq(_validate(at8), "")
	assert_eq(AttackCommand.forecast(state, at8[0], at8[1]).range_factor, 0.5)
	assert_eq(AttackCommand.hit_on(state, at8[0], at8[1]), 1)  # floor(3 / 2)
	at8[1].coord = Vector2i(13, 0)
	assert_eq(_validate(at8), "out_of_range")


func test_infantry_at_3_shoots_at_half_and_not_at_4() -> void:
	var pair := _pair(SQUAD, RU_SQUAD, 3)
	assert_eq(_validate(pair), "")
	assert_eq(AttackCommand.forecast(state, pair[0], pair[1]).range_factor, 0.5)
	pair[1].coord = Vector2i(4, 0)
	assert_false(sim.execute(AttackCommand.new(pair[0].id, pair[1].id)))
	assert_eq(rejections, ["out_of_range"] as Array[String])


func test_tank_behind_a_forest_has_no_line_of_sight_but_homar_fires() -> void:
	_forest(Vector2i(2, 0))
	var tank := _pair(T72B3, SQUAD, 4)
	assert_false(sim.execute(AttackCommand.new(tank[0].id, tank[1].id)))
	assert_eq(rejections, ["no_line_of_sight"] as Array[String])
	tank[0].coord = Vector2i(-5, 5)
	var homar := state.add_unit(0, HOMAR, Vector2i(0, 0))
	assert_true(sim.execute(AttackCommand.new(homar.id, tank[1].id)))


func test_artillery_cannot_hit_within_its_minimum_range() -> void:
	var pair := _pair(HOMAR, SQUAD, 1)
	assert_eq(_validate(pair), "too_close")
	pair[1].coord = Vector2i(2, 0)
	assert_false(sim.execute(AttackCommand.new(pair[0].id, pair[1].id)))
	assert_eq(rejections, ["too_close"] as Array[String])
	pair[1].coord = Vector2i(3, 0)
	assert_eq(_validate(pair), "")


func test_rejection_order_is_range_before_line_of_sight() -> void:
	_forest(Vector2i(2, 0))
	var pair := _pair(SQUAD, RU_SQUAD, 4)
	assert_eq(_validate(pair), "out_of_range")


func test_tiles_in_range_follow_minimum_range_and_line_of_sight() -> void:
	_forest(Vector2i(2, 0))
	var tank := state.add_unit(0, T72B3, Vector2i(0, 0))
	var tiles := AttackCommand.tiles_in_range(state, tank)
	assert_true(Vector2i(2, 0) in tiles, "the forest itself is seen")
	assert_false(Vector2i(4, 0) in tiles, "behind the forest")
	assert_true(Vector2i(12, -6) in tiles)
	assert_false(Vector2i(13, 0) in tiles)
	tank.definition = HOMAR
	tiles = AttackCommand.tiles_in_range(state, tank)
	assert_false(Vector2i(2, 0) in tiles)
	assert_true(Vector2i(3, 0) in tiles)
	assert_true(Vector2i(4, 0) in tiles)


# --- roll maths ---


func test_hit_faces_table() -> void:
	# [base, max_hp, span, over, faces]
	var table := [
		[4, 10, 4, 2, 3],
		[4, 10, 4, 4, 2],
		[4, 10, 4, 0, 4],
		[4, 10, 1, 0, 4],
		[4, 10, 1, 1, 2],
		[4, 10, 0, 0, 4],
		[4, 10, 0, 3, 4],
		[30, 10, 4, 4, 10],
		[1, 10, 1, 1, 0],
		[3, 10, 4, 1, 2],
	]
	for row: Array in table:
		assert_eq(AttackCommand.hit_faces(row[0], row[1], row[2], row[3]), row[4], str(row))
	# The rule's own wording: a roll hits when roll * 2 * span <= base * (2 * span - over).
	for roll in range(1, 11):
		assert_eq(roll * 8 <= 4 * 6, roll <= AttackCommand.hit_faces(4, 10, 4, 2), str(roll))


func test_falloff_strike_draws_the_rng_exactly_hp_times() -> void:
	var pair := _pair(T72B3, SQUAD, 11)
	pair[0].hp = 7
	var probe := RandomNumberGenerator.new()
	probe.seed = state.rng.seed
	probe.state = state.rng.state
	var expected := 0
	var faces := AttackCommand.hit_on(state, pair[0], pair[1])
	for i in 7:
		if probe.randi_range(1, 8) <= faces:
			expected += 1
	assert_eq(AttackCommand.roll_hits(state, pair[0], pair[1]), expected)
	assert_eq(state.rng.state, probe.state)


# --- counterattack ---


func test_abrams_hit_by_a_squad_from_3_hexes_counters() -> void:
	var pair := _pair(SQUAD, ABRAMS, 3)
	assert_true(sim.execute(AttackCommand.new(pair[0].id, pair[1].id)))
	assert_eq(_counters(), 1)


func test_squad_hit_by_an_abrams_from_6_hexes_does_not_counter() -> void:
	var pair := _pair(ABRAMS, SQUAD, 6)
	assert_true(sim.execute(AttackCommand.new(pair[0].id, pair[1].id)))
	assert_true(pair[1].is_alive())
	assert_eq(_counters(), 0)


func test_direct_defender_without_line_of_sight_does_not_counter() -> void:
	_forest(Vector2i(2, 0))
	var pair := _pair(HOMAR, Fixtures.fighter(1, 50, 30, 14), 4)
	assert_true(sim.execute(AttackCommand.new(pair[0].id, pair[1].id)))
	assert_eq(_counters(), 0)
	assert_false(AttackCommand.forecast(state, pair[0], pair[1]).counter_possible)


func test_artillery_defender_counters_at_4_without_sight_but_not_at_2() -> void:
	_forest(Vector2i(2, 0))
	var artillery := Fixtures.set_range(Fixtures.fighter(5, 50, 30), 280, 320, 3, &"indirect")
	var pair := _pair(HOMAR, artillery, 4)
	var squad := state.add_unit(0, Fixtures.fighter(5, 2, 10, 2), Vector2i(0, 3))
	assert_true(sim.execute(AttackCommand.new(pair[0].id, pair[1].id)))
	assert_eq(_counters(), 1)
	events.clear()
	pair[1].coord = Vector2i(0, 5)
	assert_true(sim.execute(AttackCommand.new(squad.id, pair[1].id)))
	assert_eq(_counters(), 0)


# --- forecast ---


func test_forecast_at_maximum_range_is_half_of_effective_range() -> void:
	var pair := _pair(ABRAMS, SQUAD, 8)  # base 7 - 3 = 4, 10 shots
	var full := AttackCommand.forecast(state, pair[0], pair[1])
	pair[1].coord = Vector2i(14, 0)
	var half := AttackCommand.forecast(state, pair[0], pair[1])
	assert_true(is_equal_approx(full.expected_damage, 4.0), str(full.expected_damage))
	assert_true(is_equal_approx(half.expected_damage, 2.0), str(half.expected_damage))
	assert_eq([half.distance, half.range_factor, half.line_of_sight], [14, 0.5, true])


func test_forecast_problem_mirrors_validate() -> void:
	_forest(Vector2i(-2, 0))
	var tank := state.add_unit(0, T72B3, Vector2i(0, 0))
	var homar := state.add_unit(0, HOMAR, Vector2i(0, 2))
	for c: Vector2i in [Vector2i(5, 0), Vector2i(13, 0), Vector2i(-4, 0), Vector2i(1, 2)]:
		var target := state.add_unit(1, SQUAD, c)
		for shooter: Unit in [tank, homar]:
			assert_eq(
				AttackCommand.forecast(state, shooter, target).problem,
				AttackCommand.new(shooter.id, target.id).validate(state),
				"%s -> %s" % [shooter.definition.id, c]
			)
		target.hp = 0
	var hidden := state.add_unit(1, SQUAD, Vector2i(-4, 0))
	assert_eq(AttackCommand.forecast(state, tank, hidden).problem, "no_line_of_sight")
	assert_false(AttackCommand.forecast(state, tank, hidden).line_of_sight)
