extends TestCase
## Headless AI-vs-AI match runner (see TASK-012).


func test_harness_limit_after_one_turn() -> void:
	var r := MatchRunner.play(12345, 1)
	assert_eq(r["result"], "harness_limit")
	assert_eq(r["winner"], -1)
	assert_eq(r["turns"], 1)
	assert_eq(r["reason"], "")
	assert_eq(r["scenario"], "default_battle")


func test_play_is_deterministic() -> void:
	assert_eq(MatchRunner.play(7, 50), MatchRunner.play(7, 50))


func test_play_never_errors() -> void:
	var r := MatchRunner.play(7, 50)
	assert_true(r["result"] == "victory" or r["result"] == "harness_limit")
	assert_eq(r["seed"], 7)
	if r["result"] == "victory":
		assert_true(r["winner"] == 0 or r["winner"] == 1)
		assert_true(r["turns"] >= 1 and r["turns"] <= 50)
	assert_true(r["commands"] > 0)


func test_summarize() -> void:
	var results: Array[Dictionary] = [
		{"winner": 0, "turns": 10, "result": "victory"},
		{"winner": -1, "turns": 50, "result": "harness_limit"},
		{"winner": 1, "turns": 20, "result": "victory"},
		{"winner": -1, "turns": 8, "result": "draw"},
	]
	var s := MatchRunner.summarize(results)
	assert_eq(s["matches"], 4)
	assert_eq(s["wins"], [1, 1])
	assert_eq(s["draws"], 1)
	assert_eq(s["harness_limits"], 1)
	assert_eq(s["errors"], 0)
	assert_eq(s["avg_turns_decided"], 15.0)
	assert_eq(s["avg_turns_all"], 22.0)


func test_summarize_counts_errors_separately() -> void:
	var results: Array[Dictionary] = [
		{"winner": -1, "turns": 5, "result": "error"},
		{"winner": 0, "turns": 4, "result": "victory"},
	]
	var s := MatchRunner.summarize(results)
	assert_eq(s["errors"], 1)
	assert_eq(s["wins"], [1, 0])
	assert_eq(s["avg_turns_decided"], 4.0)


func test_summarize_empty() -> void:
	var s := MatchRunner.summarize([] as Array[Dictionary])
	assert_eq(s["matches"], 0)
	assert_eq(s["avg_turns_decided"], 0.0)
	assert_eq(s["avg_turns_all"], 0.0)


func test_play_with_swapped_factions_is_deterministic_and_never_errors() -> void:
	var factions: Array[StringName] = [&"russia", &"poland"]
	var a := MatchRunner.play(7, 50, factions)
	assert_eq(a, MatchRunner.play(7, 50, factions))
	assert_true(a["result"] == "victory" or a["result"] == "harness_limit")


func test_play_uses_the_given_factions() -> void:
	var factions: Array[StringName] = [&"russia", &"poland"]
	assert_eq(MatchRunner.play(7, 1, factions)["factions"], factions)
	assert_eq(MatchRunner.play(7, 1)["factions"], FactionRegistry.DEFAULT_IDS)


func test_objective_battle_ends_by_the_rules_within_the_turn_limit() -> void:
	for seed_value: int in [1, 2, 3]:
		var r := MatchRunner.play(seed_value, 50, FactionRegistry.DEFAULT_IDS, "objective_battle")
		assert_eq(r["scenario"], "objective_battle")
		assert_true(r["result"] == "victory" or r["result"] == "draw", str(r))
		assert_true(r["turns"] <= 8, str(r))
		assert_true(
			r["reason"] in ["objective_taken", "turn_limit", "eliminated", "enemy_destroyed"]
		)
		if r["result"] == "draw":
			assert_eq(r["winner"], -1)
			assert_eq(r["reason"], "turn_limit")


func test_unknown_scenario_is_an_error() -> void:
	# Expected engine output: none – Scenario.build returns null for an unknown name.
	assert_eq(MatchRunner.play(1, 5, FactionRegistry.DEFAULT_IDS, "atlantis")["result"], "error")
