class_name BattleReplay
extends RefCounted
## Tactical side of a campaign record (TASK-094d): a played battle as its BattleSetup + tactical
## command dicts + BattleResult. Lets CampaignRecord (operational layer) store and verify a battle
## without touching GameState / GameSimulation / commands itself (ADR 0015 §1).


## The `to_dict()` form of a battle's executed commands (GameSimulation.history).
static func command_dicts(history: Array[Command]) -> Array[Dictionary]:
	var dicts: Array[Dictionary] = []
	for command in history:
		dicts.append(command.to_dict())
	return dicts


## The commands in canonical `to_dict()` form (JSON floats back to ints); null when an entry is
## not a dictionary or CommandCodec cannot decode it.
static func canonical(commands: Array) -> Variant:
	var dicts: Array[Dictionary] = []
	for value: Variant in commands:
		var command := CommandCodec.from_dict(value) if value is Dictionary else null
		if command == null:
			return null
		dicts.append(command.to_dict())
	return dicts


## "" when `commands` replayed on `Scenario.from_setup(setup)` end the battle with `result`;
## otherwise why not: "setup_failed", "command <j>: <reason>", "not_over" or "result".
static func problem(
	setup: BattleSetup, commands: Array[Dictionary], result: BattleResult
) -> String:
	var state := Scenario.from_setup(setup)
	if state == null:
		return "setup_failed"
	var battle := GameSimulation.new(state)
	var rejection: Array[String] = [""]
	battle.command_rejected.connect(
		func(_c: Command, reason: String) -> void: rejection[0] = reason
	)
	for j in commands.size():
		var command := CommandCodec.from_dict(commands[j])
		if command == null:
			return "command %d: invalid" % j
		if not battle.execute(command):
			return "command %d: %s" % [j, rejection[0]]
	if result.resolution == BattleResult.CONCLUDED:
		var rest := AutoResolve.resolve_from(setup, state)
		if state.is_over() or rest == null or rest.to_dict() != result.to_dict():
			return "result"
		return ""
	if not state.is_over():
		return "not_over"
	if BattleResult.from_battle(setup, state).to_dict() != result.to_dict():
		return "result"
	return ""
