extends TestCase
## BattleSetup / BattleResult – the hand-off between the operational and the tactical layer
## (ADR 0015) – and Scenario.from_setup.


static func _json_round_trip(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


func _sample_setup() -> BattleSetup:
	var setup := Scenario.default_battle_setup(777)
	setup.map_region = Rect2i(3, 4, 20, 16)
	setup.companies[0].strength = 3
	setup.companies[0].ref = "pl_15bde/2"
	setup.conditions[1].command_points = 2
	setup.conditions[1].ammunition = 40
	setup.conditions[0].morale = 80
	setup.conditions[0].fire_support = 1
	setup.objectives = BattleObjectives.default_objectives()
	setup.objectives.turn_limit = 8
	return setup


func test_setup_survives_a_json_round_trip() -> void:
	var setup := _sample_setup()
	var loaded := BattleSetup.from_dict(_json_round_trip(setup.to_dict()))
	assert_true(loaded != null)
	assert_eq(loaded.to_dict(), setup.to_dict())
	assert_eq(loaded.map_region, Rect2i(3, 4, 20, 16))
	assert_eq(loaded.companies[0].coord, setup.companies[0].coord)
	assert_eq(loaded.factions, [&"poland", &"russia"] as Array[StringName])
	assert_eq(loaded.conditions[1].command_points, 2)


func test_malformed_setup_is_rejected() -> void:
	var good := _json_round_trip(_sample_setup().to_dict())
	assert_true(BattleSetup.from_dict(good) != null)
	for key: String in good.keys():
		var missing := good.duplicate(true)
		missing.erase(key)
		assert_true(BattleSetup.from_dict(missing) == null, "without %s" % key)
	var bad_coord := good.duplicate(true)
	bad_coord["companies"][0]["coord"] = [1.5, 2]
	assert_true(BattleSetup.from_dict(bad_coord) == null)
	var bad_conditions := good.duplicate(true)
	bad_conditions["conditions"][0].erase("morale")
	assert_true(BattleSetup.from_dict(bad_conditions) == null)
	var one_side := good.duplicate(true)
	one_side["conditions"].pop_back()
	assert_true(BattleSetup.from_dict(one_side) == null, "conditions per faction")
	var negative := good.duplicate(true)
	negative["map_region"] = [0, 0, -1, 4]
	assert_true(BattleSetup.from_dict(negative) == null, "negative region")


func test_default_battle_is_its_setup() -> void:
	for seed_value: int in [12345, 7]:
		var setup := BattleSetup.from_dict(
			_json_round_trip(Scenario.default_battle_setup(seed_value).to_dict())
		)
		var from_setup := Scenario.from_setup(setup)
		var direct := Scenario.default_battle(seed_value)
		assert_eq(from_setup.snapshot(), direct.snapshot())
		assert_eq(from_setup.operation_name, direct.operation_name)
		assert_eq(from_setup.player_factions, direct.player_factions)
		for c in direct.grid.coords():
			assert_eq(from_setup.grid.get_terrain(c), direct.grid.get_terrain(c))


func test_default_setup_has_full_strength_scenario_companies() -> void:
	var setup := Scenario.default_battle_setup(12345)
	assert_eq(setup.companies.size(), 9)
	assert_eq(setup.conditions.size(), 2)
	assert_eq(setup.objectives.to_dict(), BattleObjectives.default_objectives().to_dict())
	var state := Scenario.from_setup(setup)
	for i in setup.companies.size():
		assert_eq(setup.companies[i].ref, "")
		assert_eq(setup.companies[i].strength, state.get_unit(i + 1).definition.max_hp)


func test_company_strength_sets_starting_hp() -> void:
	var setup := Scenario.default_battle_setup(12345)
	setup.companies[2].strength = 2
	var state := Scenario.from_setup(setup)
	assert_eq(state.get_unit(3).hp, 2)
	assert_eq(state.get_unit(3).definition.id, setup.companies[2].unit_type)


func test_setup_that_cannot_be_placed_gives_no_state() -> void:
	# Expected engine output: push_error for each rejected setup.
	var foreign := Scenario.default_battle_setup(1)
	foreign.companies[0].player = 1  # a Polish unit type for Russia
	assert_true(Scenario.from_setup(foreign) == null)
	var weak := Scenario.default_battle_setup(1)
	weak.companies[0].strength = 0
	assert_true(Scenario.from_setup(weak) == null)
	var stacked := Scenario.default_battle_setup(1)
	stacked.companies[1].coord = stacked.companies[0].coord
	assert_true(Scenario.from_setup(stacked) == null)
	var unknown_map := Scenario.default_battle_setup(1)
	unknown_map.map_id = &"atlantis"
	assert_true(Scenario.from_setup(unknown_map) == null)


func test_result_reports_losses_per_company() -> void:
	var setup := _sample_setup()
	var state := Scenario.from_setup(setup)
	state.get_unit(2).hp -= 1
	state.get_unit(5).hp = 0
	state.finish(0, &"eliminated")
	state.turn = 6
	var result := BattleResult.from_battle(setup, state)
	assert_eq(result.winner, 0)
	assert_eq(result.reason, &"eliminated")
	assert_eq(result.turns, 6)
	assert_eq(result.companies.size(), setup.companies.size())
	assert_eq(result.companies[0].ref, "pl_15bde/2")
	assert_eq(result.companies[0].strength_start, 3)
	assert_eq(result.companies[0].losses(), 0)
	assert_eq(result.companies[1].losses(), 1)
	assert_eq(result.companies[4].strength_end, 0)
	assert_eq(result.companies[4].player, 1)


func test_running_battle_has_no_winner_or_reason() -> void:
	var setup := Scenario.default_battle_setup(3)
	var result := BattleResult.from_battle(setup, Scenario.from_setup(setup))
	assert_eq(result.winner, -1)
	assert_eq(result.reason, &"")


func test_result_survives_a_json_round_trip() -> void:
	var setup := _sample_setup()
	var state := Scenario.from_setup(setup)
	state.get_unit(4).hp = 1
	state.finish(1, &"eliminated")
	var result := BattleResult.from_battle(setup, state)
	var loaded := BattleResult.from_dict(_json_round_trip(result.to_dict()))
	assert_true(loaded != null)
	assert_eq(loaded.to_dict(), result.to_dict())
	assert_eq(loaded.companies[3].losses(), result.companies[3].losses())


func test_malformed_result_is_rejected() -> void:
	var setup := Scenario.default_battle_setup(3)
	var good := _json_round_trip(
		BattleResult.from_battle(setup, Scenario.from_setup(setup)).to_dict()
	)
	assert_true(BattleResult.from_dict(good) != null)
	for key: String in good.keys():
		var missing := good.duplicate(true)
		missing.erase(key)
		assert_true(BattleResult.from_dict(missing) == null, "without %s" % key)
	var bad_company := good.duplicate(true)
	bad_company["companies"][0]["strength_end"] = "full"
	assert_true(BattleResult.from_dict(bad_company) == null)
