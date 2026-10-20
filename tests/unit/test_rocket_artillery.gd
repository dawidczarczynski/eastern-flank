extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")
const SQUAD := preload("res://data/units/pl_mech_infantry.tres")
const T72B3 := preload("res://data/units/t72b3.tres")
const HOMAR := preload("res://data/units/homar_k.tres")
const URAGAN := preload("res://data/units/bm27_uragan.tres")


## Player 0 attacks; returns events of AttackCommand(attacker, target).
func _setup(attacker_def: UnitDefinition, target_def: UnitDefinition, distance: int) -> Array:
	var state := GameState.new(Fixtures.plains_grid(7), 2, 1)
	var attacker := state.add_unit(0, attacker_def, Vector2i(0, 0))
	var target := state.add_unit(1, target_def, Vector2i(distance, 0))
	var sim := GameSimulation.new(state)
	var events: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	sim.execute(AttackCommand.new(attacker.id, target.id))
	return [attacker, target, events, sim]


func _attacks(events: Array) -> int:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == &"unit_attacked").size()


func test_homar_k_hits_a_squad_at_distance_2_and_6_without_counter() -> void:
	for distance in [2, 6]:
		var r := _setup(HOMAR, SQUAD, distance)
		assert_eq((r[1] as Unit).hp, 7)
		assert_eq((r[0] as Unit).hp, 6)
		assert_eq(_attacks(r[2]), 1)


func test_uragan_adjacent_to_a_squad_is_countered() -> void:
	var r := _setup(URAGAN, SQUAD, 1)
	assert_eq((r[1] as Unit).hp, 7)
	assert_eq((r[0] as Unit).hp, 3)


func test_tank_attacks_an_mlrs_and_is_countered() -> void:
	var r := _setup(T72B3, URAGAN, 1)
	assert_eq((r[1] as Unit).hp, 1)
	assert_eq((r[0] as Unit).hp, 6)


func test_homar_k_outranges_the_uragan() -> void:
	var r := _setup(HOMAR, URAGAN, 6)
	assert_eq((r[1] as Unit).hp, 1)
	assert_eq((r[0] as Unit).hp, 6, "the Uragan (range 5) cannot counter at 6")
	r = _setup(HOMAR, URAGAN, 5)
	assert_eq((r[1] as Unit).hp, 1)
	assert_eq((r[0] as Unit).hp, 1, "countered within 5")


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
