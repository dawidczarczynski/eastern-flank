extends TestCase
## TerrainSplat: per-vertex ground layer weights (TASK-055).

const SUM_TOLERANCE := 1e-4
const WATER_LEVEL := 0.0
const PLAINS := Terrain.Type.PLAINS
const FOREST := Terrain.Type.FOREST
const HILLS := Terrain.Type.HILLS
const WATER := Terrain.Type.WATER


func _weights(
	terrain: int, slope: float, height: float, moisture := 0.5, macro := 0.5
) -> PackedFloat32Array:
	return TerrainSplat.weights(terrain, slope, height, WATER_LEVEL, moisture, macro)


func _assert_valid(w: PackedFloat32Array, label: String) -> void:
	assert_eq(w.size(), TerrainSplat.LAYER_COUNT, label + ": layer count")
	var total := 0.0
	for value in w:
		assert_true(value >= 0.0, "%s: negative weight %s" % [label, value])
		total += value
	assert_true(absf(total - 1.0) < SUM_TOLERANCE, "%s: sum %s" % [label, total])


func test_every_result_is_six_non_negative_weights_summing_to_one() -> void:
	for terrain: int in [-1] + Terrain.Type.values():
		for slope: float in [0.0, 0.2, 0.45, 0.7, 1.0]:
			for height: float in [-0.8, -0.05, 0.0, 0.02, 0.1, 0.3, 1.0, 1.6, 2.5]:
				for k: float in [0.0, 0.5, 0.9, 1.0]:
					var label := "t%d s%.2f h%.2f k%.1f" % [terrain, slope, height, k]
					_assert_valid(_weights(terrain, slope, height, k, k), label)


func test_flat_plains_are_mostly_grass() -> void:
	var w := _weights(PLAINS, 0.0, 0.3)
	assert_true(w[TerrainSplat.GRASS] >= 0.6, "grass %s" % w[TerrainSplat.GRASS])


func test_dry_macro_patch_turns_plains_dry() -> void:
	var w := _weights(PLAINS, 0.0, 0.3, 0.5, 0.85)
	assert_true(w[TerrainSplat.DRY_GRASS] > w[TerrainSplat.GRASS], "dry %s" % w)


func test_moist_plains_get_dirt_patches_up_to_the_limit() -> void:
	var dry := _weights(PLAINS, 0.0, 0.3, 0.5)
	var moist := _weights(PLAINS, 0.0, 0.3, 1.0)
	assert_true(is_zero_approx(dry[TerrainSplat.DIRT]), "no dirt at average moisture")
	assert_true(moist[TerrainSplat.DIRT] > 0.2, "dirt patch %s" % moist[TerrainSplat.DIRT])
	assert_true(moist[TerrainSplat.DIRT] <= TerrainSplat.DIRT_PATCH_MAX + SUM_TOLERANCE)


func test_steep_hills_are_rock() -> void:
	var w := _weights(HILLS, 0.7, 0.8)
	assert_true(w[TerrainSplat.ROCK] >= 0.6, "rock %s" % w[TerrainSplat.ROCK])


func test_gentle_hills_have_no_rock() -> void:
	var w := _weights(HILLS, 0.05, 0.8)
	assert_true(w[TerrainSplat.ROCK] <= 0.05, "rock %s" % w[TerrainSplat.ROCK])


func test_gravel_at_the_rock_transition() -> void:
	var w := _weights(HILLS, (TerrainSplat.ROCK_SLOPE_FROM + TerrainSplat.ROCK_SLOPE_TO) * 0.5, 0.8)
	assert_true(w[TerrainSplat.GRAVEL] > 0.1, "gravel %s" % w[TerrainSplat.GRAVEL])
	assert_true(w[TerrainSplat.ROCK] > 0.1, "rock %s" % w[TerrainSplat.ROCK])


func test_high_hills_are_rock_even_when_flat() -> void:
	var w := _weights(HILLS, 0.05, 2.0)
	assert_true(w[TerrainSplat.ROCK] >= 0.6, "rock %s" % w[TerrainSplat.ROCK])


func test_land_just_above_the_water_is_mud() -> void:
	var w := _weights(PLAINS, 0.0, WATER_LEVEL + 0.02)
	assert_true(w[TerrainSplat.MUD] >= 0.5, "mud %s" % w[TerrainSplat.MUD])


func test_land_well_above_the_water_has_no_mud() -> void:
	var w := _weights(PLAINS, 0.0, WATER_LEVEL + 0.2)
	assert_eq(w[TerrainSplat.MUD], 0.0)


func test_shore_mud_is_capped() -> void:
	var w := _weights(FOREST, 0.0, WATER_LEVEL + 0.001)
	assert_true(w[TerrainSplat.MUD] <= TerrainSplat.SHORE_MUD_MAX + SUM_TOLERANCE)


func test_water_bed_is_mud() -> void:
	var w := _weights(WATER, 0.1, WATER_LEVEL - 0.4)
	assert_true(w[TerrainSplat.MUD] >= 0.99, "mud %s" % w[TerrainSplat.MUD])


func test_forest_floor_is_dirt() -> void:
	var w := _weights(FOREST, 0.0, 0.4)
	assert_true(w[TerrainSplat.DIRT] >= 0.5, "dirt %s" % w[TerrainSplat.DIRT])


func test_off_map_land_uses_the_plains_rules() -> void:
	assert_eq(_weights(-1, 0.1, 0.4, 0.3, 0.6), _weights(PLAINS, 0.1, 0.4, 0.3, 0.6))


func test_deterministic() -> void:
	var a := TerrainSplat.weights(HILLS, 0.41, 0.53, 0.1, 0.77, 0.62)
	var b := TerrainSplat.weights(HILLS, 0.41, 0.53, 0.1, 0.77, 0.62)
	assert_eq(a, b)


func test_smooth_averages_neighbours_and_keeps_the_sum() -> void:
	# 3 x 1 grid: a grass vertex between two rock vertices.
	var layers := TerrainSplat.LAYER_COUNT
	var w := PackedFloat32Array()
	w.resize(3 * layers)
	w[0 * layers + TerrainSplat.ROCK] = 1.0
	w[1 * layers + TerrainSplat.GRASS] = 1.0
	w[2 * layers + TerrainSplat.ROCK] = 1.0
	var smoothed := TerrainSplat.smooth(w, 3, 1)
	for v in 3:
		_assert_valid(smoothed.slice(v * layers, (v + 1) * layers), "vertex %d" % v)
	assert_true(smoothed[1 * layers + TerrainSplat.ROCK] > 0.5, "middle picks up rock")
	assert_true(smoothed[0 * layers + TerrainSplat.GRASS] > 0.0, "edge picks up grass")


func test_real_terrain_types_have_their_own_base_layers() -> void:
	var fields := _weights(Terrain.Type.FIELDS, 0.0, 0.3)
	assert_true(fields[TerrainSplat.DRY_GRASS] >= 0.4, "fields stubble %s" % fields)
	var urban := _weights(Terrain.Type.URBAN, 0.0, 0.3)
	assert_true(urban[TerrainSplat.GRAVEL] >= 0.4, "urban gravel %s" % urban)
	var marsh := _weights(Terrain.Type.MARSH, 0.0, 0.3)
	assert_true(marsh[TerrainSplat.MUD] >= 0.35, "marsh mud %s" % marsh)
	assert_true(marsh[TerrainSplat.GRASS] >= 0.3, "marsh grass %s" % marsh)


func test_slope_rock_applies_on_real_terrain_types_too() -> void:
	for t: int in [Terrain.Type.FIELDS, Terrain.Type.URBAN, Terrain.Type.MARSH]:
		var w := _weights(t, 0.7, 0.3)
		assert_true(w[TerrainSplat.ROCK] > 0.9, "type %d: rock %s" % [t, w])
