extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

const SEED := 777
const EPSILON := 1e-5


func _generate(map_seed: int) -> HexGrid:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	return MapGenerator.generate(12, 10, rng)


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


func after_each() -> void:
	LookPreset.reset()


func _tile_plan(terrain: Terrain.Type, elevation := 1.0) -> Dictionary:
	var grid := _grid({Vector2i(0, 0): terrain}, {Vector2i(0, 0): elevation})
	return _plan(grid)


func test_existing_arrays_are_identical_under_current_and_meadow_scrub_is_empty() -> void:
	for map_seed in [1, 12345, 777]:
		var grid := _generate(map_seed)
		LookPreset.apply(&"current")
		var current := _plan(grid)
		LookPreset.reset()
		var summer := _plan(grid)
		for key in ["trees", "rocks", "bushes", "edge_shrubs", "young_trees", "ground_cover"]:
			assert_eq(summer[key], current[key], key)
		assert_eq((current["meadow_scrub"] as Array).size(), 0)
		assert_true((summer["meadow_scrub"] as Array).size() > 0)


func test_meadow_scrub_clump_geometry() -> void:
	var m := LookPreset.meadow()
	var grid := Fixtures.plains_grid(6)
	for c in grid.coords():
		grid.set_elevation(c, 1.0)
	var surface := TerrainSurface.new(grid)
	var clumps := 0
	for c in grid.coords():
		if Hex.distance(Vector2i.ZERO, c) > 4:
			continue  # the outer ring slopes down to the map edge
		var out: Array[Dictionary] = []
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([SEED, c.x, c.y])
		ScatterPlanner.plan_tile_meadow(grid, surface, rng, c, out, m)
		if out.is_empty():
			continue
		clumps += 1
		assert_eq(out.size(), 3)
		var shrub: Dictionary = out[0]
		assert_eq(shrub["species"], &"shrub")
		var r := _dist(shrub["position"], c)
		assert_true(r >= 0.55 - EPSILON and r <= 0.92 + EPSILON, "shrub r %f" % r)
		for i in [1, 2]:
			var u: Dictionary = out[i]
			assert_eq(u["species"], &"undergrowth")
			var p: Vector3 = u["position"]
			var s: Vector3 = shrub["position"]
			var d := Vector2(p.x - s.x, p.z - s.z).length()
			assert_true(d >= 0.06 - EPSILON and d <= 0.14 + EPSILON, "companion %f" % d)
			assert_true(_dist(p, c) >= 0.4)
	assert_true(clumps > 0)


func test_plan_tile_meadow_draws_a_fixed_count_on_land_and_nothing_on_water() -> void:
	var m := LookPreset.meadow()
	var tiles := {
		Vector2i(0, 0): Terrain.Type.PLAINS,
		Vector2i(10, 0): Terrain.Type.FOREST,
		Vector2i(20, 0): Terrain.Type.HILLS,
		Vector2i(30, 0): Terrain.Type.WATER,
	}
	var grid := _grid(tiles, {Vector2i(20, 0): 1.0})
	var surface := TerrainSurface.new(grid)
	var next := {}
	for c: Vector2i in tiles:
		var out: Array[Dictionary] = []
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		ScatterPlanner.plan_tile_meadow(grid, surface, rng, c, out, m)
		next[c] = rng.randf()
		if tiles[c] == Terrain.Type.FOREST or tiles[c] == Terrain.Type.WATER:
			assert_eq(out.size(), 0)
	assert_eq(next[Vector2i(0, 0)], next[Vector2i(10, 0)])
	assert_eq(next[Vector2i(0, 0)], next[Vector2i(20, 0)])
	var fresh := RandomNumberGenerator.new()
	fresh.seed = 5
	assert_eq(next[Vector2i(30, 0)], fresh.randf(), "water draws nothing")


func _share_with_clump(terrain: Terrain.Type, elevation: float) -> float:
	var grid := Fixtures.plains_grid(6)
	for c in grid.coords():
		grid.set_terrain(c, terrain)
		grid.set_elevation(c, elevation)
	var plan := _plan(grid)
	var tiles := {}
	for item: Dictionary in plan["meadow_scrub"]:
		var p: Vector3 = item["position"]
		tiles[Hex.from_world(p, TerrainField.HEX_SIZE)] = true
	return float(tiles.size()) / grid.coords().size()


func test_meadow_scrub_tile_shares() -> void:
	var plains := _share_with_clump(Terrain.Type.PLAINS, 1.0)
	var hills := _share_with_clump(Terrain.Type.HILLS, 1.0)
	print("  meadow scrub tile share: plains %.2f, hills %.2f" % [plains, hills])
	assert_true(plains >= 0.2 and plains <= 0.5, "plains share %f" % plains)
	assert_true(hills < plains, "hills have fewer")
	assert_eq(_share_with_clump(Terrain.Type.FOREST, 1.0), 0.0)
	assert_eq(_share_with_clump(Terrain.Type.WATER, 0.0), 0.0)
