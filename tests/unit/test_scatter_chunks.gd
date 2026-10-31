extends TestCase
## ScatterChunks (TASK-108 performance): bushes and rocks as frustum-cullable chunk MultiMeshes,
## bushes with a coarser far mesh.


func _transforms() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for i in 40:
		result.append(Transform3D(Basis(), Vector3(i * 0.9 - 18.0, 0.1, (i % 7) * 2.5 - 8.0)))
	return result


func test_every_instance_once_in_its_chunk_without_far_mesh() -> void:
	var transforms := _transforms()
	var colors := PackedColorArray()
	for i in transforms.size():
		colors.append(Color(i / 40.0, 0.5, 0.5))
	var root := ScatterChunks.build("Rocks", FoliageMeshes.rock(), null, transforms, colors)
	assert_eq(String(root.name), "Rocks")
	assert_true(root.get_child_count() > 1, "several chunks")
	var seen := 0
	for node: MultiMeshInstance3D in root.get_children():
		assert_true(String(node.name).begins_with("Rocks_"), node.name)
		assert_eq(node.visibility_range_end, 0.0, "no LOD without a far mesh")
		assert_eq(node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		var chunk := TreeField.chunk_of(node.position)
		assert_true(node.position.is_equal_approx(TreeField.chunk_center(chunk)))
		for k in node.multimesh.instance_count:
			var world := node.position + node.multimesh.get_instance_transform(k).origin
			assert_eq(TreeField.chunk_of(world), chunk, "instance in its chunk")
			seen += 1
	assert_eq(seen, transforms.size(), "every instance once")
	root.free()


func test_bushes_get_near_and_far_nodes() -> void:
	var transforms := _transforms()
	var root := ScatterChunks.build(
		"Bushes",
		FoliageMeshes.bush(),
		null,
		transforms,
		PackedColorArray(),
		FoliageMeshes.bush_far()
	)
	var near := 0
	var far := 0
	for node: MultiMeshInstance3D in root.get_children():
		if String(node.name).begins_with("BushesFar_"):
			far += node.multimesh.instance_count
			assert_eq(node.visibility_range_begin, ScatterChunks.BUSH_LOD_DISTANCE)
			assert_true(node.multimesh.mesh == FoliageMeshes.bush_far())
		else:
			near += node.multimesh.instance_count
			assert_eq(node.visibility_range_end, ScatterChunks.BUSH_LOD_DISTANCE)
			assert_true(node.multimesh.mesh == FoliageMeshes.bush())
		assert_eq(node.visibility_range_fade_mode, GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF)
	assert_eq(near, transforms.size())
	assert_eq(far, transforms.size())
	root.free()


func test_far_bush_is_cheaper_and_the_same_size() -> void:
	var near := FoliageMeshes.bush()
	var far := FoliageMeshes.bush_far()
	var near_tris: int = near.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3
	var far_tris: int = far.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3
	assert_true(far_tris * 3 <= near_tris, "far %d vs near %d triangles" % [far_tris, near_tris])
	assert_true(near.get_aabb().size.distance_to(far.get_aabb().size) < 0.03, "same size")
