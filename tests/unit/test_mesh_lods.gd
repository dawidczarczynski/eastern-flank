extends TestCase
## MeshLods: the procedural unit meshes get shared vertices and generated levels of detail.


## A detailed, unindexed MeshKit mesh (a 48-sided rod).
func _rod() -> ArrayMesh:
	var kit := MeshKit.new()
	kit.rod(Vector3.ZERO, Vector3.UP, 0.5, 2.0, 48)
	return kit.commit()


func test_a_detailed_mesh_gets_indexed_and_levels_of_detail() -> void:
	var source := _rod()
	var mesh := MeshLods.with_lods(source) as ArrayMesh
	assert_true(mesh != source, "a new mesh")
	assert_true(MeshLods.lod_count(mesh) > 0, "generated levels")
	var arrays := mesh.surface_get_arrays(0)
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	assert_eq(indices.size(), source.surface_get_array_len(0), "same triangles at full detail")
	assert_true(
		(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() < source.surface_get_array_len(0),
		"shared vertices"
	)
	assert_true(arrays[Mesh.ARRAY_COLOR] != null, "the paint masks survive")


func test_the_result_is_cached_and_not_processed_twice() -> void:
	var source := _rod()
	var mesh := MeshLods.with_lods(source)
	assert_true(MeshLods.with_lods(source) == mesh, "cached per source mesh")
	assert_true(MeshLods.with_lods(mesh) == mesh, "already has its levels")


func test_a_small_mesh_is_left_alone() -> void:
	var kit := MeshKit.new()
	kit.cbox(Vector3.ZERO, Vector3.ONE, 0.0)
	var box := kit.commit()
	assert_true(MeshLods.with_lods(box) == box)
	assert_eq(MeshLods.lod_count(box), 0)


func test_apply_swaps_the_meshes_of_a_model() -> void:
	var root := Node3D.new()
	var part := MeshInstance3D.new()
	part.mesh = _rod()
	root.add_child(part)
	MeshLods.apply(root)
	assert_true(MeshLods.lod_count(part.mesh) > 0)
	root.free()


func test_built_unit_models_carry_levels_of_detail() -> void:
	var model := UnitModels.build(&"m1a2_sepv3", 0, null)
	var with_levels := 0
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		if MeshLods.lod_count((node as MeshInstance3D).mesh) > 0:
			with_levels += 1
	assert_true(with_levels > 10, "%d meshes with levels" % with_levels)
	model.free()


## Kit geometry: hundreds of separate primitives in one mesh. Chamfers collapse, a primitive
## smaller than a pixel is dropped, and the corners keep original vertices (their colour masks).
func test_levels_simplify_primitives_and_drop_tiny_ones() -> void:
	var kit := MeshKit.new()
	kit.cbox(Vector3.ZERO, Vector3(0.4, 0.2, 0.3), 0.004)
	for i in 8:
		kit.bolt(Vector3(-0.15 + 0.04 * i, 0.1, 0.0), Vector3.UP)
	kit.rod(Vector3(0.0, 0.3, 0.0), Vector3.RIGHT, 0.03, 0.5, 24, 0.003)
	var st := SurfaceTool.new()
	st.create_from(kit.commit(), 0)
	st.index()
	var arrays := st.commit_to_arrays()
	var vertices := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var full := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	var lods := MeshLods.levels(arrays)
	assert_true(lods.size() >= 2, "%d levels" % lods.size())
	var errors := lods.keys()
	errors.sort()
	var last := full
	for error: float in errors:
		var indices: PackedInt32Array = lods[error]
		assert_true(indices.size() < last, "each level is coarser")
		last = indices.size()
		for index in indices:
			if index < 0 or index >= vertices:
				_fail("index %d outside the vertex buffer" % index)
				return
	# The coarsest level still has the box and the rod (12 + a few triangles), not the bolts.
	assert_true(last >= 12 * 3, "the large primitives stay: %d indices" % last)
	assert_true(last < full / 4, "%d of %d indices" % [last, full])


## A thin plate must not fold through its thickness: every face of every level still points the
## way a face of the full mesh does.
func test_a_thin_plate_keeps_both_faces() -> void:
	var kit := MeshKit.new()
	kit.cbox(Vector3.ZERO, Vector3(0.6, 0.004, 0.3), 0.001)
	for i in 30:
		kit.cbox(Vector3(-0.28 + 0.02 * i, 0.01, 0.0), Vector3(0.01, 0.01, 0.2), 0.002)
	var st := SurfaceTool.new()
	st.create_from(kit.commit(), 0)
	st.index()
	var arrays := st.commit_to_arrays()
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var lods := MeshLods.levels(arrays)
	assert_true(lods.size() > 0, "levels")
	for error: float in lods:
		var indices: PackedInt32Array = lods[error]
		var up := 0.0
		var down := 0.0
		for i in range(0, indices.size(), 3):
			var a := vertices[indices[i]]
			var face := (vertices[indices[i + 2]] - a).cross(vertices[indices[i + 1]] - a)
			if maxf(absf(a.y), 0.0) <= 0.0021:  # the plate
				up += maxf(face.y, 0.0)
				down += maxf(-face.y, 0.0)
		assert_true(up > 0.3 and down > 0.3, "level %.4f: top %.3f bottom %.3f" % [error, up, down])


func test_levels_come_back_from_the_disk_cache() -> void:
	var dir := "user://test_mesh_lods_cache"
	MeshLods.cache_dir = dir
	MeshLods._stored = {}
	MeshLods._stored_read = false
	var first := MeshLods.with_lods(_rod()) as ArrayMesh
	MeshLods.flush()
	assert_true(FileAccess.file_exists(MeshLods.cache_path()), "written")
	MeshLods._stored = {}
	MeshLods._stored_read = false
	var again := MeshLods.with_lods(_rod()) as ArrayMesh
	assert_eq(MeshLods._stored.size(), 1, "read back")
	assert_false(MeshLods._dirty, "nothing new to write")
	assert_eq(again.get_meta(MeshLods.META_LOD_LEVELS), first.get_meta(MeshLods.META_LOD_LEVELS))
	assert_eq(again.surface_get_arrays(0), first.surface_get_arrays(0))
	DirAccess.remove_absolute(MeshLods.cache_path())
	DirAccess.remove_absolute(dir)
	MeshLods.cache_dir = ""
	MeshLods._stored = {}
	MeshLods._stored_read = false
