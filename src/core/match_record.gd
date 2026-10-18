class_name MatchRecord
extends RefCounted
## A whole match as scenario + seed + executed commands (their `to_dict()` form).
## The state is never stored: Replay rebuilds it from the scenario and replays the commands.
## JSON format: {"version": 1, "scenario": "default_battle", "seed": 12345,
##               "factions": ["poland", "russia"], "commands": [...]}.
## "factions" (one id per player) is optional: records written before TASK-038 have none and
## load with FactionRegistry.DEFAULT_IDS.
## Extra top-level keys are ignored (the regression fixture adds "expected_final").
## The seed is written as a JSON number, so it must lie within +-2^53 to load back exactly.

const VERSION := 1

var version: int = VERSION
var scenario: String = "default_battle"
var seed: int
var factions: Array[StringName] = FactionRegistry.DEFAULT_IDS.duplicate()
var commands: Array[Dictionary] = []


## Record of every command the simulation has executed so far (`sim.history`).
static func from_simulation(sim: GameSimulation, seed_value: int) -> MatchRecord:
	var record := MatchRecord.new()
	record.seed = seed_value
	record.factions = sim.state.player_factions.duplicate()
	for command in sim.history:
		record.commands.append(command.to_dict())
	return record


## null on invalid JSON, `version != 1` or malformed fields (incl. "factions" that is not an
## array of strings; unknown ids are reported by Replay.run). Commands are not decoded here –
## Replay.run reports an undecodable command with its index.
static func from_json(text: String) -> MatchRecord:
	# JSON.new().parse() instead of JSON.parse_string(): no engine error log for bad input.
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return null
	return from_dict(json.data)


static func from_dict(d: Dictionary) -> MatchRecord:
	if CommandCodec.to_int_or_null(d.get("version")) != VERSION:
		return null
	var scenario_name: Variant = d.get("scenario")
	var seed_value: Variant = CommandCodec.to_int_or_null(d.get("seed"))
	var command_list: Variant = d.get("commands")
	if not scenario_name is String or seed_value == null or not command_list is Array:
		return null
	var record := MatchRecord.new()
	record.scenario = scenario_name
	record.seed = seed_value
	if d.has("factions"):
		var faction_list: Variant = d["factions"]
		if not faction_list is Array:
			return null
		record.factions.clear()
		for entry: Variant in faction_list:
			if not entry is String:
				return null
			record.factions.append(StringName(entry))
	for entry: Variant in command_list:
		if not entry is Dictionary:
			return null
		record.commands.append(entry)
	return record


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
