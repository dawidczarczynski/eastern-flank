extends SceneTree
## Plays N AI-vs-AI matches headless and prints win rates and match length. Run via
## tools/simulate.sh. Exit codes: 0 ok, 1 some match ended with "error" / a runtime error (unknown
## operation, unwritable --out), 2 invalid arguments. `--mode=operation` (TASK-103a) plays whole
## operations AI-vs-AI (OperationMatchRunner); the default tactical mode is unchanged.

const SimulateOptions := preload("res://tools/simulate_options.gd")
const USAGE := (
	"Usage: tools/simulate.sh N [--seed=S] [--max-turns=T] [--factions=A,B]"
	+ " [--scenario=default_battle|objective_battle|command_points_battle|suwalki_battle] [--verbose]"
	+ "\n       tools/simulate.sh N --mode=operation [--seed=S] [--max-rounds=R]"
	+ " [--scenario=<operation id>] [--battles=auto|played] [--out=file.csv] [--verbose]"
)


func _initialize() -> void:
	var options := SimulateOptions.parse(OS.get_cmdline_user_args())
	if options["error"] != "":
		printerr(USAGE)
		quit(2)
		return
	if options["mode"] == "operation":
		_run_operation(options)
		return
	var count: int = options["count"]
	var first_seed: int = options["seed"]
	var max_turns: int = options["max_turns"]
	var factions: Array[StringName] = options["factions"]
	var scenario: String = options["scenario"]
	var results: Array[Dictionary] = []
	for i in count:
		var r := MatchRunner.play(first_seed + i, max_turns, factions, scenario)
		results.append(r)
		if options["verbose"]:
			print(
				(
					"seed=%d result=%s reason=%s winner=%d turns=%d"
					% [r["seed"], r["result"], r["reason"], r["winner"], r["turns"]]
				)
			)
	var s := MatchRunner.summarize(results)
	var wins: Array = s["wins"]
	print(
		(
			"Matches: %d (%s, seeds %d..%d, max turns %d)"
			% [count, scenario, first_seed, first_seed + count - 1, max_turns]
		)
	)
	print("Factions: %s vs %s" % [factions[0], factions[1]])
	for p in wins.size():
		print("Player %d wins: %d (%s)" % [p, wins[p], _percent(wins[p], count)])
	print("Draws (rules): %d (%s)" % [s["draws"], _percent(s["draws"], count)])
	print(
		(
			"Harness limit reached: %d (%s)"
			% [s["harness_limits"], _percent(s["harness_limits"], count)]
		)
	)
	print("Errors: %d" % s["errors"])
	print(
		(
			"Average length: %.1f turns (decided), %.1f turns (all)"
			% [s["avg_turns_decided"], s["avg_turns_all"]]
		)
	)
	quit(1 if s["errors"] > 0 else 0)


func _percent(part: int, total: int) -> String:
	return "%.1f%%" % (100.0 * part / total)


func _run_operation(options: Dictionary) -> void:
	var count: int = options["count"]
	var first_seed: int = options["seed"]
	var operation := StringName(options["scenario"])
	var battles := StringName(options["battles"])
	var max_rounds: int = options["max_rounds"]
	if not Operation.NAMES.has(operation):
		printerr("Unknown operation '%s' (known: %s)" % [operation, Operation.NAMES])
		quit(1)
		return
	var results: Array[Dictionary] = []
	for i in count:
		var r := OperationMatchRunner.play(operation, first_seed + i, max_rounds, battles)
		results.append(r)
		if battles == OperationMatchRunner.PLAYED:
			for c in r["contacts"] as Array:
				print("seed=%d contact: played winner %d, auto winner %d" % [r["seed"], c[0], c[1]])
		if options["verbose"]:
			print(
				(
					"seed=%d winner=%d ending=%s rounds=%d max_level=%d battles=%d"
					% [
						r["seed"],
						r["winner"],
						r["ending"],
						r["rounds"],
						r["max_level"],
						r["battles"]
					]
				)
			)
	var out_path: String = options["out"]
	if out_path != "":
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file == null:
			printerr("Cannot write '%s'" % out_path)
			quit(1)
			return
		file.store_string(OperationMatchRunner.csv(results))
		file.close()
	var s := OperationMatchRunner.summarize(results)
	for line in _operation_report(options, results, s):
		print(line)
	quit(1 if s["errors"] > 0 else 0)


func _operation_report(
	options: Dictionary, results: Array[Dictionary], s: Dictionary
) -> Array[String]:
	var count: int = options["count"]
	var first_seed: int = options["seed"]
	var names: Array[String] = ["Player 0", "Player 1"]
	for r in results:
		var sides: Array = r["sides"]
		if sides.size() == 2:
			names = [String(sides[0]).to_upper(), String(sides[1]).to_upper()]
			break
	var cap_text := "operation cap" if options["max_rounds"] == 0 else "%d" % options["max_rounds"]
	var lines: Array[String] = []
	lines.append(
		(
			"Operation matches: %d (%s, seeds %d..%d, max rounds %s, battles %s)"
			% [
				count,
				options["scenario"],
				first_seed,
				first_seed + count - 1,
				cap_text,
				options["battles"]
			]
		)
	)
	lines.append("Sides: %s vs %s" % names)
	var wins: Array = s["wins"]
	var wins_decided: Array = s["wins_decided"]
	var wins_by_score: Array = s["wins_by_score"]
	for p in 2:
		lines.append(
			(
				"%s wins: %d (%s) - by a rule %d, by score at the round limit %d"
				% [names[p], wins[p], _percent(wins[p], count), wins_decided[p], wins_by_score[p]]
			)
		)
	lines.append("Draws: %d (%s)" % [s["draws"], _percent(s["draws"], count)])
	lines.append("Ended without an error: %d (%s)" % [s["decided"], _percent(s["decided"], count)])
	var decided_wins: int = wins[0] + wins[1]
	if decided_wins > 0:
		lines.append(
			(
				"Win share of decided operations: %s %s, %s %s"
				% [
					names[0],
					_percent(wins[0], decided_wins),
					names[1],
					_percent(wins[1], decided_wins)
				]
			)
		)
	else:
		lines.append("Win share of decided operations: n/a (no decided operation with a winner)")
	var endings: Dictionary = s["endings"]
	(
		lines
		. append(
			(
				"Endings: collapse %s, threshold %s, nuclear %s, gap closed %s, round limit %s, error %s"
				% [
					_percent(endings[&"collapse"], count),
					_percent(endings[&"threshold"], count),
					_percent(endings[&"nuclear"], count),
					_percent(endings[&"gap_closed"], count),
					_percent(endings[&"round_limit"], count),
					_percent(endings[&"error"], count)
				]
			)
		)
	)
	lines.append("Errors: %d" % s["errors"])
	lines.append("Average length: %.1f rounds" % s["avg_rounds"])
	lines.append("Average max escalation level: %.2f" % s["avg_max_level"])
	var caused: Array = s["caused"]
	lines.append(
		"Escalation steps caused: %s %d, %s %d" % [names[0], caused[0], names[1], caused[1]]
	)
	var fired: Array = s["strikes_fired"]
	lines.append(
		(
			"Strikes fired: %s %d, %s %d; intercepted %d; installations destroyed %d"
			% [
				names[0],
				fired[0],
				names[1],
				fired[1],
				s["strikes_intercepted"],
				s["installations_destroyed"]
			]
		)
	)
	lines.append(
		(
			"Battles fought: %d (auto %d, played %d)"
			% [s["battles"], s["battles_auto"], s["battles_played"]]
		)
	)
	if options["battles"] == "played":
		lines.append(
			(
				"Played vs auto-resolve winner agreement: %d / %d (%s)"
				% [s["agreed"], s["compared"], _percent(s["agreed"], maxi(s["compared"], 1))]
			)
		)
	return lines
