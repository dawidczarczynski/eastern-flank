extends TestCase
## Normalising a reference GLB to the catalog dimensions (TASK-179, tools/glb_reference.gd).

const GlbReference := preload("res://tools/glb_reference.gd")
const GLB_PATH := "user://test_glb_reference.glb"
const REAL := {"length": 10.0, "width": 3.0, "height": 2.0}


## Bounds of the scene's vertices with its normalising transform applied.
func _placed_bounds(scene: Node3D) -> AABB:
	return GlbReference.bounds(scene.transform * GlbReference.vertices(scene))


## A tank-like fixture: a hull box (4 x 1 x 2 along z, lying on its side in the file) and a thin
## barrel at the +z end, standing 5 units above the file's origin.
func _fixture(barrel_sign: float = 1.0) -> Node3D:
	var root := Node3D.new()
	var hull := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 1.0, 4.0)
	hull.mesh = box
	hull.position = Vector3(10.0, 5.0, -3.0)
	root.add_child(hull)
	var barrel := MeshInstance3D.new()
	var cylinder_box := BoxMesh.new()
	cylinder_box.size = Vector3(0.2, 0.2, 3.0)
	barrel.mesh = cylinder_box
	barrel.position = Vector3(10.0, 5.2, -3.0 + barrel_sign * 3.5)
	root.add_child(barrel)
	return root


func test_longer_horizontal_axis_becomes_the_length_and_the_model_stands_on_the_ground() -> void:
	var scene := _fixture()
	var result := GlbReference.normalise(scene, REAL)
	var box := _placed_bounds(scene)
	assert_true(absf(box.size.x - 10.0) < 0.001, "length = catalog length, got %s" % box.size.x)
	assert_true(absf(box.position.y) < 0.001, "stands on y = 0")
	assert_true(absf(box.get_center().x) < 0.001 and absf(box.get_center().z) < 0.001, "centred")
	assert_true(result["front_auto"])
	scene.free()


func test_narrow_end_is_the_front_whichever_way_the_file_points() -> void:
	for sign in [1.0, -1.0]:
		var scene := _fixture(sign)
		GlbReference.normalise(scene, REAL)
		var points := scene.transform * GlbReference.vertices(scene)
		var barrel_end := Vector3.ZERO
		for point in points:
			if point.x > barrel_end.x:
				barrel_end = point
		var box := GlbReference.bounds(points)
		# The barrel (y above the hull's centre line, thin) reaches the +x end.
		assert_true(absf(barrel_end.x - box.end.x) < 0.001)
		assert_true(
			barrel_end.y > box.position.y + box.size.y * 0.4, "tip is the barrel (sign %s)" % sign
		)
		scene.free()


func test_front_option_overrides_the_automatic_choice() -> void:
	var scene := _fixture(1.0)
	var points := GlbReference.vertices(scene)
	assert_eq(GlbReference.front_yaw_deg(points, "+x"), 0.0)
	assert_eq(GlbReference.front_yaw_deg(points, "-z"), -90.0)
	scene.free()


func test_foot_unit_is_scaled_to_its_height() -> void:
	var scene := _fixture()
	GlbReference.normalise(scene, {"height": 1.8})
	assert_true(absf(_placed_bounds(scene).size.y - 1.8) < 0.001)
	scene.free()


func test_size_far_from_the_catalog_warns() -> void:
	var scene := _fixture()
	var result := GlbReference.normalise(scene, {"length": 10.0, "width": 3.0, "height": 0.5})
	assert_false((result["warnings"] as Array).is_empty(), "height 4x too big must warn")
	scene.free()


func test_thin_antenna_does_not_count_as_height() -> void:
	var points := PackedVector3Array()
	for i in 1000:
		points.append(Vector3(i * 0.01, 2.0, 0.0))
		points.append(Vector3(i * 0.01, 0.0, 0.0))
	points.append(Vector3(0.0, 6.0, 0.0))  # a single antenna vertex
	assert_true(GlbReference._robust_height(points) < 2.5)


func test_glb_round_trip_loads_and_rejects_missing_files() -> void:
	var scene := _fixture()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	document.append_from_scene(scene, state)
	assert_eq(document.write_to_filesystem(state, GLB_PATH), OK)
	scene.free()
	var loaded := GlbReference.load_scene(ProjectSettings.globalize_path(GLB_PATH))
	assert_true(loaded != null)
	if loaded != null:
		assert_eq(GlbReference.mesh_instances(loaded).size(), 2)
		loaded.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GLB_PATH))
	assert_true(GlbReference.load_scene("user://does_not_exist.glb") == null)


func test_render_reference_falls_back_to_the_glb_side_view() -> void:
	var catalog := "user://test_glb_catalog"
	var dir := "%s/glb_only/reference_views" % catalog
	DirAccess.make_dir_recursive_absolute(dir)
	var Options := preload("res://tools/render_unit_options.gd")
	assert_eq(Options.default_reference({}, "glb_only", catalog), "")
	FileAccess.open(dir + "/glb_side.png", FileAccess.WRITE).store_string("png")
	assert_true(
		Options.default_reference({}, "glb_only", catalog).ends_with("reference_views/glb_side.png")
	)
	DirAccess.remove_absolute(dir + "/glb_side.png")
	DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute("%s/glb_only" % catalog)
	DirAccess.remove_absolute(catalog)
