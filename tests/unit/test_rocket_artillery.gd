extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")
const SQUAD := preload("res://data/units/pl_mech_infantry.tres")
const T72B3 := preload("res://data/units/t72b3.tres")
const HOMAR := preload("res://data/units/homar_k.tres")
const URAGAN := preload("res://data/units/bm27_uragan.tres")
## A seed whose T-72B3 strike leaves a full Uragan alive (destroyed about half the time).
const SURVIVING_SEED := 3


## Player 0 attacks; returns events of AttackCommand(attacker, target).
func _setup(
	attacker_def: UnitDefinition, target_def: UnitDefinition, distance: int, seed_value := 1
) -> Array:
	var state := GameState.new(Fixtures.plains_grid(7), 2, seed_value)
	var attacker := state.add_unit(0, attacker_def, Vector2i(0, 0))
	var target := state.add_unit(1, target_def, Vector2i(distance, 0))
	var sim := GameSimulation.new(state)
	var events: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	sim.execute(AttackCommand.new(attacker.id, target.id))
	return [attacker, target, events, sim]


func _attacks(events: Array) -> int:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == &"unit_attacked").size()


## Checks one attack from _setup: the target lost the first strike's damage and, when `countered`,
## the attacker the counter's damage (the counter happens; the seeds used leave the target alive).
func _check(r: Array, countered: bool, message := "") -> void:
	var attacker: Unit = r[0]
	var target: Unit = r[1]
	var strikes: Array = (r[2] as Array).filter(
		func(e: Dictionary) -> bool: return e["type"] == &"unit_attacked"
	)
	assert_eq(target.hp, maxi(0, target.definition.max_hp - int(strikes[0]["damage"])), message)
	assert_true(target.is_alive(), message)
	assert_eq(strikes.size(), 2 if countered else 1, message)
	var counter_damage: int = strikes[1]["damage"] if countered else 0
	assert_eq(attacker.hp, maxi(0, attacker.definition.max_hp - counter_damage), message)


func test_homar_k_hits_a_squad_at_distance_2_and_6_without_counter() -> void:
	for distance in [2, 6]:
		_check(_setup(HOMAR, SQUAD, distance), false, "distance %d" % distance)


func test_uragan_adjacent_to_a_squad_is_countered() -> void:
	_check(_setup(URAGAN, SQUAD, 1), true)


func test_tank_attacks_an_mlrs_and_is_countered() -> void:
	_check(_setup(T72B3, URAGAN, 1, SURVIVING_SEED), true)


func test_homar_k_outranges_the_uragan() -> void:
	_check(_setup(HOMAR, URAGAN, 6), false, "the Uragan (range 5) cannot counter at 6")
	_check(_setup(HOMAR, URAGAN, 5), true, "countered within 5")


func test_mlrs_cannot_attack_beyond_its_range() -> void:
	var state := GameState.new(Fixtures.plains_grid(7), 2, 1)
	var uragan := state.add_unit(0, URAGAN, Vector2i(0, 0))
	var homar := state.add_unit(0, HOMAR, Vector2i(0, 1))
	var near := state.add_unit(1, SQUAD, Vector2i(6, 0))
	var far := state.add_unit(1, SQUAD, Vector2i(7, 0))
	assert_eq(AttackCommand.new(uragan.id, near.id).validate(state), "out_of_range")
	assert_eq(AttackCommand.new(homar.id, near.id).validate(state), "")
	assert_eq(Hex.distance(homar.coord, far.coord), 7)
	assert_eq(AttackCommand.new(homar.id, far.id).validate(state), "out_of_range")


## Rocket volleys follow the unit class, so every MLRS fires one, whatever its id.
func test_volley_fire_follows_the_mlrs_class() -> void:
	assert_true(UnitModels.fires_volley(HOMAR))
	assert_true(UnitModels.fires_volley(URAGAN))
	assert_false(UnitModels.fires_volley(T72B3))
	assert_false(UnitModels.fires_volley(null))
