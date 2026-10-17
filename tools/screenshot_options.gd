extends RefCounted
## Pure argument parsing for tools/screenshot.gd (no engine state, tested headless).
## Usage: ScreenshotOptions.parse(["out.png", "--frames=30"])
## -> {"output": String, "frames": int, "error": String}; "error" is "" on success.

const DEFAULT_FRAMES := 10
const MIN_FRAMES := 1
const MAX_FRAMES := 600
const FRAMES_PREFIX := "--frames="


static func parse(args: PackedStringArray) -> Dictionary:
	var result := {"output": "", "frames": DEFAULT_FRAMES, "error": ""}
	var positional := 0
	for arg in args:
		if arg.begins_with(FRAMES_PREFIX):
			var value := arg.substr(FRAMES_PREFIX.length())
			if not value.is_valid_int() or not _frames_in_range(value.to_int()):
				return _with_error(result, "invalid_frames")
			result["frames"] = value.to_int()
		elif arg.begins_with("-"):
			return _with_error(result, "unknown_option")
		else:
			positional += 1
			if positional > 1:
				return _with_error(result, "too_many_arguments")
			result["output"] = arg
	return result


static func _frames_in_range(frames: int) -> bool:
	return frames >= MIN_FRAMES and frames <= MAX_FRAMES


static func _with_error(result: Dictionary, error: String) -> Dictionary:
	result["error"] = error
	return result
