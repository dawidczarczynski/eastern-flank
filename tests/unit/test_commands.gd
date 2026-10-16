extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var sim: GameSimulation
var unit: Unit
var enemy: Unit


func before_each() -> void:
	var state := GameState.new(Fixtures.plains_grid(4), 2, 1)
	unit = state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	enemy = state.add_unit(1, Fixtures.infantry(), Vector2i(3, 0))
	sim = GameSimulation.new(state)


func test_move_within_range() -> void:
	assert_true(sim.execute(MoveUnitCommand.new(unit.id, Vector2i(2, 0))))
	assert_eq(unit.coord, Vector2i(2, 0))
	assert_eq(unit.moves_left, 1)


func test_move_emits_event() -> void:
	var events: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	sim.execute(MoveUnitCommand.new(unit.id, Vector2i(1, 0)))
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], &"unit_moved")


func test_move_beyond_range_is_rejected() -> void:
	assert_false(sim.execute(MoveUnitCommand.new(unit.id, Vector2i(4, -4))))
	assert_eq(unit.coord, Vector2i.ZERO)
	assert_eq(sim.history.size(), 0)


func test_cannot_move_enemy_unit() -> void:
	assert_false(sim.execute(MoveUnitCommand.new(enemy.id, Vector2i(2, 0))))


func test_cannot_move_onto_occupied_tile() -> void:
	assert_false(sim.execute(MoveUnitCommand.new(unit.id, enemy.coord)))


func test_end_turn_switches_player_and_restores_moves() -> void:
	sim.execute(MoveUnitCommand.new(unit.id, Vector2i(1, 0)))
	sim.execute(EndTurnCommand.new())
	assert_eq(sim.state.current_player, 1)
	assert_eq(sim.state.turn, 1)
	sim.execute(EndTurnCommand.new())
	assert_eq(sim.state.current_player, 0)
	assert_eq(sim.state.turn, 2)
	assert_eq(unit.moves_left, 3)
