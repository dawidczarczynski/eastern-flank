extends TestCase
## BattleNameText: translated two-line / one-line battle names and their strings.

var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_all() -> void:
	TranslationServer.set_locale(_previous_locale)


func _setup(terrain: StringName, task := &"attack") -> BattleSetup:
	var setup := BattleSetup.new()
	setup.attacker = 0
	setup.terrain = terrain
	for i in 2:
		var mission := BattleSetup.Mission.new()
		mission.task = task if i == 0 else &"defend"
		setup.missions.append(mission)
	return setup


func _map() -> ImportedMap:
	var map := ImportedMap.new()
	map.hex_spacing_m = 1000.0
	map.place_names.append("Suwałki")
	map.place_positions.append(Vector2.ZERO)
	map.place_ranks.append(ImportedMap.PLACE_TOWN)
	return map


func test_two_lines_and_one_line() -> void:
	var setup := _setup(&"urban", &"hold_out")
	var lines := BattleNameText.two_lines(setup, 0, _map(), Vector2i(5, 0))
	assert_eq(lines, ["Contact with the enemy", "Suwałki, 5 km east"] as Array[String])
	assert_eq(
		BattleNameText.one_line(setup, 0, _map(), Vector2i(5, 0)),
		"Contact with the enemy · Suwałki, 5 km east"
	)


func test_without_a_map_the_place_is_the_hex() -> void:
	var lines := BattleNameText.two_lines(_setup(&"plains"), 0, null, Vector2i(5, 0))
	assert_eq(lines[0], "Assault")
	assert_true(lines[1].begins_with("HEX "))


func test_scenario_battle_has_no_name() -> void:
	assert_eq(BattleNameText.two_lines(BattleSetup.new(), 0, null, Vector2i.ZERO).size(), 0)
	assert_eq(BattleNameText.one_line(BattleSetup.new(), 0, null, Vector2i.ZERO), "")


func test_key_of_event_follows_the_viewer() -> void:
	var event := {"situation": [BattleName.ASSAULT_TOWN, BattleName.DEFENCE_TOWN]}
	assert_eq(BattleNameText.key_of(event, 0), BattleName.ASSAULT_TOWN)
	assert_eq(BattleNameText.key_of(event, 1), BattleName.DEFENCE_TOWN)
	assert_eq(BattleNameText.key_of({}, 0), &"")


func test_every_key_has_english_and_polish() -> void:
	for key in BattleName.KEYS:
		var id := "BATTLE_NAME_" + String(key)
		for locale in ["en", "pl"]:
			TranslationServer.set_locale(locale)
			var text := TranslationServer.translate(id)
			assert_true(text != "" and text != id, "%s missing in %s" % [id, locale])
	TranslationServer.set_locale("en")
