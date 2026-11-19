extends RefCounted
## Pure argument parsing for tools/render_unit.gd (no rendering, tested headless).
## Usage: RenderUnitOptions.parse(["t72b3", "--faction=russia", "--views=side,top"])
## -> {"unit_id": String, "faction": String, "views": Array[String], "reference": String,
##     "out": String, "pose": String, "soldier": int, "real": Dictionary, "error": String};
##     "error" is "" on success, else one of missing_unit_id, invalid_unit_id, too_many_arguments,
##     unknown_option, unknown_unit, unknown_faction, unknown_view, invalid_views, unknown_pose,
##     invalid_soldier, invalid_soldier_yaw (also a yaw without --soldier), empty_option (a flag
##     with an empty value), reference_not_found. A flag given twice: the last value wins.
## "soldier" is -1, or the squad slot of `--soldier=<i>`: only that soldier is shown, at the
## origin facing +X turned by "soldier_yaw" (`--soldier-yaw=<deg>`, + = left, default 0;
## `isolate_soldier`) – to judge one figure or compare it with a one-soldier reference GLB whose
## figure is turned (tools/compare_silhouette.sh).
## "pose" is one of POSES: "rest" (as built) or "fire" (a launcher at traverse 0 and its
## max_elevation_deg, to check the actuators at full extension).
## "out" is the sheet path; per-view PNGs go next to it (see view_path). "reference" is "" when
## there is none. "real" holds the catalog's real dimensions in metres ({"length", "width",
## "height"}; only {"height"} for a foot unit, whose entry describes one soldier) or is
## empty. Unit catalog entries: docs/design/units/units/<id>/unit.json.

const DEFAULT_CATALOG_DIR := "res://docs/design/units/units"
const DEFAULT_OUT_DIR := "res://.screenshots/units"
const DEFAULT_FACTION := "poland"
const VIEWS: Array[String] = ["side", "front", "top", "three_quarter"]
const POSES: Array[String] = ["rest", "fire"]
const DEFAULT_POSE := "rest"
## Catalog image views usable as the default reference, best first.
const REFERENCE_VIEWS: Array[String] = ["side", "drawing"]
## Foot units (squads): there are no drawings of soldiers, any photo of a soldier is a reference.
const FOOT_REFERENCE_VIEWS: Array[String] = ["side", "front", "three_quarter", "drawing"]
const SHEET_SUFFIX := "_sheet.png"


## `catalog_dir` and `model_exists` (Callable(unit_id: StringName) -> bool) are injectable for
## tests; by default the project's catalog and UnitModels.has_model are used.
static func parse(
	args: PackedStringArray,
	catalog_dir: String = DEFAULT_CATALOG_DIR,
	model_exists: Callable = Callable()
) -> Dictionary:
	var result := {
		"unit_id": "",
		"faction": "",
		"views": VIEWS.duplicate(),
		"reference": "",
		"out": "",
		"pose": DEFAULT_POSE,
		"soldier": -1,
		"soldier_yaw": 0.0,
		"real": {},
		"error": "",
	}
	var faction := ""
	var views_spec := ""
	var reference := ""
	var out := ""
	var pose := DEFAULT_POSE
	var soldier := ""
	var soldier_yaw := ""
	var positional := 0
	for arg in args:
		if arg.begins_with("--faction="):
			faction = arg.substr("--faction=".length())
		elif arg.begins_with("--views="):
			views_spec = arg.substr("--views=".length())
		elif arg.begins_with("--reference="):
			reference = arg.substr("--reference=".length())
		elif arg.begins_with("--out="):
			out = arg.substr("--out=".length())
		elif arg.begins_with("--pose="):
			pose = arg.substr("--pose=".length())
		elif arg.begins_with("--soldier="):
			soldier = arg.substr("--soldier=".length())
		elif arg.begins_with("--soldier-yaw="):
			soldier_yaw = arg.substr("--soldier-yaw=".length())
		elif arg.begins_with("-"):
			return _with_error(result, "unknown_option")
		else:
			positional += 1
			if positional > 1:
				return _with_error(result, "too_many_arguments")
			result["unit_id"] = arg
	for flag in ["--faction=", "--out=", "--reference=", "--pose=", "--soldier=", "--soldier-yaw="]:
		for arg in args:
			if arg == flag:
				return _with_error(result, "empty_option")
	var unit_id: String = result["unit_id"]
	if unit_id == "":
		return _with_error(result, "missing_unit_id")
	if not _is_valid_id(unit_id):
		return _with_error(result, "invalid_unit_id")
	if views_spec != "" or _has_prefix(args, "--views="):
		var views := parse_views(views_spec)
		if views.is_empty():
			return _with_error(result, "invalid_views")
		for view in views:
			if view not in VIEWS:
				return _with_error(result, "unknown_view")
		result["views"] = views
	if pose not in POSES:
		return _with_error(result, "unknown_pose")
	result["pose"] = pose
	if soldier != "":
		if not soldier.is_valid_int() or soldier.to_int() < 0:
			return _with_error(result, "invalid_soldier")
		result["soldier"] = soldier.to_int()
	if soldier_yaw != "":
		if not soldier_yaw.is_valid_float() or soldier == "":
			return _with_error(result, "invalid_soldier_yaw")
		result["soldier_yaw"] = soldier_yaw.to_float()
	var exists := model_exists if model_exists.is_valid() else _model_exists
	if not exists.call(StringName(unit_id)):
		return _with_error(result, "unknown_unit")
	var entry := load_catalog_entry(unit_id, catalog_dir)
	if faction == "":
		faction = default_faction(entry)
	elif not FactionRegistry.has_faction(StringName(faction)):
		return _with_error(result, "unknown_faction")
	result["faction"] = faction
	result["real"] = real_dimensions(entry)
	if reference != "":
		if not FileAccess.file_exists(reference):
			return _with_error(result, "reference_not_found")
		result["reference"] = reference
	else:
		result["reference"] = default_reference(entry, unit_id, catalog_dir)
	result["out"] = out if out != "" else default_out(unit_id, faction)
	return result


## Shows only the squad's "Soldier<index>" pivot of `model` (the other soldiers hidden), moved to
## the origin and facing +X turned by `yaw_deg` (+ = left). Returns false when `model` has no such
## pivot.
static func isolate_soldier(model: Node3D, index: int, yaw_deg := 0.0) -> bool:
	var keep := model.get_node_or_null("Soldier%d" % index) as Node3D
	if keep == null:
		return false
	for child in model.get_children():
		if child is Node3D and String(child.name).begins_with("Soldier"):
			(child as Node3D).visible = child == keep
	keep.position = Vector3.ZERO
	keep.rotation.y = deg_to_rad(yaw_deg)
	return true


## "side,top" -> ["side", "top"]; duplicates are dropped, order is kept; a blank entry gives [].
static func parse_views(spec: String) -> Array[String]:
	var views: Array[String] = []
	for part in spec.split(","):
		var view := part.strip_edges()
		if view == "":
			return []
		if view not in views:
			views.append(view)
	return views


## The catalog entry (unit.json) of a unit, {} when there is none or it is unreadable.
static func load_catalog_entry(
	unit_id: String, catalog_dir: String = DEFAULT_CATALOG_DIR
) -> Dictionary:
	var path := "%s/%s/unit.json" % [catalog_dir, unit_id]
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## First operator of the entry that is a known faction, else poland.
static func default_faction(entry: Dictionary) -> String:
	var operators: Variant = entry.get("operators", [])
	if operators is Array:
		for operator_id: Variant in operators:
			if operator_id is String and FactionRegistry.has_faction(StringName(operator_id)):
				return operator_id
	return DEFAULT_FACTION


## Absolute path of the first existing image of the entry in reference-view order (side, else
## drawing; foot units also front and three-quarter photos), or "".
static func default_reference(
	entry: Dictionary, unit_id: String, catalog_dir: String = DEFAULT_CATALOG_DIR
) -> String:
	var images: Variant = entry.get("images", [])
	if not images is Array:
		images = []
	var views := FOOT_REFERENCE_VIEWS if _is_foot(entry) else REFERENCE_VIEWS
	for view in views:
		for image: Variant in images:
			if not image is Dictionary or image.get("view", "") != view:
				continue
			var path := "%s/%s/%s" % [catalog_dir, unit_id, image.get("file", "")]
			if image.get("file", "") != "" and FileAccess.file_exists(path):
				return ProjectSettings.globalize_path(path)
	# No photo: the side view rendered from the unit's reference GLB (tools/analyze_glb.sh).
	var glb_side := "%s/%s/reference_views/glb_side.png" % [catalog_dir, unit_id]
	if FileAccess.file_exists(glb_side):
		return ProjectSettings.globalize_path(glb_side)
	return ""


## Real dimensions in metres: length = overall_length (else hull_length), width, height; {} unless
## all three are known and positive. A foot unit gives only {"height"}: its entry describes one
## soldier, while the model is a whole squad whose footprint has nothing to compare against.
static func real_dimensions(entry: Dictionary) -> Dictionary:
	var dimensions: Variant = entry.get("dimensions", {})
	if not dimensions is Dictionary:
		return {}
	if _is_foot(entry):
		var soldier_height := float(dimensions.get("height", 0.0))
		return {"height": soldier_height} if soldier_height > 0.0 else {}
	var length := float(dimensions.get("overall_length", dimensions.get("hull_length", 0.0)))
	var width := float(dimensions.get("width", 0.0))
	var height := float(dimensions.get("height", 0.0))
	if length <= 0.0 or width <= 0.0 or height <= 0.0:
		return {}
	return {"length": length, "width": width, "height": height}


static func default_out(unit_id: String, faction: String) -> String:
	return ProjectSettings.globalize_path(
		"%s/%s_%s%s" % [DEFAULT_OUT_DIR, unit_id, faction, SHEET_SUFFIX]
	)


## PNG path of one view next to the sheet: `<sheet without _sheet.png>_<view>.png`.
static func view_path(sheet_path: String, view: String) -> String:
	var base := sheet_path
	if base.ends_with(SHEET_SUFFIX):
		base = base.left(base.length() - SHEET_SUFFIX.length())
	else:
		base = base.get_basename()
	return "%s_%s.png" % [base, view]


## Model size (metres, x = length, y = height, z = width) vs. the real dimensions:
## "Real: 9.5x3.6x2.2 m, diff: +3.0%/-1.0%/+2.0%" (length/width/height), for a foot unit
## "Real: soldier height 1.8 m, diff: +10.0%". "" without real data.
static func real_line(aabb_m: Vector3, real: Dictionary) -> String:
	if real.is_empty():
		return ""
	if not real.has("length"):
		var soldier_height: float = real["height"]
		return (
			"Real: soldier height %s m, diff: %s"
			% [_trim(soldier_height), _diff(aabb_m.y, soldier_height)]
		)
	var length: float = real["length"]
	var width: float = real["width"]
	var height: float = real["height"]
	return (
		"Real: %sx%sx%s m, diff: %s/%s/%s"
		% [
			_trim(length),
			_trim(width),
			_trim(height),
			_diff(aabb_m.x, length),
			_diff(aabb_m.z, width),
			_diff(aabb_m.y, height),
		]
	)


## Compact list of pivot names: unique names in first-seen order, numbered runs collapsed
## (["Wheel0", "Wheel1", "Wheel2", "Turret"] -> "Wheel0-2,Turret").
static func summarize_names(names: Array) -> String:
	var order: Array[String] = []  # prefix or plain name, first-seen order
	var runs := {}  # prefix -> Array[int]
	var seen := {}
	for name_value: Variant in names:
		var node_name := String(name_value)
		if seen.has(node_name):
			continue
		seen[node_name] = true
		var digits := 0
		while (
			digits < node_name.length()
			and node_name[node_name.length() - 1 - digits].is_valid_int()
		):
			digits += 1
		if digits == 0 or digits == node_name.length():
			order.append(node_name)
			continue
		var prefix := node_name.left(node_name.length() - digits)
		if not runs.has(prefix):
			runs[prefix] = []
			order.append("#" + prefix)
		runs[prefix].append(node_name.right(digits).to_int())
	var parts: PackedStringArray = []
	for item in order:
		if not item.begins_with("#"):
			parts.append(item)
			continue
		var prefix := item.substr(1)
		var numbers: Array = runs[prefix]
		numbers.sort()
		parts.append_array(_number_runs(prefix, numbers))
	return ",".join(parts)


## One vertical ortho size for side, front and top (same scale): the largest horizontal extent
## (model length for side and top, width for front) and vertical extent (height for side and
## front, width for top) any view needs, plus MARGIN, fitted to the aspect ratio.
static func ortho_size(aabb: AABB, aspect: float, margin: float = 1.1) -> float:
	var needed_width := maxf(aabb.size.x, aabb.size.z)
	var needed_height := maxf(aabb.size.y, aabb.size.z)
	return maxf(needed_height, needed_width / aspect) * margin


static func _number_runs(prefix: String, numbers: Array) -> PackedStringArray:
	var parts: PackedStringArray = []
	var start: int = numbers[0]
	var previous := start
	for i in range(1, numbers.size() + 1):
		if i < numbers.size() and numbers[i] == previous + 1:
			previous = numbers[i]
			continue
		parts.append(
			"%s%d" % [prefix, start] if previous == start else "%s%d-%d" % [prefix, start, previous]
		)
		if i < numbers.size():
			start = numbers[i]
			previous = start
	return parts


static func _diff(model: float, real: float) -> String:
	var text := "%+.1f%%" % ((model - real) / real * 100.0)
	return "+0.0%" if text == "-0.0%" else text


static func _trim(value: float) -> String:
	return ("%.2f" % value).rstrip("0").rstrip(".")


static func _is_valid_id(unit_id: String) -> bool:
	if unit_id.length() < 2 or unit_id.length() > 48:
		return false
	for character in unit_id:
		if (
			not (character >= "a" and character <= "z")
			and not (character >= "0" and character <= "9")
			and character != "_"
		):
			return false
	return true


static func _has_prefix(args: PackedStringArray, prefix: String) -> bool:
	for arg in args:
		if arg.begins_with(prefix):
			return true
	return false


static func _model_exists(unit_id: StringName) -> bool:
	return UnitModels.has_model(unit_id)


static func _with_error(result: Dictionary, error: String) -> Dictionary:
	result["error"] = error
	return result


static func _is_foot(entry: Dictionary) -> bool:
	return entry.get("mobility", "") == "foot"
