extends TestCase
## CombatForecast (TASK-089a): exact distribution of a strike and its counter, without the rng.

const Fixtures := preload("res://tests/fixtures.gd")
const ABRAMS := preload("res://data/units/m1a2_sepv3.tres")
const T72B3 := preload("res://data/units/t72b3.tres")
const SQUAD := preload("res://data/units/pl_mech_infantry.tres")
const HOMAR := preload("res://data/units/homar_k.tres")
const URAGAN := preload("res://data/units/bm27_uragan.tres")

var state: GameState


func before_each() -> void:
	state = GameState.new(Fixtures.plains_grid(7), 2, 1)


func _forecast(
	attacker_def: UnitDefinition, defender_def: UnitDefinition, distance: int = 1
) -> CombatForecast:
	var a := state.add_unit(0, attacker_def, Vector2i(0, 0))
	var d := state.add_unit(1, defender_def, Vector2i(distance, 0))
	return AttackCommand.forecast(state, a, d)


func _near(actual: float, expected: float, tolerance: float) -> void:
	assert_true(
		absf(actual - expected) <= tolerance, "%f is not %f ± %f" % [actual, expected, tolerance]
	)


func test_abrams_on_a_squad() -> void:
	var f := _forecast(ABRAMS, SQUAD)
	assert_eq(f.shots, 10)
	assert_eq(f.hit_on, 4)
	assert_eq(f.die, 10)
	_near(f.expected_damage, 4.0, 1e-6)
	assert_eq(f.damage_low, 2)
	assert_eq(f.damage_high, 6)
	_near(f.kill_chance, pow(0.4, 10), 1e-12)  # all ten hit: ~0.01 %
	assert_true(f.counter_possible)
	_near(f.counter_expected, 0.6, 1e-3)


func test_squad_on_an_abrams() -> void:
	var f := _forecast(SQUAD, ABRAMS)
	_near(f.expected_damage, 1.0, 1e-6)
	assert_eq(f.damage_low, 0)
	assert_eq(f.damage_high, 2)
	_near(f.kill_chance, pow(0.1, 10), 1e-15)
	_near(f.counter_expected, 3.6, 1e-3)
	assert_true(f.counter_low <= f.counter_high)


func test_abrams_on_an_mlrs() -> void:
	for mlrs: UnitDefinition in [HOMAR, URAGAN]:
		before_each()
		var f := _forecast(ABRAMS, mlrs)
		_near(f.expected_damage, 5.398, 1e-3)
		assert_eq(f.damage_low, 4)
		assert_eq(f.damage_high, 6)
		_near(f.kill_chance, 0.6331, 1e-4)
		assert_true(f.counter_possible)
		_near(f.counter_expected, 0.2007, 1e-3)


func test_abrams_on_a_t72b3() -> void:
	var f := _forecast(ABRAMS, T72B3)
	_near(f.expected_damage, 3.0, 1e-3)
	assert_eq(f.damage_low, 1)
	assert_eq(f.damage_high, 5)
	_near(f.kill_chance, 0.0016, 1e-4)
	_near(f.counter_expected, 1.25, 1e-3)


func test_homar_on_an_uragan_at_six_has_no_counter() -> void:
	var f := _forecast(HOMAR, URAGAN, 6)
	assert_false(f.counter_possible)
	_near(f.counter_expected, 0.0, 1e-12)
	assert_eq(f.counter_low, 0)
	assert_eq(f.counter_high, 0)
	_near(f.attacker_loss_chance, 0.0, 1e-12)
	_near(f.kill_chance, 0.3349, 1e-4)


func test_expected_damage_follows_the_attackers_strength() -> void:
	var a := state.add_unit(0, ABRAMS, Vector2i(0, 0))
	var d := state.add_unit(1, SQUAD, Vector2i(1, 0))
	for hp in range(0, 11):
		a.hp = hp
		var f := AttackCommand.forecast(state, a, d)
		assert_eq(f.shots, hp)
		_near(f.expected_damage, 0.4 * hp, 1e-6)
	a.hp = 5
	_near(AttackCommand.forecast(state, a, d).expected_damage, 2.0, 1e-6)


func test_expected_damage_is_capped_by_the_targets_hp() -> void:
	var a := state.add_unit(0, Fixtures.fighter(20, 2, 6), Vector2i(0, 0))
	var d := state.add_unit(1, SQUAD, Vector2i(1, 0))
	d.hp = 4
	var f := AttackCommand.forecast(state, a, d)
	_near(f.expected_damage, 4.0, 1e-9)
	_near(f.kill_chance, 1.0, 1e-9)
	assert_eq(f.damage_low, 4)
	assert_eq(f.damage_high, 4)
	_near(f.counter_expected, 0.0, 1e-12)


func test_attacker_loss_chance_from_a_certain_counter() -> void:
	# A 3-HP squad attacks an A20 6-HP fighter: it deals at most 3, so at least 3 counter shots
	# answer, every one of them hits (hit_on capped at 6 on a d6) and the squad always dies.
	var a := state.add_unit(0, SQUAD, Vector2i(0, 0))
	var d := state.add_unit(1, Fixtures.fighter(20, 9, 6), Vector2i(1, 0))
	a.hp = 3
	var f := AttackCommand.forecast(state, a, d)
	_near(f.attacker_loss_chance, 1.0, 1e-9)
	_near(f.counter_expected, 3.0, 1e-9)
	assert_eq(f.counter_low, 3)
	assert_eq(f.counter_high, 3)


func test_forecast_touches_neither_the_rng_nor_units() -> void:
	var a := state.add_unit(0, ABRAMS, Vector2i(0, 0))
	var d := state.add_unit(1, T72B3, Vector2i(1, 0))
	state.rng.randi()
	var rng_state := state.rng.state
	var before := state.snapshot()
	AttackCommand.forecast(state, a, d)
	assert_eq(state.rng.state, rng_state)
	assert_eq(state.snapshot(), before)
	assert_eq(a.hp, 10)
	assert_eq(d.hp, 8)
