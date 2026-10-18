extends RefCounted
## Pure argument parsing for tools/render_unit.gd (no rendering, tested headless).
## Usage: RenderUnitOptions.parse(["cavalry", "--faction=russia", "--views=side,top"])
## -> {"unit_id": String, "faction": String, "views": Array[String], "reference": String,
##     "out": String, "real": Dictionary, "error": String}; "error" is "" on success, else one of
##     missing_unit_id, invalid_unit_id, too_many_arguments, unknown_option, unknown_unit,
##     unknown_faction, unknown_view, invalid_views, empty_option (a flag with an empty value),
##     reference_not_found. A flag given twice: the last value wins.
## "out" is the sheet path; per-view PNGs go next to it (see view_path). "reference" is "" when
## there is none. "real" holds the catalog's real dimensions in metres ({"length", "width",
## "height"}) or is empty. Unit catalog entries: docs/design/units/units/<id>/unit.json.

const DEFAULT_CATALOG_DIR := "res://docs/design/units/units"
const DEFAULT_OUT_DIR := "res://.screenshots/units"
const DEFAULT_FACTION := "poland"
const VIEWS: Array[String] = ["side", "front", "top", "three_quarter"]
## Catalog image views usable as the default reference, best first.
const REFERENCE_VIEWS: Array[String] = ["side", "drawing"]
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
		"real": {},
		"error": "",
	}
	var faction := ""
	var views_spec := ""
	var reference := ""
	var out := ""
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
		elif arg.begins_with("-"):
			return _with_error(result, "unknown_option")
		else:
			positional += 1
			if positional > 1:
				return _with_error(result, "too_many_arguments")
			result["unit_id"] = arg
	for flag in ["--faction=", "--out=", "--reference="]:
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


## Absolute path of the first side (else drawing) image of the entry that exists on disk, or "".
static func default_reference(
	entry: Dictionary, unit_id: String, catalog_dir: String = DEFAULT_CATALOG_DIR
) -> String:
	var images: Variant = entry.get("images", [])
	if not images is Array:
		return ""
	for view in REFERENCE_VIEWS:
		for image: Variant in images:
			if not image is Dictionary or image.get("view", "") != view:
				continue
			var path := "%s/%s/%s" % [catalog_dir, unit_id, image.get("file", "")]
			if image.get("file", "") != "" and FileAccess.file_exists(path):
				return ProjectSettings.globalize_path(path)
	return ""


## Real dimensions in metres: length = overall_length (else hull_length), width, height; {} unless
## all three are known and positive.
static func real_dimensions(entry: Dictionary) -> Dictionary:
	var dimensions: Variant = entry.get("dimensions", {})
	if not dimensions is Dictionary:
		return {}
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
## "Real: 9.5x3.6x2.2 m, diff: +3.0%/-1.0%/+2.0%" (length/width/height). "" without real data.
static func real_line(aabb_m: Vector3, real: Dictionary) -> String:
	if real.is_empty():
		return ""
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
