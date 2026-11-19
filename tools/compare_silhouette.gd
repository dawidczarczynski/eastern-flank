extends SceneTree
## Compares the silhouettes of a unit's game model and its reference GLB (TASK-181) in the side,
## front and top view: IoU, area difference, a diff image per view and the largest mismatch
## regions. Run via tools/compare_silhouette.sh <unit_id> [--min-iou=0.90] [--pixel=0.02]
## [--front=+x|-x|+z|-z] [--faction=<id>]. Needs no rendering: both meshes are rasterised
## orthographically (tools/silhouette.gd) in metres, the GLB normalised as by tools/analyze_glb.sh
## (the front is taken from its normalisation.json unless --front is given) and both centred in
## x / z over their bounding boxes, standing on y = 0.
## Exit codes: 0 every IoU >= --min-iou, 1 below it / load failure, 2 invalid arguments.

const RenderUnitOptions := preload("res://tools/render_unit_options.gd")
const GlbReference := preload("res://tools/glb_reference.gd")
const Silhouette := preload("res://tools/silhouette.gd")
const CATALOG := "res://docs/design/units/units"
const OUT_DIR := "res://.screenshots/units"
const USAGE := (
	"Usage: tools/compare_silhouette.sh <unit_id> [--min-iou=0.90] [--pixel=0.02] "
	+ "[--front=+x|-x|+z|-z] [--faction=<id>]"
)
const DEFAULT_MIN_IOU := 0.90
const DEFAULT_PIXEL := 0.02
const REGIONS := 3
const ZOOM_PIXELS := 600  # diff images are scaled up to about this width


func _initialize() -> void:
	root.gui_disable_input = true
	var min_iou := DEFAULT_MIN_IOU
	var pixel := DEFAULT_PIXEL
	var front := ""
	var args := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--min-iou="):
			min_iou = arg.substr("--min-iou=".length()).to_float()
		elif arg.begins_with("--pixel="):
			pixel = arg.substr("--pixel=".length()).to_float()
		elif arg.begins_with("--front="):
			front = arg.substr("--front=".length())
		else:
			args.append(arg)
	var options := RenderUnitOptions.parse(args, CATALOG, Callable(self, "_has_glb"))
	if options["error"] == "" and (min_iou <= 0.0 or min_iou > 1.0 or pixel < 0.005):
		options["error"] = "invalid_number"
	if options["error"] == "" and front != "" and not GlbReference.FRONT_YAW_DEG.has(front):
		options["error"] = "invalid_front"
	if options["error"] != "":
		printerr("ERROR: invalid arguments (%s). %s" % [options["error"], USAGE])
		quit(2)
		return
	quit(_compare(options, min_iou, pixel, front))


func _has_glb(unit_id: StringName) -> bool:
	return FileAccess.file_exists("%s/%s/reference.glb" % [CATALOG, unit_id])


func _compare(options: Dictionary, min_iou: float, pixel: float, front: String) -> int:
	var unit_id := String(options["unit_id"])
	var reference := _reference_mesh(unit_id, options["real"], front)
	if reference.is_empty():
		printerr("ERROR: cannot load a mesh from reference.glb of '%s'" % unit_id)
		return 1
	var model := _model_mesh(unit_id, String(options["faction"]))
	if (model["positions"] as PackedVector3Array).is_empty():
		printerr("ERROR: the game model of '%s' has no visible triangles" % unit_id)
		return 1
	_align(model)
	_align(reference)
	var bounds := GlbReference.bounds(model["positions"]).merge(
		GlbReference.bounds(reference["positions"])
	)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var ious := {}
	var failed := false
	var all_regions: Array[String] = []
	var regions_by_area: Array[Dictionary] = []
	for view in Silhouette.VIEWS:
		var frame := Silhouette.frame(bounds, view, pixel)
		var model_mask := Silhouette.rasterize(model["positions"], model["indices"], view, frame)
		var reference_mask := Silhouette.rasterize(
			reference["positions"], reference["indices"], view, frame
		)
		var value := Silhouette.iou(model_mask, reference_mask)
		ious[view] = value
		failed = failed or value < min_iou
		var model_area := Silhouette.area_pixels(model_mask) * pixel * pixel
		var reference_area := Silhouette.area_pixels(reference_mask) * pixel * pixel
		print(
			(
				"%s: iou=%.3f model_area=%.2f m2 glb_area=%.2f m2 (%+.1f%%)"
				% [
					view,
					value,
					model_area,
					reference_area,
					(model_area - reference_area) / maxf(reference_area, 0.0001) * 100.0
				]
			)
		)
		var size: Vector2i = frame["size"]
		var zoom := maxi(1, ZOOM_PIXELS / maxi(size.x, 1))
		var image := Silhouette.diff_image(model_mask, reference_mask, size, view, zoom)
		var path := ProjectSettings.globalize_path("%s/%s_diff_%s.png" % [OUT_DIR, unit_id, view])
		if image.save_png(path) != OK:
			printerr("ERROR: could not save '%s'" % path)
			return 1
		print("Diff saved: ", path)
		for region in Silhouette.mismatch_regions(model_mask, reference_mask, frame, REGIONS):
			region["view"] = view
			regions_by_area.append(region)
	regions_by_area.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["area_m2"] > b["area_m2"]
	)
	for region in regions_by_area.slice(0, REGIONS):
		all_regions.append(Silhouette.describe_region(region, region["view"]))
	print(
		(
			"IoU side=%.2f front=%.2f top=%.2f (min %.2f: %s)"
			% [ious["side"], ious["front"], ious["top"], min_iou, "FAIL" if failed else "ok"]
		)
	)
	for line in all_regions:
		print("Mismatch: ", line)
	return 1 if failed else 0


## The reference GLB as triangles in metres, front +X, the same normalisation as analyze_glb.sh.
func _reference_mesh(unit_id: String, real: Dictionary, front: String) -> Dictionary:
	var folder := "%s/%s" % [CATALOG, unit_id]
	var scene := GlbReference.load_scene(ProjectSettings.globalize_path(folder + "/reference.glb"))
	if scene == null:
		return {}
	if front == "":
		front = _front_from_normalisation(folder + "/normalisation.json")
	GlbReference.normalise(scene, real, front)
	var mesh := GlbReference.triangles(scene)
	scene.free()
	return mesh


## The `--front` that analyze_glb.sh used (normalisation.json: front_auto false + yaw), or "".
func _front_from_normalisation(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or bool((data as Dictionary).get("front_auto", true)):
		return ""
	var yaw := fposmod(float((data as Dictionary).get("yaw_deg", 0.0)), 360.0)
	for key: String in GlbReference.FRONT_YAW_DEG:
		if absf(fposmod(GlbReference.FRONT_YAW_DEG[key], 360.0) - yaw) < 0.5:
			return key
	return ""


## The visible triangles of the game model in metres (model space is 1 unit = 10 m, faces +X).
func _model_mesh(unit_id: String, faction_id: String) -> Dictionary:
	var faction := FactionRegistry.get_faction(StringName(faction_id))
	var model_root := UnitModels.build(StringName(unit_id), 0, faction)
	var model := model_root.get_node("Model") as Node3D
	model.scale = Vector3.ONE
	root.add_child(model_root)
	var positions := PackedVector3Array()
	var indices := PackedInt32Array()
	_collect(model_root, Transform3D.IDENTITY, positions, indices)
	model_root.free()
	var to_metres := Transform3D(
		Basis.from_scale(Vector3.ONE * UnitModels.METERS_PER_UNIT), Vector3.ZERO
	)
	return {"positions": to_metres * positions, "indices": indices}


func _collect(
	node: Node3D, parent: Transform3D, positions: PackedVector3Array, indices: PackedInt32Array
) -> void:
	var transform := parent * node.transform
	if node is MeshInstance3D and node.visible and (node as MeshInstance3D).mesh != null:
		var instance := node as MeshInstance3D
		for surface in instance.mesh.get_surface_count():
			if instance.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertex_data: Variant = arrays[Mesh.ARRAY_VERTEX]
			if not vertex_data is PackedVector3Array:
				continue
			var points := vertex_data as PackedVector3Array
			var base := positions.size()
			positions.append_array(transform * points)
			var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
			if index_data is PackedInt32Array and not (index_data as PackedInt32Array).is_empty():
				for index in index_data as PackedInt32Array:
					indices.append(base + index)
			else:
				for i in points.size() - points.size() % 3:
					indices.append(base + i)
	for child in node.get_children():
		if child is Node3D and (child as Node3D).visible:
			_collect(child as Node3D, transform, positions, indices)


## Centres the mesh in x / z over its bounding box and stands it on y = 0.
func _align(mesh: Dictionary) -> void:
	var points: PackedVector3Array = mesh["positions"]
	var box := GlbReference.bounds(points)
	var centre := box.get_center()
	var shift := Vector3(-centre.x, -box.position.y, -centre.z)
	for i in points.size():
		points[i] += shift
	mesh["positions"] = points
