extends TestCase
## UnitRenderRules: what a unit model's materials and geometry may cost the renderer (ADR 0023).


func _shader_material(fragment: String, mode := "") -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = "shader_type spatial;\n%s\nvoid fragment() {\n%s\n}\n" % [mode, fragment]
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func test_plain_opaque_materials_are_allowed() -> void:
	assert_eq(UnitRenderRules.material_violations(null), [] as Array[String])
	assert_eq(UnitRenderRules.material_violations(StandardMaterial3D.new()), [] as Array[String])
	var scissor := StandardMaterial3D.new()
	scissor.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	assert_eq(UnitRenderRules.material_violations(scissor), [] as Array[String], "opaque pass")
	var shaded := _shader_material(
		"ALBEDO = vec3(0.5);\nALPHA = 1.0;\nALPHA_SCISSOR_THRESHOLD = 0.5;"
	)
	assert_eq(UnitRenderRules.material_violations(shaded), [] as Array[String], "scissor shader")


func test_standard_material_features_that_leave_the_opaque_pass() -> void:
	var cases := {
		"transparency":
		func(m: StandardMaterial3D) -> void: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA,
		"subsurface": func(m: StandardMaterial3D) -> void: m.subsurf_scatter_enabled = true,
		"refraction": func(m: StandardMaterial3D) -> void: m.refraction_enabled = true,
		"proximity": func(m: StandardMaterial3D) -> void: m.proximity_fade_enabled = true,
		"blend": func(m: StandardMaterial3D) -> void: m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD,
		"next_pass": func(m: StandardMaterial3D) -> void: m.next_pass = StandardMaterial3D.new(),
	}
	for word: String in cases:
		var material := StandardMaterial3D.new()
		(cases[word] as Callable).call(material)
		var found := UnitRenderRules.material_violations(material)
		assert_true(found.size() > 0, word)
		assert_true(" ".join(found).contains(word), "%s named in %s" % [word, found])


func test_shader_code_that_needs_a_full_screen_or_alpha_pass() -> void:
	var sss := UnitRenderRules.material_violations(_shader_material("SSS_STRENGTH = 0.3;"))
	assert_true(sss.size() == 1 and sss[0].contains("subsurface"), str(sss))
	var alpha := UnitRenderRules.material_violations(_shader_material("ALPHA = 0.5;"))
	assert_true(alpha.size() == 1 and alpha[0].contains("ALPHA"), str(alpha))
	var blend := _shader_material("ALBEDO = vec3(1.0);", "render_mode blend_add;")
	assert_true(UnitRenderRules.material_violations(blend).size() > 0, "blend_add")
	var screen := _shader_material("ALBEDO = vec3(1.0);")
	screen.shader.code = screen.shader.code.replace(
		"void fragment", "uniform sampler2D screen : hint_screen_texture;\nvoid fragment"
	)
	assert_true(UnitRenderRules.material_violations(screen).size() > 0, "screen texture")


func test_comments_do_not_count_and_includes_do() -> void:
	var commented := _shader_material(
		"// SSS_STRENGTH would cost a full-screen pass\nALBEDO = vec3(1.0);"
	)
	assert_eq(UnitRenderRules.material_violations(commented), [] as Array[String])
	var source := UnitRenderRules.shader_source(
		'shader_type spatial;\n#include "res://assets/shaders/wind.gdshaderinc"\n'
	)
	assert_true(source.contains("wind_offset"), "the include is pasted in")


func test_the_shared_unit_shaders_follow_the_rules() -> void:
	for path: String in [
		"res://assets/shaders/camo.gdshader", "res://assets/shaders/skin.gdshader"
	]:
		var material := ShaderMaterial.new()
		material.shader = load(path)
		assert_eq(UnitRenderRules.material_violations(material), [] as Array[String], path)


func test_violations_name_the_part_and_hidden_parts_count_too() -> void:
	var model := Node3D.new()
	var hidden := Node3D.new()
	hidden.visible = false
	model.add_child(hidden)
	var part := MeshInstance3D.new()
	part.name = "Visor"
	part.mesh = BoxMesh.new()
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	part.material_override = glass
	hidden.add_child(part)
	var found := UnitRenderRules.violations(model)
	assert_eq(found.size(), 1)
	assert_true(found[0].contains("Visor") and found[0].contains("transparency"), found[0])
	model.free()


func test_far_triangles_use_the_generated_levels_and_skip_hidden_parts() -> void:
	var kit := MeshKit.new()
	kit.rod(Vector3.ZERO, Vector3.UP, 0.05, 0.3, 48, 0.004)
	var mesh := MeshLods.with_lods(kit.commit())
	var model := Node3D.new()
	var part := MeshInstance3D.new()
	part.mesh = mesh
	model.add_child(part)
	var full := UnitRenderRules.triangles(model)
	assert_eq(full, MeshLods.triangles(mesh))
	assert_true(UnitRenderRules.far_triangles(model) < full, "a coarser level in the battle view")
	assert_eq(UnitRenderRules.far_triangles(model, 1e-6), full, "full detail up close")
	# A model drawn half as large is as coarse as one twice as far away.
	var half := UnitRenderRules.far_triangles(model, UnitRenderRules.FAR_PIXEL * 2.0)
	model.scale = Vector3.ONE * 0.5
	assert_eq(UnitRenderRules.far_triangles(model), half)
	part.visible = false
	assert_eq(UnitRenderRules.far_triangles(model), 0)
	model.free()
