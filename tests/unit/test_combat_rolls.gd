extends TestCase
## Per-element rolls (TASK-089a): each strength point (HP) of the striker rolls a die with
## max_hp faces on GameState.rng and hits on a roll <= hit_on.

const Fixtures := preload("res://tests/fixtures.gd")
const ABRAMS := preload("res://data/units/m1a2_sepv3.tres")
const SQUAD := preload("res://data/units/pl_mech_infantry.tres")
const HOMAR := preload("res://data/units/homar_k.tres")
const URAGAN := preload("res://data/units/bm27_uragan.tres")

var state: GameState
var sim: GameSimulation
var events: Array[Dictionary] = []


func before_each() -> void:
	_reset(1)


func _reset(seed_value: int) -> void:
	state = GameState.new(Fixtures.plains_grid(7), 2, seed_value)
	sim = GameSimulation.new(state)
	events = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))


func _attacks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for e in events:
		if e["type"] == &"unit_attacked":
			result.append(e)
	return result


## A copy of the state's generator at its current position.
func _rng_copy() -> RandomNumberGenerator:
	var copy := RandomNumberGenerator.new()
	copy.seed = state.rng.seed
	copy.state = state.rng.state
	return copy


## Replays `shots` rolls of a d`die` on `rng`; returns the number of results <= hit_on.
func _replay_hits(rng: RandomNumberGenerator, shots: int, die: int, hit_on: int) -> int:
	var hits := 0
	for i in shots:
		if rng.randi_range(1, die) <= hit_on:
			hits += 1
	return hits


# --- hit_on -------------------------------------------------------------------------------------


func _hit_on(attacker_def: UnitDefinition, target_def: UnitDefinition, tile: Terrain.Type) -> int:
	state.grid.set_terrain(Vector2i(1, 0), tile)
	var a := state.add_unit(0, attacker_def, Vector2i(0, 0))
	var t := state.add_unit(1, target_def, Vector2i(1, 0))
	var result := AttackCommand.hit_on(state, a, t)
	state.units.erase(a.id)
	state.units.erase(t.id)
	return result


func test_hit_on_abrams_on_a_squad_by_terrain() -> void:
	assert_eq(_hit_on(ABRAMS, SQUAD, Terrain.Type.PLAINS), 4)
	assert_eq(_hit_on(ABRAMS, SQUAD, Terrain.Type.FOREST), 3)
	assert_eq(_hit_on(ABRAMS, SQUAD, Terrain.Type.HILLS), 2)


func test_hit_on_is_never_below_one() -> void:
	assert_eq(_hit_on(SQUAD, ABRAMS, Terrain.Type.HILLS), 1)


func test_hit_on_homar_on_uragan_on_plains() -> void:
	assert_eq(_hit_on(HOMAR, URAGAN, Terrain.Type.PLAINS), 5)


func test_hit_on_is_capped_at_max_hp_and_then_every_shot_hits() -> void:
	var a := state.add_unit(0, Fixtures.fighter(20, 2, 6), Vector2i(0, 0))
	var t := state.add_unit(1, Fixtures.fighter(1, 1, 30), Vector2i(1, 0))
	assert_eq(AttackCommand.hit_on(state, a, t), 6)
	a.hp = 4
	assert_true(sim.execute(AttackCommand.new(a.id, t.id)))
	assert_eq(_attacks()[0]["damage"], 4)
	assert_eq(_attacks()[0]["shots"], 4)
	assert_eq(t.hp, 26)


# --- the roll -----------------------------------------------------------------------------------


func _check_strike_replays(attacker_hp: int) -> void:
	var a := state.add_unit(0, ABRAMS, Vector2i(0, 0))
	var t := state.add_unit(1, Fixtures.fighter(1, 3, 30), Vector2i(1, 0))
	a.hp = attacker_hp
	var replay := _rng_copy()
	var expected := _replay_hits(replay, attacker_hp, 10, 4)
	assert_true(sim.execute(AttackCommand.new(a.id, t.id)))
	var hit := _attacks()[0]
	assert_eq(hit["shots"], attacker_hp)
	assert_eq(hit["damage"], expected)
	assert_eq(t.hp, 30 - expected)
	# The counter (A1 vs D4: hit_on 1, d30) rolls t.hp times after the attacker's rolls.
	_replay_hits(replay, t.hp, 30, 1)
	assert_eq(state.rng.state, replay.state)


func test_full_strength_strike_rolls_ten_times_and_counts_hits() -> void:
	_check_strike_replays(10)


func test_battered_strike_rolls_only_its_hp() -> void:
	_check_strike_replays(3)


func test_roll_hits_matches_a_replayed_generator() -> void:
	var a := state.add_unit(0, ABRAMS, Vector2i(0, 0))
	var t := state.add_unit(1, SQUAD, Vector2i(1, 0))
	for i in 20:
		var replay := _rng_copy()
		assert_eq(AttackCommand.roll_hits(state, a, t), _replay_hits(replay, 10, 10, 4))
		assert_eq(state.rng.state, replay.state)


func test_damage_can_be_zero() -> void:
	var found := false
	for seed_value in range(1, 200):
		_reset(seed_value)
		var squad := state.add_unit(0, SQUAD, Vector2i(0, 0))
		var tank := state.add_unit(1, ABRAMS, Vector2i(1, 0))
		assert_true(sim.execute(AttackCommand.new(squad.id, tank.id)))
		var hit := _attacks()[0]
		assert_true(hit.has("shots"))
		assert_eq(hit["shots"], 10)
		assert_eq(tank.hp, 10 - int(hit["damage"]))
		if hit["damage"] == 0:
			assert_eq(hit["target_hp"], 10)
			assert_eq(tank.hp, 10)
			found = true
			break
	assert_true(found, "some seed gives a complete miss (35 % per strike)")


func test_hp_never_goes_below_zero_and_a_dead_victim_dies() -> void:
	var a := state.add_unit(0, Fixtures.fighter(20, 2, 6), Vector2i(0, 0))
	var t := state.add_unit(1, Fixtures.fighter(1, 1, 10), Vector2i(1, 0))
	state.add_unit(1, SQUAD, Vector2i(-5, 0))
	t.hp = 2
	assert_true(sim.execute(AttackCommand.new(a.id, t.id)))
	assert_eq(t.hp, 0)
	assert_eq(events[0]["damage"], 6, "damage is the hits, before clamping")
	assert_eq(events[0]["target_hp"], 0)
	assert_eq(events[1], {"type": &"unit_died", "unit_id": t.id})


func test_all_shots_are_rolled_even_after_the_target_died() -> void:
	var a := state.add_unit(0, ABRAMS, Vector2i(0, 0))
	var t := state.add_unit(1, Fixtures.fighter(1, 1, 10), Vector2i(1, 0))
	state.add_unit(1, SQUAD, Vector2i(-5, 0))
	t.hp = 1
	var replay := _rng_copy()
	_replay_hits(replay, 10, 10, 6)
	sim.execute(AttackCommand.new(a.id, t.id))
	if t.is_alive():
		_replay_hits(replay, t.hp, 10, 1)
	assert_eq(state.rng.state, replay.state)


# --- counter rolls ------------------------------------------------------------------------------


func test_counter_rolls_the_defenders_hp_left_with_its_die() -> void:
	state.grid.set_terrain(Vector2i(0, 0), Terrain.Type.FOREST)
	var a := state.add_unit(0, SQUAD, Vector2i(0, 0))  # D3 + forest 1 = 4
	var t := state.add_unit(1, Fixtures.fighter(9, 1, 8), Vector2i(1, 0))  # counter hit_on 5, d8
	var replay := _rng_copy()
	var hits := _replay_hits(replay, 10, 10, 3)  # squad A4 vs D1: hit_on 3 on its d10
	var left := 8 - hits
	assert_true(left > 0, "precondition: the fixture seed leaves the defender alive")
	var counter_hits := _replay_hits(replay, left, 8, 5)
	assert_true(sim.execute(AttackCommand.new(a.id, t.id)))
	var strikes := _attacks()
	assert_eq(strikes[0]["damage"], hits)
	assert_eq(strikes.size(), 2)
	assert_true(strikes[1]["counter"])
	assert_eq(strikes[1]["shots"], left)
	assert_eq(strikes[1]["damage"], counter_hits)
	assert_eq(a.hp, maxi(0, 10 - counter_hits))
	assert_eq(state.rng.state, replay.state)


func _assert_only_attacker_rolled(replay: RandomNumberGenerator) -> void:
	assert_eq(state.rng.state, replay.state)
	assert_eq(_attacks().size(), 1)


func test_no_counter_rolls_when_the_defender_died() -> void:
	var a := state.add_unit(0, Fixtures.fighter(20, 2, 6), Vector2i(0, 0))
	var t := state.add_unit(1, Fixtures.fighter(5, 1, 5), Vector2i(1, 0))
	state.add_unit(1, SQUAD, Vector2i(-5, 0))
	var replay := _rng_copy()
	_replay_hits(replay, 6, 6, 6)
	sim.execute(AttackCommand.new(a.id, t.id))
	assert_false(t.is_alive())
	_assert_only_attacker_rolled(replay)


func test_no_counter_rolls_when_out_of_range() -> void:
	var a := state.add_unit(0, Fixtures.fighter(5, 2, 10, 2), Vector2i(0, 0))
	var t := state.add_unit(1, Fixtures.fighter(5, 1, 10), Vector2i(2, 0))
	var replay := _rng_copy()
	_replay_hits(replay, 10, 10, 4)
	sim.execute(AttackCommand.new(a.id, t.id))
	assert_true(t.is_alive())
	_assert_only_attacker_rolled(replay)


func test_no_counter_rolls_when_the_battle_ended() -> void:
	var a := state.add_unit(0, Fixtures.fighter(20, 2, 6), Vector2i(0, 0))
	var t := state.add_unit(1, Fixtures.fighter(5, 1, 10), Vector2i(1, 0))
	state.set_objectives(
		Fixtures.objectives(
			0, [], [], [Fixtures.condition(VictoryCondition.Kind.DESTROY_SHARE, 0, [], 10)]
		)
	)
	state.record_starting_hp()
	var replay := _rng_copy()
	_replay_hits(replay, 6, 6, 6)
	sim.execute(AttackCommand.new(a.id, t.id))
	assert_true(t.is_alive())
	assert_true(state.is_over())
	_assert_only_attacker_rolled(replay)


# --- determinism --------------------------------------------------------------------------------


## Ten ranged attackers (no counter) shoot one big target; returns [events, snapshot].
func _ten_attacks(seed_value: int) -> Array:
	_reset(seed_value)
	var target := state.add_unit(1, Fixtures.fighter(1, 2, 100), Vector2i(0, 0))
	var placed := 0
	for c in state.grid.coords():
		var d := Hex.distance(c, Vector2i.ZERO)
		if placed < 10 and d >= 2 and d <= 4:
			state.add_unit(0, Fixtures.fighter(6, 2, 10, 5), c)
			placed += 1
	for unit in state.units_of(0):
		assert_true(sim.execute(AttackCommand.new(unit.id, target.id)))
	return [events.duplicate(true), state.snapshot()]


func test_same_seed_same_commands_give_the_same_result() -> void:
	var first := _ten_attacks(7)
	var second := _ten_attacks(7)
	assert_eq(first[0], second[0])
	assert_eq(first[1], second[1])


func test_a_different_seed_gives_a_different_result() -> void:
	var first := _ten_attacks(7)
	var other := _ten_attacks(8)
	assert_true(first[0] != other[0])


# --- calibration --------------------------------------------------------------------------------


func _mean_damage(
	attacker_def: UnitDefinition, attacker_hp: int, target_def: UnitDefinition
) -> float:
	var a := state.add_unit(0, attacker_def, Vector2i(0, 0))
	var t := state.add_unit(1, target_def, Vector2i(1, 0))
	a.hp = attacker_hp
	var total := 0
	for i in 2000:
		total += AttackCommand.roll_hits(state, a, t)
	return total / 2000.0


func test_full_abrams_on_a_squad_averages_four() -> void:
	var mean := _mean_damage(ABRAMS, 10, SQUAD)
	assert_true(absf(mean - 4.0) <= 0.15, "mean %f" % mean)


func test_half_strength_squad_on_an_abrams_averages_half() -> void:
	var mean := _mean_damage(SQUAD, 5, ABRAMS)
	assert_true(absf(mean - 0.5) <= 0.05, "mean %f" % mean)
