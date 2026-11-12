extends RefCounted
## Pure argument parsing for tools/simulate.gd (no engine state, tested headless).
## Usage: SimulateOptions.parse(["100", "--seed=5", "--max-turns=30", "--factions=russia,poland",
##                               "--scenario=objective_battle", "--verbose"])
## -> {"count", "seed", "max_turns", "factions", "scenario", "verbose", "error"}; "error" is "" on
## success. "--factions=<p0>,<p1>" takes exactly two known faction ids (FactionRegistry);
## "--scenario=<name>" one of Scenario.NAMES (default "default_battle").
## TASK-103a: "--mode=tactical|operation" (default tactical). Operation mode adds "--max-rounds=R"
## (int >= 1; result "max_rounds", 0 = the operation's own cap), "--battles=auto|played" and
## "--out=<path>"; "--scenario" is then an operation id (default "suwalki_gap", checked at run
## time) and "--max-turns" / "--factions" are rejected; "--max-rounds" / "--battles" / "--out"
## are rejected in tactical mode ("error" = "wrong_mode_option").

const DEFAULT_SEED := 1
const DEFAULT_MAX_TURNS := 50
const DEFAULT_OPERATION := "suwalki_gap"
const OPERATION_ONLY := ["--max-rounds=", "--battles=", "--out="]
const TACTICAL_ONLY := ["--max-turns=", "--factions="]


static func parse(args: PackedStringArray) -> Dictionary:
	var result := {
		"count": 0,
		"seed": DEFAULT_SEED,
		"max_turns": DEFAULT_MAX_TURNS,
		"factions": FactionRegistry.DEFAULT_IDS.duplicate(),
		"scenario": "default_battle",
		"verbose": false,
		"mode": "tactical",
		"max_rounds": 0,
		"battles": "auto",
		"out": "",
		"error": "",
	}
	var have_count := false
	var scenario_given := false
	var seen: Array[String] = []
	for arg in args:
		for prefix in OPERATION_ONLY + TACTICAL_ONLY:
			if arg.begins_with(prefix):
				seen.append(prefix)
		if arg == "--verbose":
			result["verbose"] = true
		elif arg.begins_with("--seed="):
			var value := arg.substr("--seed=".length())
			if not value.is_valid_int():
				return _with_error(result, "invalid_seed")
			result["seed"] = value.to_int()
		elif arg.begins_with("--max-turns="):
			var value := arg.substr("--max-turns=".length())
			if not value.is_valid_int() or value.to_int() < 1:
				return _with_error(result, "invalid_max_turns")
			result["max_turns"] = value.to_int()
		elif arg.begins_with("--factions="):
			var factions := _parse_factions(arg.substr("--factions=".length()))
			if factions.is_empty():
				return _with_error(result, "invalid_factions")
			result["factions"] = factions
		elif arg.begins_with("--scenario="):
			result["scenario"] = arg.substr("--scenario=".length())
			scenario_given = true
		elif arg.begins_with("--mode="):
			var mode := arg.substr("--mode=".length())
			if mode != "tactical" and mode != "operation":
				return _with_error(result, "invalid_mode")
			result["mode"] = mode
		elif arg.begins_with("--max-rounds="):
			var value := arg.substr("--max-rounds=".length())
			if not value.is_valid_int() or value.to_int() < 1:
				return _with_error(result, "invalid_max_rounds")
			result["max_rounds"] = value.to_int()
		elif arg.begins_with("--battles="):
			var value := arg.substr("--battles=".length())
			if value != "auto" and value != "played":
				return _with_error(result, "invalid_battles")
			result["battles"] = value
		elif arg.begins_with("--out="):
			result["out"] = arg.substr("--out=".length())
			if result["out"] == "":
				return _with_error(result, "invalid_out")
		elif arg.begins_with("-") and not arg.is_valid_int():
			return _with_error(result, "unknown_option")
		elif have_count or not arg.is_valid_int() or arg.to_int() < 1:
			return _with_error(result, "invalid_count")
		else:
			have_count = true
			result["count"] = arg.to_int()
	if not have_count:
		return _with_error(result, "missing_count")
	if result["mode"] == "operation":
		for prefix in TACTICAL_ONLY:
			if seen.has(prefix):
				return _with_error(result, "wrong_mode_option")
		if not scenario_given:
			result["scenario"] = DEFAULT_OPERATION
	else:
		for prefix in OPERATION_ONLY:
			if seen.has(prefix):
				return _with_error(result, "wrong_mode_option")
		if not Scenario.NAMES.has(result["scenario"]):
			return _with_error(result, "invalid_scenario")
	return result


## Two known faction ids separated by a comma; empty on anything else.
static func _parse_factions(value: String) -> Array[StringName]:
	var result: Array[StringName] = []
	var parts := value.split(",")
	if parts.size() != 2:
		return result
	for part in parts:
		if not FactionRegistry.has_faction(StringName(part)):
			return [] as Array[StringName]
		result.append(StringName(part))
	return result


static func _with_error(result: Dictionary, error: String) -> Dictionary:
	result["error"] = error
	return result
