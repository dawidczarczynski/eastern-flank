extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var _view: MapView


func before_each() -> void:
	_view = MapView.new()
	# Not in a scene tree in tests, so run the setup _ready() would do.
	_view._ready()
	_view.build(Fixtures.plains_grid(1))


func after_each() -> void:
	_view.free()


func _surface_mesh(node_name: String) -> ArrayMesh:
	var instance := _view._tiles_root.get_node(node_name) as MeshInstance3D
	return instance.mesh as ArrayMesh


func test_terrain_mesh_has_uvs_scaled_by_detail_tile() -> void:
	var arrays := _surface_mesh("Terrain").surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_true(uvs.size() > 0 and uvs.size() == vertices.size(), "one UV per vertex")
	var v := vertices[7]
	assert_true(uvs[7].is_equal_approx(Vector2(v.x, v.z) / MapView.DETAIL_TILE))


func test_terrain_material_is_the_splat_shader_with_three_layer_arrays() -> void:
	var material := _surface_mesh("Terrain").surface_get_material(0) as ShaderMaterial
	assert_true(material != null, "ShaderMaterial")
	assert_eq(material.shader.resource_path, "res://assets/shaders/terrain.gdshader")
	for param: StringName in [&"albedo_height", &"normal_maps", &"roughness_ao"]:
		var array := material.get_shader_parameter(param) as Texture2DArray
		assert_true(array != null, "%s is a Texture2DArray" % param)
		if array != null:
			assert_eq(array.get_layers(), TerrainSplat.LAYER_COUNT, "%s layers" % param)
	assert_eq((material.get_shader_parameter(&"layer_repeat") as PackedFloat32Array).size(), 6)


func test_terrain_vertices_carry_weights_summing_to_one() -> void:
	var arrays := _surface_mesh("Terrain").surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	assert_eq(colors.size(), vertices.size(), "one colour (layers 0-3) per vertex")
	assert_eq(custom.size(), vertices.size() * 4, "RGBA float CUSTOM0 (layers 4-5) per vertex")
	for v in vertices.size():
		var c := colors[v]
		var total := c.r + c.g + c.b + c.a + custom[v * 4] + custom[v * 4 + 1]
		assert_true(absf(total - 1.0) <= 0.01, "vertex %d weights sum to %s" % [v, total])
		if absf(total - 1.0) > 0.01:
			return


func test_off_map_margin_is_darkened() -> void:
	var arrays := _surface_mesh("Terrain").surface_get_arrays(0)
	var tints: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# Vertex 0 is the mesh corner (off the map); the map centre is on it.
	assert_true(is_equal_approx(tints[0].x, MapView.OFF_MAP_VALUE))
	var centre := vertices.size() / 2
	assert_true(is_equal_approx(tints[centre].x, 1.0), "on-map vertex %s" % vertices[centre])


func test_low_quality_switches_anti_tiling_and_triplanar_off() -> void:
	_view.quality = GraphicsQuality.features(GraphicsQuality.Level.LOW)
	_view.build(Fixtures.plains_grid(1))
	var material := _surface_mesh("Terrain").surface_get_material(0) as ShaderMaterial
	assert_false(material.get_shader_parameter(&"anti_tiling"))
	assert_false(material.get_shader_parameter(&"triplanar"))
	var array := material.get_shader_parameter(&"albedo_height") as Texture2DArray
	assert_eq(array.get_width(), 512)


func _water_material() -> ShaderMaterial:
	var plane := _view._tiles_root.get_node("Water") as MeshInstance3D
	return plane.mesh.material as ShaderMaterial


## Default value of a uniform, parsed from the shader source: the headless runner uses the dummy
## renderer, where RenderingServer and Shader.get_shader_uniform_list() know no uniforms.
func _uniform_default(shader: Shader, name: String) -> Variant:
	var re := RegEx.create_from_string("uniform\\s+\\w+\\s+%s\\b[^=;]*=\\s*([^;]+);" % name)
	var m := re.search(shader.code)
	assert_true(m != null, "uniform %s has a default" % name)
	var text := m.get_string(1).replace("vec2(", "Vector2(").replace("vec4(", "Color(")
	var expression := Expression.new()
	assert_eq(expression.parse(text), OK)
	return expression.execute()


func test_water_has_normal_map() -> void:
	var material := _water_material()
	assert_true(material.shader.resource_path.ends_with("water.gdshader"))
	assert_true(material.get_shader_parameter(&"normal_map") is Texture2D)
	assert_true(is_equal_approx(_uniform_default(material.shader, "normal_scale"), 0.3))


func test_water_uniforms_have_design_values() -> void:
	var shader := _water_material().shader
	var expect_color := func(name: String, hex: String) -> void:
		var c: Color = _uniform_default(shader, name)
		assert_eq("#" + c.to_html(false), hex, "%s is %s" % [name, hex])
	expect_color.call("shallow_color", "#4c7464")
	expect_color.call("deep_color", "#1b3842")
	assert_true(is_equal_approx(_uniform_default(shader, "deep_distance"), 0.45))
	var speeds: Vector2 = _uniform_default(shader, "ripple_speeds")
	assert_true(speeds.is_equal_approx(Vector2(0.010, 0.016)))


func test_water_has_no_shore_foam() -> void:
	assert_false(_water_material().shader.code.contains("foam"))


func test_water_shader_declares_its_uniforms() -> void:
	# Compiling needs a real renderer (done in the screenshot run); headless we check the source.
	var code := _water_material().shader.code
	assert_true(code.contains("shader_type spatial;"))
	assert_true(RegEx.create_from_string("render_mode[^;]*blend_mix").search(code) != null)
	assert_true(RegEx.create_from_string("render_mode[^;]*depth_draw_never").search(code) != null)
	assert_true(
		code.contains("CURRENT_RENDERER == RENDERER_COMPATIBILITY"), "NDC depth per renderer"
	)
	for name: String in [
		"shallow_color",
		"deep_color",
		"deep_distance",
		"ripple_speeds",
		"normal_map",
		"depth_texture",
		"wind_direction"
	]:
		var declared := RegEx.create_from_string("uniform\\s+\\w+\\s+%s\\b" % name)
		assert_true(declared.search(code) != null, "uniform %s" % name)


func test_terrain_has_tangents_perpendicular_to_normals() -> void:
	var arrays := _surface_mesh("Terrain").surface_get_arrays(0)
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_eq(tangents.size(), normals.size() * 4)
	for i in [0, 7, normals.size() / 2, normals.size() - 1]:
		var t := Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])
		assert_true(absf(t.length() - 1.0) < 1e-4, "unit tangent")
		assert_true(absf(t.dot(normals[i])) < 1e-4, "tangent perpendicular to normal")
		assert_true(t.x > 0.5, "tangent points along +x")
		# Binormal = cross(normal, tangent) * w must be the -z side (up the normal map image).
		var binormal := normals[i].cross(t) * tangents[i * 4 + 3]
		assert_true(binormal.z < -0.5, "binormal points along -z")


func test_foliage_is_built_by_default() -> void:
	assert_true(_view._tiles_root.has_node("Bushes"))
	assert_true(_view.trees().get_child_count() > 0, "tree chunk nodes")


func test_scrub_is_drawn_by_the_tree_field_and_undergrowth_casts_no_shadow() -> void:
	var species := {}
	for node in _view.trees().lod0_nodes():
		if not node.get_meta(&"backdrop"):
			species[node.name] = node.cast_shadow
	for key: String in species:
		if "undergrowth" in key:
			assert_eq(species[key], GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		else:
			assert_eq(species[key], GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


func test_low_quality_builds_no_foliage() -> void:
	_view.quality = GraphicsQuality.features(GraphicsQuality.Level.LOW)
	_view.build(Fixtures.plains_grid(1))
	assert_false(_view._tiles_root.has_node("Bushes"))
	assert_eq(_view.trees().get_child_count(), 0, "no tree nodes")
	assert_eq(_view.trees().planned_count(), 0)
	assert_true(_view._tiles_root.has_node("Terrain"))
