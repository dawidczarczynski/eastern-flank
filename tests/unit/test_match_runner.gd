extends TestCase
## Headless AI-vs-AI match runner (see TASK-012).


func test_turn_limit_after_one_turn() -> void:
	var r := MatchRunner.play(12345, 1)
	assert_eq(r["result"], "turn_limit")
	assert_eq(r["winner"], -1)
	assert_eq(r["turns"], 1)


func test_play_is_deterministic() -> void:
	assert_eq(MatchRunner.play(7, 50), MatchRunner.play(7, 50))


func test_play_never_errors() -> void:
	var r := MatchRunner.play(7, 50)
	assert_true(r["result"] == "victory" or r["result"] == "turn_limit")
	assert_eq(r["seed"], 7)
	if r["result"] == "victory":
		assert_true(r["winner"] == 0 or r["winner"] == 1)
		assert_true(r["turns"] >= 1 and r["turns"] <= 50)
	assert_true(r["commands"] > 0)


func test_summarize() -> void:
	var results: Array[Dictionary] = [
		{"winner": 0, "turns": 10, "result": "victory"},
		{"winner": -1, "turns": 50, "result": "turn_limit"},
		{"winner": 1, "turns": 20, "result": "victory"},
	]
	var s := MatchRunner.summarize(results)
	assert_eq(s["matches"], 3)
	assert_eq(s["wins"], [1, 1])
	assert_eq(s["draws"], 1)
	assert_eq(s["errors"], 0)
	assert_eq(s["avg_turns_decided"], 15.0)
	assert_true(absf(s["avg_turns_all"] - 26.67) < 0.01)


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
