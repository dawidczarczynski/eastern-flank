class_name MatchRunner
extends RefCounted
## Plays whole AI-vs-AI matches headless and aggregates the results (balancing tool, TASK-012).
## `max_turns` is a harness limit only; the battle's own turn limit (BattleObjectives, TASK-088)
## is a rule and ends a match as a "victory" or "draw".


## Plays the scenario `scenario` (Scenario.NAMES) with an `AiPlayer` on every side until the battle
## is over or `max_turns` is exceeded. `factions` = faction id of player 0 and player 1.
## Result keys: seed, scenario, factions, winner, turns, commands, reason (GameState.end_reason as
## a String, "" when the rules did not end the match) and result:
##   "victory"       – the rules ended the battle with a winner;
##   "draw"          – the rules ended it without one (e.g. the turn limit);
##   "harness_limit" – `max_turns` ran out first (turns = max_turns);
##   "error"         – unknown scenario or the AI stopped issuing turns.
static func play(
	seed_value: int,
	max_turns: int,
	factions: Array[StringName] = FactionRegistry.DEFAULT_IDS,
	scenario: String = "default_battle"
) -> Dictionary:
	var result := {
		"seed": seed_value,
		"scenario": scenario,
		"factions": factions.duplicate(),
		"winner": -1,
		"turns": 0,
		"result": "error",
		"reason": "",
		"commands": 0,
	}
	var start := Scenario.build(scenario, seed_value, factions)
	if start == null:
		return result
	var sim := GameSimulation.new(start)
	var state := sim.state
	var ai := AiPlayer.new()
	var max_iterations := max_turns * state.player_count + 1
	var iterations := 0
	var errored := false
	while not state.is_over() and state.turn <= max_turns:
		iterations += 1
		if iterations > max_iterations:
			errored = true
			break
		ai.take_turn(sim)
	var turns := state.turn
	if errored:
		result["result"] = "error"
	elif not state.is_over():
		result["result"] = "harness_limit"
		turns = max_turns
	elif state.winner == -1:
		result["result"] = "draw"
	else:
		result["result"] = "victory"
	result["winner"] = state.winner
	result["turns"] = turns
	result["reason"] = String(state.end_reason)
	result["commands"] = sim.history.size()
	return result


## Aggregates `play` results: per-player wins, draws by the rules, harness limits, errors and
## average match length (`avg_turns_decided` over victories only, `avg_turns_all` over every
## match – error matches count with the turn the guard fired at).
static func summarize(results: Array[Dictionary]) -> Dictionary:
	var wins: Array[int] = [0, 0]
	var draws := 0
	var harness_limits := 0
	var errors := 0
	var decided_turns := 0
	var decided := 0
	var all_turns := 0
	for r in results:
		all_turns += r["turns"] as int
		match r["result"]:
			"victory":
				var winner := r["winner"] as int
				while wins.size() <= winner:
					wins.append(0)
				wins[winner] += 1
				decided += 1
				decided_turns += r["turns"] as int
			"draw":
				draws += 1
			"harness_limit":
				harness_limits += 1
			_:
				errors += 1
	return {
		"matches": results.size(),
		"wins": wins,
		"draws": draws,
		"harness_limits": harness_limits,
		"errors": errors,
		"avg_turns_decided": float(decided_turns) / decided if decided > 0 else 0.0,
		"avg_turns_all": float(all_turns) / results.size() if not results.is_empty() else 0.0,
	}
