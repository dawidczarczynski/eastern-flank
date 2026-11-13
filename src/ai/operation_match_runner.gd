class_name OperationMatchRunner
extends RefCounted
## Plays whole operations AI-vs-AI headless and aggregates them (TASK-103a, balancing tool).
## Both sides play with OperationalAiTurn; every contact battle is auto-resolved (AutoResolve) or,
## in `played` mode, fought as a headless tactical AI-vs-AI battle and compared with the
## auto-resolve of the same setup.
## Ending of a match: the operation's own result (OperationVictory, TASK-107a): `gap_closed`,
## `round_limit` (the higher score wins, a draw inside the margin), `nuclear_use` -> `nuclear`;
## `collapse` / `escalation_threshold` results map to `collapse` / `threshold` when a rule
## produces them.

const AUTO := &"auto"
const PLAYED := &"played"
const ENDINGS: Array[StringName] = [
	&"collapse", &"threshold", &"nuclear", &"gap_closed", &"round_limit", &"error"
]
## Harness limit of one played contact battle (tactical turns).
const PLAYED_MAX_TURNS := 50

var _level_max: int = 0
var _fired: Array[int] = [0, 0]
var _intercepted: int = 0
var _destroyed: int = 0


## One match on the operation `operation_id`. `max_rounds` <= 0 = the operation's own cap
## (OperationDefinition.round_limit; a smaller value ends the match by `round_limit` earlier).
## `battles` = AUTO / PLAYED.
## Result keys: seed, operation, sides (side ids), winner, ending, reason, rounds, max_level,
## battles, battles_auto, battles_played, compared, agreed, caused ([int, int] escalation steps
## per player), strikes_fired ([int, int]), strikes_intercepted, installations_destroyed,
## totals (OperationVictory score totals at the end), contacts (played mode: [played winner,
## auto winner]
## per contact).
static func play(
	operation_id: StringName, seed_value: int, max_rounds: int = 0, battles: StringName = AUTO
) -> Dictionary:
	var state := Operation.build(operation_id, seed_value)
	if state == null:
		return _error_result(operation_id, seed_value)
	return play_state(OperationalSimulation.new(state), seed_value, max_rounds, battles)


## The match of an already built simulation (hand-made states in tests).
static func play_state(
	sim: OperationalSimulation, seed_value: int, max_rounds: int = 0, battles: StringName = AUTO
) -> Dictionary:
	var runner := OperationMatchRunner.new()
	return runner._run(sim, seed_value, max_rounds, battles)


## Aggregates `play` results: per-player wins (`wins_decided` = ended by a rule other than the
## round limit, `wins_by_score` = at the round limit), draws, endings, average length, politics
## and battle counts. `decided` = matches that ended without an error.
static func summarize(results: Array[Dictionary]) -> Dictionary:
	var out := {
		"matches": results.size(),
		"wins": [0, 0],
		"wins_decided": [0, 0],
		"wins_by_score": [0, 0],
		"draws": 0,
		"decided": 0,
		"endings": {},
		"errors": 0,
		"avg_rounds": 0.0,
		"avg_max_level": 0.0,
		"caused": [0, 0],
		"strikes_fired": [0, 0],
		"strikes_intercepted": 0,
		"installations_destroyed": 0,
		"battles": 0,
		"battles_auto": 0,
		"battles_played": 0,
		"compared": 0,
		"agreed": 0,
		"contacts": [] as Array,
	}
	for e in ENDINGS:
		out["endings"][e] = 0
	var rounds := 0
	var levels := 0
	for r in results:
		var ending: StringName = r["ending"]
		out["endings"][ending] += 1
		if ending == &"error":
			out["errors"] += 1
			continue
		rounds += r["rounds"] as int
		levels += r["max_level"] as int
		var winner: int = r["winner"]
		out["decided"] += 1
		if winner < 0:
			out["draws"] += 1
		else:
			out["wins"][winner] += 1
			var key := "wins_by_score" if ending == &"round_limit" else "wins_decided"
			out[key][winner] += 1
		for p in 2:
			out["caused"][p] += (r["caused"] as Array)[p]
			out["strikes_fired"][p] += (r["strikes_fired"] as Array)[p]
		for key in ["strikes_intercepted", "installations_destroyed", "battles", "battles_auto"]:
			out[key] += r[key] as int
		for key in ["battles_played", "compared", "agreed"]:
			out[key] += r[key] as int
	var valid: int = results.size() - (out["errors"] as int)
	if valid > 0:
		out["avg_rounds"] = float(rounds) / valid
		out["avg_max_level"] = float(levels) / valid
	return out


## CSV text of `results`: header `seed,winner,ending,rounds,max_level,battles`, one row per match.
static func csv(results: Array[Dictionary]) -> String:
	var lines: Array[String] = ["seed,winner,ending,rounds,max_level,battles"]
	for r in results:
		lines.append(
			(
				"%d,%d,%s,%d,%d,%d"
				% [r["seed"], r["winner"], r["ending"], r["rounds"], r["max_level"], r["battles"]]
			)
		)
	return "\n".join(lines) + "\n"


static func _error_result(operation_id: StringName, seed_value: int) -> Dictionary:
	return {
		"seed": seed_value,
		"operation": operation_id,
		"sides": [] as Array[StringName],
		"winner": -1,
		"ending": &"error",
		"reason": &"",
		"rounds": 0,
		"max_level": 0,
		"battles": 0,
		"battles_auto": 0,
		"battles_played": 0,
		"compared": 0,
		"agreed": 0,
		"contacts": [] as Array,
		"caused": [0, 0],
		"strikes_fired": [0, 0],
		"strikes_intercepted": 0,
		"installations_destroyed": 0,
		"totals": [0, 0],
	}


func _run(
	sim: OperationalSimulation, seed_value: int, max_rounds: int, battles: StringName
) -> Dictionary:
	var state := sim.state
	if max_rounds > 0 and state.definition != null:
		state.definition = state.definition.duplicate()  # the shared resource stays untouched
		state.definition.round_limit = max_rounds
	var cap := max_rounds
	if state.definition != null and max_rounds <= 0:
		cap = state.definition.round_limit
	elif cap <= 0:
		cap = 30
	var out := _error_result(state.operation_id, seed_value)
	out["sides"] = state.player_sides.duplicate()
	_level_max = state.escalation_level
	sim.event_emitted.connect(_on_event)
	var stalled := false
	var max_iterations := (cap + 1) * 2 * 20 + 20
	var iterations := 0
	while state.result.is_empty() and state.turn <= cap:
		iterations += 1
		if iterations > max_iterations:
			stalled = true
			break
		if not state.pending_battles.is_empty():
			if not _resolve_pending(sim, battles, out):
				stalled = true
				break
			continue
		var turn := OperationalAiTurn.play(sim, state.current_player)
		if (turn["results"] as Array).is_empty():
			stalled = true
			break
	sim.event_emitted.disconnect(_on_event)
	if state.definition != null:
		var scores := OperationVictory.score(state, state.definition)
		out["totals"] = [scores[0]["total"], scores[1]["total"]]
	if stalled:
		out["ending"] = &"error"
	elif not state.result.is_empty():
		out["ending"] = _ending_of(state.result)
		out["winner"] = state.result["winner"]
		out["reason"] = state.result["reason"]
		out["rounds"] = mini(state.turn, cap)
	else:
		out["ending"] = &"error"  # the round limit was reached without the rule firing
	out["max_level"] = maxi(_level_max, state.escalation_level)
	out["caused"] = state.escalation_caused.duplicate()
	out["strikes_fired"] = _fired.duplicate()
	out["strikes_intercepted"] = _intercepted
	out["installations_destroyed"] = _destroyed
	return out


## Resolves the first pending battle (auto, or played and compared); false when it cannot.
func _resolve_pending(sim: OperationalSimulation, mode: StringName, out: Dictionary) -> bool:
	var setup := sim.state.pending_battles[0]
	var auto := AutoResolve.resolve(setup)
	if auto == null:
		return false
	var result := auto
	var played := _play(sim.state) if mode == PLAYED else null
	if played != null:
		result = played
		out["battles_played"] += 1
		out["compared"] += 1
		if result.winner == auto.winner:
			out["agreed"] += 1
		(out["contacts"] as Array).append([result.winner, auto.winner])
	else:
		out["battles_auto"] += 1
	out["battles"] += 1
	return sim.execute(ResolveBattleCommand.new(result))


## The first pending battle fought as a headless tactical AI-vs-AI battle on its cut map; null
## when it cannot be prepared (it is then auto-resolved and not compared).
func _play(state: OperationalState) -> BattleResult:
	var prepared := ContactBattle.prepare(state)
	if prepared == null:
		return null
	var start := Scenario.from_setup(prepared)
	if start == null:
		return null
	var battle := GameSimulation.new(start)
	MatchRunner.run(battle, PLAYED_MAX_TURNS)
	var result := BattleResult.from_battle(prepared, battle.state)
	result.resolution = BattleResult.PLAYED
	return result


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"escalation_changed":
			_level_max = maxi(_level_max, event["level"] as int)
		&"strike_launched":
			_fired[event["player"] as int] += 1
		&"strike_resolved":
			_intercepted += event["intercepted"] as int
			if event["target_destroyed"] as bool:
				_destroyed += 1


static func _ending_of(result: Dictionary) -> StringName:
	match result["reason"]:
		&"nuclear_use":
			return &"nuclear"
		&"escalation_threshold":
			return &"threshold"
		&"collapse":
			return &"collapse"
		&"gap_closed":
			return &"gap_closed"
		&"round_limit":
			return &"round_limit"
	push_error("OperationMatchRunner: unknown result reason '%s'" % result["reason"])
	return &"error"
