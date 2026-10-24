extends SceneTree
## Renders one unit model alone on a model-space grid from fixed angles and writes per-view PNGs
## plus a sheet (2 x 2 views, the reference image next to it). Run via tools/render_unit.sh.
## Manually: godot --path . --resolution 1280x720 --script res://tools/render_unit.gd --
##   <unit_id> [options]
## Exit codes: 0 saved, 1 render / save failure, 2 invalid arguments.
##
## Scene: flat #5a5d55 background, the battle scene's sun and sky ambient, shadows, a ground plane
## with a grid in model space (1 model unit = 10 m: faint every 0.1 = 1 m, stronger every 0.5 =
## 5 m; walls with the same grid behind the side and front views). The model is shown without
## the unit model scale (VisualScale.unit_model_scale()). Orthographic views share one scale;
## three_quarter is perspective.
## `--pose=fire` raises a launcher to its max elevation (traverse 0) before framing, so the views
## and the AABB show the fire pose.
## Stats: the AABB covers visible nodes only, while triangle and mesh counts include hidden poses
## (e.g. the kneeling soldiers' Stand), the same rule as the contract test budgets.

const RenderUnitOptions := preload("res://tools/render_unit_options.gd")
const ScreenshotImage := preload("res://tools/screenshot_image.gd")
const USAGE := (
	"Usage: tools/render_unit.sh <unit_id> [--faction=<id>] "
	+ "[--views=side,front,top,three_quarter] [--reference=path] [--out=sheet.png] "
	+ "[--pose=rest|fire] [--windows|--linux]"
)
const EXPECTED_SIZE := Vector2i(1280, 720)
const CELL_SIZE := Vector2i(640, 360)
const MAX_REFERENCE_WIDTH := 1280
const BACKGROUND := Color("#5a5d55")
const GROUND_COLOR := Color("#50534b")
const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
const BATTLE_ENVIRONMENT := "res://assets/environments/battle_environment.tres"
const MARGIN := 1.1  # ortho views frame the AABB with 10 % margin
const WARMUP_FRAMES := 6
const VIEW_FRAMES := 3
const GRID_STEP := 0.1
const GRID_MAJOR_EVERY := 5
const GRID_HALF := 1.6  # grid extends from -GRID_HALF to +GRID_HALF in x and z
const GRID_HEIGHT := 1.2
const PORTRAIT_FOV := 24.0  # three_quarter framing = TASK-034 portrait
const PORTRAIT_OFFSET := Vector3(0.82, 0.4, 1.02)
const ORTHO_DISTANCE := 6.0
const ORTHO_NEAR := 0.05
const ORTHO_FAR := 40.0

var _options: Dictionary
var _model: Node3D
var _camera: Camera3D
var _ground_grid: MeshInstance3D
var _side_wall: MeshInstance3D  # grid in x/y behind the side view (z = -GRID_HALF)
var _front_wall: MeshInstance3D  # grid in z/y behind the front view (x = -GRID_HALF)
var _aabb: AABB


func _initialize() -> void:
	_options = _parse_arguments()
	if _options["error"] != "":
		_fail("invalid arguments (%s). %s" % [_options["error"], USAGE], 2)
		return
	var out := String(_options["out"]).simplify_path()
	if not out.is_absolute_path():
		_fail("the output path must be absolute (tools/render_unit.sh resolves it): '%s'" % out, 2)
		return
	_options["out"] = out
	root.gui_disable_input = true
	root.set_disable_input(true)
	_run()


func _parse_arguments() -> Dictionary:
	return RenderUnitOptions.parse(OS.get_cmdline_user_args())


func _run() -> void:
	_build_scene()
	for i in WARMUP_FRAMES:
		await process_frame
	var images := {}
	for view: String in _options["views"]:
		_frame_view(view)
		for i in VIEW_FRAMES:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image == null or image.is_empty() or image.get_size() != EXPECTED_SIZE:
			_fail("view '%s': unexpected viewport image" % view, 1)
			return
		if images.is_empty() and ScreenshotImage.is_blank(image):
			_fail("blank render", 1)
			return
		images[view] = image
	var out: String = _options["out"]
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	for view: String in images:
		var path := RenderUnitOptions.view_path(out, view)
		var error: Error = (images[view] as Image).save_png(path)
		if error != OK:
			_fail("could not save '%s' (%s)" % [path, error_string(error)], 1)
			return
	var sheet := _make_sheet(images)
	var sheet_error := sheet.save_png(out)
	if sheet_error != OK:
		_fail("could not save '%s' (%s)" % [out, error_string(sheet_error)], 1)
		return
	_print_result(out)
	quit(0)


func _print_result(out: String) -> void:
	var aabb_m := _aabb.size * UnitModels.METERS_PER_UNIT
	var meshes := _all_meshes(_model)
	var triangles := 0
	for instance in meshes:
		triangles += instance.mesh.get_faces().size() / 3
	var pivots: Array[String] = []
	_collect_pivots(_model, pivots)
	print("Render saved: ", out)
	print(
		(
			"Stats: aabb_m=%.1fx%.1fx%.1f triangles=%d mesh_instances=%d pivots=%s"
			% [
				aabb_m.x,
				aabb_m.z,
				aabb_m.y,
				triangles,
				meshes.size(),
				RenderUnitOptions.summarize_names(pivots),
			]
		)
	)
	var real := RenderUnitOptions.real_line(aabb_m, _options["real"])
	if real != "":
		print(real)


# --- Scene ------------------------------------------------------------------------------------


func _build_scene() -> void:
	var faction := FactionRegistry.get_faction(StringName(_options["faction"]))
	var model_root := UnitModels.build(StringName(_options["unit_id"]), 0, faction)
	_model = model_root.get_node("Model") as Node3D
	_model.scale = Vector3.ONE  # model space: 1 unit = 10 m
	if _options["pose"] == "fire":
		UnitModels.pose_launcher(_model, 0.0, UnitModels.launcher_elevation(_model))
	root.add_child(model_root)
	_aabb = _visible_aabb(model_root)  # root yaw is 0: the model faces +X

	var environment := (load(BATTLE_ENVIRONMENT) as Environment).duplicate() as Environment
	environment.background_mode = Environment.BG_CANVAS
	environment.fog_enabled = false
	environment.ssao_enabled = false
	_use_flat_sky_ambient(environment)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)
	var background := CanvasLayer.new()
	background.layer = -10
	var fill := ColorRect.new()
	fill.color = BACKGROUND
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.add_child(fill)
	root.add_child(background)
	root.add_child(_battle_sun())

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * GRID_HALF * 2.0
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = GROUND_COLOR
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	root.add_child(ground)
	_ground_grid = _grid_mesh(Vector3.AXIS_Y, 0.001)
	_side_wall = _grid_mesh(Vector3.AXIS_Z, -GRID_HALF)
	_front_wall = _grid_mesh(Vector3.AXIS_X, -GRID_HALF)

	_camera = Camera3D.new()
	_camera.current = true
	root.add_child(_camera)


## Sky ambient as a plain colour (the pre-HDRI mean of the old procedural zenith and horizon
## colours, energy 0.65, so unit sheets keep their look). Image-based sky ambient is not available
## with the canvas background (the background has to stay the exact flat colour) and shadowed faces
## would render black.
func _use_flat_sky_ambient(environment: Environment) -> void:
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.675, 0.72, 0.745)
	environment.ambient_light_energy = 0.65


## DirectionalLight3D with the properties of the battle scene's "Sun" node (read from the packed
## scene, so the two never drift apart).
func _battle_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	var state := (load(BATTLE_SCENE) as PackedScene).get_state()
	for node_index in state.get_node_count():
		if state.get_node_name(node_index) != &"Sun":
			continue
		for property_index in state.get_node_property_count(node_index):
			sun.set(
				state.get_node_property_name(node_index, property_index),
				state.get_node_property_value(node_index, property_index)
			)
	return sun


## Grid lines on the plane perpendicular to `axis` at `offset`: ground (Y), side wall (Z, x/y)
## or front wall (X, z/y). Lines every GRID_STEP, stronger every GRID_MAJOR_EVERY steps.
func _grid_mesh(axis: int, offset: float) -> MeshInstance3D:
	var minor := PackedVector3Array()
	var major := PackedVector3Array()
	var steps := int(round(GRID_HALF / GRID_STEP))
	var height_steps := int(round(GRID_HEIGHT / GRID_STEP))
	var horizontal_axis := Vector3.AXIS_Z if axis == Vector3.AXIS_X else Vector3.AXIS_X
	var vertical_axis := Vector3.AXIS_Y if axis != Vector3.AXIS_Y else Vector3.AXIS_Z
	var vertical_min := 0.0 if axis != Vector3.AXIS_Y else -GRID_HALF
	var vertical_max := GRID_HEIGHT if axis != Vector3.AXIS_Y else GRID_HALF
	var vertical_first := 0 if axis != Vector3.AXIS_Y else -steps
	var vertical_last := height_steps if axis != Vector3.AXIS_Y else steps
	for i in range(-steps, steps + 1):
		var target := major if i % GRID_MAJOR_EVERY == 0 else minor
		var h := i * GRID_STEP
		target.append(_plane_point(axis, offset, horizontal_axis, h, vertical_axis, vertical_min))
		target.append(_plane_point(axis, offset, horizontal_axis, h, vertical_axis, vertical_max))
	for j in range(vertical_first, vertical_last + 1):
		var target := major if j % GRID_MAJOR_EVERY == 0 else minor
		var v := j * GRID_STEP
		target.append(_plane_point(axis, offset, horizontal_axis, -GRID_HALF, vertical_axis, v))
		target.append(_plane_point(axis, offset, horizontal_axis, GRID_HALF, vertical_axis, v))
	var mesh := ArrayMesh.new()
	_add_lines(mesh, minor, Color(1, 1, 1, 0.14))
	_add_lines(mesh, major, Color(1, 1, 1, 0.4))
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)
	return instance


func _plane_point(
	axis: int, offset: float, axis_a: int, a: float, axis_b: int, b: float
) -> Vector3:
	var point := Vector3.ZERO
	point[axis] = offset
	point[axis_a] = a
	point[axis_b] = b
	return point


func _add_lines(mesh: ArrayMesh, points: PackedVector3Array, color: Color) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


# --- Views ------------------------------------------------------------------------------------


func _frame_view(view: String) -> void:
	_ground_grid.visible = view != "front" and view != "side"
	_side_wall.visible = view == "side"
	_front_wall.visible = view == "front"
	var center := _aabb.get_center()
	var aspect := float(EXPECTED_SIZE.x) / float(EXPECTED_SIZE.y)
	if view == "three_quarter":
		_ground_grid.visible = true
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = PORTRAIT_FOV
		_camera.near = 0.05
		_camera.far = 60.0
		var size := _aabb.size.length()
		_camera.position = center + PORTRAIT_OFFSET * size
		_camera.look_at(center - Vector3(0, 0.02, 0), Vector3.UP)
		return
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = RenderUnitOptions.ortho_size(_aabb, aspect, MARGIN)
	_camera.near = ORTHO_NEAR
	_camera.far = ORTHO_FAR
	match view:
		"side":  # looks along -Z, +X to the right
			_camera.position = center + Vector3(0, 0, ORTHO_DISTANCE)
			_camera.look_at(center, Vector3.UP)
		"front":  # looks along -X
			_camera.position = center + Vector3(ORTHO_DISTANCE, 0, 0)
			_camera.look_at(center, Vector3.UP)
		"top":  # looks along -Y, +X to the right
			_camera.position = center + Vector3(0, ORTHO_DISTANCE, 0)
			_camera.look_at(center, Vector3(0, 0, -1))


# --- Measuring --------------------------------------------------------------------------------


## AABB of the visible meshes below `node` in the space of `node`'s parent (hidden parts such as
## the kneeling soldiers' Stand pose do not count). Accumulates local transforms instead of using
## global ones, so it does not depend on the tree having processed the new nodes yet.
func _visible_aabb(node: Node3D, to_root: Transform3D = Transform3D.IDENTITY) -> AABB:
	var result := AABB()
	var has := false
	for child in node.get_children():
		var spatial := child as Node3D
		if spatial == null or not spatial.visible:
			continue
		var transform_to_root := to_root * spatial.transform
		var box := AABB()
		var has_box := false
		var instance := spatial as MeshInstance3D
		if instance != null:
			box = transform_to_root * instance.get_aabb()
			has_box = true
		var inner := _visible_aabb(spatial, transform_to_root)
		if inner.size != Vector3.ZERO:
			box = box.merge(inner) if has_box else inner
			has_box = true
		if has_box:
			result = result.merge(box) if has else box
			has = true
	return result


func _all_meshes(node: Node, into: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	for child in node.get_children():
		if child is MeshInstance3D:
			into.append(child)
		_all_meshes(child, into)
	return into


## Names of the pivots: Node3D descendants that are not meshes (auto-generated names such as
## "@Node3D@2" or "_Node3D_2" are skipped).
func _collect_pivots(node: Node, into: Array[String]) -> void:
	for child in node.get_children():
		if child is Node3D and not child is MeshInstance3D:
			var pivot := String(child.name)
			if not pivot.begins_with("@") and not pivot.begins_with("_"):
				into.append(pivot)
		_collect_pivots(child, into)


# --- Sheet ------------------------------------------------------------------------------------


## 2 x 2 grid of the views (CELL_SIZE each, in the order of `_options["views"]`), the reference
## scaled to the height of the first view cell (the side view by default) on the right.
func _make_sheet(images: Dictionary) -> Image:
	var views: Array = _options["views"]
	var columns := mini(2, views.size())
	var rows := ceili(views.size() / 2.0)
	var reference := _load_reference()
	var reference_width := 0
	if reference != null:
		var scale := float(CELL_SIZE.y) / float(reference.get_height())
		reference_width = clampi(int(round(reference.get_width() * scale)), 1, MAX_REFERENCE_WIDTH)
		# Wider than MAX_REFERENCE_WIDTH: scaled down to fit, keeping the aspect ratio.
		var height := CELL_SIZE.y
		if reference_width == MAX_REFERENCE_WIDTH:
			height = maxi(
				1,
				int(round(reference.get_height() * float(reference_width) / reference.get_width()))
			)
		reference.resize(reference_width, height, Image.INTERPOLATE_LANCZOS)
	var sheet := Image.create(
		columns * CELL_SIZE.x + reference_width, rows * CELL_SIZE.y, false, Image.FORMAT_RGBA8
	)
	sheet.fill(BACKGROUND)
	for i in views.size():
		var cell := (images[views[i]] as Image).duplicate() as Image
		cell.convert(Image.FORMAT_RGBA8)
		cell.resize(CELL_SIZE.x, CELL_SIZE.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(
			cell,
			Rect2i(Vector2i.ZERO, CELL_SIZE),
			Vector2i((i % 2) * CELL_SIZE.x, (i / 2) * CELL_SIZE.y)
		)
	if reference != null:
		sheet.blit_rect(
			reference,
			Rect2i(Vector2i.ZERO, reference.get_size()),
			Vector2i(columns * CELL_SIZE.x, 0)
		)
	return sheet


func _load_reference() -> Image:
	var path: String = _options["reference"]
	if path == "":
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		printerr("WARNING: could not read the reference image '%s', sheet without it" % path)
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


func _fail(message: String, exit_code: int) -> void:
	printerr("ERROR: ", message)
	quit(exit_code)
