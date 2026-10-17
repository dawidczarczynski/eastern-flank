extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")
const SETTINGS := preload("res://data/map/terrain_generation.tres")
const WIDTH := 12
const HEIGHT := 10


func _generate(map_seed: int) -> HexGrid:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	return MapGenerator.generate(WIDTH, HEIGHT, rng)


func _classify(h: float, moisture: float) -> Terrain.Type:
	return MapGenerator.classify(h, moisture, SETTINGS)


# --- HexGrid elevation ---


func test_default_elevation_per_type() -> void:
	assert_eq(Terrain.default_elevation(Terrain.Type.PLAINS), 0.2)
	assert_eq(Terrain.default_elevation(Terrain.Type.FOREST), 0.25)
	assert_eq(Terrain.default_elevation(Terrain.Type.HILLS), 0.9)
	assert_eq(Terrain.default_elevation(Terrain.Type.WATER), -0.3)


func test_grid_elevation_defaults_to_terrain_type() -> void:
	var grid := Fixtures.plains_grid(1)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.HILLS)
	assert_eq(grid.elevation(Vector2i(0, 0)), 0.2)
	assert_eq(grid.elevation(Vector2i(1, 0)), 0.9)
	assert_true(grid.field == null)


func test_grid_elevation_off_map_is_zero() -> void:
	assert_eq(Fixtures.plains_grid(1).elevation(Vector2i(9, 9)), 0.0)


func test_grid_stored_elevation_overrides_default() -> void:
	var grid := Fixtures.plains_grid(1)
	grid.set_elevation(Vector2i(0, 0), 0.55)
	assert_eq(grid.elevation(Vector2i(0, 0)), 0.55)


# --- classify ---


func test_classify_boundaries() -> void:
	assert_eq(_classify(0.0, 0.5), Terrain.Type.WATER)
	assert_eq(_classify(0.019, 0.9), Terrain.Type.WATER)
	assert_eq(_classify(0.02, 0.5), Terrain.Type.PLAINS)
	assert_eq(_classify(0.3, 0.61), Terrain.Type.PLAINS)
	assert_eq(_classify(0.3, 0.62), Terrain.Type.FOREST)
	assert_eq(_classify(0.7, 0.5), Terrain.Type.PLAINS)
	assert_eq(_classify(0.71, 0.5), Terrain.Type.HILLS)
	assert_eq(_classify(0.71, 0.67), Terrain.Type.FOREST)
	assert_eq(_classify(2.0, 0.1), Terrain.Type.HILLS)


# --- generate ---


func test_generation_is_deterministic() -> void:
	var a := _generate(12345)
	var b := _generate(12345)
	assert_eq(a.coords().size(), WIDTH * HEIGHT)
	for c in a.coords():
		assert_eq(a.get_terrain(c), b.get_terrain(c), str(c))
		assert_eq(a.elevation(c), b.elevation(c), str(c))


func test_different_seeds_give_different_maps() -> void:
	var a := _generate(1)
	var b := _generate(2)
	var differing := 0
	for c in a.coords():
		if a.get_terrain(c) != b.get_terrain(c):
			differing += 1
	assert_true(differing >= 12, "only %d tiles differ" % differing)


func test_generated_tiles_match_the_field() -> void:
	var grid := _generate(12345)
	assert_true(grid.field != null)
	for c in grid.coords():
		var center := Hex.to_world(c, TerrainField.HEX_SIZE)
		var h := grid.field.height(center.x, center.z)
		assert_eq(grid.elevation(c), h, str(c))
		var moisture := grid.field.moisture(center.x, center.z)
		assert_eq(_classify(grid.elevation(c), moisture), grid.get_terrain(c), str(c))


# --- force_terrain ---


func _forced_elevation(start: float, t: Terrain.Type) -> float:
	var grid := Fixtures.plains_grid(1)
	grid.set_elevation(Vector2i.ZERO, start)
	MapGenerator.force_terrain(grid, Vector2i.ZERO, t)
	assert_eq(grid.get_terrain(Vector2i.ZERO), t)
	return grid.elevation(Vector2i.ZERO)


func test_force_terrain_clamps_elevation_into_the_band() -> void:
	assert_eq(_forced_elevation(-0.4, Terrain.Type.PLAINS), 0.12)
	assert_eq(_forced_elevation(0.35, Terrain.Type.PLAINS), 0.35)
	assert_eq(_forced_elevation(1.2, Terrain.Type.PLAINS), 0.7)
	assert_eq(_forced_elevation(0.3, Terrain.Type.WATER), -0.05)
	assert_eq(_forced_elevation(0.3, Terrain.Type.HILLS), 0.71)


# --- distribution ---


func test_terrain_distribution_over_50_seeds() -> void:
	var counts := {}
	for t: int in Terrain.Type.values():
		counts[t] = 0
	var total := 0
	var connected_maps := 0
	for map_seed in range(1, 51):
		var grid := _generate(map_seed)
		for c in grid.coords():
			counts[grid.get_terrain(c)] += 1
			total += 1
		if _largest_land_share(grid) >= 0.9:
			connected_maps += 1
	var water := float(counts[Terrain.Type.WATER]) / total
	var forest := float(counts[Terrain.Type.FOREST]) / total
	var hills := float(counts[Terrain.Type.HILLS]) / total
	var plains := float(counts[Terrain.Type.PLAINS]) / total
	var summary := (
		"water %.3f forest %.3f hills %.3f plains %.3f connected %d/50"
		% [water, forest, hills, plains, connected_maps]
	)
	print("  distribution: " + summary)
	assert_true(water >= 0.03 and water <= 0.15, summary)
	assert_true(forest >= 0.10 and forest <= 0.30, summary)
	assert_true(hills >= 0.05 and hills <= 0.25, summary)
	assert_true(plains >= 0.40, summary)
	assert_true(connected_maps >= 45, summary)


## Share of non-water tiles in the largest connected group of non-water tiles.
func _largest_land_share(grid: HexGrid) -> float:
	var seen := {}
	var land := 0
	var largest := 0
	for start in grid.coords():
		if grid.get_terrain(start) == Terrain.Type.WATER:
			continue
		land += 1
		if seen.has(start):
			continue
		seen[start] = true
		var size := 0
		var stack: Array[Vector2i] = [start]
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			size += 1
			for n in Hex.neighbors(c):
				if (
					grid.has_tile(n)
					and not seen.has(n)
					and grid.get_terrain(n) != Terrain.Type.WATER
				):
					seen[n] = true
					stack.append(n)
		largest = maxi(largest, size)
	return 1.0 if land == 0 else float(largest) / land


# --- regression pin ---


func test_regression_pin_seed_12345() -> void:
	var grid := _generate(12345)
	var expected := [
		[Vector2i(0, 0), Terrain.Type.PLAINS, 0.19],
		[Vector2i(5, 4), Terrain.Type.FOREST, 0.299],
		[Vector2i(10, 9), Terrain.Type.FOREST, 0.198],
	]
	for row: Array in expected:
		var offset: Vector2i = row[0]
		var c := MapGenerator.offset_to_axial(offset.x, offset.y)
		var label := "offset %s: %s %.3f" % [offset, grid.get_terrain(c), grid.elevation(c)]
		assert_eq(grid.get_terrain(c), row[1], label)
		assert_eq(snappedf(grid.elevation(c), 0.001), row[2], label)
