extends SceneTree
## Plays N AI-vs-AI matches headless and prints win rates and match length. Run via
## tools/simulate.sh. Exit codes: 0 ok, 1 some match ended with "error", 2 invalid arguments.

const SimulateOptions := preload("res://tools/simulate_options.gd")
const USAGE := "Usage: tools/simulate.sh N [--seed=S] [--max-turns=T] [--factions=A,B] [--verbose]"


func _initialize() -> void:
	var options := SimulateOptions.parse(OS.get_cmdline_user_args())
	if options["error"] != "":
		printerr(USAGE)
		quit(2)
		return
	var count: int = options["count"]
	var first_seed: int = options["seed"]
	var max_turns: int = options["max_turns"]
	var factions: Array[StringName] = options["factions"]
	var results: Array[Dictionary] = []
	for i in count:
		var r := MatchRunner.play(first_seed + i, max_turns, factions)
		results.append(r)
		if options["verbose"]:
			print(
				(
					"seed=%d result=%s winner=%d turns=%d"
					% [r["seed"], r["result"], r["winner"], r["turns"]]
				)
			)
	var s := MatchRunner.summarize(results)
	var wins: Array = s["wins"]
	print(
		(
			"Matches: %d (seeds %d..%d, max turns %d)"
			% [count, first_seed, first_seed + count - 1, max_turns]
		)
	)
	print("Factions: %s vs %s" % [factions[0], factions[1]])
	for p in wins.size():
		print("Player %d wins: %d (%s)" % [p, wins[p], _percent(wins[p], count)])
	print("Draws (turn limit): %d (%s)" % [s["draws"], _percent(s["draws"], count)])
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
