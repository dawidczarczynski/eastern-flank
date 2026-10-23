extends TestCase
## Unit surface v2 (TASK-062): chamfered part helpers with the vertex masks, the camo shader's
## weathering uniforms, per-unit wear seed.

const SIZE := Vector3(0.1, 0.06, 0.2)
const AABB_TOLERANCE := 0.0005


func _arrays(mesh: Mesh) -> Array:
	return mesh.surface_get_arrays(0)


func _aabb(mesh: Mesh) -> AABB:
	return mesh.get_aabb()


func test_default_bevel_box_keeps_its_size() -> void:
	var box := ModelParts.box_mesh(SIZE)
	var aabb := _aabb(box)
	assert_true(aabb.size.distance_to(SIZE) < AABB_TOLERANCE)
	assert_true(aabb.get_center().length() < AABB_TOLERANCE)


func test_default_bevel_box_has_unit_normals_and_masks() -> void:
	var arrays := _arrays(ModelParts.box_mesh(SIZE))
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for n in normals:
		assert_true(absf(n.length() - 1.0) < 1e-4)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(colors.size(), normals.size())
	var edge := 0
	var face := 0
	for c in colors:
		assert_true(c.g >= 0.0 and c.g <= 1.0 and c.b >= 0.0 and c.b <= 1.0)
		if c.r >= 1.0:
			edge += 1
		elif c.r <= 0.0:
			face += 1
	assert_true(edge >= 1, "chamfer vertices have r = 1")
	assert_true(face >= 1, "face vertices have r = 0")


func test_sharp_box_matches_the_old_box() -> void:
	var sharp := ModelParts.box_mesh(SIZE, 0.0)
	var old := BoxMesh.new()
	old.size = SIZE
	var sharp_arrays := _arrays(sharp)
	var old_arrays := _arrays(old)
	assert_eq(
		(sharp_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		(old_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	)
	assert_true(_aabb(sharp).size.distance_to(_aabb(old).size) < 1e-6)
	for c: Color in sharp_arrays[Mesh.ARRAY_COLOR]:
		assert_eq(c.r, 0.0)


func test_bevel_costs_triangles_and_tiny_parts_stay_sharp() -> void:
	var sharp := ModelParts.box_mesh(SIZE, 0.0).get_faces().size() / 3
	var bevelled := ModelParts.box_mesh(SIZE).get_faces().size() / 3
	assert_eq(sharp, 12)
	assert_true(bevelled > sharp)
	var tiny := Vector3(0.004, 0.004, 0.004)
	assert_eq(ModelParts.box_mesh(tiny).get_faces().size() / 3, 12)


func test_mesh_helpers_write_masks_and_keep_sizes() -> void:
	var cyl := ModelParts.cyl_mesh(0.02, 0.02, 0.1, 12)
	assert_true(absf(_aabb(cyl).size.y - 0.1) < AABB_TOLERANCE)
	assert_true(absf(_aabb(cyl).size.x - 0.04) < AABB_TOLERANCE)
	var outline: Array[Vector2] = [
		Vector2(-0.1, -0.05), Vector2(0.1, -0.05), Vector2(0.1, 0.05), Vector2(-0.1, 0.05)
	]
	var prism := ModelParts.prism_mesh("test_wear:prism", outline, 0.04)
	assert_true(_aabb(prism).size.distance_to(Vector3(0.2, 0.1, 0.04)) < AABB_TOLERANCE)
	var top: Array[Vector2] = [
		Vector2(-0.05, -0.04), Vector2(0.05, -0.04), Vector2(0.05, 0.04), Vector2(-0.05, 0.04)
	]
	var loft := ModelParts.loft_mesh("test_wear:loft", outline, top, 0.0, 0.05)
	assert_true(absf(_aabb(loft).size.y - 0.05) < AABB_TOLERANCE)
	var profile: Array[Vector2] = [
		Vector2(0, 0.05), Vector2(0.04, 0.05), Vector2(0.04, -0.05), Vector2(0, -0.05)
	]
	var lathe := ModelParts.lathe_mesh("test_wear:lathe", profile, 12)
	for mesh: Mesh in [cyl, prism, loft, lathe, ModelParts.sphere_mesh(0.02, false, 8, 5)]:
		var arrays := _arrays(mesh)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		assert_eq(colors.size(), (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	var edges := 0
	for c: Color in _arrays(lathe)[Mesh.ARRAY_COLOR]:
		edges += 1 if c.r >= 1.0 else 0
	assert_true(edges > 0, "lathe rims carry the edge mask")


func test_merging_keeps_masks_and_varies_tint_per_part() -> void:
	var box := ModelParts.box_mesh(SIZE)
	var parts := [
		[box, Transform3D(Basis.IDENTITY, Vector3(0.3, 0.1, 0.0))],
		[box, Transform3D(Basis.IDENTITY, Vector3(-0.2, 0.5, 0.4))],
	]
	var merged := ModelParts.merged_mesh("test_wear:merged", parts)
	var colors: PackedColorArray = _arrays(merged)[Mesh.ARRAY_COLOR]
	var half := colors.size() / 2
	assert_eq(colors.size(), (_arrays(box)[Mesh.ARRAY_COLOR] as PackedColorArray).size() * 2)
	assert_true(colors[0].b != colors[half].b, "each part has its own tint seed")
	var edges := 0
	for c in colors:
		edges += 1 if c.r >= 1.0 else 0
	assert_true(edges > 0)


func test_camo_shader_declares_the_weathering_uniforms() -> void:
	var names: Array[String] = []
	for u: Dictionary in ModelParts.CAMO_SHADER.get_shader_uniform_list():
		names.append(u["name"])
	for uniform: String in [
		"wear_amount",
		"wear_color",
		"tint_amount",
		"dust_amount",
		"dust_color",
		"mud_color",
		"mud_height",
		"mud_amount",
		"streak_amount",
		"fade",
		"color_a",
		"pattern_mode",
		"digital_cells",
		"pattern_scale"
	]:
		assert_true(uniform in names, "camo shader declares %s (%s)" % [uniform, names])
	# Instance uniforms are not part of get_shader_uniform_list().
	assert_true(ModelParts.CAMO_SHADER.code.contains("instance uniform float wear_seed"))


func test_wear_seed_is_stable_per_id_and_differs_between_ids() -> void:
	assert_eq(UnitModels.wear_seed(7), UnitModels.wear_seed(7))
	assert_true(UnitModels.wear_seed(7) != UnitModels.wear_seed(8))
	assert_true(UnitModels.wear_seed(&"m1a2_sepv3") != UnitModels.wear_seed(&"t72b3"))
	for id in 50:
		var s := UnitModels.wear_seed(id)
		assert_true(s >= 0.0 and s < UnitModels.WEAR_SEED_RANGE)


func test_built_models_carry_the_unit_wear_seed() -> void:
	var faction := load("res://data/factions/poland.tres") as FactionDefinition
	var a := UnitModels.build(&"m1a2_sepv3", 0, faction, 11)
	var b := UnitModels.build(&"m1a2_sepv3", 0, faction, 12)
	var camo := _first_camo_instance(a)
	var other := _first_camo_instance(b)
	assert_true(camo != null and other != null)
	assert_eq(camo.get_instance_shader_parameter(&"wear_seed"), UnitModels.wear_seed(11))
	assert_true(
		(
			camo.get_instance_shader_parameter(&"wear_seed")
			!= other.get_instance_shader_parameter(&"wear_seed")
		)
	)
	a.free()
	b.free()


func _first_camo_instance(node: Node) -> MeshInstance3D:
	var instance := node as MeshInstance3D
	if instance != null and instance.material_override is ShaderMaterial:
		return instance
	for child in node.get_children():
		var found := _first_camo_instance(child)
		if found != null:
			return found
	return null
