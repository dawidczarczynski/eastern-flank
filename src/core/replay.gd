class_name Replay
extends RefCounted
## Rebuilds a match from a MatchRecord: the scenario's starting state from the seed, then every
## recorded command through GameSimulation.execute – the same path as live play.
## Result: {"ok": true, "simulation": GameSimulation} or
##         {"ok": false, "error": <code>, "index": <command index, -1 if none>, "reason": <String>}
## Error codes: "unknown_scenario", "invalid_command" (CommandCodec could not decode it),
## "diverged" (the simulation rejected it; "reason" is the validate() code).


static func run(record: MatchRecord) -> Dictionary:
	var state := _build_state(record.scenario, record.seed)
	if state == null:
		return _failure("unknown_scenario", -1, "")
	var sim := GameSimulation.new(state)
	var rejection: Array[String] = [""]
	sim.command_rejected.connect(func(_c: Command, reason: String) -> void: rejection[0] = reason)
	for i in record.commands.size():
		var command := CommandCodec.from_dict(record.commands[i])
		if command == null:
			return _failure("invalid_command", i, "")
		if not sim.execute(command):
			return _failure("diverged", i, rejection[0])
	return {"ok": true, "simulation": sim}


## Starting state of a named scenario; null for an unknown name.
static func _build_state(scenario: String, seed_value: int) -> GameState:
	match scenario:
		"default_battle":
			return Scenario.default_battle(seed_value)
	return null


static func _failure(error: String, index: int, reason: String) -> Dictionary:
	return {"ok": false, "error": error, "index": index, "reason": reason}
