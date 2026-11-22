extends TestCase
## ForestFill, the reference of the GPU-placed forest (TASK-189, ADR 0027): the integer hash and
## the cell -> tree formulas are fixed (the GLSL twin in forest_hash.gdshaderinc must give the same
## bits), the include carries the same constants, and the cells of adjacent impostor chunks
## partition the grid.

const Fixtures := preload("res://tests/fixtures.gd")
const INCLUDE := "res://assets/shaders/forest_hash.gdshaderinc"
const SEED := 20240518
const CELLS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(-3, 7), Vector2i(123, -45), Vector2i(-1000, -2000)
]


func after_each() -> void:
	VisualScale.reset()
	MapScale.reset()


static func _flat(_x: float, _z: float) -> float:
	return 0.5


static func _forest(radius: int) -> HexGrid:
	var grid := Fixtures.plains_grid(radius)
	for c in grid.coords():
		grid.set_terrain(c, Terrain.Type.FOREST)
	return grid


func test_the_cell_hash_is_fixed_uint32_arithmetic() -> void:
	# [point hash, value hash, pick hash, unit(point hash, 3)] of CELLS (checked against an
	# independent uint32 model): the GLSL forest_tile_seed / forest_unit give the same bits.
	var expected := [
		[2618942042, 1340312561, 2838500331, 0.35743463039398193],
		[3766323544, 2672345729, 1443834870, 0.5473013520240784],
		[2592828300, 686537518, 3481677125, 0.5643780827522278],
		[1567729376, 3241971949, 2050300578, 0.45889443159103394],
		[3369430706, 2916618415, 2494496666, 0.5173080563545227],
	]
	for n in CELLS.size():
		var cell := CELLS[n]
		var h := ScatterPlanner.tile_seed(SEED, cell, ForestFill.POINT_SALT)
		assert_eq(h, expected[n][0], "point hash of %s" % cell)
		assert_eq(ScatterPlanner.tile_seed(SEED, cell, ForestFill.VALUE_SALT), expected[n][1])
		assert_eq(ScatterPlanner.tile_seed(SEED, cell, ForestFill.PICK_SALT), expected[n][2])
		assert_eq(ForestFill.unit(h, 3), expected[n][3], "unit of %s" % cell)


func test_the_tree_of_a_cell_is_fixed() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var fill := ForestFill.new(_forest(3), _flat, SEED, Rect2(-4.0, -4.0, 8.0, 8.0))
	# cell: [point, species, variant, scale, conifer]
	var expected := {
		Vector2i(5, 5): [Vector2(0.187952, 0.197904), &"birch", 0, 1.116015625, false],
		Vector2i(10, -3): [Vector2(0.379206, -0.095778), &"pine", 0, 0.942578125, true],
		Vector2i(-7, 2): [Vector2(-0.241729, 0.080241), &"birch", 2, 0.921484375, false],
		Vector2i(0, 12): [Vector2(0.025845, 0.446188), &"oak", 1, 1.0875, false],
		Vector2i(-15, -15): [Vector2(-0.533094, -0.508748), &"spruce", 1, 1.165625, true],
		Vector2i(30, 31): [Vector2(1.11008, 1.144667), &"birch", 0, 1.1453125, false],
	}
	for cell: Vector2i in expected:
		var want: Array = expected[cell]
		var tree := fill.cell_tree(cell)
		assert_false(tree.is_empty(), "%s holds a tree" % cell)
		var p: Vector3 = tree["position"]
		assert_true(Vector2(p.x, p.z).distance_to(want[0]) < 1.0e-5, "%s at %s" % [cell, p])
		assert_eq(tree["species"], want[1], "%s species" % cell)
		assert_eq(tree["variant"], want[2], "%s variant" % cell)
		assert_true(absf(float(tree["scale"]) - float(want[3])) < 1.0e-9, "%s scale" % cell)
		assert_eq(tree["conifer"], want[4], "%s conifer" % cell)
	# The tile-centre clearing holds none.
	assert_true(fill.cell_tree(Vector2i(0, 0)).is_empty(), "cell (0, 0) lies in the clearing")


func test_the_shader_include_carries_the_same_constants() -> void:
	var text := FileAccess.get_file_as_string(INCLUDE)
	var expected := {
		"FOREST_MIX_MULTIPLIER": ForestFill.MIX_MULTIPLIER,
		"FOREST_UNIT_MULTIPLIER": ForestFill.UNIT_MULTIPLIER,
		"FOREST_POINT_SALT": ForestFill.POINT_SALT,
		"FOREST_VALUE_SALT": ForestFill.VALUE_SALT,
		"FOREST_PICK_SALT": ForestFill.PICK_SALT,
		"FOREST_JITTER": ForestFill.JITTER,
		"FOREST_SCALE_MIN": ForestFill.SCALE_MIN,
		"FOREST_SCALE_RANGE": ForestFill.SCALE_RANGE,
		"FOREST_PART_SPECIES": ForestFill.PART_SPECIES,
		"FOREST_PART_VARIANT": ForestFill.PART_VARIANT,
		"FOREST_PART_HUE": ForestFill.PART_HUE,
		"FOREST_PART_VALUE": ForestFill.PART_VALUE,
		"FOREST_PART_SATURATION": ForestFill.PART_SATURATION,
		"FOREST_PART_PHASE": ForestFill.PART_PHASE,
		"FOREST_PART_AUTUMN": ForestFill.PART_AUTUMN,
		"FOREST_PART_AUTUMN_HUE": ForestFill.PART_AUTUMN_HUE,
		"FOREST_HUE_SHIFT": TreeSpecies.HUE_SHIFT,
		"FOREST_VALUE_MIN": TreeSpecies.VALUE_MIN,
		"FOREST_VALUE_MAX": TreeSpecies.VALUE_MAX,
		"FOREST_SATURATION_MIN": TreeSpecies.SATURATION_MIN,
		"FOREST_SATURATION_MAX": TreeSpecies.SATURATION_MAX,
		"FOREST_AUTUMN_HUE_MIN": TreeSpecies.AUTUMN_HUE_MIN,
		"FOREST_AUTUMN_HUE_MAX": TreeSpecies.AUTUMN_HUE_MAX,
		"FOREST_VARIANTS": TreeMeshes.VARIANTS,
	}
	var found := {}
	var pattern := RegEx.create_from_string(r"const \w+ (FOREST_\w+) = ([0-9.]+)u?;")
	for m in pattern.search_all(text):
		found[m.get_string(1)] = m.get_string(2)
	for name: String in expected:
		assert_true(found.has(name), "%s in the include" % name)
		var value: Variant = expected[name]
		if value is int:
			assert_eq(int(found.get(name, "-1")), value, name)
		else:
			assert_eq(float(found.get(name, "-1")), value, name)
	assert_eq(found.size(), expected.size(), "every shared constant is checked")


func test_the_cells_of_adjacent_chunks_partition_the_grid() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var fill := ForestFill.new(_forest(3), _flat, SEED, Rect2(-4.0, -4.0, 8.0, 8.0))
	var seen := {}
	for cx in range(-2, 2):
		for cz in range(-2, 2):
			var cells := fill.cells_of(Rect2(Vector2(cx, cz) * 2.0, Vector2.ONE * 2.0))
			for j in range(cells.position.y, cells.end.y):
				for i in range(cells.position.x, cells.end.x):
					assert_false(
						seen.has(Vector2i(i, j)), "cell %s in one chunk only" % Vector2i(i, j)
					)
					seen[Vector2i(i, j)] = true
	var all := fill.cells_of(Rect2(-4.0, -4.0, 8.0, 8.0))
	assert_eq(seen.size(), all.size.x * all.size.y, "no cell left out")
	# The impostor layer's shared MultiMesh holds the largest chunk's cells.
	var side := ceili(2.0 / fill.spacing) + 1
	for cx in range(-2, 2):
		var cells := fill.cells_of(Rect2(Vector2(cx, 0) * 2.0, Vector2.ONE * 2.0))
		assert_true(cells.size.x <= side and cells.size.y <= side)


func test_the_keep_off_mask_holds_roads_off() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grid := _forest(3)
	# A road from (-1, 0) through (0, 0) to (1, 0) (directions 0 and 3).
	grid.set_road_links(Vector2i(-1, 0), 0b000001)
	grid.set_road_links(Vector2i(0, 0), 0b001001)
	grid.set_road_links(Vector2i(1, 0), 0b001000)
	var fill := ForestFill.new(grid, _flat, SEED, Rect2(-4.0, -4.0, 8.0, 8.0))
	var road := FeatureRibbonPlanner.lines(grid, FeatureRibbonPlanner.Kind.ROAD)
	assert_false(road.is_empty(), "the grid has a road")
	var on_road := 0
	for p in road[0]:
		if not fill.mask_allows(p.x, p.y):
			on_road += 1
	assert_eq(on_road, road[0].size(), "every centreline point kept off")
	# No tree within the road's half width + clearance less one mask texel (the mask's rounding).
	var reach := (
		FeatureRibbonPlanner.max_half_width(FeatureRibbonPlanner.Kind.ROAD)
		+ FeatureRibbonPlanner.clearance(FeatureRibbonPlanner.Kind.ROAD)
		- 1.5 / ForestFill.MASK_PER_UNIT
	)
	var trees := fill.plan_rect(Rect2(-2.0, -1.0, 4.0, 2.0))
	assert_true(trees.size() > 1000, "%d trees" % trees.size())
	for tree in trees:
		var p: Vector3 = tree["position"]
		for k in road[0].size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(
				Vector2(p.x, p.z), road[0][k], road[0][k + 1]
			)
			assert_true(q.distance_to(Vector2(p.x, p.z)) >= reach, "%s off the road" % p)


## The mask source is the one place that knows where forest is (ADR 0027): its resolution is the
## caller's, not the hex's; the hex source (transitional, TASK-108g replaces it) fills forest tiles
## and keeps the tile-centre clearing and the ribbons off.
func test_the_hex_mask_source_fills_forest_tiles_at_the_requested_resolution() -> void:
	var grid := Fixtures.plains_grid(3)
	grid.set_terrain(Vector2i(0, 0), Terrain.Type.FOREST)
	var area := Rect2(-4.0, -4.0, 8.0, 8.0)
	var masks := HexForestMaskSource.new(0.1).build(grid, area, 16.0)
	var forest: Image = masks["forest"]
	var keep_off: Image = masks["keep_off"]
	assert_eq(forest.get_size(), Vector2i(128, 128))
	assert_eq(keep_off.get_size(), forest.get_size())
	var texel := func(image: Image, x: float, z: float) -> float:
		return image.get_pixel(floori((x + 4.0) * 16.0), floori((z + 4.0) * 16.0)).r
	assert_true(texel.call(forest, 0.5, 0.0) > 0.5, "inside the forest hex")
	assert_true(texel.call(forest, 0.0, 0.95) > 0.5, "near its pointy top")
	assert_true(texel.call(forest, 0.8, 0.9) < 0.5, "outside the hex, inside its box")
	assert_true(texel.call(forest, 1.732, 0.0) < 0.5, "the plains neighbour")
	assert_true(texel.call(keep_off, 0.0, 0.0) > 0.5, "the clearing")
	assert_true(texel.call(keep_off, 0.5, 0.0) < 0.5)
	# A finer resolution is the same shape, finer.
	var fine: Image = HexForestMaskSource.new(0.1).build(grid, area, 64.0)["forest"]
	assert_eq(fine.get_size(), Vector2i(512, 512))
	# The fill reads the merged mask (at MASK_PER_UNIT): no tree farther off the forest tile than a
	# mask texel, none in its clearing.
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var fill := ForestFill.new(grid, _flat, SEED, area)
	var trees := fill.plan_rect(area)
	assert_true(trees.size() > 500, "%d trees" % trees.size())
	for tree in trees:
		var p: Vector3 = tree["position"]
		var texel_reach := Vector2.ONE.length() / ForestFill.MASK_PER_UNIT
		if Hex.from_world(p, TerrainField.HEX_SIZE) != Vector2i(0, 0):
			var inward := p * (1.0 - texel_reach / maxf(p.length(), 1.0e-6))
			assert_eq(Hex.from_world(inward, TerrainField.HEX_SIZE), Vector2i(0, 0), "%s" % p)
		assert_true(Vector2(p.x, p.z).length() > 0.1 - texel_reach, "off the clearing")
