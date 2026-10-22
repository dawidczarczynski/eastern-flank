extends RefCounted
## Pure argument parsing for tools/screenshot.gd (no engine state, tested headless).
## Usage: ScreenshotOptions.parse(["out.png", "--frames=30"])
## -> {"output": String, "frames": int, "error": String}; "error" is "" on success.
## ScreenshotOptions.parse_camera("3,-30,12") (SCREENSHOT_CAMERA: unit id, yaw in degrees, distance)
## -> {"unit_id": int, "yaw_degrees": float, "distance": float, "error": String};
## "error" is "none" for an empty spec (keep the default camera), "invalid_camera" if malformed.
## ScreenshotOptions.parse_focus("14.7,4.5,-30,7") (SCREENSHOT_FOCUS: world x, world z, yaw in
## degrees, distance) -> {"target": Vector2, "yaw_degrees": float, "distance": float, "error"};
## "error" is "none" for an empty spec, "invalid_focus" if malformed.
## ScreenshotOptions.parse_measure_frames("120") (SCREENSHOT_MEASURE_FRAMES) -> frames to time
## after the warm-up (0 = no measurement, capped at MAX_FRAMES).

const DEFAULT_FRAMES := 10
const MIN_FRAMES := 1
const MAX_FRAMES := 600
const FRAMES_PREFIX := "--frames="
const QUALITY_PREFIX := "--quality="


static func parse(args: PackedStringArray) -> Dictionary:
	var result := {"output": "", "frames": DEFAULT_FRAMES, "error": ""}
	var positional := 0
	for arg in args:
		if arg.begins_with(FRAMES_PREFIX):
			var value := arg.substr(FRAMES_PREFIX.length())
			if not value.is_valid_int() or not _frames_in_range(value.to_int()):
				return _with_error(result, "invalid_frames")
			result["frames"] = value.to_int()
		elif arg.to_lower().begins_with(QUALITY_PREFIX):
			pass  # read by the battle scene itself (GraphicsQuality.parse_override)
		elif arg.begins_with("-"):
			return _with_error(result, "unknown_option")
		else:
			positional += 1
			if positional > 1:
				return _with_error(result, "too_many_arguments")
			result["output"] = arg
	return result


static func parse_camera(spec: String) -> Dictionary:
	var result := {"unit_id": -1, "yaw_degrees": 0.0, "distance": 0.0, "error": ""}
	if spec.strip_edges() == "":
		return _with_error(result, "none")
	var parts := spec.split(",")
	if parts.size() != 3:
		return _with_error(result, "invalid_camera")
	var unit := parts[0].strip_edges()
	var yaw := parts[1].strip_edges()
	var distance := parts[2].strip_edges()
	if not unit.is_valid_int() or not yaw.is_valid_float() or not distance.is_valid_float():
		return _with_error(result, "invalid_camera")
	if distance.to_float() <= 0.0:
		return _with_error(result, "invalid_camera")
	result["unit_id"] = unit.to_int()
	result["yaw_degrees"] = yaw.to_float()
	result["distance"] = distance.to_float()
	return result


static func parse_focus(spec: String) -> Dictionary:
	var result := {"target": Vector2.ZERO, "yaw_degrees": 0.0, "distance": 0.0, "error": ""}
	if spec.strip_edges() == "":
		return _with_error(result, "none")
	var parts := spec.split(",")
	if parts.size() != 4:
		return _with_error(result, "invalid_focus")
	var values: Array[float] = []
	for part in parts:
		var text := part.strip_edges()
		if not text.is_valid_float():
			return _with_error(result, "invalid_focus")
		values.append(text.to_float())
	if values[3] <= 0.0:
		return _with_error(result, "invalid_focus")
	result["target"] = Vector2(values[0], values[1])
	result["yaw_degrees"] = values[2]
	result["distance"] = values[3]
	return result


static func parse_measure_frames(spec: String) -> int:
	var text := spec.strip_edges()
	if not text.is_valid_int() or text.to_int() <= 0:
		return 0
	return mini(text.to_int(), MAX_FRAMES)


static func _frames_in_range(frames: int) -> bool:
	return frames >= MIN_FRAMES and frames <= MAX_FRAMES


static func _with_error(result: Dictionary, error: String) -> Dictionary:
	result["error"] = error
	return result
