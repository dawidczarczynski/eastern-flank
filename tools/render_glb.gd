extends "res://tools/render_unit.gd"
## Renders the reference GLB of a unit (docs/design/units/units/<id>/reference.glb, TASK-179) with
## the unit render sheet: normalised to the catalog dimensions (tools/glb_reference.gd), same
## scene, grid, views and stats as tools/render_unit.gd. Run via `tools/analyze_glb.sh <id>`
## (or `tools/render_unit.sh --glb <id>`). Extra option `--front=+x|-x|+z|-z` (the GLB axis that
## points to the front; default: the narrower end of the longer horizontal axis).
## Writes `normalisation.json` next to the GLB; a bounding box more than 25 % off the catalog
## fails the run (exit 1) unless `--force` is given.

const GlbReference := preload("res://tools/glb_reference.gd")
const CATALOG := "res://docs/design/units/units"

var _front := ""
var _force := false


func _parse_arguments() -> Dictionary:
	var args := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--front="):
			_front = arg.substr("--front=".length())
		elif arg == "--force":
			_force = true
		else:
			args.append(arg)
	var options := RenderUnitOptions.parse(args, CATALOG, Callable(self, "_has_glb"))
	if options["error"] == "" and _front != "" and not GlbReference.FRONT_YAW_DEG.has(_front):
		options["error"] = "invalid_front"
	var has_out := false
	for arg in OS.get_cmdline_user_args():
		has_out = has_out or arg.begins_with("--out=")
	if options["error"] == "" and not has_out:
		options["out"] = ProjectSettings.globalize_path(
			"%s/%s/reference_views/glb_sheet.png" % [CATALOG, options["unit_id"]]
		)
	return options


func _has_glb(unit_id: StringName) -> bool:
	return FileAccess.file_exists("%s/%s/reference.glb" % [CATALOG, unit_id])


func _build_model() -> Node3D:
	var unit_id := String(_options["unit_id"])
	var path := ProjectSettings.globalize_path("%s/%s/reference.glb" % [CATALOG, unit_id])
	var scene := GlbReference.load_scene(path)
	if scene == null:
		_fail("cannot load a mesh from '%s'" % path, 1)
		return Node3D.new()
	var holder := Node3D.new()
	holder.add_child(scene)
	var result := GlbReference.normalise(scene, _options["real"], _front)
	var applied: Transform3D = scene.transform
	scene.transform = Transform3D(
		applied.basis / UnitModels.METERS_PER_UNIT, applied.origin / UnitModels.METERS_PER_UNIT
	)
	_model = scene
	_write_normalisation(unit_id, result)
	for warning: String in result["warnings"]:
		printerr("WARNING: ", warning)
	if not result["warnings"].is_empty() and not _force:
		_fail("the GLB deviates from the catalog dimensions (use --force to render anyway)", 1)
	return holder


func _write_normalisation(unit_id: String, result: Dictionary) -> void:
	var size: Vector3 = result["size_m"]
	var source: Vector3 = result["source_size"]
	var data := {
		"yaw_deg": result["yaw_deg"],
		"scale": result["scale"],
		"front_auto": result["front_auto"],
		"size_m": {"length": size.x, "height": size.y, "width": size.z},
		"source_size": {"x": source.x, "y": source.y, "z": source.z},
		"robust_height_m": result["robust_height_m"],
		"warnings": result["warnings"],
	}
	var file := FileAccess.open("%s/%s/normalisation.json" % [CATALOG, unit_id], FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  ") + "\n")
