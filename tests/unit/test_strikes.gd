extends TestCase
## Deep strikes (TASK-097a, TASK-141a): means data (named weapons), installations, stock and its
## side rule, range, ROE, resolution, resupply.

const Fixtures := preload("res://tests/fixtures.gd")
const Politics := preload("res://tests/unit/test_country_rules.gd")
const A1 := Vector2i(6, 0)
## The shipped weapons table of TASK-141a: accuracy, interceptability, damage, formation damage,
## max salvo, range (hexes), side, class.
const WEAPONS := {
	&"iskander_m": [80, 40, 45, 3, 3, 100, 1, &"ballistic"],
	&"kinzhal": [75, 25, 45, 3, 2, 400, 1, &"aeroballistic"],
	&"kalibr": [80, 100, 35, 2, 12, 300, 1, &"cruise"],
	&"kh101": [85, 80, 40, 2, 12, 500, 1, &"cruise"],
	&"geran_2": [55, 150, 12, 1, 24, 360, 1, &"drone"],
	&"jassm_er": [90, 70, 40, 2, 12, 185, 0, &"cruise"],
	&"storm_shadow": [85, 85, 40, 2, 9, 110, 0, &"cruise"],
	&"atacms": [80, 45, 35, 3, 4, 60, 0, &"ballistic"],
	&"prsm": [85, 40, 40, 3, 3, 100, 0, &"ballistic"],
	&"homar_k": [70, 90, 20, 2, 24, 58, 0, &"rocket"],
	&"warmate": [60, 130, 8, 1, 20, 10, 0, &"loitering"],
	&"tomahawk": [85, 90, 40, 2, 9, 320, 0, &"cruise"],
}


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
	id: StringName, class_id: StringName, owner: int, coord: Vector2i, ad_type := &""
) -> InstallationPlacement:
	var placement := InstallationPlacement.new()
	placement.id = id
	placement.display_name = String(id)
	placement.class_id = class_id
	placement.owner = owner
	placement.coord = coord
	placement.ad_type = ad_type if ad_type != &"" or class_id != &"air_defence" else &"short"
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
			{&"jassm_er": 8, &"atacms": 4, &"warmate": 6},
			{&"kalibr": 8, &"iskander_m": 6, &"geran_2": 16},
		]
		as Array[Dictionary]
	)
	op.strike_resupply = ([{&"jassm_er": 1}, {&"kalibr": 1, &"geran_2": 2}] as Array[Dictionary])
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


## The operation of `_definition` (or `op`) plus the code-built test weapons: the generic
## `cruise` / `ballistic` / `strike_drone` (Fixtures, either side) and `sure` / `never` / `short`.
static func _state(op: OperationDefinition = null, seed_value := 1) -> OperationalState:
	var state := Operation.from_definition(
		op if op != null else _definition(), seed_value, Politics._grid(), Politics._country_map()
	)
	if state != null:
		Fixtures.add_generic_strike_means(state)
		state.strike_means[&"sure"] = _means(&"sure")
		state.strike_means[&"never"] = _means(&"never", 0)
		state.strike_means[&"short"] = _means(&"short", 100, 100, 35, 2)
		state.strike_stock[0][&"sure"] = 10
		state.strike_stock[1][&"sure"] = 10
	return state


static func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e: Dictionary) -> Variant: return e["type"])


# --- means data ---


func test_shipped_weapons_table() -> void:
	assert_eq(StrikeMeansDefinition.SHIPPED.size(), WEAPONS.size())
	var shipped := StrikeMeansDefinition.shipped()
	assert_eq(shipped.size(), WEAPONS.size(), "unique ids")
	for id: StringName in WEAPONS:
		assert_true(StrikeMeansDefinition.SHIPPED.has(id), String(id))
		var means := StrikeMeansDefinition.find(id)
		assert_true(means != null, String(id))
		assert_eq(means.id, id)
		assert_eq(means.problem(), "", String(id))
		assert_true(means.side == 0 or means.side == 1, "no shared weapon in v1: %s" % id)
		assert_true(means.display_name != "" and means.designation != "", String(id))
		assert_true(means.platform != "", String(id))
		assert_eq(
			[
				means.accuracy_pct,
				means.interceptability_pct,
				means.damage,
				means.formation_damage,
				means.max_salvo,
				means.range_hexes,
				means.side,
				means.weapon_class,
			],
			WEAPONS[id],
			String(id)
		)
	assert_true(StrikeMeansDefinition.find(&"nope") == null)


func test_old_generic_ids_are_gone() -> void:
	for id: StringName in [&"cruise", &"ballistic", &"strike_drone"]:
		assert_true(StrikeMeansDefinition.find(id) == null, String(id))
		assert_false(StrikeMeansDefinition.SHIPPED.has(id), String(id))


func test_usable_by() -> void:
	var any := Fixtures.strike_means(&"any")
	assert_true(any.usable_by(0) and any.usable_by(1))
	var nato := Fixtures.strike_means(&"n", [80, 100, 35, 2, 4, 50], 0)
	assert_true(nato.usable_by(0))
	assert_false(nato.usable_by(1))
	assert_false(StrikeMeansDefinition.find(&"iskander_m").usable_by(0))
	assert_true(StrikeMeansDefinition.find(&"tomahawk").usable_by(0))


func test_means_problems() -> void:
	assert_eq(_means(&"ok").problem(), "")
	for weapon_class in StrikeMeansDefinition.WEAPON_CLASSES:
		var classed := _means(&"ok")
		classed.weapon_class = weapon_class
		assert_eq(classed.problem(), "", String(weapon_class))
	var defaults := StrikeMeansDefinition.new()
	defaults.id = &"d"
	assert_eq(defaults.problem(), "", "defaults keep a test-made means valid")
	assert_eq(defaults.side, StrikeMeansDefinition.ANY_SIDE)
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
		"class": func(m: StrikeMeansDefinition) -> void: m.weapon_class = &"laser",
		"side low": func(m: StrikeMeansDefinition) -> void: m.side = -2,
		"side high": func(m: StrikeMeansDefinition) -> void: m.side = 2,
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
	assert_eq(StrikeRules.stock(state, 0, &"jassm_er"), 8)
	assert_eq(StrikeRules.stock(state, 1, &"geran_2"), 16)
	assert_eq(state.strike_resupply[1], {&"kalibr": 1, &"geran_2": 2})
	assert_eq(state.strikes_left, 2)
	var snap := state.snapshot()
	assert_eq((snap["installations"] as Array).size(), 3)
	assert_eq((snap["installations"] as Array)[0]["id"], "a1")
	assert_eq((snap["strike_stock"] as Array)[0]["jassm_er"], 8)
	assert_eq(snap["strikes_left"], 2)


func test_defaults() -> void:
	var op := OperationDefinition.new()
	assert_eq(op.strikes_per_turn, 2)
	assert_eq(op.suppression_rounds, 2)
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
		"negative stock":
		func(op: OperationDefinition) -> void: op.strike_stock[0][&"jassm_er"] = -1,
		"negative resupply":
		func(op: OperationDefinition) -> void: op.strike_resupply[0][&"jassm_er"] = -1,
		"old generic id": func(op: OperationDefinition) -> void: op.strike_stock[0][&"cruise"] = 1,
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
	var events := StrikeRules.add_stock(state, 1, &"kh101", 3, &"china_components")
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], &"strike_stock_changed")
	assert_eq(events[0]["means"], &"kh101")
	assert_eq(events[0]["count"], 3)
	assert_eq(events[0]["total"], 3)
	assert_eq(events[0]["source"], &"china_components")
	assert_eq(StrikeRules.stock(state, 1, &"kh101"), 3)
	assert_eq(StrikeRules.add_stock(state, 1, &"kh101", 0, &"x"), [])
	assert_eq(StrikeRules.add_stock(state, 1, &"kh101", -2, &"x"), [])
	assert_eq(StrikeRules.add_stock(state, 1, &"nuke", 2, &"x"), [])
	assert_eq(StrikeRules.stock(state, 1, &"kh101"), 3)
	# Either-side test weapons go to both players.
	assert_eq(StrikeRules.add_stock(state, 0, &"cruise", 1, &"x")[0]["total"], 9)
	assert_eq(StrikeRules.add_stock(state, 1, &"cruise", 1, &"x")[0]["total"], 9)


func test_add_stock_rejects_the_other_sides_weapon() -> void:
	var state := _state()
	var before := state.snapshot()
	assert_eq(StrikeRules.add_stock(state, 0, &"iskander_m", 2, &"allied_strike_means"), [])
	assert_eq(StrikeRules.add_stock(state, 1, &"tomahawk", 2, &"china_components"), [])
	assert_eq(state.snapshot(), before, "no change")
	assert_eq(StrikeRules.add_stock(state, 0, &"tomahawk", 2, &"allied_strike_means").size(), 1)
	assert_eq(StrikeRules.add_stock(state, 1, &"geran_2", 8, &"iran_drones").size(), 1)
	assert_eq(StrikeRules.stock(state, 0, &"tomahawk"), 2)
	assert_eq(StrikeRules.stock(state, 1, &"geran_2"), 24)


func test_definition_rejects_the_other_sides_weapon() -> void:
	var cases := {
		"russian stock for nato":
		func(op: OperationDefinition) -> void: op.strike_stock[0][&"iskander_m"] = 2,
		"nato stock for russia":
		func(op: OperationDefinition) -> void: op.strike_stock[1][&"tomahawk"] = 0,
		"russian resupply for nato":
		func(op: OperationDefinition) -> void: op.strike_resupply[0][&"geran_2"] = 1,
		"nato resupply for russia":
		func(op: OperationDefinition) -> void: op.strike_resupply[1][&"jassm_er"] = 1,
	}
	for label: String in cases:
		var op := _definition()
		(cases[label] as Callable).call(op)
		assert_true(_state(op) == null, label)


# --- shipped data ---


func test_shipped_operation() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	assert_eq(state.installations.size(), 16)
	assert_eq(state.strikes_left, 2)
	assert_eq(state.strikes_per_turn, 2)
	assert_eq(state.suppression_rounds, 2)
	assert_eq(state.repair_per_round, 5)
	assert_eq(
		state.strike_stock[0],
		{
			&"jassm_er": 24,
			&"atacms": 12,
			&"prsm": 8,
			&"homar_k": 36,
			&"warmate": 40,
			&"storm_shadow": 0,
			&"tomahawk": 0,
		}
	)
	assert_eq(
		state.strike_stock[1],
		{&"iskander_m": 18, &"kinzhal": 6, &"kalibr": 20, &"kh101": 20, &"geran_2": 80}
	)
	assert_eq(state.strike_resupply[0], {&"jassm_er": 4, &"homar_k": 6, &"warmate": 6})
	assert_eq(state.strike_resupply[1], {&"kh101": 3, &"geran_2": 8})
	for player in 2:
		for entries: Array[Dictionary] in [state.strike_stock, state.strike_resupply]:
			for means_id: StringName in entries[player]:
				var means: StrikeMeansDefinition = state.strike_means[means_id]
				assert_eq(means.side, player, "side rule: %s" % means_id)
	var by_owner := [[], []]
	var classes := [{}, {}]
	for installation in state.installations:
		(by_owner[installation.owner] as Array).append(installation)
		classes[installation.owner][installation.class_id] = (
			int(classes[installation.owner].get(installation.class_id, 0)) + 1
		)
		assert_true(state.grid.move_cost(installation.coord) != Terrain.IMPASSABLE)
		assert_true(state.country_at(installation.coord) != &"", String(installation.id))
	assert_eq((by_owner[0] as Array).size(), 8)
	assert_eq((by_owner[1] as Array).size(), 8)
	assert_eq(classes[0], {&"airfield": 2, &"depot": 2, &"c2": 1, &"air_defence": 3})
	assert_eq(classes[1], {&"airfield": 2, &"depot": 2, &"c2": 1, &"air_defence": 3})


func test_shipped_ladder_effect_on_russian_targets() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	var enemy := StrikeRules.targets(state, 0).filter(
		func(t: Dictionary) -> bool: return t["kind"] == &"installation"
	)
	assert_eq(enemy.size(), 8)
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
