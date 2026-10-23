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


func test_current_preset_has_the_meadow_off() -> void:
	LookPreset.apply(&"current")
	assert_eq(LookPreset.meadow(), LookPreset.MEADOW_OFF)
	var m := LookPreset.meadow()
	for key in ["dry_stalk_share", "nettle_share", "flower_density", "bare_thinning"]:
		assert_eq(m[key], 0.0, key)
	assert_eq(m["scrub_chance_plains"], 0.0)
	assert_eq(m["scrub_chance_hills"], 0.0)
	assert_eq(m["edge_tall_bonus"], 0.0)
	for key in ["tall_height", "dry_stalk_height", "nettle_height"]:
		assert_eq(m[key], 1.0, key)
	# No tall grass at all: the smoothstep never leaves 0 for a noise in [0, 1].
	assert_eq(TerrainNoise.smooth(m["tall_from"], m["tall_to"], 1.0), 0.0)


func test_meadow_returns_a_copy() -> void:
	var m := LookPreset.meadow()
	m["tall_height"] = 9.0
	(m["flowers"] as Array).clear()
	assert_eq(LookPreset.meadow()["tall_height"], 1.5)
	assert_eq((LookPreset.meadow()["flowers"] as Array).size(), 4)
	assert_eq(LookPreset.MEADOW_OFF["tall_height"], 1.0)


func test_every_preset_meadow_is_within_the_limits() -> void:
	for name: StringName in LookPreset.PRESETS:
		LookPreset.apply(name)
		var m := LookPreset.meadow()
		if name != &"current":
			var total := 0.0
			for group: Dictionary in m["flowers"]:
				total += group["share"]
			assert_true(absf(total - 1.0) < 1e-6, "%s flower shares %f" % [name, total])
		for key in ["tall_height", "dry_stalk_height", "nettle_height"]:
			assert_true(m[key] <= 1.5, "%s %s" % [name, key])
		assert_true((m["flower_height"] as Vector2).y <= 1.5, "%s flower_height" % name)
		assert_true(m["centre_clear"] >= 0.35, "%s centre_clear" % name)


func test_early_autumn_meadow_overrides() -> void:
	LookPreset.apply(&"early_autumn")
	var m := LookPreset.meadow()
	assert_eq(m["dry_stalk_share"], 0.5)
	assert_eq(m["flower_density"], 12.0)
	assert_eq((m["flowers"] as Array)[1]["share"], 0.45)
