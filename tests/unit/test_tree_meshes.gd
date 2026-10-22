extends TestCase

const SPECIES: Array[StringName] = [&"pine", &"spruce", &"birch", &"oak", &"alder"]


func _arrays(mesh: ArrayMesh, surface: int) -> Array:
	return mesh.surface_get_arrays(surface)


func _cards(mesh: ArrayMesh) -> int:
	var indices: PackedInt32Array = _arrays(mesh, TreeMeshes.SURFACE_LEAVES)[Mesh.ARRAY_INDEX]
	return indices.size() / 6


func test_at_least_three_variants() -> void:
	assert_true(TreeMeshes.VARIANTS >= 3)
	for species in SPECIES:
		assert_true(TreeMeshes.species().has(species), "species %s" % species)


func test_deterministic_and_variants_differ() -> void:
	for species in SPECIES:
		var verts: Array[PackedVector3Array] = []
		for variant in 3:
			var a: PackedVector3Array = _arrays(TreeMeshes.build(species, variant), 1)[
				Mesh.ARRAY_VERTEX
			]
			var b: PackedVector3Array = _arrays(TreeMeshes.build(species, variant), 1)[
				Mesh.ARRAY_VERTEX
			]
			assert_true(a == b, "%s %d deterministic" % [species, variant])
			verts.append(a)
		assert_true(verts[0] != verts[1], "%s 0 != 1" % species)
		assert_true(verts[1] != verts[2], "%s 1 != 2" % species)
		assert_true(verts[0] != verts[2], "%s 0 != 2" % species)


func test_two_surfaces_card_counts_and_sizes() -> void:
	for species in SPECIES:
		var conifer := TreeSpecies.is_conifer(species)
		for variant in 3:
			var mesh := TreeMeshes.lod0(species, variant)
			assert_eq(mesh.get_surface_count(), 2)
			var cards := _cards(mesh)
			var lo := 40 if conifer else 60
			var hi := 100 if conifer else 120
			assert_true(cards >= lo and cards <= hi, "%s %d cards %d" % [species, variant, cards])
			var verts: PackedVector3Array = _arrays(mesh, TreeMeshes.SURFACE_LEAVES)[
				Mesh.ARRAY_VERTEX
			]
			assert_eq(verts.size(), cards * 4, "4 vertices per card")
			for c in cards:
				for edge: Vector3 in [
					verts[c * 4 + 1] - verts[c * 4], verts[c * 4 + 3] - verts[c * 4]
				]:
					var size := edge.length()
					if size < 0.04 - 1e-4 or size > 0.07 + 1e-4:
						_fail("%s %d card size %f" % [species, variant, size])
						return


func test_leaf_normals_point_out_of_the_crown_and_are_unit() -> void:
	for species in SPECIES:
		for variant in 3:
			var mesh := TreeMeshes.lod0(species, variant)
			var center: Vector3 = TreeMeshes.shape(species, variant)["crown_center"]
			var arrays := _arrays(mesh, TreeMeshes.SURFACE_LEAVES)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var outward := 0
			for i in verts.size():
				if normals[i].dot(verts[i] - center) > 0.0:
					outward += 1
			assert_true(
				outward >= 0.95 * verts.size(),
				"%s %d outward %d/%d" % [species, variant, outward, verts.size()]
			)
			for s in 2:
				for n: Vector3 in _arrays(mesh, s)[Mesh.ARRAY_NORMAL]:
					if absf(n.length() - 1.0) > 1e-3:
						_fail("%s %d normal length %f" % [species, variant, n.length()])
						return


func test_trunk_is_closed_inside_the_crown_and_base_at_zero() -> void:
	for species in SPECIES:
		for variant in 3:
			var mesh := TreeMeshes.lod0(species, variant)
			var top: Vector3 = TreeMeshes.shape(species, variant)["trunk_top"]
			var bark: PackedVector3Array = _arrays(mesh, TreeMeshes.SURFACE_BARK)[Mesh.ARRAY_VERTEX]
			var leaves: PackedVector3Array = _arrays(mesh, TreeMeshes.SURFACE_LEAVES)[
				Mesh.ARRAY_VERTEX
			]
			var has_cap := false
			var min_y := INF
			for v in bark:
				min_y = minf(min_y, v.y)
				if v.is_equal_approx(top):
					has_cap = true
			assert_true(has_cap, "%s %d cap centre vertex" % [species, variant])
			assert_true(absf(min_y) <= 0.001, "%s %d base %f" % [species, variant, min_y])
			var leaf_lo := INF
			var leaf_hi := -INF
			for v in leaves:
				leaf_lo = minf(leaf_lo, v.y)
				leaf_hi = maxf(leaf_hi, v.y)
			assert_true(top.y < leaf_hi, "%s %d trunk below the crown top" % [species, variant])
			assert_true(top.y > leaf_lo, "%s %d trunk above the lowest card" % [species, variant])
			var height := mesh.get_aabb().size.y
			assert_true(
				height >= 0.2 and height <= 0.35, "%s %d height %f" % [species, variant, height]
			)


func test_vertex_colours() -> void:
	for species in SPECIES:
		for variant in 3:
			var mesh := TreeMeshes.lod0(species, variant)
			for s in 2:
				for c: Color in _arrays(mesh, s)[Mesh.ARRAY_COLOR]:
					var ok := (
						c.r >= 0.0
						and c.r <= 1.0
						and c.g >= 0.0
						and c.g < 1.0
						and c.b == (1.0 if s == TreeMeshes.SURFACE_LEAVES else 0.0)
					)
					if not ok:
						_fail("%s %d surface %d colour %s" % [species, variant, s, c])
						return


func test_triangle_budgets() -> void:
	for species in SPECIES:
		var total := 0
		for variant in 3:
			var tris := TreeMeshes.triangle_count(TreeMeshes.lod0(species, variant))
			assert_true(tris <= 400, "%s %d LOD0 %d" % [species, variant, tris])
			total += tris
		var average := total / 3.0
		var lod1 := TreeMeshes.triangle_count(TreeMeshes.lod1(species))
		assert_true(lod1 <= 250, "%s LOD1 %d" % [species, lod1])
		assert_true(lod1 <= 0.6 * average, "%s LOD1 %d vs LOD0 avg %f" % [species, lod1, average])
		print("  %s: LOD0 avg %.0f, LOD1 %d triangles" % [species, average, lod1])


func test_lod1_has_bark_and_crown_surfaces() -> void:
	for species in SPECIES:
		var mesh := TreeMeshes.lod1(species)
		assert_eq(mesh.get_surface_count(), 2)
		for c: Color in _arrays(mesh, TreeMeshes.SURFACE_LEAVES)[Mesh.ARRAY_COLOR]:
			assert_eq(c.b, 1.0)
			break


func test_meshes_are_cached() -> void:
	var first := TreeMeshes.lod0(&"oak", 1)
	assert_true(first == TreeMeshes.lod0(&"oak", 1))
	var simple := TreeMeshes.lod1(&"pine")
	assert_true(simple == TreeMeshes.lod1(&"pine"))
