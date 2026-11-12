extends TestCase
## The operational AI (TASK-102a): profile, goals on the definition, orders and strikes.

const Fixtures := preload("res://tests/fixtures.gd")
const Strikes := preload("res://tests/unit/test_strikes.gd")
const Politics := preload("res://tests/unit/test_country_rules.gd")
const MECH := "res://data/formations/pl_mech_battalion.tres"
const MR := "res://data/formations/ru_motor_rifle_battalion.tres"


static func _goal(
	id: StringName, player: int, coord: Vector2i, role: StringName, weight := 5
) -> AiGoal:
	var goal := AiGoal.new()
	goal.id = id
	goal.player = player
	goal.coord = coord
	goal.role = role
	goal.weight = weight
	return goal


static func _plains(columns: int, rows: int) -> HexGrid:
	var grid := HexGrid.new()
	for q in columns:
		for r in rows:
			grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
	return grid


## A 20 x 12 plain without countries. Player 0: b1 (2,2), b2 (2,3); player 1: r1 (17,2). Goals
## for both sides; `extra` more player-0 formations in column 1.
static func _orders_state(extra := 0) -> OperationalState:
	var op := Politics._definition()
	var placements: Array[FormationPlacement] = [
		Strikes._formation(&"b1", MECH, 0, Vector2i(2, 2)),
		Strikes._formation(&"b2", MECH, 0, Vector2i(2, 3)),
		Strikes._formation(&"r1", MR, 1, Vector2i(17, 2)),
	]
	for i in extra:
		placements.append(Strikes._formation(StringName("x%d" % i), MECH, 0, Vector2i(1, i)))
	op.formations = placements
	op.ai_goals = (
		[
			_goal(&"nato_take", 0, Vector2i(8, 2), AiGoal.TAKE),
			_goal(&"ru_take", 1, Vector2i(3, 2), AiGoal.TAKE),
			_goal(&"ru_hold", 1, Vector2i(17, 2), AiGoal.HOLD),
		]
		as Array[AiGoal]
	)
	return Operation.from_definition(op, 1, _plains(20, 12), {})


static func _profile() -> AiProfile:
	return AiProfile.new()


static func _run(state: OperationalState, commands: Array[OperationalCommand]) -> Array[String]:
	var sim := OperationalSimulation.new(state)
	var rejected: Array[String] = []
	sim.command_rejected.connect(
		func(_c: OperationalCommand, r: String) -> void: rejected.append(r)
	)
	for command in commands:
		sim.execute(command)
	return rejected


static func _orders(commands: Array[OperationalCommand]) -> Array[IssueOrderCommand]:
	var result: Array[IssueOrderCommand] = []
	for command in commands:
		if command is IssueOrderCommand:
			result.append(command)
	return result


static func _strikes(commands: Array[OperationalCommand]) -> Array[StrikeCommand]:
	var result: Array[StrikeCommand] = []
	for command in commands:
		if command is StrikeCommand:
			result.append(command)
	return result


static func _targets(commands: Array[OperationalCommand]) -> Array:
	return _strikes(commands).map(func(c: StrikeCommand) -> StringName: return c.target_id)


# --- profile and data ---


func test_default_profile() -> void:
	var profile := AiProfile.shipped()
	assert_true(profile != null)
	assert_eq(profile.problem(), "")
	assert_eq(profile.aggression, 0.5)
	assert_eq(profile.strike_reserve, 1)
	assert_eq(profile.min_strike_value, 10.0)
	assert_eq(profile.max_commands, 40)
	assert_true(profile.goal_weight > 0.0 and profile.distance_weight > 0.0)
	assert_true(profile.threat_weight > 0.0)
	var bad := AiProfile.new()
	bad.aggression = 1.5
	assert_true(bad.problem() != "")


func test_suwalki_goals() -> void:
	var op := OperationDefinition.find(&"suwalki_gap")
	var grid := ImportedMap.find(op.map_id).to_grid()
	var ids := {}
	for placement in op.installations:
		ids[placement.id] = true
	var per_side := [0, 0]
	for goal in op.ai_goals:
		per_side[goal.player] += 1
		assert_true(AiGoal.ROLES.has(goal.role), "%s role" % goal.id)
		if goal.installation_id != &"":
			assert_true(ids.has(goal.installation_id), "%s installation" % goal.id)
		else:
			assert_true(grid.has_tile(goal.coord), "%s hex" % goal.id)
	assert_true(per_side[0] >= 3 and per_side[1] >= 3, "goals per side %s" % [per_side])
	assert_true(Operation.build(&"suwalki_gap", 1) != null)


func test_invalid_goal_rejects_the_definition() -> void:
	var op := Politics._definition()
	var goal := _goal(&"g", 0, Vector2i(500, 500), AiGoal.TAKE)
	op.ai_goals = [goal] as Array[AiGoal]
	assert_true(Operation.from_definition(op, 1, Politics._grid(), Politics._country_map()) == null)


func test_suwalki_plan_executes() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	var commands := OperationalAi.plan(state, state.current_player)
	assert_false(commands.is_empty())
	assert_eq(_run(state, commands), [] as Array[String])


# --- orders ---


func test_plan_leaves_state_untouched() -> void:
	var state := _orders_state()
	var before := state.snapshot().hash()
	assert_false(OperationalAi.plan(state, 0).is_empty())
	assert_eq(state.snapshot().hash(), before)


func test_take_goal_march_and_distinct_destinations() -> void:
	var state := _orders_state()
	var orders := _orders(OperationalAi.plan(state, 0))
	assert_eq(orders.size(), 2)
	var destinations := {}
	for order in orders:
		assert_eq(order.posture, &"march", "far from the enemy")
		destinations[order.destination] = true
	assert_eq(destinations.size(), 2, "never one destination twice")
	assert_true(destinations.has(Vector2i(8, 2)), "one takes the goal hex itself")
	for destination: Vector2i in destinations:
		assert_true(Hex.distance(destination, Vector2i(8, 2)) <= 1, "the other is next to it")


func test_advance_near_the_enemy() -> void:
	var state := _orders_state()
	state.ai_goals[0].coord = Vector2i(15, 2)  # 2 hexes from r1
	var orders := _orders(OperationalAi.plan(state, 0))
	assert_eq(orders[0].posture, &"advance")
	assert_eq(orders[0].destination, Vector2i(15, 2))
	var shy := _profile()
	shy.aggression = 1.0  # ceil(1 / 1) = 1 hex
	assert_eq(_orders(OperationalAi.plan(state, 0, shy))[0].posture, &"march")


func test_hold_goal_sets_defend() -> void:
	var state := _orders_state()
	state.current_player = 1
	var r1 := state.get_formation(&"r1")
	r1.posture = &"march"
	var commands := OperationalAi.plan(state, 1)
	var postures: Array[SetPostureCommand] = []
	for command in commands:
		if command is SetPostureCommand:
			postures.append(command)
	assert_eq(postures.size(), 1)
	assert_eq(postures[0].formation_id, &"r1")
	assert_eq(postures[0].posture, &"defend")
	assert_eq(_run(state, commands), [] as Array[String])
	assert_true(r1.order == null, "no destination change")


func test_executed_plan_is_accepted_and_orders_are_not_repeated() -> void:
	var state := _orders_state()
	var plan := OperationalAi.plan(state, 0)
	assert_eq(plan.size(), 2)
	assert_eq(_run(state, plan), [] as Array[String])
	assert_eq(OperationalAi.plan(state, 0).size(), 0, "valid orders towards the goal stay")


func test_both_sides_use_the_same_code() -> void:
	var state := _orders_state()
	state.current_player = 1
	var orders := _orders(OperationalAi.plan(state, 1))
	assert_eq(orders.size(), 0, "r1 holds, and the take goal is far from nobody else")
	state.get_formation(&"r1").coord = Vector2i(12, 2)
	state.ai_goals[2].weight = 1  # the hold goal pulls less than the take goal
	orders = _orders(OperationalAi.plan(state, 1))
	assert_eq(orders.size(), 1)
	assert_eq(orders[0].formation_id, &"r1")
	assert_true(Hex.distance(orders[0].destination, Vector2i(3, 2)) <= 1, str(orders[0].to_dict()))
	for path in ["operational_ai.gd"]:
		var text := FileAccess.get_file_as_string("res://src/ai/" + path).to_lower()
		for word in ["nato", "russia", "poland"]:
			assert_false(text.contains(word), "%s in %s" % [word, path])


func test_max_commands() -> void:
	var state := _orders_state(10)
	var profile := _profile()
	assert_eq(OperationalAi.plan(state, 0, profile).size(), 12)
	profile.max_commands = 3
	var plan := OperationalAi.plan(state, 0, profile)
	assert_eq(plan.size(), 3)
	assert_eq(_run(state, plan), [] as Array[String])


func test_determinism_and_profile_effect() -> void:
	var state := _orders_state()
	state.ai_goals[0].coord = Vector2i(15, 2)
	var first := OperationalAi.plan(state, 0).map(
		func(c: OperationalCommand) -> Dictionary: return c.to_dict()
	)
	var second := OperationalAi.plan(state, 0).map(
		func(c: OperationalCommand) -> Dictionary: return c.to_dict()
	)
	assert_eq(first, second)
	var shy := _profile()
	shy.aggression = 1.0
	var other := OperationalAi.plan(state, 0, shy).map(
		func(c: OperationalCommand) -> Dictionary: return c.to_dict()
	)
	assert_true(first != other)


func test_not_current_or_over_gives_nothing() -> void:
	var state := _orders_state()
	assert_eq(OperationalAi.plan(state, 1).size(), 0)
	state.result = {"winner": 0, "reason": &"test", "by": 0}
	assert_eq(OperationalAi.plan(state, 0).size(), 0)


# --- strikes ---


static func _strike_means() -> StrikeMeansDefinition:
	var means := Strikes._means(&"ai_missile", 100, 0, 35, 50)
	means.max_salvo = 2
	return means


## A 10 x 2 strip: Poland q0-3, Lithuania (aligned, side 0) q4-5, Belarus (belligerent, side 1)
## q6-7, Russia (sanctuary) q8-9. Russian air defence (6,0), airfield (8,0), command post (7,1),
## depot (7,0); Polish airfield (0,1). Polish formation b (4,1) two hexes from the Russian r (6,1).
## One weapon, `stock` of it for both sides.
static func _strike_state(level := 2, stock := 20) -> OperationalState:
	var op := Strikes._definition()
	op.installations = (
		[
			Strikes._placement(&"a1", &"airfield", 1, Vector2i(8, 0)),
			Strikes._placement(&"d1", &"depot", 1, Vector2i(7, 0)),
			Strikes._placement(&"pl_air", &"airfield", 0, Vector2i(0, 1)),
			Strikes._placement(&"ru_ad", &"air_defence", 1, Vector2i(6, 0), &"short"),
			Strikes._placement(&"ru_c2", &"c2", 1, Vector2i(7, 1)),
		]
		as Array[InstallationPlacement]
	)
	op.formations = (
		[
			Strikes._formation(&"b", MECH, 0, Vector2i(4, 1)),
			Strikes._formation(&"r", MR, 1, Vector2i(6, 1)),
		]
		as Array[FormationPlacement]
	)
	op.countries[2].stance = &"belligerent"
	var grid := _plains(10, 2)
	var by_column: Array[StringName] = [
		&"poland",
		&"poland",
		&"poland",
		&"poland",
		&"lithuania",
		&"lithuania",
		&"belarus",
		&"belarus",
		&"russia",
		&"russia",
	]  # gdlint: disable=max-line-length
	var country_map := {}
	for q in 10:
		for r in 2:
			country_map[Vector2i(q, r)] = by_column[q]
	var state := Operation.from_definition(op, 1, grid, country_map)
	state.strike_means = {&"ai_missile": _strike_means()}
	state.strike_stock = [{&"ai_missile": stock}, {&"ai_missile": stock}]
	state.escalation_level = level
	return state


func test_strike_priority_air_defence_first() -> void:
	var state := _strike_state()
	var plan := OperationalAi.plan(state, 0)
	assert_eq(_targets(plan), [&"ru_ad", &"a1"])
	assert_eq(plan.size(), 2, "no goals, so no orders")
	assert_eq(_run(state, plan), [] as Array[String])


func test_strike_tiers_down_to_formations() -> void:
	var state := _strike_state()
	state.installations = state.installations.filter(
		func(i: Installation) -> bool: return i.class_id != &"air_defence" and i.id != &"a1"
	)
	assert_eq(_targets(OperationalAi.plan(state, 0)), [&"ru_c2", &"r"])
	state.installations.clear()
	assert_eq(_targets(OperationalAi.plan(state, 0)), [&"r"])
	state.get_formation(&"b").coord = Vector2i(0, 0)
	assert_eq(_targets(OperationalAi.plan(state, 0)), [])


func test_strike_limit_per_turn() -> void:
	var state := _strike_state()
	state.strikes_left = 1
	assert_eq(_targets(OperationalAi.plan(state, 0)), [&"ru_ad"])
	state.strikes_left = 0
	assert_eq(_targets(OperationalAi.plan(state, 0)), [])


func test_strike_roe_and_range_fall_through() -> void:
	var state := _strike_state(0)
	assert_eq(_targets(OperationalAi.plan(state, 0)), [&"r"], "contained: formations only")
	state = _strike_state()
	state.strike_means[&"ai_missile"].range_hexes = 1  # only the hexes next to Lithuania
	assert_eq(_targets(OperationalAi.plan(state, 0)), [&"ru_ad", &"r"])


func test_strike_minimum_value_and_reserve() -> void:
	var state := _strike_state()
	var profile := _profile()
	profile.min_strike_value = 100000.0
	assert_eq(_targets(OperationalAi.plan(state, 0, profile)), [])
	state = _strike_state(2, 2)  # stock == 1 salvo == the reserve
	assert_eq(_targets(OperationalAi.plan(state, 0)), [])
	state = _strike_state(2, 3)
	var plan := _strikes(OperationalAi.plan(state, 0))
	assert_eq(plan.size(), 1)
	assert_eq(plan[0].count, 1)
	profile = _profile()
	profile.strike_reserve = 0
	assert_eq(_strikes(OperationalAi.plan(_strike_state(2, 2), 0, profile)).size(), 1)


func test_strike_never_pushes_to_the_cap() -> void:
	var state := _strike_state(4)  # a first breach of Russia would reach the cap (5)
	var plan := OperationalAi.plan(state, 0)
	assert_eq(_targets(plan), [&"ru_ad", &"ru_c2"])
	assert_eq(_run(state, plan), [] as Array[String])
	assert_true(state.escalation_level <= state.ladder.cap())
	assert_eq(_targets(OperationalAi.plan(_strike_state(3), 0)), [&"ru_ad", &"a1"])


func test_strikes_for_the_other_side() -> void:
	var state := _strike_state()
	state.current_player = 1
	state.get_formation(&"b").coord = Vector2i(3, 1)
	state.get_formation(&"r").coord = Vector2i(5, 1)
	var plan := OperationalAi.plan(state, 1)
	assert_eq(_targets(plan), [&"pl_air", &"b"])
	assert_eq(_run(state, plan), [] as Array[String])
