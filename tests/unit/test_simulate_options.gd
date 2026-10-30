extends TestCase
## Argument parsing for tools/simulate.gd (see TASK-012).

const SimulateOptions := preload("res://tools/simulate_options.gd")


func test_defaults() -> void:
	var o := SimulateOptions.parse(PackedStringArray(["100"]))
	assert_eq(o["count"], 100)
	assert_eq(o["seed"], 1)
	assert_eq(o["max_turns"], 50)
	assert_eq(o["verbose"], false)
	assert_eq(o["error"], "")


func test_all_options() -> void:
	var o := SimulateOptions.parse(
		PackedStringArray(["--seed=5", "20", "--max-turns=30", "--verbose"])
	)
	assert_eq(o["count"], 20)
	assert_eq(o["seed"], 5)
	assert_eq(o["max_turns"], 30)
	assert_eq(o["verbose"], true)
	assert_eq(o["error"], "")


func test_missing_count() -> void:
	assert_true(SimulateOptions.parse(PackedStringArray())["error"] != "")


func test_non_positive_or_invalid_count() -> void:
	for bad in ["0", "-3", "abc"]:
		assert_true(SimulateOptions.parse(PackedStringArray([bad]))["error"] != "")


func test_unknown_option_and_bad_values() -> void:
	for bad in [["5", "--nope"], ["5", "--max-turns=0"], ["5", "--seed=x"], ["5", "6"]]:
		assert_true(SimulateOptions.parse(PackedStringArray(bad))["error"] != "")


func test_factions_default_to_poland_vs_russia() -> void:
	var o := SimulateOptions.parse(PackedStringArray(["10"]))
	assert_eq(o["factions"], [&"poland", &"russia"] as Array[StringName])


func test_factions_option() -> void:
	var o := SimulateOptions.parse(PackedStringArray(["10", "--factions=russia,poland"]))
	assert_eq(o["error"], "")
	assert_eq(o["factions"], [&"russia", &"poland"] as Array[StringName])


## Every parse error makes tools/simulate.gd print the usage and exit with code 2.
func test_bad_factions_are_usage_errors() -> void:
	for bad in [
		"--factions=poland", "--factions=poland,atlantis", "--factions=", "--factions=a,b,c"
	]:
		assert_eq(
			SimulateOptions.parse(PackedStringArray(["10", bad]))["error"], "invalid_factions", bad
		)


func test_scenario_defaults_to_the_default_battle() -> void:
	assert_eq(SimulateOptions.parse(PackedStringArray(["10"]))["scenario"], "default_battle")


func test_scenario_option() -> void:
	var o := SimulateOptions.parse(PackedStringArray(["10", "--scenario=objective_battle"]))
	assert_eq(o["error"], "")
	assert_eq(o["scenario"], "objective_battle")
	for bad in ["--scenario=atlantis", "--scenario="]:
		assert_eq(
			SimulateOptions.parse(PackedStringArray(["10", bad]))["error"], "invalid_scenario", bad
		)
