extends TestCase

const Battle := preload("res://src/presentation/battle_controller.gd")
const DESIGN_SHARES := {&"pine": 0.6, &"spruce": 0.4, &"birch": 0.35, &"oak": 0.3, &"alder": 0.35}


func _plan_trees() -> Array:
	var grid := Scenario.default_battle(Battle.MAP_SEED).grid
	return ScatterPlanner.plan(grid, TerrainSurface.new(grid), MapView.SCATTER_SEED)["trees"]


func test_pick_is_deterministic() -> void:
	var tree := {"position": Vector3(1.5, 0.2, -3.25), "k": 0.37, "conifer": false}
	var a := TreeSpecies.pick(tree)
	var b := TreeSpecies.pick(tree.duplicate())
	assert_eq(a["species"], b["species"])
	assert_eq(a["variant"], b["variant"])
	assert_eq(a["custom"], b["custom"])


func test_species_groups_shares_and_variants() -> void:
	var trees := _plan_trees()
	assert_true(trees.size() > 300, "enough trees: %d" % trees.size())
	var counts := {}
	var group_totals := {true: 0, false: 0}
	var variants := {}
	for tree: Dictionary in trees:
		var pick := TreeSpecies.pick(tree)
		var species: StringName = pick["species"]
		var conifer: bool = tree["conifer"]
		if conifer:
			assert_true(species in [&"pine", &"spruce"], "conifer got %s" % species)
		else:
			assert_true(species in [&"birch", &"oak", &"alder"], "deciduous got %s" % species)
		counts[species] = counts.get(species, 0) + 1
		group_totals[conifer] += 1
		variants["%s%d" % [species, pick["variant"]]] = true
	for species: StringName in DESIGN_SHARES:
		var total: int = group_totals[TreeSpecies.is_conifer(species)]
		var share := float(counts.get(species, 0)) / total
		assert_true(absf(share - DESIGN_SHARES[species]) <= 0.1, "%s share %.3f" % [species, share])
		for variant in 3:
			assert_true(
				variants.has("%s%d" % [species, variant]), "%s variant %d" % [species, variant]
			)


func test_custom_data_ranges_and_autumn_share() -> void:
	var autumn := 0
	var deciduous := 0
	for tree: Dictionary in _plan_trees():
		var custom: Color = TreeSpecies.pick(tree)["custom"]
		var conifer: bool = tree["conifer"]
		var is_autumn := custom.r >= 0.04 - 1e-6
		if is_autumn:
			assert_false(conifer, "no autumn conifer")
			assert_true(custom.r <= 0.07 + 1e-6, "autumn hue %f" % custom.r)
			autumn += 1
		else:
			assert_true(custom.r >= -0.03 - 1e-6 and custom.r <= 0.03 + 1e-6, "hue %f" % custom.r)
		assert_true(custom.g >= 0.85 and custom.g <= 1.1, "value %f" % custom.g)
		assert_true(custom.b >= 0.9 and custom.b <= 1.05, "saturation %f" % custom.b)
		assert_true(custom.a >= 0.0 and custom.a < 1.0, "phase %f" % custom.a)
		if not conifer:
			deciduous += 1
	var share := float(autumn) / deciduous
	assert_true(absf(share - 0.04) <= 0.02, "autumn share %.3f" % share)
