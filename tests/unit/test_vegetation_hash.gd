extends TestCase
## VegetationHash, the shared cell hash of the GPU-placed vegetation layers (TASK-217a, ADR 0033):
## fixed uint32 values (an independent uint32 model gave them; the GLSL twin
## vegetation_hash.gdshaderinc must give the same bits), the include carries the same constants
## and reuses the forest's hash, chunks partition the cells, the value noise is smooth and fixed.

const INCLUDE := "res://assets/shaders/vegetation_hash.gdshaderinc"
const SHRUB_INCLUDE := "res://assets/shaders/shrub_rules.gdshaderinc"
## (seed, cell) -> [point hash, value hash, unit(value hash, 0)] with the shrub salts.
const PAIRS := [
	[0, Vector2i(0, 0), 3497628272, 205214433, 0.47975921630859375],
	[1, Vector2i(1, 0), 2944219861, 522787261, 0.003270864486694336],
	[20240518, Vector2i(-3, 7), 1337661925, 1872830035, 0.07860791683197021],
	[4294967295, Vector2i(123, -45), 4108112213, 734237174, 0.5621074438095093],
	[987654321, Vector2i(-1000, -2000), 630617605, 2284402803, 0.9007770419120789],
]


func test_the_cell_hash_of_five_pairs_is_fixed() -> void:
	for pair: Array in PAIRS:
		var seed_value: int = pair[0]
		var cell: Vector2i = pair[1]
		var h := VegetationHash.cell_hash(seed_value, cell, ShrubRules.POINT_SALT)
		assert_eq(h, pair[2], "point hash of %d %s" % [seed_value, cell])
		var v := VegetationHash.cell_hash(seed_value, cell, ShrubRules.VALUE_SALT)
		assert_eq(v, pair[3], "value hash of %d %s" % [seed_value, cell])
		var value := VegetationHash.unit(v, 0)
		assert_true(absf(value - float(pair[4])) < 1.0e-12, "unit of %d %s" % [seed_value, cell])
		assert_true(h >= 0 and h <= 0xFFFFFFFF, "32 bits")


func test_the_include_reuses_the_forest_hash_and_carries_the_constants() -> void:
	var text := FileAccess.get_file_as_string(INCLUDE)
	assert_true(text.contains('#include "res://assets/shaders/forest_hash.gdshaderinc"'))
	assert_eq(VegetationHash.MIX_MULTIPLIER, ForestFill.MIX_MULTIPLIER)
	assert_eq(VegetationHash.UNIT_MULTIPLIER, ForestFill.UNIT_MULTIPLIER)
	var found := _constants(text, "VEG_")
	assert_eq(int(found.get("VEG_NOISE_SALT", "-1")), VegetationHash.NOISE_SALT)
	assert_eq(found.size(), 1, "every shared constant is checked")


func test_the_shrub_include_carries_the_shrub_rules_constants() -> void:
	var text := FileAccess.get_file_as_string(SHRUB_INCLUDE)
	var expected := {
		"SHRUB_POINT_SALT": ShrubRules.POINT_SALT,
		"SHRUB_VALUE_SALT": ShrubRules.VALUE_SALT,
		"SHRUB_NOISE_SALT": ShrubRules.NOISE_SALT,
		"SHRUB_VARIANT_SALT": ShrubRules.VARIANT_SALT,
		"SHRUB_PART_CHANCE": ShrubRules.PART_CHANCE,
		"SHRUB_PART_KIND": ShrubRules.PART_KIND,
		"SHRUB_PART_HEIGHT": ShrubRules.PART_HEIGHT,
		"SHRUB_PART_WIDTH": ShrubRules.PART_WIDTH,
		"SHRUB_PART_YAW": ShrubRules.PART_YAW,
		"SHRUB_PART_HUE": ShrubRules.PART_HUE,
		"SHRUB_PART_VALUE": ShrubRules.PART_VALUE,
		"SHRUB_PART_PHASE": ShrubRules.PART_PHASE,
		"SHRUB_JITTER": ShrubRules.JITTER,
		"SHRUB_EDGE_FROM": ShrubRules.EDGE_FROM,
		"SHRUB_EDGE_TO": ShrubRules.EDGE_TO,
		"SHRUB_PARCEL_NONE": ShrubRules.PARCEL_NONE,
		"SHRUB_PARCEL_BALK": ShrubRules.PARCEL_BALK,
		"SHRUB_PARCEL_MEADOW": ShrubRules.PARCEL_MEADOW,
		"SHRUB_CROP_NONE": ShrubRules.CROP_NONE,
		"SHRUB_CROP_FIELD": ShrubRules.CROP_FIELD,
		"SHRUB_CROP_BALK": ShrubRules.CROP_BALK,
		"SHRUB_NO_REAL_PARCEL": VegetationMasks.NO_REAL_PARCEL,
		"SHRUB_NO_STRIP_PARCEL": VegetationMasks.NO_STRIP_PARCEL,
		"SHRUB_CODE_MASK": VegetationMasks.CODE_MASK,
		"SHRUB_HEATH_NOISE_MIN": ShrubRules.HEATH_NOISE_MIN,
		"SHRUB_HEATH_NOISE_SPAN": ShrubRules.HEATH_NOISE_SPAN,
		"SHRUB_MEADOW_NOISE_FROM": ShrubRules.MEADOW_NOISE_FROM,
		"SHRUB_MEADOW_NOISE_TO": ShrubRules.MEADOW_NOISE_TO,
		"SHRUB_HUE_SHIFT": ShrubRules.HUE_SHIFT,
		"SHRUB_VALUE_MIN": ShrubRules.VALUE_MIN,
		"SHRUB_VALUE_MAX": ShrubRules.VALUE_MAX,
		"SHRUB_VARIANTS": TreeMeshes.VARIANTS,
		"SHRUB_CODE_FIELD_EDGE": VegetationMasks.Habitat.FIELD_EDGE,
		"SHRUB_CODE_HEATH": VegetationMasks.Habitat.HEATH,
		"SHRUB_CODE_BANK": VegetationMasks.Habitat.BANK,
		"SHRUB_CODE_HEDGE": VegetationMasks.Habitat.HEDGE,
		"SHRUB_CODE_KEEP_OFF": VegetationMasks.Habitat.KEEP_OFF,
		"SHRUB_NONE": ShrubRules.Habitat.NONE,
		"SHRUB_FOREST_EDGE": ShrubRules.Habitat.FOREST_EDGE,
		"SHRUB_HEDGE": ShrubRules.Habitat.HEDGE,
		"SHRUB_BANK": ShrubRules.Habitat.BANK,
		"SHRUB_HEATH": ShrubRules.Habitat.HEATH,
		"SHRUB_FIELD_EDGE": ShrubRules.Habitat.FIELD_EDGE,
		"SHRUB_MEADOW": ShrubRules.Habitat.MEADOW,
	}
	var found := _constants(text, "SHRUB_")
	for name: String in expected:
		assert_true(found.has(name), "%s in the include" % name)
		var value: Variant = expected[name]
		if value is int:
			assert_eq(int(found.get(name, "-1")), value, name)
		else:
			assert_eq(float(found.get(name, "-1")), value, name)
	assert_eq(found.size(), expected.size(), "every shared constant is checked")


func test_adjacent_chunks_partition_the_cells() -> void:
	var spacing := 0.0173
	var whole := VegetationHash.cells_of(Rect2(0.0, 0.0, 2.0, 2.0), spacing)
	var total := 0
	var seen := {}
	for x in 4:
		for z in 4:
			var cells := VegetationHash.cells_of(Rect2(x * 0.5, z * 0.5, 0.5, 0.5), spacing)
			assert_true(cells.size.x * cells.size.y <= VegetationHash.max_cells(0.5, spacing))
			for i in range(cells.position.x, cells.end.x):
				for j in range(cells.position.y, cells.end.y):
					assert_false(seen.has(Vector2i(i, j)), "cell owned once")
					seen[Vector2i(i, j)] = true
			total += cells.size.x * cells.size.y
	assert_eq(total, whole.size.x * whole.size.y, "the chunks' cells add up to the whole")


func test_the_value_noise_is_fixed_smooth_and_in_range() -> void:
	var a := VegetationHash.value_noise(7, 0.3, 0.7, 1.0, 5)
	assert_eq(a, VegetationHash.value_noise(7, 0.3, 0.7, 1.0, 5), "same input, same value")
	assert_true(a != VegetationHash.value_noise(8, 0.3, 0.7, 1.0, 5), "another seed")
	var lo := 1.0
	var hi := 0.0
	var previous := VegetationHash.value_noise(7, 0.0, 0.0, 1.0, 5)
	for k in 400:
		var n := VegetationHash.value_noise(7, k * 0.01, 0.0, 1.0, 5)
		lo = minf(lo, n)
		hi = maxf(hi, n)
		assert_true(absf(n - previous) < 0.05, "smooth at %d" % k)
		previous = n
	assert_true(lo >= 0.0 and hi < 1.0 and hi - lo > 0.3, "range %.3f..%.3f" % [lo, hi])


func _constants(text: String, prefix: String) -> Dictionary:
	var found := {}
	var pattern := RegEx.create_from_string(r"const \w+ (%s\w+) = ([0-9.]+)u?;" % prefix)
	for m in pattern.search_all(text):
		found[m.get_string(1)] = m.get_string(2)
	return found
