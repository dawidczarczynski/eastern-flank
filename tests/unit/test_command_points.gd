extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var state: GameState
var sim: GameSimulation
var events: Array[Dictionary] = []
var rejections: Array[String] = []
var a: Unit
var b: Unit
var c: Unit
var enemy: Unit


## Player 0 has three companies A, B, C; player 1 has one enemy next to A's start.
func before_each() -> void:
	events.clear()
	rejections.clear()
	state = GameState.new(Fixtures.plains_grid(5), 2, 1)
	a = state.add_unit(0, Fixtures.fighter(4, 2, 10), Vector2i(0, 0))
	b = state.add_unit(0, Fixtures.fighter(4, 2, 10), Vector2i(0, 2))
	c = state.add_unit(0, Fixtures.fighter(4, 2, 10), Vector2i(0, -2))
	enemy = state.add_unit(1, Fixtures.fighter(4, 2, 30), Vector2i(1, 0))
	sim = GameSimulation.new(state)
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	sim.command_rejected.connect(
		func(_c: Command, reason: String) -> void: rejections.append(reason)
	)


func _limit(points: int) -> void:
	state.set_command_points_per_turn([points, points] as Array[int])


func _types() -> Array[StringName]:
	var result: Array[StringName] = []
	for e in events:
		result.append(e["type"])
	return result


func _point_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for e in events:
		if e["type"] == &"command_points_changed":
			result.append(e)
	return result


func test_two_points_example_from_the_task() -> void:
	_limit(2)
	assert_eq(state.command_points, 2)
	assert_true(sim.execute(MoveUnitCommand.new(a.id, Vector2i(0, 1))), "move A costs 1")
	assert_eq(state.command_points, 1)
	assert_true(sim.execute(AttackCommand.new(a.id, enemy.id)), "attack with A is free")
	assert_eq(state.command_points, 1)
	assert_true(sim.execute(MoveUnitCommand.new(b.id, Vector2i(0, 3))), "move B costs 1")
	assert_eq(state.command_points, 0)
	assert_false(sim.execute(MoveUnitCommand.new(c.id, Vector2i(0, -3))))
	assert_eq(rejections, ["no_command_points"] as Array[String])


func test_attack_by_a_fresh_unit_is_rejected_without_points() -> void:
	_limit(1)
	assert_true(sim.execute(MoveUnitCommand.new(c.id, Vector2i(0, -3))))
	var attack := AttackCommand.new(a.id, enemy.id)
	assert_eq(attack.validate(state), "no_command_points")
	assert_false(sim.execute(attack))
	assert_eq(AttackCommand.valid_targets(state, a.id), [] as Array[int])
	assert_false(enemy.hp < 30)


func test_an_attack_first_costs_a_point_and_activates_the_unit() -> void:
	_limit(1)
	assert_true(sim.execute(AttackCommand.new(a.id, enemy.id)))
	assert_eq(state.command_points, 0)
	assert_true(a.activated)
	assert_eq(MoveUnitCommand.new(a.id, Vector2i(0, 1)).validate(state), "unreachable")


func test_activated_unit_may_still_move_without_points() -> void:
	_limit(1)
	assert_true(sim.execute(MoveUnitCommand.new(a.id, Vector2i(0, 1))))
	a.moves_left = 2
	assert_eq(MoveUnitCommand.new(a.id, Vector2i(-1, 2)).validate(state), "")
	assert_true(sim.execute(MoveUnitCommand.new(a.id, Vector2i(-1, 2))))
	assert_eq(state.command_points, 0)


func test_ownership_is_checked_before_points() -> void:
	_limit(1)
	assert_eq(MoveUnitCommand.new(enemy.id, Vector2i(2, 0)).validate(state), "not_your_unit")
	assert_eq(AttackCommand.new(enemy.id, a.id).validate(state), "not_your_unit")


func test_counterattack_costs_nothing_and_does_not_activate() -> void:
	_limit(1)
	assert_true(sim.execute(AttackCommand.new(a.id, enemy.id)))
	var counters := events.filter(func(e: Dictionary) -> bool: return e.get("counter", false))
	assert_eq(counters.size(), 1, "the enemy counters")
	assert_false(enemy.activated)
	assert_eq(_point_events().size(), 1, "only the attacker's activation is announced")


func test_event_follows_the_first_action_event_and_is_emitted_once() -> void:
	_limit(2)
	sim.execute(MoveUnitCommand.new(a.id, Vector2i(0, 1)))
	sim.execute(AttackCommand.new(a.id, enemy.id))
	assert_eq(_types()[0], &"unit_moved")
	assert_eq(
		_point_events(),
		[{"type": &"command_points_changed", "player": 0, "remaining": 1}] as Array[Dictionary]
	)
	assert_eq(_types()[1], &"command_points_changed")


func test_points_reset_and_event_at_turn_start() -> void:
	_limit(2)
	sim.execute(MoveUnitCommand.new(a.id, Vector2i(0, 1)))
	sim.execute(MoveUnitCommand.new(b.id, Vector2i(0, 3)))
	events.clear()
	sim.execute(EndTurnCommand.new())
	assert_eq(
		_types(), [&"turn_ended", &"turn_started", &"command_points_changed"] as Array[StringName]
	)
	assert_eq(_point_events()[0], {"type": &"command_points_changed", "player": 1, "remaining": 2})
	assert_eq(state.command_points, 2)
	sim.execute(EndTurnCommand.new())
	assert_eq(state.command_points, 2)
	assert_false(a.activated)
	assert_false(b.activated)
	assert_true(sim.execute(MoveUnitCommand.new(c.id, Vector2i(0, -3))))


func test_unlimited_never_rejects_and_emits_nothing() -> void:
	assert_false(state.is_command_limited(0))
	assert_true(sim.execute(MoveUnitCommand.new(a.id, Vector2i(0, 1))))
	assert_true(sim.execute(MoveUnitCommand.new(b.id, Vector2i(0, 3))))
	assert_true(sim.execute(MoveUnitCommand.new(c.id, Vector2i(0, -3))))
	sim.execute(EndTurnCommand.new())
	assert_eq(_point_events().size(), 0)
	assert_eq(state.command_points, 0)


func test_unlimited_still_marks_units_activated() -> void:
	sim.execute(MoveUnitCommand.new(a.id, Vector2i(0, 1)))
	assert_true(a.activated)
	assert_false(b.activated)
	assert_true(state.can_activate(c))


func test_limits_are_per_player() -> void:
	state.set_command_points_per_turn([1, 0] as Array[int])
	assert_true(state.is_command_limited(0))
	assert_false(state.is_command_limited(1))
	assert_false(state.is_command_limited(7))
	sim.execute(MoveUnitCommand.new(a.id, Vector2i(0, 1)))
	assert_false(state.can_activate(b))
	assert_true(state.can_activate(a))
	events.clear()
	sim.execute(EndTurnCommand.new())
	assert_eq(_point_events().size(), 0, "player 1 is unlimited")
	assert_eq(state.command_points, 0)


func test_setter_loads_the_current_players_points() -> void:
	state.set_command_points_per_turn([3, 1] as Array[int])
	assert_eq(state.command_points, 3)
	assert_eq(state.command_points_per_turn, [3, 1] as Array[int])


func test_snapshot_contains_points_and_activated() -> void:
	_limit(2)
	sim.execute(MoveUnitCommand.new(a.id, Vector2i(0, 1)))
	var snap := state.snapshot()
	assert_eq(snap["command_points"], 1)
	var units: Array = snap["units"]
	assert_true(units[0]["activated"])
	assert_false(units[1]["activated"])
