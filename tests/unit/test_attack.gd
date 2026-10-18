# gdlint: disable=max-public-methods
extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var sim: GameSimulation
var state: GameState
var unit: Unit
var enemy: Unit
var far_enemy: Unit
var events: Array[Dictionary] = []
var rejections: Array[String] = []


func before_each() -> void:
	state = GameState.new(Fixtures.plains_grid(4), 2, 1)
	unit = state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	enemy = state.add_unit(1, Fixtures.infantry(), Vector2i(1, 0))
	far_enemy = state.add_unit(1, Fixtures.infantry(), Vector2i(-3, 0))
	sim = GameSimulation.new(state)
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	sim.command_rejected.connect(
		func(_c: Command, reason: String) -> void: rejections.append(reason)
	)


func _events_of(type: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for e in events:
		if e["type"] == type:
			result.append(e)
	return result


func test_attack_adjacent_enemy_deals_attack_minus_defense() -> void:
	assert_true(sim.execute(AttackCommand.new(unit.id, enemy.id)))
	assert_eq(enemy.hp, 8)  # 10 - (4 - 2)


func test_damage_is_at_least_one() -> void:
	var tank := state.add_unit(1, Fixtures.fighter(1, 9), Vector2i(0, 1))
	assert_true(sim.execute(AttackCommand.new(unit.id, tank.id)))
	assert_eq(tank.hp, 9)


func test_unit_attacked_event_fields() -> void:
	sim.execute(AttackCommand.new(unit.id, enemy.id))
	assert_eq(events.size(), 2)  # the hit and the target's counter
	var e := events[0]
	assert_eq(e["type"], &"unit_attacked")
	assert_false(e["counter"])
	assert_eq(e["attacker_id"], unit.id)
	assert_eq(e["target_id"], enemy.id)
	assert_eq(e["damage"], 2)
	assert_eq(e["target_hp"], 8)


func test_out_of_range_is_rejected() -> void:
	assert_false(sim.execute(AttackCommand.new(unit.id, far_enemy.id)))
	assert_eq(rejections, ["out_of_range"] as Array[String])
	assert_eq(far_enemy.hp, 10)


func test_attack_range_comes_from_definition() -> void:
	var archer := state.add_unit(0, Fixtures.fighter(4, 2, 10, 2), Vector2i(-1, 0))
	assert_true(sim.execute(AttackCommand.new(archer.id, enemy.id)))  # distance 2


func test_target_beyond_attack_range_is_rejected() -> void:
	var archer := state.add_unit(0, Fixtures.fighter(4, 2, 10, 2), Vector2i(-2, 0))
	assert_false(sim.execute(AttackCommand.new(archer.id, enemy.id)))  # distance 3
	assert_eq(rejections, ["out_of_range"] as Array[String])


func test_cannot_attack_own_unit() -> void:
	var friend := state.add_unit(0, Fixtures.infantry(), Vector2i(0, 1))
	assert_false(sim.execute(AttackCommand.new(unit.id, friend.id)))
	assert_eq(rejections, ["not_an_enemy"] as Array[String])


func test_cannot_attack_with_enemy_unit() -> void:
	assert_false(sim.execute(AttackCommand.new(enemy.id, unit.id)))
	assert_eq(rejections, ["not_your_unit"] as Array[String])


func test_missing_units_are_rejected() -> void:
	assert_false(sim.execute(AttackCommand.new(999, enemy.id)))
	assert_false(sim.execute(AttackCommand.new(unit.id, 999)))
	assert_eq(rejections, ["unit_not_found", "unit_not_found"] as Array[String])


func test_cannot_attack_dead_unit() -> void:
	enemy.hp = 0
	assert_false(sim.execute(AttackCommand.new(unit.id, enemy.id)))
	assert_eq(rejections, ["unit_not_found"] as Array[String])


func test_can_attack_only_once_per_turn() -> void:
	assert_true(sim.execute(AttackCommand.new(unit.id, enemy.id)))
	assert_false(sim.execute(AttackCommand.new(unit.id, enemy.id)))
	assert_eq(rejections, ["already_attacked"] as Array[String])
	assert_eq(enemy.hp, 8)


func test_attack_zeroes_remaining_moves() -> void:
	assert_true(sim.execute(AttackCommand.new(unit.id, enemy.id)))
	assert_true(unit.has_attacked)
	assert_eq(unit.moves_left, 0)
	assert_false(sim.execute(MoveUnitCommand.new(unit.id, Vector2i(-1, 0))))


func test_attack_resets_on_next_own_turn() -> void:
	sim.execute(AttackCommand.new(unit.id, enemy.id))
	sim.execute(EndTurnCommand.new())
	assert_true(unit.has_attacked)  # still the enemy's turn
	sim.execute(EndTurnCommand.new())
	assert_false(unit.has_attacked)
	assert_eq(unit.moves_left, 3)
	assert_true(sim.execute(AttackCommand.new(unit.id, enemy.id)))
	assert_eq(enemy.hp, 6)


func test_lethal_attack_kills_and_emits_unit_died() -> void:
	enemy.hp = 2
	assert_true(sim.execute(AttackCommand.new(unit.id, enemy.id)))
	assert_eq(enemy.hp, 0)
	assert_false(enemy.is_alive())
	assert_eq(events.size(), 2)
	assert_eq(events[0]["type"], &"unit_attacked")
	assert_eq(events[0]["target_hp"], 0)
	assert_eq(events[1], {"type": &"unit_died", "unit_id": enemy.id})


func test_hp_does_not_go_below_zero() -> void:
	enemy.hp = 1
	sim.execute(AttackCommand.new(unit.id, enemy.id))
	assert_eq(enemy.hp, 0)
	assert_eq(events[0]["damage"], 2)


func test_dead_unit_is_not_returned_and_does_not_block() -> void:
	enemy.hp = 2
	sim.execute(AttackCommand.new(unit.id, enemy.id))
	assert_eq(state.unit_at(Vector2i(1, 0)), null)
	assert_false(state.units_of(1).has(enemy))
	assert_eq(state.units_of(1).size(), 1)
	assert_false(state.occupied().has(Vector2i(1, 0)))
	# Another own unit can step onto the freed tile.
	var other := state.add_unit(0, Fixtures.infantry(), Vector2i(0, 1))
	assert_true(sim.execute(MoveUnitCommand.new(other.id, Vector2i(1, 0))))


func test_killing_last_enemy_ends_game() -> void:
	far_enemy.hp = 0
	enemy.hp = 2
	assert_true(sim.execute(AttackCommand.new(unit.id, enemy.id)))
	assert_eq(state.winner, 0)
	assert_eq(events.size(), 3)
	assert_eq(events[1]["type"], &"unit_died")
	assert_eq(events[2], {"type": &"game_over", "winner": 0})


func test_killing_non_last_enemy_does_not_end_game() -> void:
	enemy.hp = 2
	sim.execute(AttackCommand.new(unit.id, enemy.id))
	assert_eq(state.winner, -1)
	assert_eq(_events_of(&"game_over").size(), 0)


func test_game_continues_while_two_players_have_units() -> void:
	state = GameState.new(Fixtures.plains_grid(4), 3, 1)
	unit = state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	enemy = state.add_unit(1, Fixtures.infantry(), Vector2i(1, 0))
	state.add_unit(2, Fixtures.infantry(), Vector2i(-3, 0))
	sim = GameSimulation.new(state)
	enemy.hp = 2
	assert_true(sim.execute(AttackCommand.new(unit.id, enemy.id)))
	assert_false(enemy.is_alive())
	assert_eq(state.winner, -1)


func test_commands_rejected_after_game_over() -> void:
	far_enemy.hp = 0
	enemy.hp = 2
	var second := state.add_unit(0, Fixtures.infantry(), Vector2i(0, 1))
	sim.execute(AttackCommand.new(unit.id, enemy.id))
	rejections.clear()
	assert_false(sim.execute(MoveUnitCommand.new(second.id, Vector2i(0, 2))))
	assert_false(sim.execute(AttackCommand.new(second.id, enemy.id)))
	assert_false(sim.execute(EndTurnCommand.new()))
	assert_eq(rejections, ["game_over", "game_over", "game_over"] as Array[String])
	assert_eq(state.current_player, 0)


func _damage_on(terrain: Terrain.Type, attack: int, attacker_terrain := Terrain.Type.PLAINS) -> int:
	state.grid.set_terrain(Vector2i(0, 0), attacker_terrain)
	state.grid.set_terrain(Vector2i(1, 0), terrain)
	var striker := state.add_unit(0, Fixtures.fighter(attack, 2), Vector2i(0, 0))
	return AttackCommand.compute_damage(state, striker, enemy)


func test_compute_damage_attack_four_by_terrain() -> void:
	assert_eq(_damage_on(Terrain.Type.PLAINS, 4), 2)
	assert_eq(_damage_on(Terrain.Type.FOREST, 4), 1)
	assert_eq(_damage_on(Terrain.Type.HILLS, 4), 1)


func test_compute_damage_attack_seven_by_terrain() -> void:
	assert_eq(_damage_on(Terrain.Type.PLAINS, 7), 5)
	assert_eq(_damage_on(Terrain.Type.FOREST, 7), 4)
	assert_eq(_damage_on(Terrain.Type.HILLS, 7), 3)


func test_attacker_tile_is_ignored() -> void:
	assert_eq(_damage_on(Terrain.Type.PLAINS, 7, Terrain.Type.HILLS), 5)


func test_attack_applies_terrain_defense() -> void:
	state.grid.set_terrain(enemy.coord, Terrain.Type.HILLS)
	assert_true(sim.execute(AttackCommand.new(unit.id, enemy.id)))
	assert_eq(enemy.hp, 9)  # max(1, 4 - (2 + 2))
