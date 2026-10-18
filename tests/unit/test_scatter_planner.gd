extends TestCase

const SEED := 777
const MIN_CLEARING := 0.3
const MAX_TREE_RADIUS := 0.95
const MAX_ROCK_RADIUS := 0.9
const EPSILON := 1e-5


func _generate(map_seed: int) -> HexGrid:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	return MapGenerator.generate(12, 10, rng)


## Isolated single-terrain tiles far apart (flat per tile, no field).
func _grid(tiles: Dictionary, elevations: Dictionary = {}) -> HexGrid:
	var grid := HexGrid.new()
	for c: Vector2i in tiles:
		grid.set_terrain(c, tiles[c])
		if elevations.has(c):
			grid.set_elevation(c, elevations[c])
	return grid


func _dist(p: Vector3, c: Vector2i) -> float:
	var center := Hex.to_world(c, TerrainField.HEX_SIZE)
	return Vector2(p.x - center.x, p.z - center.z).length()


func _plan(grid: HexGrid, seed_value: int = SEED) -> Dictionary:
	return ScatterPlanner.plan(grid, TerrainSurface.new(grid), seed_value)


func _count_near(items: Array, c: Vector2i, radius: float) -> int:
	var n := 0
	for item: Dictionary in items:
		if _dist(item["position"], c) <= radius:
			n += 1
	return n


func test_plan_is_deterministic_and_seed_dependent() -> void:
	var grid := _generate(12345)
	var a := _plan(grid)
	var b := _plan(grid)
	assert_true(a["trees"].size() > 0)
	assert_true(a["rocks"].size() > 0)
	assert_eq(a["trees"], b["trees"])
	assert_eq(a["rocks"], b["rocks"])
	var other := _plan(grid, SEED + 1)
	assert_true(other["trees"] != a["trees"])


func test_generated_map_trees_stay_in_their_tile_ring() -> void:
	var grid := _generate(12345)
	var surface := TerrainSurface.new(grid)
	var plan := _plan(grid)
	var budget := 0
	var sources: Array[Vector2i] = []
	var barren: Array[Vector2i] = []
	for c in grid.coords():
		match grid.get_terrain(c):
			Terrain.Type.HILLS, Terrain.Type.WATER:
				barren.append(c)
			Terrain.Type.FOREST:
				budget += 30
				sources.append(c)
			Terrain.Type.PLAINS:
				budget += 4
				sources.append(c)
	assert_true(plan["trees"].size() <= budget)
	for tree: Dictionary in plan["trees"]:
		var p: Vector3 = tree["position"]
		var ok := false
		for c in sources:
			var d := _dist(p, c)
			if d >= MIN_CLEARING - EPSILON and d <= MAX_TREE_RADIUS + EPSILON:
				ok = true
				break
		assert_true(ok, "tree %s is not in the ring of any forest/plains tile" % p)
		for c in barren:
			assert_true(_dist(p, c) >= MIN_CLEARING, "tree %s in hills/water tile %s" % [p, c])
		assert_true(surface.ground_height(p.x, p.z) >= 0.05)


func test_per_tile_tree_counts_and_distances() -> void:
	var forest := Vector2i(0, 0)
	var plains := Vector2i(10, 0)
	var hills := Vector2i(0, 10)
	var water := Vector2i(10, 10)
	var grid := _grid(
		{
			forest: Terrain.Type.FOREST,
			plains: Terrain.Type.PLAINS,
			hills: Terrain.Type.HILLS,
			water: Terrain.Type.WATER,
		},
		{forest: 1.0, plains: 1.0, hills: 1.0, water: 1.0}
	)
	var trees: Array = _plan(grid)["trees"]
	assert_eq(_count_near(trees, hills, 3.0), 0)
	assert_eq(_count_near(trees, water, 3.0), 0)
	var n_forest := _count_near(trees, forest, 3.0)
	assert_true(n_forest > 0 and n_forest <= 30, "forest trees: %d" % n_forest)
	var n_plains := _count_near(trees, plains, 3.0)
	assert_true(n_plains <= 4, "plains trees: %d" % n_plains)
	for tree: Dictionary in trees:
		var p: Vector3 = tree["position"]
		var d := minf(_dist(p, forest), _dist(p, plains))
		assert_true(d >= MIN_CLEARING - EPSILON and d <= MAX_TREE_RADIUS + EPSILON, str(d))


func test_plains_get_zero_or_four_candidates() -> void:
	var tiles := {}
	for i in 40:
		tiles[Vector2i(i * 4, 0)] = Terrain.Type.PLAINS
	var grid := _grid(tiles, {})
	var trees: Array = _plan(grid)["trees"]
	var with_trees := 0
	for c: Vector2i in tiles:
		var n := _count_near(trees, c, 2.0)
		assert_true(n <= 4)
		if n > 0:
			with_trees += 1
	assert_true(with_trees > 5 and with_trees < 35, "tiles with trees: %d" % with_trees)


func test_tree_values_and_height() -> void:
	var grid := _generate(12345)
	var surface := TerrainSurface.new(grid)
	for tree: Dictionary in _plan(grid)["trees"]:
		var p: Vector3 = tree["position"]
		assert_true(tree["scale"] >= 0.7 - EPSILON and tree["scale"] <= 1.3 + EPSILON)
		var k: float = tree["k"]
		var expected_h: float = tree["scale"] * (0.9 + k * 0.3)
		assert_true(absf(tree["height_scale"] - expected_h) < EPSILON)
		assert_true(absf(tree["yaw"] - k * 6.0) < EPSILON)
		assert_true(absf(p.y - (surface.ground_height(p.x, p.z) - 0.02)) < EPSILON)


func _conifer_share(elevation: float) -> float:
	var tiles := {}
	var elevations := {}
	for i in 20:
		var c := Vector2i(i * 4, 0)
		tiles[c] = Terrain.Type.FOREST
		elevations[c] = elevation
	var trees: Array = _plan(_grid(tiles, elevations))["trees"]
	var conifers := 0
	for tree: Dictionary in trees:
		if tree["conifer"]:
			conifers += 1
	assert_true(trees.size() > 100)
	return float(conifers) / trees.size()


func test_conifer_share_depends_on_height() -> void:
	assert_true(_conifer_share(1.0) >= 0.6)
	assert_true(_conifer_share(0.3) <= 0.55)


func test_rocks_only_on_hills_with_mountain_count() -> void:
	var hills := Vector2i(0, 0)
	var mountain := Vector2i(10, 0)
	var forest := Vector2i(0, 10)
	var grid := _grid(
		{
			hills: Terrain.Type.HILLS,
			mountain: Terrain.Type.HILLS,
			forest: Terrain.Type.FOREST,
		},
		{hills: 1.2, mountain: 1.6, forest: 0.5}
	)
	var surface := TerrainSurface.new(grid)
	var rocks: Array = _plan(grid)["rocks"]
	assert_eq(rocks.size(), 11)
	assert_eq(_count_near(rocks, hills, MAX_ROCK_RADIUS + EPSILON), 3)
	assert_eq(_count_near(rocks, mountain, MAX_ROCK_RADIUS + EPSILON), 8)
	for rock: Dictionary in rocks:
		var p: Vector3 = rock["position"]
		assert_true(rock["scale"] >= 0.5 - EPSILON and rock["scale"] <= 1.7 + EPSILON)
		assert_true(absf(p.y - surface.ground_height(p.x, p.z)) < EPSILON)
		var s: float = rock["scale"]
		assert_true(rock["rotation"].is_equal_approx(Vector3(s, 3.0 * s, 0.0)))


func test_elevation_exactly_at_threshold_is_not_a_mountain() -> void:
	var c := Vector2i(0, 0)
	var grid := _grid({c: Terrain.Type.HILLS}, {c: 1.45})
	assert_eq(_plan(grid)["rocks"].size(), 3)


func test_bush_counts_radius_scale_and_terrain() -> void:
	var forest := Vector2i(0, 0)
	var plains := Vector2i(10, 0)
	var hills := Vector2i(0, 10)
	var water := Vector2i(10, 10)
	var grid := _grid(
		{
			forest: Terrain.Type.FOREST,
			plains: Terrain.Type.PLAINS,
			hills: Terrain.Type.HILLS,
			water: Terrain.Type.WATER,
		},
		{forest: 1.0, plains: 1.0, hills: 1.0, water: 1.0}
	)
	var surface := TerrainSurface.new(grid)
	var bushes: Array = _plan(grid)["bushes"]
	assert_eq(_count_near(bushes, hills, 3.0), 0)
	assert_eq(_count_near(bushes, water, 3.0), 0)
	var n_forest := _count_near(bushes, forest, 3.0)
	assert_true(n_forest > 0 and n_forest <= 8, "forest bushes: %d" % n_forest)
	var n_plains := _count_near(bushes, plains, 3.0)
	assert_true(n_plains > 0 and n_plains <= 2, "plains bushes: %d" % n_plains)
	for bush: Dictionary in bushes:
		var p: Vector3 = bush["position"]
		assert_true(minf(_dist(p, forest), _dist(p, plains)) <= 0.92 + EPSILON)
		var s: float = bush["scale"]
		assert_true(s >= 0.28 - EPSILON and s <= 0.53 + EPSILON)
		assert_true(absf(bush["height_scale"] - 0.6 * s) < EPSILON)
		assert_true(absf(p.y - (surface.ground_height(p.x, p.z) - 0.06 * s)) < EPSILON)
		assert_true(surface.ground_height(p.x, p.z) >= 0.05)


func test_bushes_are_deterministic_per_seed() -> void:
	var grid := _generate(12345)
	var a := _plan(grid)
	var b := _plan(grid)
	assert_true(a["bushes"].size() > 0)
	assert_eq(a["bushes"], b["bushes"])
	assert_true(_plan(grid, SEED + 1)["bushes"] != a["bushes"])


func test_no_bushes_on_ground_below_min_tree_ground() -> void:
	var forest := Vector2i(0, 0)
	var plains := Vector2i(10, 0)
	var grid := _grid(
		{forest: Terrain.Type.FOREST, plains: Terrain.Type.PLAINS}, {forest: 0.0, plains: 0.0}
	)
	assert_eq(_plan(grid)["bushes"].size(), 0)
