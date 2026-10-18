extends RefCounted
## Pure argument parsing for tools/simulate.gd (no engine state, tested headless).
## Usage: SimulateOptions.parse(["100", "--seed=5", "--max-turns=30", "--verbose"])
## -> {"count", "seed", "max_turns", "verbose", "error"}; "error" is "" on success.

const DEFAULT_SEED := 1
const DEFAULT_MAX_TURNS := 50


static func parse(args: PackedStringArray) -> Dictionary:
	var result := {
		"count": 0,
		"seed": DEFAULT_SEED,
		"max_turns": DEFAULT_MAX_TURNS,
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


static func _with_error(result: Dictionary, error: String) -> Dictionary:
	result["error"] = error
	return result
