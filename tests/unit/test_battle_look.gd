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


func test_background_is_flat_haze_color() -> void:
	assert_eq(_env.background_mode, Environment.BG_COLOR)
	_assert_color(_env.background_color, Color.html("#a9b4b2"))


func test_fog() -> void:
	assert_true(_env.fog_enabled)
	assert_eq(_env.fog_mode, Environment.FOG_MODE_DEPTH)
	assert_true(is_equal_approx(_env.fog_depth_begin, 38.0))
	assert_true(is_equal_approx(_env.fog_depth_end, 90.0))
	assert_eq(_env.fog_light_color, _env.background_color)
	# Same energy for fog and background, so fully fogged geometry blends into the background.
	assert_true(is_equal_approx(_env.fog_light_energy, _env.background_energy_multiplier))


func test_tonemap() -> void:
	assert_eq(_env.tonemap_mode, Environment.TONE_MAPPER_ACES)
	assert_true(is_equal_approx(_env.tonemap_exposure, 1.05))


func test_ambient() -> void:
	assert_eq(_env.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR)
	_assert_color(_env.ambient_light_color, Color.html("#b9bfc0"))
	assert_true(_env.ambient_light_energy >= 0.25 and _env.ambient_light_energy <= 0.6)


func test_sun() -> void:
	var battle := (load(SCENE_PATH) as PackedScene).instantiate()
	var sun := battle.get_node("Sun") as DirectionalLight3D
	_assert_color(sun.light_color, Color.html("#fff0d8"))
	assert_true(sun.light_energy >= 0.7 and sun.light_energy <= 1.4)
	assert_true(sun.shadow_enabled)
	assert_true(sun.light_angular_distance > 0.0)
	var forward := -sun.transform.basis.z
	assert_true(
		forward.distance_to(Vector3(0.520, -0.752, -0.405)) < 0.01, "sun forward is %s" % forward
	)
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
