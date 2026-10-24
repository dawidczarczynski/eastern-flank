extends TestCase
## OcclusionBake (TASK-085): analytic ambient occlusion from proxy capsules and caps, multiplied
## into the openness vertex mask (COLOR.g, ADR 0012) of MeshKit meshes.

const OcclusionBake := preload("res://src/presentation/models/parts/occlusion_bake.gd")


## A flat floor (1 x 1, facing up) as a MeshKit mesh.
func _floor() -> ArrayMesh:
	var kit := MeshKit.new()
	kit.poly(
		[
			Vector3(-0.5, 0, -0.5),
			Vector3(0.5, 0, -0.5),
			Vector3(0.5, 0, 0.5),
			Vector3(-0.5, 0, 0.5)
		],
		Vector3.UP
	)
	return kit.commit()


## Openness of the baked floor at the vertex nearest `at`.
func _g_at(mesh: ArrayMesh, at: Vector3) -> float:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var best := 0
	for i in verts.size():
		if verts[i].distance_to(at) < verts[best].distance_to(at):
			best = i
	return colors[best].g


func _dense_floor() -> ArrayMesh:
	var kit := MeshKit.new()
	var step := 0.1
	for i in 10:
		for j in 10:
			var x := -0.5 + i * step
			var z := -0.5 + j * step
			kit.poly(
				[
					Vector3(x, 0, z),
					Vector3(x + step, 0, z),
					Vector3(x + step, 0, z + step),
					Vector3(x, 0, z + step)
				],
				Vector3.UP
			)
	return kit.commit()


func test_a_sphere_above_darkens_the_floor_under_it_only() -> void:
	var bake := OcclusionBake.new()
	bake.sphere(Vector3(0.0, 0.15, 0.0), 0.1)
	var mesh: ArrayMesh = bake.bake(_dense_floor(), 1.0)
	var under := _g_at(mesh, Vector3.ZERO)
	var far := _g_at(mesh, Vector3(0.5, 0, 0.5))
	assert_true(under < 0.75, "under the sphere: %.2f" % under)
	assert_true(far > 0.95, "far away: %.2f" % far)


func test_occluders_behind_a_surface_do_not_darken_it() -> void:
	var bake := OcclusionBake.new()
	bake.capsule(Vector3(-0.3, -0.2, 0.0), Vector3(0.3, -0.2, 0.0), 0.1)
	var g := _g_at(bake.bake(_dense_floor(), 1.0), Vector3.ZERO)
	assert_true(g > 0.99, "below the floor: %.2f" % g)


func test_a_cap_darkens_what_is_under_its_rim_and_not_above() -> void:
	var bake := OcclusionBake.new()
	bake.cap(Vector3(0.0, 0.05, 0.0), Vector3.UP, 0.2)
	var mesh: ArrayMesh = bake.bake(_dense_floor(), 1.0)
	assert_true(_g_at(mesh, Vector3.ZERO) < 0.5, "under the cap")
	var above := OcclusionBake.new()
	above.cap(Vector3(0.0, -0.05, 0.0), Vector3.UP, 0.2)
	assert_true(_g_at(above.bake(_dense_floor(), 1.0), Vector3.ZERO) > 0.99, "above the cap")


func test_bake_multiplies_the_existing_mask_and_keeps_the_other_channels() -> void:
	var kit := MeshKit.new()
	kit.openness = 0.5
	kit.cbox(Vector3(0, 0.05, 0), Vector3(0.2, 0.1, 0.2), 0.02)
	var mesh := kit.commit()
	var before: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var bake := OcclusionBake.new()
	bake.sphere(Vector3(0, 0.4, 0), 0.15)
	var after: PackedColorArray = bake.bake(mesh, 1.0).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_eq(after.size(), before.size())
	var darker := 0
	for i in before.size():
		assert_true(after[i].g <= before[i].g + 1e-6)
		assert_true(absf(after[i].r - before[i].r) < 1e-6 and absf(after[i].b - before[i].b) < 1e-6)
		if after[i].g < before[i].g - 0.01:
			darker += 1
	assert_true(darker > 0, "the top of the box is under the sphere")


func test_scale_maps_mesh_units_to_the_occluder_units() -> void:
	# The mesh is in model units (0.1 per metre), the occluders in metres.
	var kit := MeshKit.new(null, Transform3D(Basis.from_scale(Vector3.ONE * 0.1), Vector3.ZERO))
	kit.poly(
		[
			Vector3(-0.5, 0, -0.5),
			Vector3(0.5, 0, -0.5),
			Vector3(0.5, 0, 0.5),
			Vector3(-0.5, 0, 0.5)
		],
		Vector3.UP
	)
	var bake := OcclusionBake.new()
	bake.sphere(Vector3(-0.5, 0.12, -0.5), 0.1)
	var g := _g_at(bake.bake(kit.commit(), 0.1), Vector3(-0.05, 0, -0.05))
	assert_true(g < 0.75, "corner under the sphere: %.2f" % g)


func test_bake_all_keeps_the_roles() -> void:
	var bake := OcclusionBake.new()
	bake.sphere(Vector3(0, 0.15, 0), 0.1)
	var baked := bake.bake_all({&"a": _floor(), &"b": _floor()}, 1.0)
	assert_eq(baked.keys(), [&"a", &"b"])
	assert_true(baked[&"a"] is ArrayMesh)
