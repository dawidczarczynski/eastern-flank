extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")
const K := GrassPlanner.Kind
const SEED := 4242
const CHUNK := Vector2i(0, 0)


func after_each() -> void:
	LookPreset.reset()
	VisualScale.reset()


func _plan(grid: HexGrid, chunk: Vector2i = CHUNK, density := 1.0, seed_value := SEED) -> Array:
	return GrassPlanner.plan_chunk(chunk, grid, TerrainSurface.new(grid), seed_value, density)


func _default_map() -> HexGrid:
	return Scenario.default_battle(12345).grid


func _plan_all(grid: HexGrid, meadow: Dictionary = {}) -> Array:
	var surface := TerrainSurface.new(grid)
	var centers: Array[Vector3] = []
	for c in grid.coords():
		centers.append(Hex.to_world(c, 1.0))
	var result: Array = []
	for chunk in GrassPlanner.chunks_covering(CameraMath.map_bounds(centers, 1.0)):
		result.append_array(
			GrassPlanner.plan_chunk(chunk, grid, surface, GrassField.SEED, 1.0, meadow)
		)
	return result


func _centre_distance(p: Vector3) -> float:
	var c := Hex.from_world(p, TerrainField.HEX_SIZE)
	var w := Hex.to_world(c, TerrainField.HEX_SIZE)
	return Vector2(p.x - w.x, p.z - w.z).length()


func test_current_preset_reproduces_task_057_and_thinning_only_removes() -> void:
	var grid := Fixtures.plains_grid(5)
	LookPreset.apply(&"current")
	var base := _plan(grid)
	for g: Dictionary in base:
		assert_eq(g["kind"], K.SHORT)
		assert_eq(g["height"], 1.0)
	LookPreset.reset()
	var summer := _plan(grid)
	var positions := {}
	for g: Dictionary in base:
		positions[g["position"]] = true
	assert_true(summer.size() <= base.size())
	for g: Dictionary in summer:
		assert_true(positions.has(g["position"]), "summer clump is also a current clump")
	# Without thinning the position lists are equal.
	var meadow := LookPreset.meadow()
	meadow["bare_thinning"] = 0.0
	var unthinned := GrassPlanner.plan_chunk(
		CHUNK, grid, TerrainSurface.new(grid), SEED, 1.0, meadow
	)
	assert_eq(unthinned.size(), base.size())
	for i in base.size():
		assert_eq(unthinned[i]["position"], base[i]["position"])


func test_pick_kind() -> void:
	var m := LookPreset.meadow()
	var plains := Terrain.Type.PLAINS
	for d in [0.0, 0.39]:
		for i in 10:
			for j in 10:
				var h1 := i * 0.1
				var h2 := j * 0.1
				assert_eq(GrassPlanner.pick_kind(plains, d, 1.0, 1.0, true, h1, h2, m), K.SHORT)
	for i in 10:
		for j in 10:
			var got := GrassPlanner.pick_kind(
				Terrain.Type.FOREST, 1.0, 1.0, 1.0, true, i * 0.1, j * 0.1, m
			)
			assert_eq(got, K.SHORT)
	assert_eq(GrassPlanner.pick_kind(plains, 1.0, 1.0, 0.0, false, 0.1, 0.5, m), K.DRY_STALK)
	assert_eq(GrassPlanner.pick_kind(plains, 1.0, 0.0, 0.0, true, 0.9, 0.5, m), K.NETTLE)
	assert_eq(GrassPlanner.pick_kind(plains, 1.0, 0.0, 0.0, false, 0.9, 0.5, m), K.SHORT)
	assert_eq(GrassPlanner.pick_kind(plains, 1.0, 0.0, 1.0, false, 0.5, 0.99, m), K.TALL)
	assert_eq(GrassPlanner.pick_kind(plains, 1.0, 0.0, 0.0, false, 0.5, 0.01, m), K.SHORT)


func _edge_grid() -> HexGrid:
	var grid := Fixtures.plains_grid(2)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	return grid


func test_forest_edge_distance() -> void:
	var grid := _edge_grid()
	var origin := Hex.to_world(Vector2i(0, 0), TerrainField.HEX_SIZE)
	var toward := (Hex.to_world(Vector2i(1, 0), TerrainField.HEX_SIZE) - origin).normalized()
	var p := origin + toward * 0.75
	assert_true(absf(GrassPlanner.forest_edge_distance(p.x, p.z, grid) - 0.982) < 0.01)
	assert_true(absf(GrassPlanner.forest_edge_distance(origin.x, origin.z, grid) - 1.732) < 0.01)
	var far := Hex.to_world(Vector2i(-2, 0), TerrainField.HEX_SIZE)
	assert_eq(GrassPlanner.forest_edge_distance(far.x, far.z, grid), INF)
	var forest := Hex.to_world(Vector2i(1, 0), TerrainField.HEX_SIZE)
	assert_eq(GrassPlanner.forest_edge_distance(forest.x, forest.z, grid), INF)
	assert_eq(GrassPlanner.forest_edge_distance(500.0, 500.0, grid), INF)


func test_tall_grass_bonus_in_the_forest_edge_band() -> void:
	var grid := _edge_grid()
	var meadow := LookPreset.meadow()
	meadow["tall_from"] = 2.0
	meadow["tall_to"] = 3.0
	meadow["dry_stalk_share"] = 0.0
	var in_band := 0
	var tall_in_band := 0
	var tall_outside := 0
	for chunk in GrassPlanner.chunks_covering(Rect2(-5, -5, 10, 10)):
		for g: Dictionary in GrassPlanner.plan_chunk(
			chunk, grid, TerrainSurface.new(grid), SEED, 1.0, meadow
		):
			var p: Vector3 = g["position"]
			var band: bool = (
				GrassPlanner.forest_edge_distance(p.x, p.z, grid) <= float(meadow["edge_band"])
			)
			if band:
				in_band += 1
				if g["kind"] == K.TALL:
					tall_in_band += 1
			elif g["kind"] == K.TALL:
				tall_outside += 1
	var share := float(tall_in_band) / maxi(in_band, 1)
	print("  tall share in the edge band: %.3f of %d" % [share, in_band])
	assert_true(share >= 0.35 and share <= 0.55, "tall share %f" % share)
	assert_eq(tall_outside, 0)


func test_heights_match_kinds_and_max_clump_height() -> void:
	var heights := {K.SHORT: 1.0, K.TALL: 1.5, K.DRY_STALK: 1.3, K.NETTLE: 1.35}
	for g: Dictionary in _plan_all(_default_map()):
		assert_eq(g["height"], heights[g["kind"]])
	VisualScale.apply(&"balanced")
	var expected := 0.05 * 1.4 * 1.3 * 1.5 + Wind.MAX_OFFSET
	assert_true(absf(GrassField.max_clump_height() - expected) < 1e-6)
	assert_true(GrassField.max_clump_height() - Wind.MAX_OFFSET <= 0.14)


func test_tall_dry_and_nettle_stay_off_the_tile_centre() -> void:
	var counts := {}
	for g: Dictionary in _plan_all(_default_map()):
		counts[g["kind"]] = counts.get(g["kind"], 0) + 1
		if g["kind"] != K.SHORT:
			assert_true(_centre_distance(g["position"]) >= 0.4 - 1e-4, "centre clear")
	assert_true(counts.size() > 1)


func test_bare_thinning_on_plains() -> void:
	var grid := Fixtures.plains_grid(12)
	var cell := 0.25
	var cells := {}
	for g: Dictionary in _plan_all(grid):
		var p: Vector3 = g["position"]
		var key := Vector2i((Vector2(p.x, p.z) / cell).floor())
		cells[key] = cells.get(key, 0) + 1
	var bare_cells := 0
	var bare_clumps := 0
	var moist_cells := 0
	var moist_clumps := 0
	for x in range(-24, 24):
		for z in range(-24, 24):
			var key := Vector2i(x, z)
			var cx := (x + 0.5) * cell
			var cz := (z + 0.5) * cell
			var c := Hex.from_world(Vector3(cx, 0, cz), TerrainField.HEX_SIZE)
			if Hex.distance(Vector2i.ZERO, c) > 9:
				continue
			var bare := TerrainNoise.smooth(
				TerrainSplat.DIRT_PATCH_FROM,
				TerrainSplat.DIRT_PATCH_TO,
				GroundNoise.moisture_k(cx, cz)
			)
			if bare >= 0.9:
				bare_cells += 1
				bare_clumps += cells.get(key, 0)
			elif bare == 0.0:
				moist_cells += 1
				moist_clumps += cells.get(key, 0)
	var bare_density := float(bare_clumps) / maxi(bare_cells, 1) / (cell * cell)
	var moist_density := float(moist_clumps) / maxi(moist_cells, 1) / (cell * cell)
	print(
		(
			"  grass density bare %.1f (%d cells) vs moist %.1f"
			% [bare_density, bare_cells, moist_density]
		)
	)
	assert_true(bare_cells >= 20, "enough bare cells: %d" % bare_cells)
	assert_true(bare_density <= moist_density * 0.35, "bare patches are thinned")


func test_kind_mix_on_the_default_map() -> void:
	var grid := _default_map()
	var meadow := LookPreset.meadow()
	var counts := {K.SHORT: 0, K.TALL: 0, K.DRY_STALK: 0, K.NETTLE: 0}
	var plains := 0
	var tall_plains := 0
	for g: Dictionary in _plan_all(grid):
		var p: Vector3 = g["position"]
		var terrain := grid.get_terrain(Hex.from_world(p, TerrainField.HEX_SIZE))
		counts[g["kind"]] += 1
		if terrain == Terrain.Type.PLAINS:
			plains += 1
			if g["kind"] == K.TALL:
				tall_plains += 1
		if g["kind"] == K.NETTLE:
			assert_true(GrassPlanner.forest_edge_distance(p.x, p.z, grid) <= meadow["edge_band"])
	var tall_share := float(tall_plains) / maxi(plains, 1)
	print("  kinds on the default map: %s (tall %.2f of plains)" % [counts, tall_share])
	for kind: int in counts:
		assert_true(counts[kind] > 0, "kind %d occurs" % kind)
	assert_true(tall_share >= 0.15 and tall_share <= 0.45, "tall share %f" % tall_share)


func test_kind_color() -> void:
	var m := LookPreset.meadow()
	var ground := Color(0.1, 0.2, 0.05)
	var short := GrassPlanner.kind_color(K.SHORT, ground, 0.3, m)
	var k := lerpf(0.85, 1.1, 0.3)
	assert_true(absf(short.r - ground.r * k) < 1e-6 and absf(short.g - ground.g * k) < 1e-6)
	assert_true(absf(short.b - ground.b * k) < 1e-6)
	var dry := GrassPlanner.kind_color(K.DRY_STALK, ground, 0.3, m)
	var target: Color = (m["dry_stalk_color"] as Color).srgb_to_linear()
	var d_dry := Vector3(dry.r - target.r, dry.g - target.g, dry.b - target.b).length()
	var d_ground := Vector3(ground.r - target.r, ground.g - target.g, ground.b - target.b).length()
	assert_true(d_dry < d_ground)
	var nettle := GrassPlanner.kind_color(K.NETTLE, ground, 0.3, m)
	var tall := GrassPlanner.kind_color(K.TALL, ground, 0.3, m)
	assert_true(nettle.g < tall.g, "nettle is darker green than tall grass")


func test_hash01_is_deterministic_and_in_range() -> void:
	assert_eq(GrassPlanner.hash01(1.5, 2.5, 1), GrassPlanner.hash01(1.5, 2.5, 1))
	assert_true(GrassPlanner.hash01(1.5, 2.5, 1) != GrassPlanner.hash01(1.5, 2.5, 2))
	for i in 100:
		var h := GrassPlanner.hash01(i * 0.37, i * 1.13, 3)
		assert_true(h >= 0.0 and h < 1.0)


func test_moisture_k_matches_the_value_noise_map_view_used() -> void:
	for p in [Vector2(0.3, 0.7), Vector2(-4.2, 9.9), Vector2(12.0, -3.3)]:
		var expected := TerrainNoise.value_noise(p.x * 0.9, p.y * 0.9, 97.0)
		assert_eq(GroundNoise.moisture_k(p.x, p.y), expected)
