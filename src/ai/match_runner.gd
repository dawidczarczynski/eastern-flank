class_name MatchRunner
extends RefCounted
## Plays whole AI-vs-AI matches headless and aggregates the results (balancing tool, TASK-012).
## The turn limit is a harness parameter only – the rules have no draw condition.


## Plays `Scenario.default_battle(seed_value, factions)` with an `AiPlayer` on every side until
## a winner exists or `max_turns` is exceeded. `factions` = faction id of player 0 and player 1.
## Result keys: seed, factions, winner, turns, result ("victory" | "turn_limit" | "error"),
## commands.
static func play(
	seed_value: int, max_turns: int, factions: Array[StringName] = FactionRegistry.DEFAULT_IDS
) -> Dictionary:
	var sim := GameSimulation.new(Scenario.default_battle(seed_value, factions))
	var state := sim.state
	var ai := AiPlayer.new()
	var max_iterations := max_turns * state.player_count + 1
	var iterations := 0
	var errored := false
	while state.winner == -1 and state.turn <= max_turns:
		iterations += 1
		if iterations > max_iterations:
			errored = true
			break
		ai.take_turn(sim)
	var result := "victory"
	var turns := state.turn
	if errored:
		result = "error"
	elif state.winner == -1:
		result = "turn_limit"
		turns = max_turns
	return {
		"seed": seed_value,
		"factions": factions.duplicate(),
		"winner": state.winner,
		"turns": turns,
		"result": result,
		"commands": sim.history.size(),
	}


## Aggregates `play` results: per-player wins, draws, errors and average match length
## (`avg_turns_decided` over victories only, `avg_turns_all` over every match – error
## matches count with the turn the guard fired at).
static func summarize(results: Array[Dictionary]) -> Dictionary:
	var wins: Array[int] = [0, 0]
	var draws := 0
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
			"turn_limit":
				draws += 1
			_:
				errors += 1
	return {
		"matches": results.size(),
		"wins": wins,
		"draws": draws,
		"errors": errors,
		"avg_turns_decided": float(decided_turns) / decided if decided > 0 else 0.0,
		"avg_turns_all": float(all_turns) / results.size() if not results.is_empty() else 0.0,
	}
