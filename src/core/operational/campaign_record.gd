class_name CampaignRecord
extends RefCounted
## A whole campaign (TASK-094d, ADR 0015 §4) as operation id + seed + the executed operational
## commands (their `to_dict()` form, in order) + one entry per resolved battle. The state is never
## stored: `replay` rebuilds it with Operation.build and the commands. The human's side lives here
## (never in the state), so the same operation replays identically for either side.
## JSON: {"version": 1, "operation": "<id>", "seed": S, "human_side": "<side id>",
##        "commands": [<operational command dicts>],
##        "battles": [{"setup": <BattleSetup dict>, "commands": [<tactical command dicts>],
##                     "result": <BattleResult dict>, "resolution": "played" | "auto"}, ...]}.
## Battle k belongs to the k-th `resolve_battle` command; a pending (or running) battle has no
## entry – replaying the commands puts it back into `pending_battles` with the same setup and seed.
## Valid only for the rules and data it was recorded with (ADR 0005). The seed is a JSON number,
## so it must lie within +-2^53.
##
## Replay result: {"ok": true, "simulation": OperationalSimulation, "events": Array[Dictionary]}
## or {"ok": false, "error": <code>, "index": <command index or -1>, "battle": <battle index or
## -1>, "reason": <String>}. Codes: "unknown_operation", "invalid_side" (human_side is not a side
## of the operation), "invalid_command" (the codec cannot decode it), "diverged" (the operation
## rejected a command – "reason" is the validate() code – or, full replay, the operation's battle
## setup differs from the recorded one: reason "battle_setup"), "invalid_record" (resolve commands
## and battle entries do not pair up, or a resolve command's result is not its entry's result) and,
## full replay only, "battle_diverged" (the played battle replayed from its setup and commands
## ends with another result, a command is rejected or the battle does not end; an `auto` entry
## whose result differs from `AutoResolve.resolve(setup)`). An auto entry (TASK-120) stores the
## pending setup, `"commands": []` and `"resolution": "auto"`.

const VERSION := 1
const PLAYED := &"played"
const AUTO := &"auto"
const CONCLUDED := &"concluded"
const RESOLUTIONS: Array[StringName] = [PLAYED, AUTO, CONCLUDED]


## One resolved battle: the setup it was played from (the cut map, ContactBattle.prepare), its
## tactical commands and its result.
class Battle:
	extends RefCounted
	var setup: BattleSetup
	var commands: Array[Dictionary] = []
	var result: BattleResult
	var resolution: StringName = PLAYED

	## Entry of a played battle: `command_dicts` are its tactical commands in `to_dict()` form
	## (BattleReplay.command_dicts of the battle's history).
	static func played(
		p_setup: BattleSetup, command_dicts: Array[Dictionary], p_result: BattleResult
	) -> Battle:
		var entry := Battle.new()
		entry.setup = p_setup
		entry.result = p_result
		entry.commands = command_dicts.duplicate(true)
		return entry

	## Entry of a battle left halfway: the tactical commands played so far; the rest was
	## auto-resolved from the state they reached (AutoResolve.resolve_from).
	static func concluded(
		p_setup: BattleSetup, command_dicts: Array[Dictionary], p_result: BattleResult
	) -> Battle:
		var entry := Battle.played(p_setup, command_dicts, p_result)
		entry.resolution = CONCLUDED
		return entry

	## Entry of an auto-resolved battle (TASK-120): the pending setup, no tactical commands.
	static func auto(p_setup: BattleSetup, p_result: BattleResult) -> Battle:
		var entry := Battle.new()
		entry.setup = p_setup
		entry.result = p_result
		entry.resolution = AUTO
		return entry

	func to_dict() -> Dictionary:
		return {
			"setup": setup.to_dict(),
			"commands": commands.duplicate(true),
			"result": result.to_dict(),
			"resolution": String(resolution),
		}

	## null when a field is missing, malformed or a tactical command cannot be decoded.
	static func from_dict(d: Variant) -> Battle:
		if not d is Dictionary:
			return null
		var setup_value: Variant = d.get("setup")
		var result_value: Variant = d.get("result")
		var command_list: Variant = d.get("commands")
		var resolution_value: Variant = d.get("resolution")
		if not (setup_value is Dictionary and result_value is Dictionary):
			return null
		if not (command_list is Array and resolution_value is String):
			return null
		if not RESOLUTIONS.has(StringName(resolution_value as String)):
			return null
		var entry := Battle.new()
		entry.setup = BattleSetup.from_dict(setup_value)
		entry.result = BattleResult.from_dict(result_value)
		if entry.setup == null or entry.result == null:
			return null
		entry.resolution = StringName(resolution_value as String)
		var dicts: Variant = BattleReplay.canonical(command_list)
		if dicts == null:
			return null
		entry.commands = dicts
		return entry


var operation_id: StringName = &""
var seed: int = 0
## Side id (SideDefinition.id) the human plays; never part of the OperationalState.
var human_side: StringName = &""
var commands: Array[Dictionary] = []
var battles: Array[Battle] = []


## Record of every command `simulation` executed so far (its history) and the given battles.
static func from_simulation(
	simulation: OperationalSimulation,
	seed_value: int,
	side: StringName,
	played_battles: Array[Battle]
) -> CampaignRecord:
	var record := CampaignRecord.new()
	record.operation_id = simulation.state.operation_id
	record.seed = seed_value
	record.human_side = side
	for command in simulation.history:
		record.commands.append(command.to_dict())
	record.battles = played_battles.duplicate()
	return record


func to_dict() -> Dictionary:
	var battle_list: Array[Dictionary] = []
	for entry in battles:
		battle_list.append(entry.to_dict())
	return {
		"version": VERSION,
		"operation": String(operation_id),
		"seed": seed,
		"human_side": String(human_side),
		"commands": commands.duplicate(true),
		"battles": battle_list,
	}


func to_json() -> String:
	return JSON.stringify(to_dict(), "\t", false)


## null on invalid JSON or anything from_dict rejects.
static func from_json(text: String) -> CampaignRecord:
	# JSON.new().parse(): no engine error log for bad input.
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return null
	return from_dict(json.data)


## null when a key is missing, has the wrong type, the version differs or a command / battle
## entry cannot be decoded. Commands are kept in their canonical `to_dict()` form (JSON floats
## back to ints). Extra keys are ignored.
static func from_dict(d: Dictionary) -> CampaignRecord:
	var version_value: Variant = OperationalCommandCodec.to_int_or_null(d.get("version"))
	var seed_value: Variant = OperationalCommandCodec.to_int_or_null(d.get("seed"))
	var operation_value: Variant = d.get("operation")
	var side_value: Variant = d.get("human_side")
	var command_list: Variant = d.get("commands")
	var battle_list: Variant = d.get("battles")
	if version_value == null or version_value != VERSION or seed_value == null:
		return null
	if not (operation_value is String and side_value is String):
		return null
	if not (command_list is Array and battle_list is Array):
		return null
	var record := CampaignRecord.new()
	record.operation_id = StringName(operation_value as String)
	record.seed = seed_value
	record.human_side = StringName(side_value as String)
	for value: Variant in command_list:
		var command := OperationalCommandCodec.from_dict(value) if value is Dictionary else null
		if command == null:
			return null
		record.commands.append(command.to_dict())
	for value: Variant in battle_list:
		var entry := Battle.from_dict(value)
		if entry == null:
			return null
		record.battles.append(entry)
	return record


## The player whose side is `human_side` in `state`; -1 when it is none of them.
func human_player(state: OperationalState) -> int:
	return state.player_sides.find(human_side)


## Rebuilds the operation (Operation.build) and replays it; see the class doc for the result.
## `full` also re-plays every battle from its setup and tactical commands and checks the result.
func replay(full := false) -> Dictionary:
	if not Operation.NAMES.has(operation_id):
		return _failure("unknown_operation", -1, -1, "")
	var state := Operation.build(operation_id, seed)
	if state == null:
		return _failure("unknown_operation", -1, -1, "")
	return replay_on(state, full)


## replay on a freshly built `state` of this record's operation and seed (a caller that already
## has the grid builds it with Operation.from_definition).
func replay_on(state: OperationalState, full := false) -> Dictionary:
	if human_player(state) < 0:
		return _failure("invalid_side", -1, -1, String(human_side))
	var simulation := OperationalSimulation.new(state)
	var events: Array[Dictionary] = []
	var rejection: Array[String] = [""]
	simulation.event_emitted.connect(func(event: Dictionary) -> void: events.append(event))
	simulation.command_rejected.connect(
		func(_c: OperationalCommand, reason: String) -> void: rejection[0] = reason
	)
	var battle_index := 0
	for i in commands.size():
		var command := OperationalCommandCodec.from_dict(commands[i])
		if command == null:
			return _failure("invalid_command", i, -1, "")
		var resolve := command as ResolveBattleCommand
		if resolve != null:
			var problem := _check_battle(state, resolve, battle_index, i, full)
			if not problem.is_empty():
				return problem
			resolve.result = battles[battle_index].result
			battle_index += 1
		if not simulation.execute(command):
			return _failure("diverged", i, -1, rejection[0])
	if battle_index != battles.size():
		return _failure("invalid_record", -1, battle_index, "battle_without_resolve")
	return {"ok": true, "simulation": simulation, "events": events}


## {} when battle `k` may close the pending battle with `resolve` (command index `i`); else the
## failure. Full: the operation's battle equals the recorded setup and the battle replays to the
## recorded result.
func _check_battle(
	state: OperationalState, resolve: ResolveBattleCommand, k: int, i: int, full: bool
) -> Dictionary:
	if k >= battles.size():
		return _failure("invalid_record", i, k, "resolve_without_battle")
	var entry := battles[k]
	if resolve.result.to_dict() != entry.result.to_dict():
		return _failure("invalid_record", i, k, "result_differs")
	if not full:
		return {}
	if entry.resolution == AUTO:
		return _check_auto(state, entry, i, k)
	return _check_played(state, entry, i, k)


func _check_played(state: OperationalState, entry: Battle, i: int, k: int) -> Dictionary:
	var prepared := ContactBattle.prepare(state)
	if prepared == null or prepared.to_dict() != entry.setup.to_dict():
		return _failure("diverged", i, k, "battle_setup")
	var reason := BattleReplay.problem(entry.setup, entry.commands, entry.result)
	if reason != "":
		return _failure("battle_diverged", i, k, reason)
	return {}


## {} when an auto entry equals the pending setup itself (no cut map, no tactical commands) and
## its result is what AutoResolve computes from it.
func _check_auto(state: OperationalState, entry: Battle, i: int, k: int) -> Dictionary:
	if state.pending_battles[0].to_dict() != entry.setup.to_dict():
		return _failure("diverged", i, k, "battle_setup")
	var computed := AutoResolve.resolve(entry.setup)
	if computed == null or computed.to_dict() != entry.result.to_dict():
		return _failure("battle_diverged", i, k, "result")
	return {}


static func _failure(error: String, index: int, battle: int, reason: String) -> Dictionary:
	return {"ok": false, "error": error, "index": index, "battle": battle, "reason": reason}
