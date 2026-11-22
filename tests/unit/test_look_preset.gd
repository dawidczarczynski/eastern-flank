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


## TASK-201a: the sun is look data. Every preset resolves every sun field.
func test_every_preset_has_all_sun_fields() -> void:
	for preset_name: StringName in LookPreset.PRESETS:
		LookPreset.apply(preset_name)
		for scale: StringName in [&"balanced", VisualScale.TRUE_PRESET]:
			VisualScale.apply(scale)
			var sun := LookPreset.sun()
			for key: String in LookPreset.SUN_DEFAULT:
				assert_true(sun.has(key), "%s / %s lacks sun.%s" % [preset_name, scale, key])
				assert_eq(typeof(sun[key]), typeof(LookPreset.SUN_DEFAULT[key]), key)
	VisualScale.reset()


## Outside `true` the sun is the battle scene's Sun node and its environment's ambient energy.
func test_balanced_sun_is_the_battle_scene_sun() -> void:
	var battle := (load("res://scenes/battle/battle.tscn") as PackedScene).instantiate()
	var scene_sun := battle.get_node("Sun") as DirectionalLight3D
	var env := (battle.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sun := LookPreset.sun()
	var toward := scene_sun.transform.basis.z
	assert_true(absf(rad_to_deg(asin(toward.y)) - sun["elevation_deg"]) < 0.05, "elevation")
	var azimuth := rad_to_deg(atan2(toward.x, -toward.z))
	assert_true(absf(wrapf(azimuth - sun["azimuth_deg"], -180.0, 180.0)) < 0.05, "azimuth")
	assert_true((sun["color"] as Color).is_equal_approx(scene_sun.light_color))
	assert_true(is_equal_approx(sun["energy"], scene_sun.light_energy))
	assert_true(is_equal_approx(sun["angular_distance"], scene_sun.light_angular_distance))
	assert_true(is_equal_approx(sun["shadow_blur"], scene_sun.shadow_blur))
	assert_true(is_equal_approx(sun["shadow_bias"], scene_sun.shadow_bias))
	assert_true(is_equal_approx(sun["shadow_normal_bias"], scene_sun.shadow_normal_bias))
	assert_true(is_equal_approx(sun["ambient_energy"], env.ambient_light_energy))
	# Applying it changes nothing on the scene's light.
	var light := DirectionalLight3D.new()
	var light_env := Environment.new()
	LookPreset.apply_to_sun(light, light_env)
	assert_true(light.transform.basis.z.distance_to(toward) < 0.001)
	assert_true(light.transform.basis.x.distance_to(scene_sun.transform.basis.x) < 0.001)
	assert_true(is_equal_approx(light.light_energy, scene_sun.light_energy))
	assert_true(is_equal_approx(light_env.ambient_light_energy, env.ambient_light_energy))
	light.free()
	battle.free()


## The `true` sun stands lower and warmer (slopes away from it darker), with an ambient floor so
## the shadows are not crushed.
func test_true_sun_is_lower_and_warmer_with_an_ambient_floor() -> void:
	var balanced := LookPreset.sun()
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var real := LookPreset.sun()
	VisualScale.reset()
	assert_true(real["elevation_deg"] < balanced["elevation_deg"])
	assert_true(real["elevation_deg"] > 10.0)
	assert_true(real["ambient_energy"] > 0.0)
	var warm: Color = real["color"]
	var base: Color = balanced["color"]
	assert_true(warm.r / warm.b > base.r / base.b, "warmer sun")
