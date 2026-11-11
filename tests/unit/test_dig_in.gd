extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var sim: GameSimulation
var state: GameState
var unit: Unit
var enemy: Unit
var events: Array[Dictionary] = []
var rejections: Array[String] = []


func before_each() -> void:
	state = GameState.new(Fixtures.plains_grid(4), 2, 1)
	unit = state.add_unit(0, _typed(Fixtures.infantry(), &"infantry"), Vector2i(0, 0))
	enemy = state.add_unit(1, _typed(Fixtures.infantry(), &"infantry"), Vector2i(1, 0))
	sim = GameSimulation.new(state)
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	sim.command_rejected.connect(
		func(_c: Command, reason: String) -> void: rejections.append(reason)
	)


func _typed(definition: UnitDefinition, unit_class: StringName) -> UnitDefinition:
	definition.unit_class = unit_class
	return definition


func _types() -> Array:
	return events.map(func(e: Dictionary) -> StringName: return e["type"])


func _next_turn_of(player_turns: int) -> void:
	for i in player_turns:
		assert_true(sim.execute(EndTurnCommand.new()))


func test_order_data_and_class_lists() -> void:
	var def := OrderRules.definition(&"dig_in")
	assert_eq(def.defence_bonus, 2)
	assert_true(def.allowed_classes.has(&"infantry"))
	assert_true(def.allowed_classes.has(&"tank"))
	assert_eq(OrderRules.orders_for(unit), [&"dig_in"])
	var mlrs := state.add_unit(0, _typed(Fixtures.infantry(), &"mlrs"), Vector2i(0, 2))
	assert_eq(OrderRules.orders_for(mlrs).size(), 0)


func test_dig_in_applies_state_and_events() -> void:
	assert_true(sim.execute(DigInCommand.new(unit.id)))
	assert_true(unit.dug)
	assert_true(unit.has_attacked)
	assert_true(unit.activated)
	assert_eq(unit.slot_order, &"dig_in")
	assert_eq(unit.moves_left, 0)
	assert_eq(events[0]["type"], &"unit_order_issued")
	assert_eq(events[0]["unit_id"], unit.id)
	assert_eq(events[0]["order"], &"dig_in")
	assert_eq(events[0]["target"], unit.coord)


func test_command_points_event_follows_the_order() -> void:
	state.set_command_points_per_turn([1, 1])
	state.command_points = 1
	assert_true(sim.execute(DigInCommand.new(unit.id)))
	assert_eq(_types(), [&"unit_order_issued", &"command_points_changed"])


func test_snapshot_has_order_keys_only_when_set() -> void:
	var before: Dictionary = state.snapshot()["units"][0]
	assert_false(before.has("dug"))
	assert_false(before.has("slot_order"))
	assert_true(sim.execute(DigInCommand.new(unit.id)))
	var after: Dictionary = state.snapshot()["units"][0]
	assert_eq(after["dug"], true)
	assert_eq(after["slot_order"], "dig_in")
	assert_false(after.has("ambush"))
	assert_false(after.has("scoot_used"))


func test_damage_bonus_values() -> void:
	var striker := state.add_unit(1, Fixtures.fighter(5, 2), Vector2i(2, 0))
	var target := state.add_unit(0, Fixtures.fighter(1, 2), Vector2i(3, 0))
	assert_eq(AttackCommand.compute_damage(state, striker, target), 3)
	target.dug = true
	assert_eq(AttackCommand.compute_damage(state, striker, target), 1)


func test_dug_bonus_stacks_with_forest() -> void:
	var grid := Fixtures.plains_grid(4)
	grid.set_terrain(Vector2i(3, 0), Terrain.Type.FOREST)
	var st := GameState.new(grid, 2, 1)
	var striker := st.add_unit(1, Fixtures.fighter(7, 2), Vector2i(2, 0))
	var target := st.add_unit(0, Fixtures.fighter(1, 2), Vector2i(3, 0))
	target.dug = true
	assert_eq(AttackCommand.compute_damage(st, striker, target), 2)


func test_forecast_uses_dug_defence() -> void:
	var striker := state.add_unit(1, Fixtures.fighter(5, 2, 10, 2), Vector2i(2, 0))
	var target := state.add_unit(0, Fixtures.fighter(1, 2), Vector2i(3, 0))
	target.dug = true
	assert_eq(AttackCommand.forecast(state, striker, target).hit_on, 1)


func test_dug_unit_still_counters() -> void:
	var sure := state.add_unit(1, Fixtures.sure_fighter(4), Vector2i(0, 1))
	assert_true(sim.execute(DigInCommand.new(unit.id)))
	assert_true(sim.execute(EndTurnCommand.new()))
	assert_true(sim.execute(AttackCommand.new(sure.id, unit.id)))
	assert_true(unit.hp < unit.definition.max_hp)
	assert_true(events.any(func(e: Dictionary) -> bool: return e.get("counter", false)))


func test_rejections() -> void:
	state.add_unit(0, _typed(Fixtures.infantry(), &"mlrs"), Vector2i(0, 2))
	assert_false(sim.execute(DigInCommand.new(99)))
	assert_false(sim.execute(DigInCommand.new(enemy.id)))
	assert_false(sim.execute(DigInCommand.new(3)))
	assert_eq(rejections, ["unit_not_found", "not_your_unit", "order_not_available"])


func test_already_acted_after_attack_and_already_dug() -> void:
	assert_true(sim.execute(AttackCommand.new(unit.id, enemy.id)))
	assert_false(sim.execute(DigInCommand.new(unit.id)))
	assert_eq(rejections[-1], "already_acted")
	var other := state.add_unit(0, _typed(Fixtures.infantry(), &"infantry"), Vector2i(0, 2))
	assert_true(sim.execute(DigInCommand.new(other.id)))
	assert_false(sim.execute(DigInCommand.new(other.id)))
	assert_eq(rejections[-1], "already_acted")
	_next_turn_of(2)
	assert_false(sim.execute(DigInCommand.new(other.id)))
	assert_eq(rejections[-1], "already_dug")


func test_no_command_points_and_game_over() -> void:
	state.set_command_points_per_turn([1, 1])
	state.command_points = 1
	var other := state.add_unit(0, _typed(Fixtures.infantry(), &"infantry"), Vector2i(0, 2))
	assert_true(sim.execute(DigInCommand.new(unit.id)))
	assert_false(sim.execute(DigInCommand.new(other.id)))
	assert_eq(rejections[-1], "no_command_points")


func test_attack_and_move_rejected_after_dig_in() -> void:
	assert_true(sim.execute(DigInCommand.new(unit.id)))
	assert_false(sim.execute(AttackCommand.new(unit.id, enemy.id)))
	assert_eq(rejections[-1], "already_attacked")
	assert_false(sim.execute(MoveUnitCommand.new(unit.id, Vector2i(0, 1))))
	assert_eq(rejections[-1], "unreachable")


func test_moving_clears_dug() -> void:
	assert_true(sim.execute(DigInCommand.new(unit.id)))
	_next_turn_of(2)
	assert_true(unit.dug, "a unit stays dug turn after turn")
	assert_eq(unit.slot_order, &"")
	events.clear()
	assert_true(sim.execute(MoveUnitCommand.new(unit.id, Vector2i(0, 1))))
	assert_false(unit.dug)
	assert_eq(events[0]["type"], &"unit_moved")
	assert_eq(events[1]["type"], &"unit_order_cleared")
	assert_eq(events[1]["order"], &"dig_in")
	assert_eq(events[1]["reason"], &"moved")


func test_turn_start_clears_slot_scoot_ambush_but_not_dug() -> void:
	unit.dug = true
	unit.ambush = true
	unit.scoot_used = true
	unit.slot_order = &"dig_in"
	assert_true(sim.execute(EndTurnCommand.new()))
	assert_true(unit.ambush, "only the owner's turn start clears it")
	assert_true(sim.execute(EndTurnCommand.new()))
	assert_true(unit.dug)
	assert_false(unit.ambush)
	assert_false(unit.scoot_used)
	assert_eq(unit.slot_order, &"")


func test_availability() -> void:
	var ok := OrderRules.availability(state, unit.id, &"dig_in")
	assert_eq(ok, {"enabled": true, "reason": ""})
	assert_true(sim.execute(DigInCommand.new(unit.id)))
	assert_eq(OrderRules.availability(state, unit.id, &"dig_in")["reason"], "already_acted")
	for id in [&"resupply", &"camouflage", &"smoke", &"blind_fire", &"ambush", &"scoot"]:
		var a := OrderRules.availability(state, unit.id, id)
		assert_false(a["enabled"])
		assert_eq(a["reason"], "order_not_available")


func test_codec_round_trip() -> void:
	var d := DigInCommand.new(7).to_dict()
	assert_eq(d, {"type": "order_dig_in", "unit_id": 7})
	var parsed: Variant = JSON.parse_string(JSON.stringify(d))
	var decoded := CommandCodec.from_dict(parsed)
	assert_true(decoded is DigInCommand)
	assert_eq((decoded as DigInCommand).unit_id, 7)
	assert_true(CommandCodec.from_dict({"type": "order_dig_in"}) == null)
	assert_true(CommandCodec.from_dict({"type": "order_dig_in", "unit_id": "x"}) == null)
	assert_true(CommandCodec.from_dict({"type": "order_nope", "unit_id": 1}) == null)
	assert_eq(MatchRecord.VERSION, 2)


func test_replay_with_dig_in_is_deterministic() -> void:
	var record := MatchRecord.new()
	record.seed = 12345
	var probe := Scenario.default_battle(12345)
	var digger: Unit = null
	for u in probe.units_of(0):
		if OrderRules.orders_for(u).has(&"dig_in"):
			digger = u
			break
	assert_true(digger != null)
	record.commands = [
		{"type": "order_dig_in", "unit_id": digger.id},
		{"type": "end_turn"},
		{"type": "end_turn"},
	]
	var a := Replay.run(record)
	var b := Replay.run(record)
	assert_true(a["ok"])
	assert_eq(a["simulation"].state.snapshot(), b["simulation"].state.snapshot())
	assert_true(a["simulation"].state.get_unit(digger.id).dug)
