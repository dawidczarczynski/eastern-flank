extends TestCase

const ENV_PATH := "res://assets/environments/battle_environment.tres"
const SCENE_PATH := "res://scenes/battle/battle.tscn"
const TOL := 0.002

var _env: Environment


func before_each() -> void:
	_env = load(ENV_PATH) as Environment


func _assert_color(actual: Color, expected: Color) -> void:
	var ok := (
		absf(actual.r - expected.r) <= TOL
		and absf(actual.g - expected.g) <= TOL
		and absf(actual.b - expected.b) <= TOL
	)
	assert_true(ok, "color %s != %s" % [actual, expected])


func test_environment_loads() -> void:
	assert_true(_env != null, "battle_environment.tres must load as Environment")


func test_background_is_hdri_sky() -> void:
	assert_eq(_env.background_mode, Environment.BG_SKY)


func test_fog() -> void:
	assert_true(_env.fog_enabled)
	assert_eq(_env.fog_mode, Environment.FOG_MODE_DEPTH)
	assert_true(is_equal_approx(_env.fog_depth_begin, 30.0))
	assert_true(is_equal_approx(_env.fog_depth_end, 140.0))
	assert_true(_env.fog_aerial_perspective >= 0.5 and _env.fog_aerial_perspective <= 0.9)
	assert_true(_env.fog_sky_affect >= 0.3 and _env.fog_sky_affect <= 0.7)
	# Derived from the HDRI horizon band (average sRGB #abb1b5), no longer the old #a9b4b2 haze.
	_assert_color(_env.fog_light_color, Color.html("#abb1b5"))
	var old := Color.html("#a9b4b2")
	assert_false(_env.fog_light_color.is_equal_approx(old))
	# Same energy for fog and sky, so fully fogged geometry blends into the sky at the horizon.
	assert_true(is_equal_approx(_env.fog_light_energy, _env.background_energy_multiplier))


func test_tonemap() -> void:
	assert_eq(_env.tonemap_mode, Environment.TONE_MAPPER_AGX)
	assert_true(is_equal_approx(_env.tonemap_exposure, 1.3))


func _high_env() -> Environment:
	# Same steps as BattleController: own copy, then the quality preset (which also adds the grade).
	var env := _env.duplicate() as Environment
	GraphicsQuality.apply_environment(env, GraphicsQuality.features(GraphicsQuality.Level.HIGH))
	return env


func test_high_has_ssil_glow_and_grade() -> void:
	var env := _high_env()
	assert_true(env.ssil_enabled)
	assert_true(env.glow_enabled)
	assert_true(env.adjustment_enabled)
	assert_true(env.adjustment_color_correction is Texture3D)


func test_low_drops_ssil_glow_and_grade_and_scene_instantiates() -> void:
	var env := _env.duplicate() as Environment
	GraphicsQuality.apply_environment(env, GraphicsQuality.features(GraphicsQuality.Level.LOW))
	assert_false(env.ssil_enabled)
	assert_false(env.glow_enabled)
	assert_false(env.adjustment_enabled)
	var battle := (load(SCENE_PATH) as PackedScene).instantiate()
	assert_true(battle != null)
	battle.free()


func test_no_depth_of_field_on_camera() -> void:
	var battle := (load(SCENE_PATH) as PackedScene).instantiate()
	var camera := battle.find_child("Camera3D", true, false) as Camera3D
	assert_true(camera != null)
	var attrs := camera.attributes as CameraAttributesPractical
	assert_true(attrs == null or not attrs.dof_blur_far_enabled)
	assert_true(attrs == null or not attrs.dof_blur_near_enabled)
	battle.free()


func test_ambient_and_reflections_from_sky() -> void:
	assert_eq(_env.ambient_light_source, Environment.AMBIENT_SOURCE_SKY)
	assert_true(_env.ambient_light_energy >= 0.3 and _env.ambient_light_energy <= 0.8)
	assert_eq(_env.reflected_light_source, Environment.REFLECTION_SOURCE_SKY)


func test_ssao() -> void:
	# The resource is the HIGH look; LOW switches effects off at runtime (GraphicsQuality).
	assert_true(_high_env().ssao_enabled)


func test_sky_material_is_hdri_panorama() -> void:
	assert_true(_env.sky is Sky, "environment needs a Sky")
	var mat := _env.sky.sky_material as PanoramaSkyMaterial
	assert_true(mat != null, "sky material must be a PanoramaSkyMaterial")
	assert_true(mat.panorama != null)
	assert_true(mat.panorama.resource_path.begins_with("res://assets/third_party/hdri/"))
	# Resource default; GraphicsQuality picks the real mode per level.
	assert_eq(_env.sky.process_mode, Sky.PROCESS_MODE_QUALITY)


## Godot's panorama mapping: u = atan2(x, -z) / TAU (u = 0 looks along -Z, increasing towards +X).
## HDRI sun at pixel x = 1228 of 2048 (measured, TASK-054). Environment.sky_rotation (Y) turns the
## sky by that angle, so the sun's world azimuth is the HDRI azimuth minus the rotation (checked
## against a render looking along the Sun light's toward-sun direction: the sun is centred).
func _hdri_sun_world_azimuth_deg() -> float:
	var u := 1228.0 / 2048.0
	var hdri_azimuth := rad_to_deg(u * TAU)
	return wrapf(hdri_azimuth - rad_to_deg(_env.sky_rotation.y), -180.0, 180.0)


func test_sky_rotation_aligns_hdri_sun_with_sun_light() -> void:
	var battle := (load(SCENE_PATH) as PackedScene).instantiate()
	var sun := battle.get_node("Sun") as DirectionalLight3D
	var toward_sun := sun.transform.basis.z  # the light shines along -Z, the sun is on the +Z side
	var light_azimuth := rad_to_deg(atan2(toward_sun.x, -toward_sun.z))
	var diff := absf(wrapf(_hdri_sun_world_azimuth_deg() - light_azimuth, -180.0, 180.0))
	assert_true(diff <= 10.0, "sun azimuth difference %s deg" % diff)
	assert_true(is_equal_approx(_env.sky_rotation.x, 0.0))
	assert_true(is_equal_approx(_env.sky_rotation.z, 0.0))
	battle.free()


func test_sun() -> void:
	var battle := (load(SCENE_PATH) as PackedScene).instantiate()
	var sun := battle.get_node("Sun") as DirectionalLight3D
	_assert_color(sun.light_color, Color.html("#ffeedd"))
	assert_true(sun.light_energy >= 0.9 and sun.light_energy <= 1.6)
	assert_true(sun.shadow_enabled)
	assert_true(sun.light_angular_distance > 0.0)
	var forward := -sun.transform.basis.z
	var elevation := rad_to_deg(asin(-forward.y))
	assert_true(elevation >= 25.0 and elevation <= 40.0, "sun elevation %s" % elevation)
	assert_true(absf(elevation - 37.9) < 1.0, "elevation matches the HDRI sun %s" % elevation)
	# Same azimuth as before TASK-051, so the README framing keeps its light direction.
	var azimuth := Vector2(forward.x, forward.z).normalized()
	assert_true(
		azimuth.distance_to(Vector2(0.520, -0.405).normalized()) < 0.01, "azimuth %s" % azimuth
	)
	assert_true(is_equal_approx(sun.shadow_blur, 1.2))
	assert_true(is_equal_approx(sun.light_angular_distance, 1.0))
	battle.free()


func test_environment_is_referenced_externally() -> void:
	var battle := (load(SCENE_PATH) as PackedScene).instantiate()
	var we := battle.get_node("WorldEnvironment") as WorldEnvironment
	assert_eq(we.environment.resource_path, ENV_PATH)
	battle.free()


func test_shadow_project_settings() -> void:
	var size: int = ProjectSettings.get_setting(
		"rendering/lights_and_shadows/directional_shadow/size"
	)
	var quality: int = ProjectSettings.get_setting(
		"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"
	)
	assert_eq(size, 4096)
	assert_eq(quality, 3)


func test_windows_uses_d3d12() -> void:
	# SSAO renders as grey blocks on Vulkan with an AMD RX 580 (Godot 4.5.1); D3D12 is correct.
	var driver: String = ProjectSettings.get_setting("rendering/rendering_device/driver.windows")
	assert_eq(driver, "d3d12")


func test_battle_camera_fov() -> void:
	var battle := (load(SCENE_PATH) as PackedScene).instantiate()
	var camera := battle.get_node("CameraRig/Camera3D") as Camera3D
	assert_true(is_equal_approx(camera.fov, 40.0), "fov %s" % camera.fov)
	battle.free()
