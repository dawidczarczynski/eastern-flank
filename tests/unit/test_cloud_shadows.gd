extends TestCase
## Moving cloud shadows and the `true` colour grade (TASK-201b).

const SHADERS := "res://assets/shaders/"
const CLOUD_INCLUDE := "cloud_shadow.gdshaderinc"


func after_each() -> void:
	VisualScale.reset()
	LookPreset.reset()
	CloudShadows.setup(true)


func _text(file: String) -> String:
	return FileAccess.get_file_as_string(SHADERS + file)


func test_world_shaders_include_the_cloud_shader() -> void:
	for file in [
		"terrain.gdshader",
		"road.gdshader",
		"grass.gdshader",
		"foliage_body.gdshaderinc",
		"canopy.gdshader",
		"tree_impostor.gdshader",
		"forest_impostor.gdshader",
	]:
		assert_true(_text(file).contains(CLOUD_INCLUDE), "%s includes the cloud shader" % file)


func test_foliage_variants_reach_the_include_through_the_body() -> void:
	for file in ["foliage.gdshader", "foliage_solid.gdshader"]:
		assert_true(_text(file).contains("foliage_body.gdshaderinc"), file)


func test_the_unit_shader_does_not_include_the_cloud_shader() -> void:
	assert_false(_text("camo.gdshader").contains("cloud_shadow"))
	assert_false(_text("skin.gdshader").contains("cloud_shadow"))


func test_the_impostor_bake_skips_the_clouds() -> void:
	var body := _text("foliage_body.gdshaderinc")
	assert_true(
		body.contains("#ifndef IMPOSTOR_BAKE\n" + '#include "res://assets/shaders/' + CLOUD_INCLUDE)
	)


func test_include_declares_the_global_uniforms() -> void:
	var text := _text(CLOUD_INCLUDE)
	for param in ["cloud_shadow_strength", "cloud_scale", "cloud_speed", "cloud_noise"]:
		assert_true(text.contains("global uniform") and text.contains(param), param)


func test_strength_is_zero_outside_true_and_on_low() -> void:
	assert_eq(LookPreset.clouds()["strength"], 0.0, "balanced")
	CloudShadows.setup(true)
	assert_eq(CloudShadows.strength(), 0.0, "balanced stays off")
	VisualScale.apply(VisualScale.TRUE_PRESET)
	assert_true(LookPreset.clouds()["strength"] > 0.0, "true look value")
	CloudShadows.setup(true)
	assert_true(CloudShadows.strength() > 0.0, "HIGH")
	CloudShadows.setup(false)
	assert_eq(CloudShadows.strength(), 0.0, "LOW")
	assert_eq(GraphicsQuality.features(GraphicsQuality.Level.LOW)["clouds"], false)


func test_every_look_but_true_has_no_clouds() -> void:
	for name: StringName in LookPreset.PRESETS:
		LookPreset.apply(name)
		assert_eq(LookPreset.clouds()["strength"], 0.0, String(name))


func test_noise_texture_is_tileable() -> void:
	var img := CloudShadows.noise_image()
	var size := img.get_width()
	assert_eq(size, CloudShadows.NOISE_SIZE)
	# The wrap step must not exceed the largest step between neighbours inside the image.
	var limit := 0.0
	for i in size:
		for j in size - 1:
			limit = maxf(limit, absf(img.get_pixel(j, i).r - img.get_pixel(j + 1, i).r))
			limit = maxf(limit, absf(img.get_pixel(i, j).r - img.get_pixel(i, j + 1).r))
	limit += 1.0 / 255.0
	for i in size:
		assert_true(
			absf(img.get_pixel(0, i).r - img.get_pixel(size - 1, i).r) <= limit, "row %d" % i
		)
		assert_true(
			absf(img.get_pixel(i, 0).r - img.get_pixel(i, size - 1).r) <= limit, "column %d" % i
		)


func test_noise_has_both_light_and_shadow_patches() -> void:
	var img := CloudShadows.noise_image()
	var covered := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).r > 0.44:
				covered += 1
	var share := float(covered) / (img.get_width() * img.get_height())
	assert_true(share > 0.15 and share < 0.6, "cloud share %f" % share)


func test_balanced_grade_is_unchanged() -> void:
	LookPreset.apply(&"muted_summer")
	var grade := LookPreset.grade(ColorGrade.DEFAULT)
	assert_eq(grade["saturation"], 0.8)
	assert_eq(grade["contrast"], ColorGrade.DEFAULT["contrast"])
	assert_eq(grade["highlight_weight"], 0.07)


func test_true_grade_follows_the_real_size_values() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grade := LookPreset.grade(ColorGrade.DEFAULT)
	for key: String in LookPreset.REAL_SIZE_GRADE:
		assert_eq(grade[key], LookPreset.REAL_SIZE_GRADE[key], key)
	assert_true(grade["saturation"] > 0.92, "fuller colour than the muted looks")


func test_baked_grade_follows_the_visual_scale() -> void:
	var balanced := ColorGrade.cached_texture()
	VisualScale.apply(VisualScale.TRUE_PRESET)
	assert_true(ColorGrade.cached_texture() != balanced, "rebuilt under true")
