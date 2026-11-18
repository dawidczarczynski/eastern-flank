extends TestCase
## Smoke screen and Blind fire (TASK-081b).

const Fixtures := preload("res://tests/fixtures.gd")

var sim: GameSimulation
var state: GameState
var events: Array[Dictionary] = []
var rejections: Array[String] = []


func before_each() -> void:
	events = []
	rejections = []
	_build(Fixtures.plains_grid(6))


func _build(grid: HexGrid) -> void:
	state = GameState.new(grid, 2, 1)
	sim = GameSimulation.new(state)
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	sim.command_rejected.connect(
		func(_c: Command, reason: String) -> void: rejections.append(reason)
	)


func _typed(definition: UnitDefinition, unit_class: StringName) -> UnitDefinition:
	definition.unit_class = unit_class
	return definition


func _tank(coord: Vector2i, owner := 0) -> Unit:
	return state.add_unit(owner, _typed(Fixtures.generic_tank(), &"tank"), coord)


func _inf(coord: Vector2i, owner := 0, attack := 4, defense := 2) -> Unit:
	var d := _typed(Fixtures.fighter(attack, defense, 10, 2), &"infantry")
	return state.add_unit(owner, d, coord)


func _smoke_at(c: Vector2i, owner := 0) -> void:
	state.smoke_hexes.append({"coord": c, "owner": owner})


func _types() -> Array:
	return events.map(func(e: Dictionary) -> StringName: return e["type"])


# --- data ---------------------------------------------------------------------------------


func test_order_data_and_class_lists() -> void:
	var smoke := OrderRules.definition(&"smoke")
	assert_eq(smoke.allowed_classes, [&"tank"])
	assert_eq(smoke.range_for(&"tank"), Vector2i(1, 2))
	var blind := OrderRules.definition(&"blind_fire")
	assert_eq(blind.attack_modifier, -1)
	assert_eq(blind.range_for(&"infantry"), Vector2i(1, 2))
	assert_eq(blind.range_for(&"tank"), Vector2i(1, 2))
	assert_eq(blind.range_for(&"mlrs"), Vector2i(3, 6))
	assert_eq(OrderRules.orders_for(_tank(Vector2i(0, 0))), [&"blind_fire", &"smoke", &"dig_in"])
	assert_eq(OrderRules.orders_for(_inf(Vector2i(0, 1))), [&"blind_fire", &"dig_in"])
	var mlrs := state.add_unit(0, _typed(Fixtures.infantry(), &"mlrs"), Vector2i(0, 2))
	assert_eq(OrderRules.orders_for(mlrs), [&"blind_fire"])


# --- smoke --------------------------------------------------------------------------------


func test_smoke_applies_state_and_events() -> void:
	var tank := _tank(Vector2i(0, 0))
	assert_true(sim.execute(SmokeCommand.new(tank.id, Vector2i(2, 0))))
	assert_eq(state.smoke_hexes, [{"coord": Vector2i(2, 0), "owner": 0}])
	assert_true(tank.has_attacked)
	assert_true(tank.activated)
	assert_eq(tank.slot_order, &"smoke")
	assert_eq(tank.moves_left, 0)
	assert_eq(events[0]["type"], &"unit_order_issued")
	assert_eq(events[0]["order"], &"smoke")
	assert_eq(events[0]["target"], Vector2i(2, 0))


func test_smoke_does_not_duplicate() -> void:
	var a := _tank(Vector2i(0, 0))
	var b := _tank(Vector2i(0, 1))
	assert_true(sim.execute(SmokeCommand.new(a.id, Vector2i(1, 0))))
	assert_true(sim.execute(SmokeCommand.new(b.id, Vector2i(1, 0))))
	assert_eq(state.smoke_hexes.size(), 1)


func test_smoke_rejections() -> void:
	var tank := _tank(Vector2i(0, 0))
	var inf := _inf(Vector2i(0, 1))
	var mlrs := state.add_unit(0, _typed(Fixtures.infantry(), &"mlrs"), Vector2i(0, 2))
	var foe := _tank(Vector2i(3, 0), 1)
	assert_false(sim.execute(SmokeCommand.new(tank.id, Vector2i(20, 20))))
	assert_false(sim.execute(SmokeCommand.new(tank.id, Vector2i(0, 0))))
	assert_false(sim.execute(SmokeCommand.new(tank.id, Vector2i(3, 0))))
	assert_false(sim.execute(SmokeCommand.new(inf.id, Vector2i(1, 1))))
	assert_false(sim.execute(SmokeCommand.new(mlrs.id, Vector2i(1, 2))))
	assert_false(sim.execute(SmokeCommand.new(99, Vector2i(1, 0))))
	assert_false(sim.execute(SmokeCommand.new(foe.id, Vector2i(2, 0))))
	assert_eq(
		rejections,
		[
			"invalid_target",
			"too_close",
			"out_of_range",
			"order_not_available",
			"order_not_available",
			"unit_not_found",
			"not_your_unit"
		]
	)
	assert_true(sim.execute(SmokeCommand.new(tank.id, Vector2i(1, 0))))
	assert_false(sim.execute(SmokeCommand.new(tank.id, Vector2i(1, 0))))
	assert_eq(rejections[-1], "already_acted")


func test_smoke_needs_command_points() -> void:
	state.set_command_points_per_turn([1, 1])
	state.command_points = 0
	var tank := _tank(Vector2i(0, 0))
	assert_false(sim.execute(SmokeCommand.new(tank.id, Vector2i(1, 0))))
	assert_eq(rejections, ["no_command_points"])


func test_smoke_after_attack_is_rejected() -> void:
	var tank := _tank(Vector2i(0, 0))
	_tank(Vector2i(1, 0), 1)
	assert_true(sim.execute(AttackCommand.new(tank.id, state.unit_at(Vector2i(1, 0)).id)))
	assert_false(sim.execute(SmokeCommand.new(tank.id, Vector2i(0, 1))))
	assert_eq(rejections, ["already_acted"])


func test_availability() -> void:
	var tank := _tank(Vector2i(0, 0))
	var inf := _inf(Vector2i(0, 1))
	assert_eq(OrderRules.availability(state, tank.id, &"smoke"), {"enabled": true, "reason": ""})
	assert_eq(OrderRules.availability(state, tank.id, &"blind_fire")["enabled"], true)
	assert_eq(OrderRules.availability(state, inf.id, &"smoke")["reason"], "order_not_available")
	assert_true(sim.execute(SmokeCommand.new(tank.id, Vector2i(1, 0))))
	assert_eq(OrderRules.availability(state, tank.id, &"blind_fire")["reason"], "already_acted")


# --- line of sight ------------------------------------------------------------------------


func test_smoke_blocks_direct_fire_between() -> void:
	var a := Vector2i(0, 0)
	var b := Vector2i(3, 0)
	assert_true(LineOfSight.visible(state.grid, a, b, state.smoke_hexes))
	_smoke_at(Vector2i(1, 0))
	assert_false(LineOfSight.visible(state.grid, a, b, state.smoke_hexes))
	assert_false(LineOfSight.visible(state.grid, b, a, state.smoke_hexes))


func test_smoke_on_endpoints_does_not_block() -> void:
	_smoke_at(Vector2i(0, 0))
	_smoke_at(Vector2i(3, 0))
	assert_true(LineOfSight.visible(state.grid, Vector2i(0, 0), Vector2i(3, 0), state.smoke_hexes))


func test_smoke_blocks_attack_without_counter() -> void:
	var shooter := _inf(Vector2i(0, 0), 0, 9)
	var foe := _inf(Vector2i(2, 0), 1)
	_smoke_at(Vector2i(1, 0), 1)
	assert_eq(AttackCommand.new(shooter.id, foe.id).validate(state), "no_line_of_sight")
	assert_false(sim.execute(AttackCommand.new(shooter.id, foe.id)))
	assert_eq(rejections, ["no_line_of_sight"])
	assert_eq(foe.hp, 10)
	assert_eq(shooter.hp, 10)


func test_indirect_fire_ignores_smoke() -> void:
	var d := _typed(Fixtures.sure_fighter(4), &"mlrs")
	Fixtures.set_range(d, 4, 5, 2, UnitDefinition.FIRE_INDIRECT)
	var mlrs := state.add_unit(0, d, Vector2i(0, 0))
	var foe := _inf(Vector2i(3, 0), 1)
	_smoke_at(Vector2i(1, 0), 1)
	_smoke_at(Vector2i(2, 0), 1)
	assert_eq(AttackCommand.new(mlrs.id, foe.id).validate(state), "")


func test_forecast_sees_smoke() -> void:
	var shooter := _inf(Vector2i(0, 0), 0, 9)
	var foe := _inf(Vector2i(2, 0), 1)
	_smoke_at(Vector2i(1, 0), 1)
	var f := CombatForecast.compute(state, shooter, foe)
	assert_false(f.line_of_sight)
	assert_eq(f.problem, "no_line_of_sight")


# --- smoke lifetime -----------------------------------------------------------------------


func test_smoke_lasts_through_enemy_turn_and_clears_at_owner_turn_start() -> void:
	var tank := _tank(Vector2i(0, 0))
	_inf(Vector2i(5, 0), 1)
	assert_true(sim.execute(SmokeCommand.new(tank.id, Vector2i(1, 0))))
	assert_true(sim.execute(EndTurnCommand.new()))
	assert_eq(state.smoke_hexes.size(), 1)
	assert_false(_types().has(&"smoke_cleared"))
	assert_true(sim.execute(EndTurnCommand.new()))
	assert_eq(state.smoke_hexes.size(), 0)
	var cleared := events.filter(func(e: Dictionary) -> bool: return e["type"] == &"smoke_cleared")
	assert_eq(cleared.size(), 1)
	assert_eq(cleared[0]["coord"], Vector2i(1, 0))
	assert_eq(cleared[0]["owner"], 0)


func test_snapshot_has_smoke_only_when_set() -> void:
	assert_false(state.snapshot().has("smoke_hexes"))
	_smoke_at(Vector2i(1, 2), 1)
	assert_eq(state.snapshot()["smoke_hexes"], [[1, 2, 1]])


# --- codec and replay ---------------------------------------------------------------------


func test_codec_round_trip() -> void:
	var smoke := SmokeCommand.new(7, Vector2i(2, -1))
	var blind := BlindFireCommand.new(8, Vector2i(-3, 4))
	assert_eq(smoke.to_dict(), {"type": "order_smoke", "unit_id": 7, "target": [2, -1]})
	assert_eq(blind.to_dict(), {"type": "order_blind_fire", "unit_id": 8, "target": [-3, 4]})
	var s: Variant = CommandCodec.from_dict(JSON.parse_string(JSON.stringify(smoke.to_dict())))
	var b: Variant = CommandCodec.from_dict(JSON.parse_string(JSON.stringify(blind.to_dict())))
	assert_true(s is SmokeCommand)
	assert_eq((s as SmokeCommand).unit_id, 7)
	assert_eq((s as SmokeCommand).target, Vector2i(2, -1))
	assert_true(b is BlindFireCommand)
	assert_eq((b as BlindFireCommand).target, Vector2i(-3, 4))
	assert_true(CommandCodec.from_dict({"type": "order_smoke", "unit_id": 1}) == null)
	assert_true(CommandCodec.from_dict({"type": "order_blind_fire", "target": [1, 2]}) == null)
	assert_true(
		CommandCodec.from_dict({"type": "order_blind_fire", "unit_id": 1, "target": [1]}) == null
	)


func _scripted_run() -> Dictionary:
	_build(Fixtures.plains_grid(6))
	var tank := _tank(Vector2i(0, 0))
	var inf := _inf(Vector2i(0, 1))
	var foe := _inf(Vector2i(2, 1), 1)
	var script: Array[Dictionary] = [
		{"type": "order_smoke", "unit_id": tank.id, "target": [1, 0]},
		{"type": "order_blind_fire", "unit_id": inf.id, "target": [foe.coord.x, foe.coord.y]},
		{"type": "end_turn"},
		{"type": "order_blind_fire", "unit_id": foe.id, "target": [0, 1]},
		{"type": "end_turn"},
	]
	for d in script:
		var command := CommandCodec.from_dict(JSON.parse_string(JSON.stringify(d)))
		assert_true(command != null)
		assert_true(sim.execute(command))
	return state.snapshot()


func test_scripted_match_with_smoke_and_blind_fire_is_deterministic() -> void:
	var a := _scripted_run()
	var b := _scripted_run()
	assert_eq(a, b)
	assert_false(a.has("smoke_hexes"))
