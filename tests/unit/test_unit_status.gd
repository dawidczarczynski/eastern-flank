extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var state: GameState
var unit: Unit


func before_each() -> void:
	state = GameState.new(Fixtures.plains_grid(3), 2, 1)
	unit = state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))


func test_fresh_unit_not_done() -> void:
	assert_false(UnitStatus.is_done(state, unit))


func test_no_moves_and_attacked_is_done() -> void:
	unit.moves_left = 0
	unit.has_attacked = true
	assert_true(UnitStatus.is_done(state, unit))


func test_no_moves_enemy_adjacent_not_done() -> void:
	state.add_unit(1, Fixtures.infantry(), Vector2i(1, 0))
	unit.moves_left = 0
	assert_false(UnitStatus.is_done(state, unit))


func test_no_moves_no_enemy_in_range_is_done() -> void:
	state.add_unit(1, Fixtures.infantry(), Vector2i(3, 0))
	unit.moves_left = 0
	assert_true(UnitStatus.is_done(state, unit))


func test_moves_left_and_attacked_not_done() -> void:
	unit.moves_left = 1
	unit.has_attacked = true
	assert_false(UnitStatus.is_done(state, unit))


func test_hp_fill_width() -> void:
	assert_eq(UnitStatus.hp_fill_width(10, 10, 26), 26)
	assert_eq(UnitStatus.hp_fill_width(5, 10, 26), 13)
	assert_eq(UnitStatus.hp_fill_width(1, 8, 26), 3)
	assert_eq(UnitStatus.hp_fill_width(0, 10, 26), 0)
	assert_eq(UnitStatus.hp_fill_width(12, 10, 26), 26)
	assert_eq(UnitStatus.hp_fill_width(5, 0, 26), 0)
