extends TestCase

const LOW := GraphicsQuality.Level.LOW
const HIGH := GraphicsQuality.Level.HIGH


func test_detect_gpu_is_high() -> void:
	assert_eq(GraphicsQuality.detect("forward_plus", "NVIDIA GeForce RTX 3060"), HIGH)


func test_detect_software_adapters_are_low() -> void:
	assert_eq(GraphicsQuality.detect("forward_plus", "llvmpipe (LLVM 15.0.7, 256 bits)"), LOW)
	assert_eq(GraphicsQuality.detect("forward_plus", "Microsoft Basic Render Driver"), LOW)
	assert_eq(GraphicsQuality.detect("forward_plus", "SwiftShader Device"), LOW)
	assert_eq(GraphicsQuality.detect("forward_plus", "softpipe"), LOW)


func test_detect_compatibility_is_low() -> void:
	assert_eq(GraphicsQuality.detect("gl_compatibility", "NVIDIA GeForce RTX 3060"), LOW)


func test_parse_override() -> void:
	assert_eq(GraphicsQuality.parse_override(PackedStringArray(["--quality=low"])), LOW)
	assert_eq(GraphicsQuality.parse_override(PackedStringArray(["--quality=HIGH"])), HIGH)
	assert_eq(GraphicsQuality.parse_override(PackedStringArray(["--foo"])), -1)
	assert_eq(GraphicsQuality.parse_override(PackedStringArray(["--quality=ultra"])), -1)
	assert_eq(GraphicsQuality.parse_override(PackedStringArray()), -1)


func test_features_have_same_keys() -> void:
	var low := GraphicsQuality.features(LOW)
	var high := GraphicsQuality.features(HIGH)
	var low_keys := low.keys()
	var high_keys := high.keys()
	low_keys.sort()
	high_keys.sort()
	assert_eq(low_keys, high_keys)


func test_features_values() -> void:
	var low := GraphicsQuality.features(LOW)
	var high := GraphicsQuality.features(HIGH)
	for key in [
		"ssao",
		"ssil",
		"ssr",
		"glow",
		"color_grade",
		"shadows",
		"foliage",
		"particles",
		"wind",
		"backdrop_scatter"
	]:
		assert_eq(low[key], false, key)
		assert_eq(high[key], true, key)
	assert_eq(low["shadow_atlas_size"], 2048)
	assert_eq(high["shadow_atlas_size"], 4096)
	assert_eq(low["shadow_max_distance"], 40.0)
	assert_eq(high["shadow_max_distance"], 80.0)
	assert_eq(low["msaa_3d"], Viewport.MSAA_DISABLED)
	assert_eq(high["msaa_3d"], Viewport.MSAA_4X)  # matches project.godot
	assert_eq(low["grass_density"], 0.0)
	assert_eq(high["grass_density"], 1.0)
	assert_eq(low["decals_max"], 16)
	assert_eq(high["decals_max"], 64)
	# The software rasteriser is geometry- and fill-bound: no foliage, no shadows, half resolution.
	assert_eq(low["render_scale"], 0.5)
	assert_eq(high["render_scale"], 1.0)


func test_high_matches_project_settings() -> void:
	var msaa: int = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d")
	assert_eq(GraphicsQuality.features(HIGH)["msaa_3d"], msaa)


func test_apply_low_turns_effects_off() -> void:
	var env := Environment.new()
	env.ssao_enabled = true
	env.ssil_enabled = true
	env.ssr_enabled = true
	env.glow_enabled = true
	GraphicsQuality.apply_environment(env, GraphicsQuality.features(LOW))
	assert_false(env.ssao_enabled)
	assert_false(env.ssil_enabled)
	assert_false(env.ssr_enabled)
	assert_false(env.glow_enabled)


func test_apply_high_enables_ssao_and_keeps_configured_effects() -> void:
	var env := Environment.new()
	env.ssil_enabled = true
	GraphicsQuality.apply_environment(env, GraphicsQuality.features(HIGH))
	assert_true(env.ssao_enabled)
	assert_true(env.ssil_enabled, "HIGH keeps what the resource configured")
	assert_false(env.ssr_enabled, "HIGH does not enable unconfigured effects")
	assert_false(env.glow_enabled)


func test_apply_sun() -> void:
	var sun := DirectionalLight3D.new()
	GraphicsQuality.apply_sun(sun, GraphicsQuality.features(LOW))
	assert_eq(sun.directional_shadow_max_distance, 40.0)
	assert_false(sun.shadow_enabled)
	GraphicsQuality.apply_sun(sun, GraphicsQuality.features(HIGH))
	assert_eq(sun.directional_shadow_max_distance, 80.0)
	assert_true(sun.shadow_enabled)
	sun.free()


func test_apply_viewport_sets_msaa_and_render_scale() -> void:
	var viewport := SubViewport.new()
	GraphicsQuality.apply_viewport(viewport, GraphicsQuality.features(LOW))
	assert_eq(viewport.msaa_3d, Viewport.MSAA_DISABLED)
	assert_eq(viewport.scaling_3d_scale, 0.5)
	GraphicsQuality.apply_viewport(viewport, GraphicsQuality.features(HIGH))
	assert_eq(viewport.msaa_3d, Viewport.MSAA_4X)
	assert_eq(viewport.scaling_3d_scale, 1.0)
	viewport.free()
