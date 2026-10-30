extends TestCase


func test_no_option_gives_the_default_battle() -> void:
	assert_eq(BattleOptions.scenario_name(PackedStringArray()), "default_battle")
	assert_eq(BattleOptions.scenario_name(PackedStringArray(["--quality=low"])), "default_battle")


func test_known_scenario_is_picked() -> void:
	var args := PackedStringArray(["--quality=high", "--scenario=objective_battle"])
	assert_eq(BattleOptions.scenario_name(args), "objective_battle")


func test_unknown_scenario_falls_back_to_the_default() -> void:
	var args := PackedStringArray(["--scenario=no_such_battle"])
	assert_eq(BattleOptions.scenario_name(args), "default_battle")


func test_every_name_is_buildable() -> void:
	for scenario_name in Scenario.NAMES:
		var args := PackedStringArray(["--scenario=" + scenario_name])
		assert_eq(BattleOptions.scenario_name(args), scenario_name)
