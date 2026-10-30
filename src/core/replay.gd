class_name Replay
extends RefCounted
## Rebuilds a match from a MatchRecord: the scenario's starting state from the seed, then every
## recorded command through GameSimulation.execute – the same path as live play.
## Result: {"ok": true, "simulation": GameSimulation} or
##         {"ok": false, "error": <code>, "index": <command index, -1 if none>, "reason": <String>}
## Error codes: "unknown_scenario", "invalid_factions" (an unknown faction id or not one per
## player), "invalid_command" (CommandCodec could not decode it),
## "diverged" (the simulation rejected it; "reason" is the validate() code).


static func run(record: MatchRecord) -> Dictionary:
	if not _valid_factions(record.factions):
		return _failure("invalid_factions", -1, "")
	var state := Scenario.build(record.scenario, record.seed, record.factions)
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


## Every scenario is a 2-player battle for now.
static func _valid_factions(factions: Array[StringName]) -> bool:
	if factions.size() != 2:
		return false
	for faction_id in factions:
		if not FactionRegistry.has_faction(faction_id):
			return false
	return true


static func _failure(error: String, index: int, reason: String) -> Dictionary:
	return {"ok": false, "error": error, "index": index, "reason": reason}
