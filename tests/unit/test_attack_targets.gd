extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var state: GameState
var a: Unit
var b: Unit
var c: Unit
var d: Unit
var e: Unit


func _build(attacker_range: int) -> void:
	state = GameState.new(Fixtures.plains_grid(3), 2, 1)
	a = state.add_unit(0, Fixtures.fighter(4, 2, 10, attacker_range), Vector2i(0, 0))
	b = state.add_unit(1, Fixtures.infantry(), Vector2i(1, 0))
	c = state.add_unit(1, Fixtures.infantry(), Vector2i(2, 0))
	d = state.add_unit(0, Fixtures.infantry(), Vector2i(0, 1))
	e = state.add_unit(1, Fixtures.infantry(), Vector2i(-1, 0))
	e.hp = 0


func before_each() -> void:
	_build(1)


func test_range_one_only_adjacent_living_enemy() -> void:
	assert_eq(AttackCommand.valid_targets(state, a.id), [b.id] as Array[int])


func test_range_two_includes_distant_enemy() -> void:
	_build(2)
	assert_eq(AttackCommand.valid_targets(state, a.id), [b.id, c.id] as Array[int])


func test_empty_after_attack() -> void:
	var sim := GameSimulation.new(state)
	sim.execute(AttackCommand.new(a.id, b.id))
	assert_eq(AttackCommand.valid_targets(state, a.id), [] as Array[int])


func test_empty_on_other_players_turn() -> void:
	state.current_player = 1
	assert_eq(AttackCommand.valid_targets(state, a.id), [] as Array[int])


func test_empty_for_unknown_attacker() -> void:
	assert_eq(AttackCommand.valid_targets(state, 99), [] as Array[int])


func test_empty_when_game_over() -> void:
	state.finish(0, &"eliminated")
	assert_eq(AttackCommand.valid_targets(state, a.id), [] as Array[int])


func test_consistent_with_validate() -> void:
	_build(2)
	var targets := AttackCommand.valid_targets(state, a.id)
	for unit: Unit in state.units.values():
		if not unit.is_alive():
			continue
		var ok := AttackCommand.new(a.id, unit.id).validate(state) == ""
		assert_eq(unit.id in targets, ok)
