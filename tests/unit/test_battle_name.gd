extends TestCase
## BattleName: the situation key of a battle for each viewer and the nearest-place maths.


func _setup(terrain: StringName, attacker := 0, task := &"attack") -> BattleSetup:
	var setup := BattleSetup.new()
	setup.attacker = attacker
	setup.terrain = terrain
	for i in 2:
		var mission := BattleSetup.Mission.new()
		mission.task = task if i == 0 else &"defend"
		setup.missions.append(mission)
	return setup


func _map(places: Array) -> ImportedMap:
	var map := ImportedMap.new()
	map.hex_spacing_m = 1000.0
	for place: Array in places:
		map.place_names.append(place[0])
		map.place_positions.append(place[1])
		map.place_ranks.append(ImportedMap.PLACE_TOWN)
	return map


func test_attacker_phrases() -> void:
	for terrain: StringName in [&"plains", &"fields", &"hills", &"marsh"]:
		assert_eq(BattleName.situation(_setup(terrain), 0), BattleName.ASSAULT)
	assert_eq(BattleName.situation(_setup(&"urban"), 0), BattleName.ASSAULT_TOWN)
	assert_eq(BattleName.situation(_setup(&"forest"), 0), BattleName.ASSAULT_FOREST)
	assert_eq(BattleName.situation(_setup(&"water"), 0), BattleName.ASSAULT_RIVER)
	assert_eq(BattleName.situation(_setup(&"plains"), 0, true), BattleName.ASSAULT_RIVER)


func test_defender_phrases() -> void:
	assert_eq(BattleName.situation(_setup(&"urban"), 1), BattleName.DEFENCE_TOWN)
	for terrain: StringName in [&"plains", &"forest", &"water"]:
		assert_eq(BattleName.situation(_setup(terrain), 1), BattleName.DEFENCE)


func test_hold_out_is_a_meeting_engagement_for_both() -> void:
	for viewer in 2:
		var setup := _setup(&"urban", 0, &"hold_out")
		assert_eq(BattleName.situation(setup, viewer), BattleName.CONTACT_ENEMY)
	var other := _setup(&"urban")
	other.missions[1].task = &"hold_out"
	assert_eq(BattleName.situation(other, 0), BattleName.CONTACT_ENEMY)


func test_scenario_battle_has_no_name() -> void:
	assert_eq(BattleName.situation(BattleSetup.new(), 0), &"")
	assert_eq(BattleName.situation(_setup(&"urban", -1), 0), &"")


func test_viewers_differ_and_output_is_stable() -> void:
	var setup := _setup(&"urban")
	assert_true(BattleName.situation(setup, 0) != BattleName.situation(setup, 1))
	assert_eq(BattleName.situation(setup, 0), BattleName.situation(setup, 0))


func test_place_nearest_of_three() -> void:
	var map := _map(
		[["Far", Vector2(50, 50)], ["Suwałki", Vector2.ZERO], ["Other", Vector2(-40, 0)]]
	)
	var place := BattleName.place(map, Vector2i(5, 0))
	assert_eq(place["name"], "Suwałki")
	assert_eq(place["km"], 5)
	assert_eq(place["dir"], "DIR_E")


func test_place_near_and_empty() -> void:
	var map := _map([["Suwałki", Vector2.ZERO]])
	var near := BattleName.place(map, Vector2i(1, 0))
	assert_eq(near["km"], 0)
	assert_eq(near["dir"], "")
	assert_eq(BattleName.place(null, Vector2i.ZERO), {})
	assert_eq(BattleName.place(ImportedMap.new(), Vector2i.ZERO), {})
