extends TestCase

const TOLERANCE := 0.002


func _srgb(hex: String) -> Color:
	return Color(hex).srgb_to_linear()


func _assert_color(actual: Color, expected: Color) -> void:
	var ok := (
		absf(actual.r - expected.r) < TOLERANCE
		and absf(actual.g - expected.g) < TOLERANCE
		and absf(actual.b - expected.b) < TOLERANCE
	)
	assert_true(ok, "expected %s, got %s" % [expected, actual])


func _grass() -> Color:
	return _srgb("#627c33").lerp(_srgb("#87974b"), TerrainNoise.smooth(0.35, 0.7, 0.5))


func test_deep_water() -> void:
	_assert_color(
		TerrainColors.color_at(-1.0, 1.0, 0.5, Terrain.Type.WATER, true), _srgb("#17323b")
	)


func test_off_map_is_darkened() -> void:
	var deep := _srgb("#17323b")
	var expected := Color(deep.r * 0.6, deep.g * 0.6, deep.b * 0.6)
	_assert_color(TerrainColors.color_at(-1.0, 1.0, 0.5, Terrain.Type.WATER, false), expected)


func test_high_flat_peak_is_snow() -> void:
	_assert_color(
		TerrainColors.color_at(2.5, 1.0, 0.5, Terrain.Type.PLAINS, true), _srgb("#eef0ef")
	)


func test_plains_are_grass() -> void:
	_assert_color(TerrainColors.color_at(0.3, 1.0, 0.5, Terrain.Type.PLAINS, true), _grass())


func test_forest_is_dark_green() -> void:
	var forest := _srgb("#46672f").lerp(_srgb("#587a38"), 0.5)
	_assert_color(
		TerrainColors.color_at(0.3, 1.0, 0.5, Terrain.Type.FOREST, true),
		_grass().lerp(forest, 0.85)
	)


func test_steep_slope_is_rock() -> void:
	var rock := _srgb("#756e5e").lerp(_srgb("#a29c8f"), 0.5)
	_assert_color(TerrainColors.color_at(0.3, 0.5, 0.5, Terrain.Type.PLAINS, true), rock)


func test_noise_helpers_are_deterministic_and_bounded() -> void:
	var k := TerrainColors.noise_k(1.3, -2.7)
	assert_eq(k, TerrainColors.noise_k(1.3, -2.7))
	assert_true(k >= 0.0 and k <= 1.0)
	var j := TerrainColors.jitter(1.3, -2.7)
	assert_eq(j, TerrainColors.jitter(1.3, -2.7))
	assert_true(absf(j.x - 1.3) <= 0.275 and absf(j.y + 2.7) <= 0.275, str(j))


func _plains(mac: float) -> Color:
	return TerrainColors.color_at(0.3, 1.0, 0.5, Terrain.Type.PLAINS, true, mac)


func test_macro_dry_patch_moves_toward_dry() -> void:
	assert_true(_plains(0.8).r > _plains(0.5).r, "dry patch must be redder")
	_assert_color(_plains(0.5), _grass())


func test_macro_moist_patch_moves_toward_moist() -> void:
	assert_true(_plains(0.2).g < _plains(0.5).g, "moist patch must be darker green")
	assert_true(_plains(0.2).r < _plains(0.5).r, "moist patch must be less red")


func test_macro_does_not_change_forest() -> void:
	var neutral := TerrainColors.color_at(0.3, 1.0, 0.5, Terrain.Type.FOREST, true, 0.5)
	_assert_color(TerrainColors.color_at(0.3, 1.0, 0.5, Terrain.Type.FOREST, true, 0.9), neutral)
	_assert_color(TerrainColors.color_at(0.3, 1.0, 0.5, Terrain.Type.FOREST, true, 0.1), neutral)


func test_macro_k_is_in_unit_range() -> void:
	for i in 20:
		var m := TerrainColors.macro_k(i * 1.7, i * 0.9)
		assert_true(m >= 0.0 and m <= 1.0)
