extends TestCase
## TASK-022: `unit_moved` carries the path the unit walked.

const Fixtures := preload("res://tests/fixtures.gd")

var sim: GameSimulation
var unit: Unit


func before_each() -> void:
	var state := GameState.new(Fixtures.plains_grid(2), 2, 1)
	unit = state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	sim = GameSimulation.new(state)


func test_straight_move_path() -> void:
	var event := _move(Vector2i(2, 0))
	assert_eq(event["path"], _path([Vector2i(1, 0), Vector2i(2, 0)]))


func test_path_avoids_forest() -> void:
	sim.state.grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	var event := _move(Vector2i(1, 1))
	assert_eq(event["path"], _path([Vector2i(0, 1), Vector2i(1, 1)]))


func test_path_is_computed_before_state_changes() -> void:
	# The unit's own origin tile is occupied in the state; the path must still be found.
	var event := _move(Vector2i(1, 0))
	assert_eq(event["path"], _path([Vector2i(1, 0)]))


func test_path_properties_for_every_move() -> void:
	for target: Vector2i in [Vector2i(1, 1), Vector2i(2, 0), Vector2i(-2, 1), Vector2i(0, -2)]:
		before_each()
		sim.state.grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
		sim.state.grid.set_terrain(Vector2i(0, 1), Terrain.Type.HILLS)
		sim.state.add_unit(1, Fixtures.infantry(), Vector2i(1, -1))
		var before := unit.moves_left
		var event := _move(target)
		var path: Array[Vector2i] = event["path"]
		assert_false(path.is_empty(), "empty path to %s" % target)
		assert_eq(path.back(), target)
		assert_false(path.has(Vector2i(1, -1)), "path through occupied tile")
		var previous: Vector2i = event["from"]
		var cost := 0
		for c in path:
			assert_eq(Hex.distance(previous, c), 1, "%s -> %s not adjacent" % [previous, c])
			cost += sim.state.grid.move_cost(c)
			previous = c
		assert_eq(cost, before - unit.moves_left, "cost mismatch to %s" % target)


func _move(target: Vector2i) -> Dictionary:
	var events: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	assert_true(sim.execute(MoveUnitCommand.new(unit.id, target)), "move to %s" % target)
	assert_eq(events.size(), 1)
	return events[0] if not events.is_empty() else {}


func _path(coords: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(coords)
	return result
