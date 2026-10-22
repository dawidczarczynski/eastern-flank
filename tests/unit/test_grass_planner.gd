extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

const SEED := 4242
const CHUNK := Vector2i(0, 0)
const EXPECTED_PLAINS := 90 * 16


func _plan(grid: HexGrid, chunk: Vector2i = CHUNK, density := 1.0, seed_value := SEED) -> Array:
	return GrassPlanner.plan_chunk(chunk, grid, TerrainSurface.new(grid), seed_value, density)


## A hex disc of `terrain` around the origin; the chunk (0, 0) lies inside it.
func _disc(terrain: Terrain.Type, elevation := -1.0) -> HexGrid:
	var grid := Fixtures.plains_grid(5)
	for c in grid.coords():
		grid.set_terrain(c, terrain)
		if elevation > -1.0:
			grid.set_elevation(c, elevation)
	return grid


func test_same_chunk_and_seed_is_identical_and_other_seed_differs() -> void:
	var grid := Fixtures.plains_grid(5)
	assert_eq(_plan(grid), _plan(grid))
	assert_true(_plan(grid) != _plan(grid, CHUNK, 1.0, SEED + 1), "different seed differs")
	assert_true(_plan(grid) != _plan(grid, Vector2i(1, 0)), "different chunk differs")


func test_plains_chunk_count_follows_density() -> void:
	var grid := Fixtures.plains_grid(5)
	var full := _plan(grid).size()
	assert_true(absf(full - EXPECTED_PLAINS) <= EXPECTED_PLAINS * 0.1, "full density: %d" % full)
	var half := _plan(grid, CHUNK, 0.5).size()
	assert_true(absf(half - EXPECTED_PLAINS * 0.5) <= EXPECTED_PLAINS * 0.05, "half: %d" % half)
	assert_eq(_plan(grid, CHUNK, 0.0).size(), 0)


func test_forest_is_sparser_than_plains() -> void:
	var n := _plan(_disc(Terrain.Type.FOREST)).size()
	var expected := 25 * 16
	assert_true(absf(n - expected) <= expected * 0.1, "forest: %d" % n)


func test_no_grass_on_water() -> void:
	assert_eq(_plan(_disc(Terrain.Type.WATER)).size(), 0)


func test_no_grass_in_the_shore_band() -> void:
	# Plains sitting just above the water level: all of it is shore.
	var grid := _disc(Terrain.Type.PLAINS, 0.03)
	assert_eq(_plan(grid).size(), 0)


func test_steep_hills_are_bare_and_gentle_ones_are_not() -> void:
	var grid := _disc(Terrain.Type.HILLS, 1.0)
	var surface := TerrainSurface.new(grid)
	var clumps := GrassPlanner.plan_chunk(CHUNK, grid, surface, SEED, 1.0)
	assert_true(clumps.size() > 0, "flat hills carry grass")
	assert_true(absf(clumps.size() - 50 * 16) <= 50 * 16 * 0.1, "hills: %d" % clumps.size())
	# A generated map has real slopes: no clump may sit on one steeper than the limit.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var map := MapGenerator.generate(12, 10, rng)
	var map_surface := TerrainSurface.new(map)
	for chunk in GrassPlanner.chunks_covering(Rect2(-2, -2, 24, 20)):
		for g: Dictionary in GrassPlanner.plan_chunk(chunk, map, map_surface, SEED, 1.0):
			var p: Vector3 = g["position"]
			if map.get_terrain(Hex.from_world(p, TerrainField.HEX_SIZE)) == Terrain.Type.HILLS:
				assert_true(GrassPlanner.slope(map_surface, p.x, p.z) <= 0.5 + 1e-4, "hill slope")


func test_positions_are_in_the_chunk_on_the_map_and_on_the_ground() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var map := MapGenerator.generate(12, 10, rng)
	var surface := TerrainSurface.new(map)
	var chunk := Vector2i(2, 1)
	var rect := GrassPlanner.chunk_rect(chunk)
	var list := GrassPlanner.plan_chunk(chunk, map, surface, SEED, 1.0)
	assert_true(list.size() > 0)
	for g: Dictionary in list:
		var p: Vector3 = g["position"]
		assert_true(rect.has_point(Vector2(p.x, p.z)), "inside chunk")
		assert_true(map.has_tile(Hex.from_world(p, TerrainField.HEX_SIZE)), "on the map")
		assert_true(absf(p.y - surface.ground_height(p.x, p.z)) <= 0.001, "on the ground")


func test_chunk_off_the_map_is_empty() -> void:
	assert_eq(_plan(Fixtures.plains_grid(1), Vector2i(20, 20)).size(), 0)


func test_scale_and_tint_ranges() -> void:
	for g: Dictionary in _plan(Fixtures.plains_grid(5)):
		assert_true(g["scale"] >= 0.7 and g["scale"] <= 1.3, "scale %s" % g["scale"])
		assert_true(g["tint"] >= 0.0 and g["tint"] <= 1.0, "tint %s" % g["tint"])


func test_chunks_covering_a_rect() -> void:
	var chunks := GrassPlanner.chunks_covering(Rect2(-1, 0.5, 6, 3))
	assert_true(chunks.has(Vector2i(-1, 0)))
	assert_true(chunks.has(Vector2i(1, 0)))
	assert_false(chunks.has(Vector2i(2, 0)))
	assert_eq(chunks.size(), 3)


func test_instance_budget_on_the_default_map() -> void:
	var grid := Scenario.default_battle(12345).grid
	var surface := TerrainSurface.new(grid)
	var centers: Array[Vector3] = []
	for c in grid.coords():
		centers.append(Hex.to_world(c, 1.0))
	var total := 0
	for chunk in GrassPlanner.chunks_covering(CameraMath.map_bounds(centers, 1.0)):
		total += GrassPlanner.plan_chunk(chunk, grid, surface, GrassField.SEED, 1.0).size()
	print("Grass instances on the default map at density 1.0: %d" % total)
	assert_true(total <= GrassPlanner.INSTANCE_BUDGET, "grass budget: %d" % total)
