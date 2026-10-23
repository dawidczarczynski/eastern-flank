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


## Forest tile at the origin: forest neighbours in directions 0 and 3, plains in the other four.
func _edge_grid(water_dir: int = -1) -> HexGrid:
	var tiles := {Vector2i.ZERO: Terrain.Type.FOREST}
	for i in Hex.DIRECTIONS.size():
		var forest := i == 0 or i == 3
		tiles[Hex.DIRECTIONS[i]] = Terrain.Type.FOREST if forest else Terrain.Type.PLAINS
	if water_dir >= 0:
		tiles[Hex.DIRECTIONS[water_dir]] = Terrain.Type.WATER
	return _grid(tiles)


func _angle_to(p: Vector3, from: Vector2i, to: Vector2i) -> float:
	var a := Hex.to_world(from, TerrainField.HEX_SIZE)
	var b := Hex.to_world(to, TerrainField.HEX_SIZE)
	var u := Vector2(p.x - a.x, p.z - a.z)
	var v := Vector2(b.x - a.x, b.z - a.z)
	return absf(u.angle_to(v))


## One tile's edge plants with a fresh stream: {"edge_shrubs", "young_trees", "ground_cover"}.
func _tile_edges(grid: HexGrid, c: Vector2i) -> Dictionary:
	var out := {
		"edge_shrubs": [] as Array[Dictionary],
		"young_trees": [] as Array[Dictionary],
		"ground_cover": [] as Array[Dictionary],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	ScatterPlanner.plan_tile_edges(
		grid,
		TerrainSurface.new(grid),
		rng,
		c,
		out["edge_shrubs"],
		out["young_trees"],
		out["ground_cover"]
	)
	return out


func test_forest_edge_shrubs_and_young_trees_per_open_side() -> void:
	var edges := _tile_edges(_edge_grid(), Vector2i.ZERO)
	assert_eq(edges["edge_shrubs"].size(), 8 * 4)
	for s: Dictionary in edges["edge_shrubs"]:
		var best := PI
		for i in [1, 2, 4, 5]:
			best = minf(best, _angle_to(s["position"], Vector2i.ZERO, Hex.DIRECTIONS[i]))
		assert_true(best <= deg_to_rad(30.0) + EPSILON)
		var r := _dist(s["position"], Vector2i.ZERO)
		assert_true(r >= 0.55 - EPSILON and r <= 0.95 + EPSILON)
	assert_eq(edges["young_trees"].size(), 2 * 4)
	for t: Dictionary in edges["young_trees"]:
		var r := _dist(t["position"], Vector2i.ZERO)
		assert_true(r >= 0.5 - EPSILON and r <= 0.8 + EPSILON)
		assert_true(t["scale"] >= 0.4 and t["scale"] <= 0.6)
	assert_eq(edges["ground_cover"].size(), 10)


func test_open_side_gets_three_shrubs_towards_the_forest() -> void:
	var grid := _edge_grid()
	for i in [1, 2, 4, 5]:
		var c: Vector2i = Hex.DIRECTIONS[i]
		var edges := _tile_edges(grid, c)
		# Plains neighbours border the origin and, for 1 and 5 / 2 and 4, a forest at 0 / 3 too.
		var forest_sides := 1
		for n in Hex.neighbors(c):
			if (
				n != Vector2i.ZERO
				and grid.has_tile(n)
				and grid.get_terrain(n) == Terrain.Type.FOREST
			):
				forest_sides += 1
		assert_eq(edges["edge_shrubs"].size(), 4 * forest_sides)
		assert_eq(edges["young_trees"].size(), 0)
		assert_eq(edges["ground_cover"].size(), 3)
		for s: Dictionary in edges["edge_shrubs"]:
			var r := _dist(s["position"], c)
			assert_true(r >= 0.65 - EPSILON and r <= 0.95 + EPSILON)


func test_open_side_shrubs_stay_in_the_forest_sector() -> void:
	var grid := HexGrid.new()
	grid.set_terrain(Vector2i.ZERO, Terrain.Type.FOREST)
	grid.set_terrain(Hex.DIRECTIONS[2], Terrain.Type.PLAINS)
	var edges := _tile_edges(grid, Hex.DIRECTIONS[2])
	assert_eq(edges["edge_shrubs"].size(), 4)
	for s: Dictionary in edges["edge_shrubs"]:
		assert_true(
			_angle_to(s["position"], Hex.DIRECTIONS[2], Vector2i.ZERO) <= deg_to_rad(25.0) + EPSILON
		)


func test_interior_forest_has_ground_cover_but_no_edge_plants() -> void:
	var tiles := {Vector2i.ZERO: Terrain.Type.FOREST}
	for d in Hex.DIRECTIONS:
		tiles[d] = Terrain.Type.FOREST
	var edges := _tile_edges(_grid(tiles), Vector2i.ZERO)
	assert_eq(edges["ground_cover"].size(), 10)
	for g: Dictionary in edges["ground_cover"]:
		assert_true(g["scale"] >= 0.7 and g["scale"] <= 1.3)
		assert_eq(g["species"], &"undergrowth")
	assert_eq(edges["edge_shrubs"].size(), 0)
	assert_eq(edges["young_trees"].size(), 0)


func test_water_neighbours_produce_no_edge_plants() -> void:
	var grid := _edge_grid(1)
	var edges := _tile_edges(grid, Vector2i.ZERO)
	assert_eq(edges["edge_shrubs"].size(), 8 * 3)
	assert_eq(edges["young_trees"].size(), 2 * 3)
	assert_eq(_tile_edges(grid, Hex.DIRECTIONS[1])["edge_shrubs"].size(), 0)
	# A plains tile whose only forest neighbour is across... water never counts as forest side.
	var lone := HexGrid.new()
	lone.set_terrain(Vector2i.ZERO, Terrain.Type.PLAINS)
	lone.set_terrain(Hex.DIRECTIONS[0], Terrain.Type.WATER)
	assert_eq(_tile_edges(lone, Vector2i.ZERO)["edge_shrubs"].size(), 0)


func test_edge_plan_is_deterministic_and_leaves_existing_output_alone() -> void:
	var grid := _generate(12345)
	var a := _plan(grid)
	var b := _plan(grid)
	assert_eq(a["edge_shrubs"], b["edge_shrubs"])
	assert_eq(a["young_trees"], b["young_trees"])
	assert_eq(a["ground_cover"], b["ground_cover"])
	assert_true(a["edge_shrubs"].size() > 0)
	assert_true(a["ground_cover"].size() > 0)
	assert_true(_plan(grid, SEED + 1)["edge_shrubs"] != a["edge_shrubs"])
