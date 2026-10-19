extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")
const INFANTRY := preload("res://data/units/infantry.tres")
const CAVALRY := preload("res://data/units/cavalry.tres")
const ARTILLERY := preload("res://data/units/rocket_artillery.tres")


## Player 0 attacks; returns events of AttackCommand(attacker, target).
func _setup(attacker_def: UnitDefinition, target_def: UnitDefinition, distance: int) -> Array:
	var state := GameState.new(Fixtures.plains_grid(6), 2, 1)
	var attacker := state.add_unit(0, attacker_def, Vector2i(0, 0))
	var target := state.add_unit(1, target_def, Vector2i(distance, 0))
	var sim := GameSimulation.new(state)
	var events: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	sim.execute(AttackCommand.new(attacker.id, target.id))
	return [attacker, target, events, sim]


func test_rocket_artillery_definition_values() -> void:
	var d := ARTILLERY
	assert_eq(d.id, &"rocket_artillery")
	assert_eq(d.display_name, "Rocket Artillery")
	assert_eq(d.short_name, "ART")
	assert_eq(d.max_hp, 6)
	assert_eq(d.move_points, 3)
	assert_eq(d.attack, 5)
	assert_eq(d.defense, 1)
	assert_eq(d.attack_range, 5)


func _attacks(events: Array) -> int:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == &"unit_attacked").size()


func test_artillery_hits_infantry_at_distance_2_and_5_without_counter() -> void:
	for distance in [2, 5]:
		var r := _setup(ARTILLERY, INFANTRY, distance)
		assert_eq((r[1] as Unit).hp, 8)
		assert_eq((r[0] as Unit).hp, 6)
		assert_eq(_attacks(r[2]), 1)


func test_artillery_adjacent_to_infantry_is_countered() -> void:
	var r := _setup(ARTILLERY, INFANTRY, 1)
	assert_eq((r[1] as Unit).hp, 8)
	assert_eq((r[0] as Unit).hp, 3)


func test_cavalry_attacks_artillery_and_is_countered() -> void:
	var r := _setup(CAVALRY, ARTILLERY, 1)
	assert_eq((r[1] as Unit).hp, 2)
	assert_eq((r[0] as Unit).hp, 5)


func test_artillery_vs_artillery_at_distance_5() -> void:
	var r := _setup(ARTILLERY, ARTILLERY, 5)
	assert_eq((r[1] as Unit).hp, 2)
	assert_eq((r[0] as Unit).hp, 2)


func test_artillery_cannot_attack_at_distance_6() -> void:
	var state := GameState.new(Fixtures.plains_grid(6), 2, 1)
	var attacker := state.add_unit(0, ARTILLERY, Vector2i(0, 0))
	var target := state.add_unit(1, INFANTRY, Vector2i(6, 0))
	assert_eq(AttackCommand.new(attacker.id, target.id).validate(state), "out_of_range")


## Rocket volleys follow the unit class, so every MLRS fires one, whatever its id.
func test_volley_fire_follows_the_mlrs_class() -> void:
	assert_true(UnitModels.fires_volley(ARTILLERY))
	assert_true(UnitModels.fires_volley(load("res://data/units/bm27_uragan.tres")))
	assert_false(UnitModels.fires_volley(load("res://data/units/t72b3.tres")))
	assert_false(UnitModels.fires_volley(null))
