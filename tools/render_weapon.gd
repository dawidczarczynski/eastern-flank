extends "res://tools/render_unit.gd"
## Renders one strike weapon model (src/presentation/models/weapons/, TASK-144) with the unit
## render sheet: same scene, grid, views and stats as tools/render_unit.gd. Run via
## `tools/render_unit.sh --weapon <means_id> [--views=...] [--reference=path] [--out=sheet.png]`.
##
## Weapon models are built in metres (1 unit = 1 m, origin at the centre of mass); here they are
## scaled to the unit sheet's model space (1 unit = 10 m, the grid's faint lines every 1 m) and
## set on the ground (lowest point y = 0, centred in x/z), so the stats line's AABB is in metres.
## Real dimensions and the default reference come from docs/design/units/weapons/<id>/unit.json.
## The default sheet is .screenshots/units/<id>_sheet.png; `--faction` is ignored, `--pose` must
## stay `rest`.

const WEAPON_CATALOG_DIR := "res://docs/design/units/weapons"


func _parse_arguments() -> Dictionary:
	var args := OS.get_cmdline_user_args()
	var options := RenderUnitOptions.parse(
		args, WEAPON_CATALOG_DIR, Callable(WeaponModels, "has_model")
	)
	if options["error"] != "":
		return options
	if options["pose"] != RenderUnitOptions.DEFAULT_POSE:
		options["error"] = "unknown_pose"
		return options
	var has_out := false
	for arg in args:
		has_out = has_out or arg.begins_with("--out=")
	if not has_out:
		options["out"] = (
			ProjectSettings
			. globalize_path(
				(
					"%s/%s%s"
					% [
						RenderUnitOptions.DEFAULT_OUT_DIR,
						options["unit_id"],
						RenderUnitOptions.SHEET_SUFFIX,
					]
				)
			)
		)
	return options


func _build_model() -> Node3D:
	var holder := Node3D.new()
	_model = WeaponModels.build(StringName(_options["unit_id"]))
	_model.scale = Vector3.ONE / UnitModels.METERS_PER_UNIT
	holder.add_child(_model)
	var box := _visible_aabb(holder)
	var centre := box.get_center()
	_model.position = Vector3(-centre.x, -box.position.y, -centre.z)
	return holder
