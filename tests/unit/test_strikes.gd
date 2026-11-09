extends TestCase
## Deep strikes (TASK-097a): means data, installations, stock, range, ROE, resolution, resupply.

const Politics := preload("res://tests/unit/test_country_rules.gd")
const A1 := Vector2i(6, 0)


static func _means(
	id: StringName, accuracy := 100, interceptability := 100, damage := 35, range_hexes := 50
) -> StrikeMeansDefinition:
	var means := StrikeMeansDefinition.new()
	means.id = id
	means.display_name = String(id)
	means.accuracy_pct = accuracy
	means.interceptability_pct = interceptability
	means.damage = damage
	means.formation_damage = 2
	means.max_salvo = 4
	means.range_hexes = range_hexes
	return means


static func _placement(
	id: StringName, class_id: StringName, owner: int, coord: Vector2i
) -> InstallationPlacement:
	var placement := InstallationPlacement.new()
	placement.id = id
	placement.display_name = String(id)
	placement.class_id = class_id
	placement.owner = owner
	placement.coord = coord
	return placement


static func _formation(
	id: StringName, path: String, player: int, coord: Vector2i
) -> FormationPlacement:
	var placement := FormationPlacement.new()
	placement.id = id
	placement.player = player
	placement.definition = load(path) as FormationDefinition
	placement.coord = coord
	return placement


static func _definition() -> OperationDefinition:
	var op := Politics._definition()
	op.installations = (
		[
			_placement(&"a1", &"airfield", 1, A1),
			_placement(&"d1", &"depot", 1, Vector2i(7, 1)),
			_placement(&"pl_air", &"airfield", 0, Vector2i(0, 1)),
		]
		as Array[InstallationPlacement]
	)
	op.strike_stock = (
		[
			{&"cruise": 8, &"ballistic": 4, &"strike_drone": 6},
			{&"cruise": 8, &"ballistic": 6, &"strike_drone": 16},
		]
		as Array[Dictionary]
	)
	op.strike_resupply = ([{&"cruise": 1}, {&"cruise": 1, &"strike_drone": 2}] as Array[Dictionary])
	op.formations = (
		[
			_formation(
				&"r", "res://data/formations/ru_motor_rifle_battalion.tres", 1, Vector2i(6, 1)
			),
			_formation(&"b", "res://data/formations/pl_mech_battalion.tres", 0, Vector2i(1, 0)),
		]
		as Array[FormationPlacement]
	)
	return op


static func _state(op: OperationDefinition = null, seed_value := 1) -> OperationalState:
	var state := Operation.from_definition(
		op if op != null else _definition(), seed_value, Politics._grid(), Politics._country_map()
	)
	if state != null:
		state.strike_means[&"sure"] = _means(&"sure")
		state.strike_means[&"never"] = _means(&"never", 0)
		state.strike_means[&"short"] = _means(&"short", 100, 100, 35, 2)
		state.strike_stock[0][&"sure"] = 10
		state.strike_stock[1][&"sure"] = 10
	return state


static func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e: Dictionary) -> Variant: return e["type"])


# --- means data ---


func test_shipped_means() -> void:
	var expected := {
		&"cruise": [80, 100, 35, 2, 4, 50],
		&"ballistic": [70, 40, 45, 3, 2, 80],
		&"strike_drone": [55, 150, 15, 1, 6, 20],
	}
	for id: StringName in expected:
		var means := StrikeMeansDefinition.find(id)
		assert_true(means != null, String(id))
		assert_eq(means.id, id)
		assert_eq(means.problem(), "")
		var row: Array = expected[id]
		assert_eq(
			[
				means.accuracy_pct,
				means.interceptability_pct,
				means.damage,
				means.formation_damage,
				means.max_salvo,
				means.range_hexes
			],
			row,
			String(id)
		)
	assert_true(StrikeMeansDefinition.find(&"nope") == null)


func test_means_problems() -> void:
	assert_eq(_means(&"ok").problem(), "")
	var cases := {
		"id": func(m: StrikeMeansDefinition) -> void: m.id = &"",
		"accuracy low": func(m: StrikeMeansDefinition) -> void: m.accuracy_pct = -1,
		"accuracy high": func(m: StrikeMeansDefinition) -> void: m.accuracy_pct = 101,
		"intercept low": func(m: StrikeMeansDefinition) -> void: m.interceptability_pct = -1,
		"intercept high": func(m: StrikeMeansDefinition) -> void: m.interceptability_pct = 201,
		"damage": func(m: StrikeMeansDefinition) -> void: m.damage = 0,
		"formation damage": func(m: StrikeMeansDefinition) -> void: m.formation_damage = 0,
		"salvo": func(m: StrikeMeansDefinition) -> void: m.max_salvo = 0,
		"range": func(m: StrikeMeansDefinition) -> void: m.range_hexes = 0,
	}
	for label: String in cases:
		var means := _means(&"ok")
		(cases[label] as Callable).call(means)
		assert_true(means.problem() != "", label)


# --- definition and state ---


func test_state_from_definition() -> void:
	var state := _state()
	assert_eq(state.installations.size(), 3)
	var a1 := state.get_installation(&"a1")
	assert_eq(a1.integrity, 100)
	assert_false(a1.destroyed())
	assert_eq(a1.owner, 1)
	assert_eq(StrikeRules.stock(state, 0, &"cruise"), 8)
	assert_eq(StrikeRules.stock(state, 1, &"strike_drone"), 16)
	assert_eq(state.strikes_left, 2)
	var snap := state.snapshot()
	assert_eq((snap["installations"] as Array).size(), 3)
	assert_eq((snap["installations"] as Array)[0]["id"], "a1")
	assert_eq((snap["strike_stock"] as Array)[0]["cruise"], 8)
	assert_eq(snap["strikes_left"], 2)


func test_defaults() -> void:
	var op := OperationDefinition.new()
	assert_eq(op.strikes_per_turn, 2)
	assert_eq(op.air_defence_radius, 4)
	assert_eq(op.air_defence_intercept_pct, 40)
	assert_eq(op.repair_per_round, 5)


func test_definition_rejections() -> void:
	var cases := {
		"unknown class":
		func(op: OperationDefinition) -> void: op.installations[0].class_id = &"port",
		"unknown stock means":
		func(op: OperationDefinition) -> void: op.strike_stock[0][&"nuke"] = 1,
		"unknown resupply means":
		func(op: OperationDefinition) -> void: op.strike_resupply[1][&"nuke"] = 1,
		"duplicate id": func(op: OperationDefinition) -> void: op.installations[1].id = &"a1",
		"same hex": func(op: OperationDefinition) -> void: op.installations[1].coord = A1,
		"off map":
		func(op: OperationDefinition) -> void: op.installations[0].coord = Vector2i(99, 0),
		"owner": func(op: OperationDefinition) -> void: op.installations[0].owner = 2,
		"negative owner": func(op: OperationDefinition) -> void: op.installations[0].owner = -1,
		"negative stock": func(op: OperationDefinition) -> void: op.strike_stock[0][&"cruise"] = -1,
		"negative resupply":
		func(op: OperationDefinition) -> void: op.strike_resupply[0][&"cruise"] = -1,
		"strikes per turn": func(op: OperationDefinition) -> void: op.strikes_per_turn = 0,
		"repair": func(op: OperationDefinition) -> void: op.repair_per_round = -1,
	}
	assert_true(_state() != null)
	for label: String in cases:
		var op := _definition()
		(cases[label] as Callable).call(op)
		assert_true(_state(op) == null, label)


# --- stock ---


func test_add_stock() -> void:
	var state := _state()
	var events := StrikeRules.add_stock(state, 1, &"cruise", 3, &"china_components")
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], &"strike_stock_changed")
	assert_eq(events[0]["count"], 3)
	assert_eq(events[0]["total"], 11)
	assert_eq(events[0]["source"], &"china_components")
	assert_eq(StrikeRules.stock(state, 1, &"cruise"), 11)
	assert_eq(StrikeRules.add_stock(state, 1, &"cruise", 0, &"x"), [])
	assert_eq(StrikeRules.add_stock(state, 1, &"cruise", -2, &"x"), [])
	assert_eq(StrikeRules.add_stock(state, 1, &"nuke", 2, &"x"), [])
	assert_eq(StrikeRules.stock(state, 1, &"cruise"), 11)


# --- shipped data ---


func test_shipped_operation() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	assert_eq(state.installations.size(), 14)
	assert_eq(state.strikes_left, 2)
	assert_eq(state.strikes_per_turn, 2)
	assert_eq(state.air_defence_radius, 4)
	assert_eq(state.air_defence_intercept_pct, 40)
	assert_eq(state.repair_per_round, 5)
	assert_eq(state.strike_stock[0], {&"cruise": 8, &"ballistic": 4, &"strike_drone": 6})
	assert_eq(state.strike_stock[1], {&"cruise": 8, &"ballistic": 6, &"strike_drone": 16})
	assert_eq(state.strike_resupply[0], {&"cruise": 1, &"strike_drone": 1})
	assert_eq(state.strike_resupply[1], {&"cruise": 1, &"strike_drone": 2})
	var by_owner := [[], []]
	var classes := [{}, {}]
	for installation in state.installations:
		(by_owner[installation.owner] as Array).append(installation)
		classes[installation.owner][installation.class_id] = (
			int(classes[installation.owner].get(installation.class_id, 0)) + 1
		)
		assert_true(state.grid.move_cost(installation.coord) != Terrain.IMPASSABLE)
		assert_true(state.country_at(installation.coord) != &"", String(installation.id))
	assert_eq((by_owner[0] as Array).size(), 7)
	assert_eq((by_owner[1] as Array).size(), 7)
	assert_eq(classes[0], {&"airfield": 2, &"depot": 2, &"c2": 1, &"air_defence": 2})
	assert_eq(classes[1], {&"airfield": 2, &"depot": 2, &"c2": 1, &"air_defence": 2})


func test_shipped_ladder_effect_on_russian_targets() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	var enemy := StrikeRules.targets(state, 0).filter(
		func(t: Dictionary) -> bool: return t["kind"] == &"installation"
	)
	assert_eq(enemy.size(), 7)
	for target: Dictionary in enemy:
		assert_eq(
			StrikeRules.target_problem(state, 0, target["id"]),
			"closed_country",
			String(target["id"])
		)
	state.escalation_level = 2
	for target: Dictionary in enemy:
		var country := state.country_at(target["coord"])
		var expected := "" if country == &"russia" else "closed_country"
		assert_eq(
			StrikeRules.target_problem(state, 0, target["id"]), expected, String(target["id"])
		)
	EscalationRules.raise(state, 1, &"test")
	assert_eq(state.escalation_level, 3)
	for target: Dictionary in enemy:
		assert_eq(StrikeRules.target_problem(state, 0, target["id"]), "", "regional war")
