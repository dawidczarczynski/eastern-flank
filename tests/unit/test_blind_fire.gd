extends TestCase
## Blind fire (TASK-081b); smoke and codec tests are in test_smoke_blind_fire.gd.

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


# --- blind fire ---------------------------------------------------------------------------


func test_blind_fire_margin_table() -> void:
	# attack 5 vs defence 2 -> 2 (normal 3); attack 3 vs defence 4 -> 1 (floor).
	var a := _inf(Vector2i(0, 0), 0, 5, 2)
	var d := _inf(Vector2i(1, 0), 1, 4, 2)
	assert_eq(AttackCommand.compute_damage(state, a, d), 3)
	assert_eq(CombatForecast.blind_margin(state, a, d), 2)
	var weak := _inf(Vector2i(0, 1), 0, 3, 2)
	var tough := _inf(Vector2i(1, 1), 1, 4, 4)
	assert_eq(CombatForecast.blind_margin(state, weak, tough), 1)


func test_blind_margin_counts_tile_bonus() -> void:
	var grid := Fixtures.plains_grid(6)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	_build(grid)
	var a := _inf(Vector2i(0, 0), 0, 7, 2)
	var d := _inf(Vector2i(1, 0), 1, 4, 2)
	var bonus := grid.defense_bonus(Vector2i(1, 0))
	assert_eq(CombatForecast.blind_margin(state, a, d), maxi(1, 7 - 2 - bonus - 1))


func test_blind_fire_applies_state_and_events() -> void:
	var shooter := _inf(Vector2i(0, 0))
	var foe := _inf(Vector2i(2, 0), 1)
	assert_true(sim.execute(BlindFireCommand.new(shooter.id, foe.coord)))
	assert_true(shooter.has_attacked)
	assert_true(shooter.activated)
	assert_eq(shooter.moves_left, 0)
	assert_eq(shooter.slot_order, &"blind_fire")
	assert_eq(events[0]["type"], &"unit_order_issued")
	assert_eq(events[0]["order"], &"blind_fire")
	assert_eq(events[0]["target"], foe.coord)
	assert_eq(events[1]["type"], &"unit_attacked")
	assert_eq(events[1]["blind"], true)
	assert_eq(events[1]["shots"], 10)
	assert_eq(AttackCommand.new(shooter.id, foe.id).validate(state), "already_attacked")


func test_normal_attack_events_carry_blind_false() -> void:
	var a := _inf(Vector2i(0, 0))
	var d := _inf(Vector2i(1, 0), 1)
	assert_true(sim.execute(AttackCommand.new(a.id, d.id)))
	for e in events:
		if e["type"] == &"unit_attacked":
			assert_eq(e["blind"], false)


func test_blind_fire_one_draw_per_hit_point() -> void:
	var shooter := _inf(Vector2i(0, 0))
	var foe := _inf(Vector2i(2, 0), 1)
	foe.hp = 1
	var probe := RandomNumberGenerator.new()
	probe.seed = 1
	var before: int = state.rng.state
	var damaged_shooter_hp := shooter.hp
	assert_true(sim.execute(BlindFireCommand.new(shooter.id, foe.coord)))
	assert_true(damaged_shooter_hp == 10)
	probe.state = before
	for i in 10:
		probe.randi_range(1, 10)
	# The victim may die (no counter) or counter with its remaining hp; shooter's draws come first.
	if not foe.is_alive():
		assert_eq(state.rng.state, probe.state)


func test_blind_fire_hits_behind_forest_where_attack_cannot() -> void:
	var grid := Fixtures.plains_grid(6)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	_build(grid)
	var shooter := _inf(Vector2i(0, 0), 0, 9, 2)
	var foe := _inf(Vector2i(2, 0), 1, 4, 2)
	assert_eq(AttackCommand.new(shooter.id, foe.id).validate(state), "no_line_of_sight")
	assert_true(sim.execute(BlindFireCommand.new(shooter.id, foe.coord)))
	assert_true(foe.hp < foe.definition.max_hp)


func test_no_counter_from_direct_fire_defender_without_sight() -> void:
	var grid := Fixtures.plains_grid(6)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	_build(grid)
	var shooter := _inf(Vector2i(0, 0), 0, 4, 2)
	var foe := _inf(Vector2i(2, 0), 1, 9, 2)
	assert_true(sim.execute(BlindFireCommand.new(shooter.id, foe.coord)))
	assert_true(foe.is_alive())
	assert_eq(shooter.hp, 10)
	assert_false(events.any(func(e: Dictionary) -> bool: return e.get("counter", false)))


func test_adjacent_defender_counters_blind_fire() -> void:
	var shooter := _inf(Vector2i(0, 0), 0, 4, 2)
	var foe := state.add_unit(1, Fixtures.sure_fighter(4), Vector2i(1, 0))
	assert_true(sim.execute(BlindFireCommand.new(shooter.id, foe.coord)))
	var counters := events.filter(func(e: Dictionary) -> bool: return e.get("counter", false))
	assert_eq(counters.size(), 1)
	assert_eq(counters[0]["blind"], false)


func test_blind_fire_rejections() -> void:
	var shooter := _inf(Vector2i(0, 0))
	_inf(Vector2i(3, 0), 1)
	_inf(Vector2i(2, 1), 1)
	var friend := _inf(Vector2i(1, 0))
	assert_false(sim.execute(BlindFireCommand.new(shooter.id, Vector2i(20, 20))))
	assert_false(sim.execute(BlindFireCommand.new(shooter.id, Vector2i(0, 0))))
	assert_false(sim.execute(BlindFireCommand.new(shooter.id, Vector2i(3, 0))))
	assert_false(sim.execute(BlindFireCommand.new(shooter.id, Vector2i(0, 2))))
	assert_false(sim.execute(BlindFireCommand.new(shooter.id, friend.coord)))
	assert_false(sim.execute(BlindFireCommand.new(99, Vector2i(2, 1))))
	assert_eq(
		rejections,
		[
			"invalid_target",
			"too_close",
			"out_of_range",
			"no_unit_at_target",
			"not_an_enemy",
			"unit_not_found"
		]
	)


func test_mlrs_blind_fire_range_and_smoke() -> void:
	var d := _typed(Fixtures.sure_fighter(4), &"mlrs")
	Fixtures.set_range(d, 4, 6, 2, UnitDefinition.FIRE_INDIRECT)
	var mlrs := state.add_unit(0, d, Vector2i(-3, 0))
	_inf(Vector2i(-2, 0), 1)
	_inf(Vector2i(4, 0), 1)
	_inf(Vector2i(0, 0), 1)
	assert_false(sim.execute(BlindFireCommand.new(mlrs.id, Vector2i(-2, 0))))
	assert_false(sim.execute(BlindFireCommand.new(mlrs.id, Vector2i(4, 0))))
	assert_eq(rejections, ["too_close", "out_of_range"])
	_smoke_at(Vector2i(-1, 0), 1)
	assert_true(sim.execute(BlindFireCommand.new(mlrs.id, Vector2i(0, 0))))


func test_self_propelled_artillery_blind_fires_at_3_to_6() -> void:
	var d := _typed(Fixtures.sure_fighter(4), &"sp_artillery")
	Fixtures.set_range(d, 4, 6, 2, UnitDefinition.FIRE_INDIRECT)
	var spa := state.add_unit(0, d, Vector2i(-3, 0))
	_inf(Vector2i(-2, 0), 1)
	_inf(Vector2i(0, 0), 1)
	assert_false(sim.execute(BlindFireCommand.new(spa.id, Vector2i(-2, 0))))
	assert_eq(rejections, ["too_close"])
	assert_true(sim.execute(BlindFireCommand.new(spa.id, Vector2i(0, 0))))


func test_blind_fire_needs_command_points() -> void:
	state.set_command_points_per_turn([1, 1])
	state.command_points = 0
	var shooter := _inf(Vector2i(0, 0))
	_inf(Vector2i(2, 0), 1)
	assert_false(sim.execute(BlindFireCommand.new(shooter.id, Vector2i(2, 0))))
	assert_eq(rejections, ["no_command_points"])
