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
