extends TestCase


func after_each() -> void:
	LookPreset.reset()


func test_default_is_muted_summer() -> void:
	assert_eq(LookPreset.DEFAULT_PRESET, &"muted_summer")
	assert_true(LookPreset.layer_tints(TerrainGround.LAYER_TINTS) != TerrainGround.LAYER_TINTS)


func test_current_preset_changes_nothing() -> void:
	LookPreset.apply(&"current")
	assert_eq(LookPreset.layer_tints(TerrainGround.LAYER_TINTS), TerrainGround.LAYER_TINTS)
	assert_eq(LookPreset.leaf_color(&"pine", Color.RED), Color.RED)
	assert_eq(LookPreset.share(&"pine", 0.6), 0.6)
	assert_eq(LookPreset.grade(ColorGrade.DEFAULT), ColorGrade.DEFAULT)
	assert_true(LookPreset.water_params().is_empty())


func test_every_preset_has_one_tint_per_ground_layer() -> void:
	for name: StringName in LookPreset.PRESETS:
		LookPreset.apply(name)
		var tints := LookPreset.layer_tints(TerrainGround.LAYER_TINTS)
		assert_eq(tints.size(), TerrainGround.LAYER_TINTS.size(), String(name))


func test_species_shares_sum_to_one_per_group() -> void:
	for name: StringName in LookPreset.PRESETS:
		LookPreset.apply(name)
		for group in [TreeSpecies.CONIFERS, TreeSpecies.DECIDUOUS]:
			var total := 0.0
			for species: StringName in group:
				total += LookPreset.share(species, TreeSpecies.SHARES[species])
			assert_true(absf(total - 1.0) < 1e-6, "%s %f" % [name, total])


func test_muted_summer_water_is_darker_and_more_opaque() -> void:
	var water := LookPreset.water_params()
	var shallow: Color = water["shallow_color"]
	assert_true(shallow.v < 0.5)
	assert_true(float(water["shallow_alpha"]) > 0.55)


func test_apply_rebuilds_the_baked_grade() -> void:
	var before := ColorGrade.cached_texture()
	LookPreset.apply(&"overcast")
	assert_true(before != ColorGrade.cached_texture())


func test_unknown_preset_falls_back_to_the_default() -> void:
	LookPreset.apply(&"nope")
	assert_eq(LookPreset.preset(&"nope"), LookPreset.preset(LookPreset.DEFAULT_PRESET))
