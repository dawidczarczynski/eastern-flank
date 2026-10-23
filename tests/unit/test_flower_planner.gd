extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

const SEED := 4242


func after_each() -> void:
	LookPreset.reset()


func _flowers(
	grid: HexGrid, chunk: Vector2i, density := 1.0, seed_value := SEED, meadow := {}
) -> Array:
	return GrassPlanner.plan_flowers(
		chunk, grid, TerrainSurface.new(grid), seed_value, density, meadow
	)


func _all(grid: HexGrid, density := 1.0, meadow := {}) -> Array:
	var centers: Array[Vector3] = []
	for c in grid.coords():
		centers.append(Hex.to_world(c, 1.0))
	var surface := TerrainSurface.new(grid)
	var result: Array = []
	for chunk in GrassPlanner.chunks_covering(CameraMath.map_bounds(centers, 1.0)):
		result.append_array(GrassPlanner.plan_flowers(chunk, grid, surface, SEED, density, meadow))
	return result


func _centre_distance(p: Vector3) -> float:
	var c := Hex.from_world(p, TerrainField.HEX_SIZE)
	var w := Hex.to_world(c, TerrainField.HEX_SIZE)
	return Vector2(p.x - w.x, p.z - w.z).length()


func test_deterministic_and_seed_chunk_dependent() -> void:
	var grid := Fixtures.plains_grid(12)
	var chunk := Vector2i(1, 1)
	var a := _flowers(grid, chunk)
	assert_true(a.size() > 0, "flowers in the chunk: %d" % a.size())
	assert_eq(a, _flowers(grid, chunk))
	assert_true(a != _flowers(grid, chunk, 1.0, SEED + 1))
	assert_true(a != _flowers(grid, Vector2i(2, 1)))


func test_current_and_zero_density_give_nothing() -> void:
	var grid := Fixtures.plains_grid(12)
	assert_eq(_all(grid, 0.0).size(), 0)
	LookPreset.apply(&"current")
	assert_eq(_all(grid).size(), 0)


func test_density_scales_the_count() -> void:
	var grid := Fixtures.plains_grid(12)
	var full := _all(grid, 1.0).size()
	var half := _all(grid, 0.5).size()
	assert_true(full > 200, "full: %d" % full)
	assert_true(absf(half - full * 0.5) <= full * 0.1, "half %d of %d" % [half, full])


func test_placement_rules() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var map := MapGenerator.generate(12, 10, rng)
	var surface := TerrainSurface.new(map)
	var meadow := LookPreset.meadow()
	var palette: Array[Color] = []
	for group: Dictionary in meadow["flowers"]:
		palette.append(group["color"])
	var count := 0
	for chunk in GrassPlanner.chunks_covering(Rect2(-2, -2, 24, 20)):
		var rect := GrassPlanner.chunk_rect(chunk)
		for f: Dictionary in GrassPlanner.plan_flowers(chunk, map, surface, SEED, 1.0, {}):
			count += 1
			var p: Vector3 = f["position"]
			var coord := Hex.from_world(p, TerrainField.HEX_SIZE)
			assert_true(rect.has_point(Vector2(p.x, p.z)), "inside the chunk")
			assert_true(map.has_tile(coord), "on the map")
			var terrain := map.get_terrain(coord)
			assert_true(
				terrain == Terrain.Type.PLAINS or terrain == Terrain.Type.HILLS, "plains or hills"
			)
			assert_true(absf(p.y - surface.ground_height(p.x, p.z)) <= 0.001, "on the ground")
			assert_true(p.y > TerrainSurface.WATER_SURFACE + GrassPlanner.SHORE_BAND, "no shore")
			if terrain == Terrain.Type.HILLS:
				assert_true(GrassPlanner.slope(surface, p.x, p.z) <= 0.5 + 1e-4, "no slope")
			assert_true(_centre_distance(p) >= meadow["centre_clear"] - 1e-4, "centre clear")
			var moisture := GroundNoise.moisture_k(p.x, p.z)
			var bare := TerrainNoise.smooth(
				TerrainSplat.DIRT_PATCH_FROM, TerrainSplat.DIRT_PATCH_TO, moisture
			)
			assert_true(bare < 0.5, "not on bare dirt")
			var cluster := TerrainNoise.smooth(
				meadow["flower_from"], meadow["flower_to"], GroundNoise.flower_k(p.x, p.z, meadow)
			)
			assert_true(cluster > 0.0, "inside a cluster")
			assert_true(palette.has(f["color"]), "palette colour")
			assert_true(f["height"] >= 1.1 - 1e-6 and f["height"] <= 1.4 + 1e-6)
			assert_true(f["scale"] >= 0.7 - 1e-6 and f["scale"] <= 1.3 + 1e-6)
	assert_true(count > 0, "some flowers")


func test_no_flowers_on_forest_or_water() -> void:
	for terrain in [Terrain.Type.FOREST, Terrain.Type.WATER]:
		var grid := Fixtures.plains_grid(8)
		for c in grid.coords():
			grid.set_terrain(c, terrain)
		assert_eq(_all(grid).size(), 0)


func test_species_shares_and_clustering() -> void:
	var grid := Fixtures.plains_grid(12)
	var meadow := LookPreset.meadow()
	var flowers := _all(grid)
	var total := flowers.size()
	assert_true(total > 500, "enough flowers: %d" % total)
	var by_color := {}
	var cells := {}
	for f: Dictionary in flowers:
		var p: Vector3 = f["position"]
		by_color[f["color"]] = by_color.get(f["color"], 0) + 1
		var key := Vector2i((Vector2(p.x, p.z) / meadow["flower_cell"]).floor())
		if not cells.has(key):
			cells[key] = {}
		var counts: Dictionary = cells[key]
		counts[f["color"]] = counts.get(f["color"], 0) + 1
	for group: Dictionary in meadow["flowers"]:
		var share := float(by_color.get(group["color"], 0)) / total
		print("  flower share %s: %.3f (configured %.2f)" % [group["name"], share, group["share"]])
		assert_true(absf(share - group["share"]) <= 0.1, "%s share %f" % [group["name"], share])
	# A cell's flowers are mostly its dominant species: p(same) = 0.75 + 0.25 * share, so a cell
	# of 8-12 flowers dips below 60 % by chance now and then; require it of 90 % of the cells.
	var checked := 0
	var clustered := 0
	for key: Vector2i in cells:
		var counts: Dictionary = cells[key]
		var n := 0
		var best := 0
		for color: Color in counts:
			n += counts[color]
			best = maxi(best, counts[color])
		if n >= 8:
			checked += 1
			if float(best) / n >= 0.6:
				clustered += 1
	print(
		(
			"  flower cells with >= 8 flowers: %d, of them >= 60%% one colour: %d"
			% [checked, clustered]
		)
	)
	assert_true(checked > 0, "cells with enough flowers")
	assert_true(float(clustered) / checked >= 0.9, "cells are dominated by one species")
