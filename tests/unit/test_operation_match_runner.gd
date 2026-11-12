extends TestCase
## OperationMatchRunner (TASK-103a): operational AI-vs-AI matches with a report.


func test_match_is_deterministic_and_ends_at_the_cap() -> void:
	var a := OperationMatchRunner.play(&"suwalki_gap", 5, 2)
	var b := OperationMatchRunner.play(&"suwalki_gap", 5, 2)
	assert_eq(a, b)
	assert_true(a["rounds"] <= 2)
	assert_true([&"turn_cap", &"nuclear"].has(a["ending"]))
	assert_eq(a["battles"], a["battles_auto"], "auto by default")
	assert_eq(a["battles_played"], 0)


func test_seeds_differ_somewhere_over_ten_matches() -> void:
	var rows: Array[Dictionary] = []
	for i in 10:
		rows.append(OperationMatchRunner.play(&"suwalki_gap", 5 + i, 3))
	var distinct := false
	for i in 9:
		for key in ["winner", "rounds", "max_level", "battles", "ending", "caused", "totals"]:
			if rows[i][key] != rows[i + 1][key]:
				distinct = true
	assert_true(distinct, "different seeds differ in a per-match field")


func test_unknown_operation_is_an_error_result() -> void:
	assert_eq(OperationMatchRunner.play(&"nope", 1)["ending"], &"error")


func test_cap_without_an_ending_uses_the_provisional_score() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	state.turn = 4
	var r := OperationMatchRunner.play_state(OperationalSimulation.new(state), 1, 3)
	assert_eq(r["ending"], &"turn_cap")
	assert_eq(r["reason"], &"provisional")
	assert_eq(r["rounds"], 3)
	assert_eq(r["winner"], ProvisionalScore.evaluate(state)["winner"])


func test_already_over_operation_plays_nothing() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	state.result = {"winner": -1, "reason": &"nuclear_use", "by": 1}
	var sim := OperationalSimulation.new(state)
	var r := OperationMatchRunner.play_state(sim, 1, 5)
	assert_eq(sim.history.size(), 0)
	assert_eq(r["ending"], &"nuclear")
	assert_eq(r["winner"], -1)


func test_summary_shares_and_csv() -> void:
	var results: Array[Dictionary] = []
	for i in 3:
		results.append(OperationMatchRunner.play(&"suwalki_gap", 1 + i, 3))
	var s := OperationMatchRunner.summarize(results)
	var total := 0
	for e in OperationMatchRunner.ENDINGS:
		total += s["endings"][e] as int
	assert_eq(total, 3)
	assert_eq(s["decided"] + s["undecided"] + s["errors"], 3)
	var lines := OperationMatchRunner.csv(results).strip_edges().split("\n")
	assert_eq(lines.size(), 4)
	assert_eq(lines[0], "seed,winner,ending,rounds,max_level,battles")


func test_played_battles_are_compared_with_auto() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	var sim := OperationalSimulation.new(state)
	# Drive until a contact exists (a few rounds), in played mode.
	var r := OperationMatchRunner.play_state(sim, 1, 4, OperationMatchRunner.PLAYED)
	assert_eq(r["battles_auto"], 0)
	assert_true(r["compared"] > 0, "a contact must have been played")
	assert_eq(r["compared"], r["battles_played"])
	assert_eq((r["contacts"] as Array).size(), r["compared"])
	assert_true(r["agreed"] <= r["compared"])
