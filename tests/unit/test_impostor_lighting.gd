extends TestCase
## Impostors and canopy lit by the scene's sun (TASK-191): the atlas carries the unlit albedo and
## the view-space normals in two textures of the same layout, the impostor shaders are lit (not
## unshaded) and turn the baked normal to the view, and the canopy shell paints the unlit atlas
## mean on the ground's normals.


func before_all() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	TreeImpostors.prime()


func after_all() -> void:
	VisualScale.reset()
	MapScale.reset()


func test_the_atlas_bakes_albedo_and_normals_in_the_same_layout() -> void:
	var albedo := TreeImpostors.atlas().get_image()
	var normals := TreeImpostors.normal_atlas().get_image()
	assert_eq(normals.get_size(), albedo.get_size())
	assert_eq(
		albedo.get_size(),
		Vector2i(
			TreeImpostors.CELL.x * TreeImpostors.VIEWS,
			TreeImpostors.CELL.y * TreeImpostors.SPECIES.size() * TreeMeshes.VARIANTS
		)
	)
	assert_true(normals.has_mipmaps(), "the normal atlas is mipmapped as the albedo one")
	# Same coverage pixel for pixel, and every covered normal is a unit vector (encoded 0..1).
	var covered := 0
	for y in range(3, albedo.get_height(), 7):
		for x in range(5, albedo.get_width(), 11):
			var a := albedo.get_pixel(x, y)
			var n := normals.get_pixel(x, y)
			assert_eq(n.a > 0.5, a.a > 0.5, "coverage at %d, %d" % [x, y])
			if a.a > 0.5:
				covered += 1
				var v := Vector3(n.r, n.g, n.b) / n.a * 2.0 - Vector3.ONE
				assert_true(absf(v.length() - 1.0) < 0.05, "unit normal at %d, %d" % [x, y])
	assert_true(covered > 100, "the atlas pictures something")


func test_the_impostor_shaders_are_lit_by_the_scene() -> void:
	for path in [
		"res://assets/shaders/tree_impostor.gdshader",
		"res://assets/shaders/forest_impostor.gdshader"
	]:
		var code := FileAccess.get_file_as_string(path)
		var render_mode := code.get_slice("render_mode", 1).get_slice(";", 0)
		assert_false(render_mode.contains("unshaded"), "%s is lit" % path)
		assert_true(code.contains("impostor_world_normal(UV)"), "%s turns the baked normal" % path)
		assert_true(code.contains("impostor_basis("), "%s passes the bake camera's axes" % path)
	var material := TreeImpostors.material(0.08)
	assert_eq(material.get_shader_parameter(&"normal_atlas"), TreeImpostors.normal_atlas())
	assert_eq(material.get_shader_parameter(&"atlas"), TreeImpostors.atlas())
	var elevation := float(material.get_shader_parameter(&"bake_elevation"))
	assert_true(absf(elevation - deg_to_rad(TreeImpostors.ELEVATION)) < 1.0e-6, "bake elevation")


func test_the_bake_material_is_the_unlit_lod0_material() -> void:
	var source := TreeField.new_material(&"oak", TreeField.Lod.NEAR)
	for normal in [false, true]:
		var bake := TreeImpostors.bake_material(&"oak", normal)
		assert_eq(bake.shader, TreeImpostors.BAKE_SHADER)
		assert_eq(bake.get_shader_parameter(&"bake_normal"), normal)
		for parameter in [&"leaf_texture", &"leaf_color", &"bark_color", &"tree_height"]:
			assert_eq(
				bake.get_shader_parameter(parameter),
				source.get_shader_parameter(parameter),
				String(parameter)
			)
	var code := FileAccess.get_file_as_string("res://assets/shaders/foliage_bake.gdshader")
	assert_true(code.get_slice("render_mode", 1).get_slice(";", 0).contains("unshaded"))


func test_the_shell_paints_the_unlit_atlas_mean() -> void:
	var grid := HexGrid.new()
	grid.set_terrain(Vector2i.ZERO, Terrain.Type.FOREST)
	var rect := Rect2(-1.0, -1.0, 2.0, 2.0)
	var shell := ForestShell.build(grid, rect, func(_x: float, _z: float) -> float: return 0.0)
	assert_true(shell != null, "a forest tile has a shell")
	var material := shell.mesh.surface_get_material(0) as ShaderMaterial
	for species in BackdropCanopy.SPECIES:
		var expected := TreeImpostors.base_color(species)
		var color: Color = material.get_shader_parameter(StringName("%s_color" % species))
		assert_true(color.is_equal_approx(expected), "%s colour is the atlas mean" % species)
	# The mean is of the unlit albedo atlas.
	var atlas := TreeImpostors.atlas().get_image()
	var row := TreeImpostors.SPECIES.find(&"pine") * TreeMeshes.VARIANTS
	assert_true(
		TreeImpostors._mean_color(atlas, row).is_equal_approx(TreeImpostors.base_color(&"pine"))
	)
	shell.free()


func test_the_shell_normals_follow_the_ground_slope() -> void:
	var grid := HexGrid.new()
	grid.set_terrain(Vector2i.ZERO, Terrain.Type.FOREST)
	# A plane rising towards +x: its normal leans to -x.
	var slope := 0.5
	var mesh := ForestShell.build_mesh(
		grid, Rect2(-1.0, -1.0, 2.0, 2.0), func(x: float, _z: float) -> float: return x * slope, 0.1
	)
	var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var expected := Vector3(-slope, 1.0, 0.0).normalized()
	assert_true(normals.size() > 0)
	for n in normals:
		assert_true(
			n.distance_to(expected) < 1.0e-3, "ground normal, not the lifted shell's: %s" % n
		)
