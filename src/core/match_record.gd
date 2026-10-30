class_name MatchRecord
extends RefCounted
## A whole match as scenario + seed + executed commands (their `to_dict()` form).
## The state is never stored: Replay rebuilds it from the scenario and replays the commands.
## JSON format: {"version": 2, "scenario": "default_battle", "seed": 12345,
##               "factions": ["poland", "russia"], "commands": [...]}.
## "factions" (one id per player) is required. Records of another version are rejected: version 1
## (before TASK-039a) spawned the generic infantry / cavalry / rocket artillery, which no longer
## exist, so its commands cannot be replayed (ADR-0009).
## Extra top-level keys are ignored (the regression fixture adds "expected_final").
## The seed is written as a JSON number, so it must lie within +-2^53 to load back exactly.

const VERSION := 2

var version: int = VERSION
var scenario: String = "default_battle"
var seed: int
var factions: Array[StringName] = FactionRegistry.DEFAULT_IDS.duplicate()
var commands: Array[Dictionary] = []


## Record of every command the simulation has executed so far (`sim.history`); `scenario` is the
## name the state was built from (Scenario.NAMES).
static func from_simulation(
	sim: GameSimulation, seed_value: int, scenario_name: String = "default_battle"
) -> MatchRecord:
	var record := MatchRecord.new()
	record.scenario = scenario_name
	record.seed = seed_value
	record.factions = sim.state.player_factions.duplicate()
	for command in sim.history:
		record.commands.append(command.to_dict())
	return record


## null on any failure of parse_json (see there).
static func from_json(text: String) -> MatchRecord:
	return parse_json(text)["record"] as MatchRecord


## {"record": MatchRecord, "error": ""} or {"record": null, "error": <readable message>} on
## invalid JSON, another `version` (an older record says it is unsupported) or malformed
## fields (incl. "factions" that is not an array of strings; unknown ids are reported by
## Replay.run). Commands are not decoded here – Replay.run reports an undecodable command with
## its index.
static func parse_json(text: String) -> Dictionary:
	# JSON.new().parse() instead of JSON.parse_string(): no engine error log for bad input.
	var json := JSON.new()
	if json.parse(text) != OK:
		return _parse_failure("Not a match record: invalid JSON (%s)." % json.get_error_message())
	if not json.data is Dictionary:
		return _parse_failure("Not a match record: the JSON is not an object.")
	return parse_dict(json.data)


static func from_dict(d: Dictionary) -> MatchRecord:
	return parse_dict(d)["record"] as MatchRecord


## Dictionary form of parse_json.
static func parse_dict(d: Dictionary) -> Dictionary:
	var found_version: Variant = CommandCodec.to_int_or_null(d.get("version"))
	if found_version == null:
		return _parse_failure("Not a match record: no format version.")
	if found_version != VERSION:
		return _parse_failure(
			(
				(
					"Match record version %d is unsupported (this build reads version %d only; "
					+ "records from before the real units of TASK-039a cannot be replayed)."
				)
				% [found_version, VERSION]
			)
		)
	var scenario_name: Variant = d.get("scenario")
	var seed_value: Variant = CommandCodec.to_int_or_null(d.get("seed"))
	var command_list: Variant = d.get("commands")
	var faction_list: Variant = d.get("factions")
	if not scenario_name is String:
		return _parse_failure('Malformed match record: "scenario" is not a string.')
	if seed_value == null:
		return _parse_failure('Malformed match record: "seed" is not an integer.')
	if not command_list is Array:
		return _parse_failure('Malformed match record: "commands" is not an array.')
	if not faction_list is Array:
		return _parse_failure('Malformed match record: "factions" is not an array.')
	var record := MatchRecord.new()
	record.scenario = scenario_name
	record.seed = seed_value
	record.factions.clear()
	for entry: Variant in faction_list:
		if not entry is String:
			return _parse_failure("Malformed match record: a faction id is not a string.")
		record.factions.append(StringName(entry))
	for entry: Variant in command_list:
		if not entry is Dictionary:
			return _parse_failure("Malformed match record: a command is not an object.")
		record.commands.append(entry)
	return {"record": record, "error": ""}


static func _parse_failure(message: String) -> Dictionary:
	return {"record": null, "error": message}


func to_dict() -> Dictionary:
	var faction_ids: Array[String] = []
	for faction_id in factions:
		faction_ids.append(String(faction_id))
	return {
		"version": version,
		"scenario": scenario,
		"seed": seed,
		"factions": faction_ids,
		"commands": commands,
	}


func to_json() -> String:
	return JSON.stringify(to_dict(), "\t", false)


## Copy of a parsed JSON value with integral floats turned back into ints (recursively), so that
## it compares equal to the original int-based data, e.g. `GameState.snapshot()`.
static func normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = normalize(value[key])
		return result
	if value is Array:
		var result := []
		for item: Variant in value:
			result.append(normalize(item))
		return result
	if value is float:
		var as_int: Variant = CommandCodec.to_int_or_null(value)
		return value if as_int == null else as_int
	return value
