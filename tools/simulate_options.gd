extends RefCounted
## Pure argument parsing for tools/simulate.gd (no engine state, tested headless).
## Usage: SimulateOptions.parse(["100", "--seed=5", "--max-turns=30", "--factions=russia,poland",
##                               "--verbose"])
## -> {"count", "seed", "max_turns", "factions", "verbose", "error"}; "error" is "" on success.
## "--factions=<p0>,<p1>" takes exactly two known faction ids (FactionRegistry).

const DEFAULT_SEED := 1
const DEFAULT_MAX_TURNS := 50


static func parse(args: PackedStringArray) -> Dictionary:
	var result := {
		"count": 0,
		"seed": DEFAULT_SEED,
		"max_turns": DEFAULT_MAX_TURNS,
		"factions": FactionRegistry.DEFAULT_IDS.duplicate(),
		"verbose": false,
		"error": "",
	}
	var have_count := false
	for arg in args:
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
		elif arg.begins_with("-") and not arg.is_valid_int():
			return _with_error(result, "unknown_option")
		elif have_count or not arg.is_valid_int() or arg.to_int() < 1:
			return _with_error(result, "invalid_count")
		else:
			have_count = true
			result["count"] = arg.to_int()
	if not have_count:
		return _with_error(result, "missing_count")
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
