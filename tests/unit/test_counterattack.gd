extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var sim: GameSimulation
var state: GameState
var events: Array[Dictionary] = []
var rejections: Array[String] = []


func before_each() -> void:
	state = GameState.new(Fixtures.plains_grid(4), 2, 1)
	sim = GameSimulation.new(state)
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	sim.command_rejected.connect(
		func(_c: Command, reason: String) -> void: rejections.append(reason)
	)


func _attacked(a: Unit, t: Unit, shots: int, damage: int, hp: int, counter: bool) -> Dictionary:
	return {
		"type": &"unit_attacked",
		"attacker_id": a.id,
		"target_id": t.id,
		"shots": shots,
		"damage": damage,
		"target_hp": hp,
		"counter": counter,
	}


func _counters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for e in events:
		if e["type"] == &"unit_attacked" and e["counter"]:
			result.append(e)
	return result


func test_surviving_target_counters_once_with_the_hp_it_has_left() -> void:
	var a := state.add_unit(0, Fixtures.sure_fighter(3), Vector2i(0, 0))
	var b := state.add_unit(1, Fixtures.sure_fighter(5), Vector2i(1, 0))
	assert_true(sim.execute(AttackCommand.new(a.id, b.id)))
	assert_eq(b.hp, 2)
	assert_eq(a.hp, 1)
	assert_eq(events.size(), 2)
	assert_eq(events[0], _attacked(a, b, 3, 3, 2, false))
	assert_eq(events[1], _attacked(b, a, 2, 2, 1, true))


func test_dead_target_does_not_counter() -> void:
	var a := state.add_unit(0, Fixtures.sure_fighter(6), Vector2i(0, 0))
	var b := state.add_unit(1, Fixtures.fighter(5, 1, 5), Vector2i(1, 0))
	state.add_unit(1, Fixtures.infantry(), Vector2i(-3, 0))
	assert_true(sim.execute(AttackCommand.new(a.id, b.id)))
	assert_eq(events.size(), 2)
	assert_eq(events[0], _attacked(a, b, 6, 6, 0, false))
	assert_eq(events[1], {"type": &"unit_died", "unit_id": b.id})
	assert_eq(a.hp, 6)


func test_counter_kills_attacker_and_ends_game() -> void:
	var a := state.add_unit(0, Fixtures.sure_fighter(3), Vector2i(0, 0))
	var b := state.add_unit(1, Fixtures.sure_fighter(10), Vector2i(1, 0))
	assert_true(sim.execute(AttackCommand.new(a.id, b.id)))
	assert_eq(events.size(), 4)
	assert_eq(events[0], _attacked(a, b, 3, 3, 7, false))
	assert_eq(events[1], _attacked(b, a, 7, 7, 0, true))
	assert_eq(events[2], {"type": &"unit_died", "unit_id": a.id})
	assert_eq(events[3], {"type": &"game_over", "winner": 1, "reason": &"eliminated"})
	assert_eq(state.winner, 1)
	rejections.clear()
	assert_false(sim.execute(EndTurnCommand.new()))
	assert_eq(rejections, ["game_over"] as Array[String])


func test_counter_kills_attacker_without_game_over_when_others_remain() -> void:
	var a := state.add_unit(0, Fixtures.sure_fighter(3), Vector2i(0, 0))
	state.add_unit(0, Fixtures.infantry(), Vector2i(-3, 0))
	var b := state.add_unit(1, Fixtures.sure_fighter(10), Vector2i(1, 0))
	assert_true(sim.execute(AttackCommand.new(a.id, b.id)))
	assert_eq(events.size(), 3)
	assert_eq(events[2], {"type": &"unit_died", "unit_id": a.id})
	assert_eq(state.winner, -1)


func test_no_counter_when_attacker_out_of_defender_range() -> void:
	var a := state.add_unit(0, Fixtures.fighter(4, 2, 10, 2), Vector2i(0, 0))
	var b := state.add_unit(1, Fixtures.sure_fighter(10), Vector2i(2, 0))
	assert_true(sim.execute(AttackCommand.new(a.id, b.id)))
	assert_eq(events.size(), 1)
	assert_eq(a.hp, 10)


func test_ranged_defender_counters_at_distance_one() -> void:
	var a := state.add_unit(0, Fixtures.sure_fighter(3), Vector2i(0, 0))
	var b := state.add_unit(1, Fixtures.sure_fighter(5, 2, 2), Vector2i(1, 0))
	assert_true(sim.execute(AttackCommand.new(a.id, b.id)))
	assert_eq(a.hp, 1)


func test_counter_ignores_and_keeps_defender_action_state() -> void:
	var a := state.add_unit(0, Fixtures.sure_fighter(3), Vector2i(0, 0))
	var b := state.add_unit(1, Fixtures.sure_fighter(5), Vector2i(1, 0))
	b.has_attacked = true
	b.moves_left = 0
	assert_true(sim.execute(AttackCommand.new(a.id, b.id)))
	assert_eq(a.hp, 1)
	assert_true(b.has_attacked)
	assert_eq(b.moves_left, 0)


func test_defender_counters_every_attacker() -> void:
	var a1 := state.add_unit(0, Fixtures.sure_fighter(1), Vector2i(0, 0))
	var a2 := state.add_unit(0, Fixtures.sure_fighter(1), Vector2i(1, -1))
	state.add_unit(0, Fixtures.infantry(), Vector2i(-3, 0))
	var b := state.add_unit(1, Fixtures.sure_fighter(5), Vector2i(1, 0))
	assert_true(sim.execute(AttackCommand.new(a1.id, b.id)))
	assert_true(sim.execute(AttackCommand.new(a2.id, b.id)))
	assert_eq(_counters().size(), 2)
	assert_eq(_counters()[0]["target_id"], a1.id)
	assert_eq(_counters()[1]["target_id"], a2.id)
	assert_eq(_counters()[1]["shots"], 3, "each counter rolls the HP left")
	assert_false(a1.is_alive())
	assert_false(a2.is_alive())


func test_counter_damage_includes_terrain_of_original_attacker() -> void:
	state.grid.set_terrain(Vector2i(0, 0), Terrain.Type.FOREST)
	var a := state.add_unit(0, Fixtures.fighter(4, 2), Vector2i(0, 0))
	var b := state.add_unit(1, Fixtures.fighter(5, 1), Vector2i(1, 0))
	assert_eq(AttackCommand.hit_on(state, b, a), 2)  # 5 - (2 + 1 forest), not 3 as on plains
	var replay := RandomNumberGenerator.new()
	replay.seed = state.rng.seed
	replay.state = state.rng.state
	var hits := 0
	for i in 10:
		if replay.randi_range(1, 10) <= 3:  # a's strike: 4 - 1
			hits += 1
	var counter_hits := 0
	for i in 10 - hits:
		if replay.randi_range(1, 10) <= 2:
			counter_hits += 1
	assert_true(sim.execute(AttackCommand.new(a.id, b.id)))
	assert_eq(events[1]["damage"], counter_hits)
	assert_eq(a.hp, 10 - counter_hits)


func test_ai_unit_dying_from_counter_does_not_break_turn() -> void:
	state.current_player = 1
	var weak := state.add_unit(1, Fixtures.fighter(4, 2, 1), Vector2i(1, 0))
	var other := state.add_unit(1, Fixtures.infantry(), Vector2i(-3, 0))
	var strong := state.add_unit(0, Fixtures.fighter(9, 5, 30), Vector2i(0, 0))
	AiPlayer.new().take_turn(sim)
	assert_false(weak.is_alive())
	assert_true(other.is_alive())
	assert_true(strong.is_alive())
	assert_eq(state.winner, -1)
	assert_eq(state.current_player, 0)
