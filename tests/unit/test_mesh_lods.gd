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
