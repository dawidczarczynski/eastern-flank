class_name WaterErrorOverlay
extends Node3D
## Devtools overlay "Water errors" (TASK-223a, ADR 0034): one pillar per WaterValidator violation of
## the map on screen, coloured per rule; pointing at one shows its rule, value and limit. Built only
## while DevTunables.water_errors is on, so it costs nothing when off.

const PILLAR_HEIGHT_M := 40.0
const PILLAR_WIDTH_M := 5.0
const HOVER_PIXELS := 18.0
const COLOURS := {
	&"surface_rises": Color("#ff3b30"),
	&"junction_step": Color("#ff9500"),
	&"lake_step": Color("#ffd60a"),
	&"dry_bed": Color("#c8a2ff"),
	&"flooded_bank": Color("#32ade6"),
	&"shallow": Color("#34c759"),
	&"width_jump": Color("#ff2d95"),
	&"bridge_short": Color("#ffffff"),
	&"steep_water": Color("#8e5a2b"),
}

var _violations: Array[Dictionary] = []
var _tops: Array[Vector3] = []
var _label := Label.new()


## Adds an overlay for `grid` drawn over `surface` to `parent`, with its hover label on `hud`.
static func create(
	parent: Node, hud: CanvasLayer, grid: HexGrid, surface: TerrainSurface
) -> WaterErrorOverlay:
	var overlay := WaterErrorOverlay.new()
	overlay.name = "WaterErrorOverlay"
	parent.add_child(overlay)
	overlay._build(WaterValidator.check(WaterSampleAdapter.build(grid, surface)), surface)
	overlay._label.name = "WaterErrorLabel"
	overlay._label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay._label.add_theme_color_override(&"font_color", Color.WHITE)
	overlay._label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	overlay._label.add_theme_constant_override(&"outline_size", 4)
	overlay._label.visible = false
	hud.add_child(overlay._label)
	print("Water errors: %d violations" % overlay._violations.size())
	return overlay


## "dry_bed  2.17 / 0.05" text of a violation.
static func describe(violation: Dictionary) -> String:
	return "%s  %.2f / %.2f" % [violation["rule"], violation["value"], violation["limit"]]


func violation_count() -> int:
	return _violations.size()


func _build(violations: Array[Dictionary], surface: TerrainSurface) -> void:
	_violations = violations
	if violations.is_empty():
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(
		MapScale.to_units(PILLAR_WIDTH_M),
		MapScale.to_units(PILLAR_HEIGHT_M),
		MapScale.to_units(PILLAR_WIDTH_M)
	)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	mesh.material = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = violations.size()
	for i in violations.size():
		var at: Vector2 = violations[i]["position"]
		var base := Vector3(at.x, surface.height_at(at.x, at.y), at.y)
		var centre := base + Vector3.UP * (mesh.size.y * 0.5)
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, centre))
		multi.set_instance_color(i, COLOURS.get(violations[i]["rule"], Color.WHITE))
		_tops.append(base + Vector3.UP * mesh.size.y)
	var instance := MultiMeshInstance3D.new()
	instance.name = "Pillars"
	instance.multimesh = multi
	instance.custom_aabb = AABB(Vector3(-1e4, -1e4, -1e4), Vector3(2e4, 2e4, 2e4))
	add_child(instance)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _tops.is_empty():
		_label.visible = false
		return
	var mouse := get_viewport().get_mouse_position()
	var best := -1
	var best_d := HOVER_PIXELS
	for i in _tops.size():
		if camera.is_position_behind(_tops[i]):
			continue
		var d := camera.unproject_position(_tops[i]).distance_to(mouse)
		if d < best_d:
			best_d = d
			best = i
	_label.visible = best >= 0
	if best >= 0:
		_label.text = describe(_violations[best])
		_label.position = mouse + Vector2(14.0, 14.0)
