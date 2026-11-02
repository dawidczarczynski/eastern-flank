extends TestCase
## Reeds on marshes and river banks (TASK-108e): GrassPlanner.Kind.REED, the marsh density
## factor, the bank band in metres (MapScale), the LookPreset keys and GrassTexture.reed_card.

const Fixtures := preload("res://tests/fixtures.gd")
const K := GrassPlanner.Kind
const SEED := 4242
const CHUNK := Vector2i(0, 0)
const RIVER := FeatureRibbonPlanner.Kind.RIVER


func after_each() -> void:
	LookPreset.reset()
	VisualScale.reset()
	MapScale.reset()


func _meadow_without_reeds() -> Dictionary:
	var m := LookPreset.meadow()
	m["marsh_density"] = 1.0
	m["reed_share"] = 0.0
	m["bank_reeds"] = 0.0
	return m


func _plan(grid: HexGrid, chunk: Vector2i, meadow: Dictionary = {}) -> Array:
	return GrassPlanner.plan_chunk(chunk, grid, TerrainSurface.new(grid), SEED, 1.0, meadow)


func _centre_distance(p: Vector3) -> float:
	var c := Hex.from_world(p, TerrainField.HEX_SIZE)
	var w := Hex.to_world(c, TerrainField.HEX_SIZE)
	return Vector2(p.x - w.x, p.z - w.z).length()


func _marsh_grid() -> HexGrid:
	var grid := Fixtures.plains_grid(5)
	for c in grid.coords():
		grid.set_terrain(c, Terrain.Type.MARSH)
	return grid


## A plains grid with a straight river along the x axis (links east-west through row r = 0).
func _river_grid() -> HexGrid:
	var grid := Fixtures.plains_grid(5)
	for q in range(-4, 4):
		var dir := 0
		grid.set_river_links(Vector2i(q, 0), grid.river_links(Vector2i(q, 0)) | (1 << dir))
		grid.set_river_links(Vector2i(q + 1, 0), grid.river_links(Vector2i(q + 1, 0)) | (1 << 3))
	return grid


func _chunks_of(grid: HexGrid) -> Array[Vector2i]:
	var centers: Array[Vector3] = []
	for c in grid.coords():
		centers.append(Hex.to_world(c, 1.0))
	return GrassPlanner.chunks_covering(CameraMath.map_bounds(centers, 1.0))


func test_reed_kind_and_height() -> void:
	assert_eq(K.REED, 4)
	var m := LookPreset.meadow()
	assert_eq(GrassPlanner.kind_height(K.REED, m), 1.5)
	assert_eq(m["reed_height"], 1.5)
	VisualScale.apply(&"balanced")
	var expected := 0.05 * 1.4 * 1.3 * 1.5 + Wind.MAX_OFFSET
	assert_true(absf(GrassField.max_clump_height() - expected) < 1e-6)


func test_current_preset_has_no_reeds() -> void:
	LookPreset.apply(&"current")
	var m := LookPreset.meadow()
	assert_eq(m["reed_share"], 0.0)
	assert_eq(m["bank_reeds"], 0.0)
	assert_eq(m["marsh_density"], 1.0)
	var grid := _marsh_grid()
	var river := _river_grid()
	for g: Dictionary in _plan(grid, CHUNK) + _plan(river, CHUNK):
		assert_true(g["kind"] != K.REED)


func test_marsh_reed_share_and_density() -> void:
	var marsh := _marsh_grid()
	var plains := Fixtures.plains_grid(5)
	var clear: float = LookPreset.meadow()["centre_clear"]
	var marsh_count := 0
	var plains_count := 0
	var reeds := 0
	var away := 0
	for chunk in [Vector2i(0, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0)]:
		var plan := _plan(marsh, chunk)
		marsh_count += plan.size()
		plains_count += _plan(plains, chunk).size()
		for g: Dictionary in plan:
			if _centre_distance(g["position"]) < clear:
				assert_true(g["kind"] != K.REED, "no reeds on the tile centre")
				continue
			away += 1
			if g["kind"] == K.REED:
				reeds += 1
				assert_eq(g["height"], 1.5)
	var share := float(reeds) / maxi(away, 1)
	var ratio := float(marsh_count) / maxi(plains_count, 1)
	print("  marsh reed share %.3f of %d, count ratio %.3f" % [share, away, ratio])
	assert_true(share >= 0.55 and share <= 0.80, "reed share %f" % share)
	assert_true(ratio >= 1.2 and ratio <= 1.4, "marsh count ratio %f" % ratio)


func test_marsh_positions_of_the_old_stream_do_not_move() -> void:
	var marsh := _marsh_grid()
	var on := {}
	for g: Dictionary in _plan(marsh, CHUNK):
		on[g["position"]] = true
	for g: Dictionary in _plan(marsh, CHUNK, _meadow_without_reeds()):
		assert_true(on.has(g["position"]), "old clump still planned")


func test_bank_reeds_follow_the_ten_metre_band() -> void:
	var grid := _river_grid()
	var band := MapScale.to_units(10.0)
	assert_true(absf(band - 0.0693) < 0.001, "band %f" % band)
	var in_band := 0
	var reeds_in_band := 0
	for chunk in _chunks_of(grid):
		for g: Dictionary in _plan(grid, chunk):
			var p: Vector3 = g["position"]
			var d := FeatureRibbonPlanner.edge_distance(grid, RIVER, p.x, p.z)
			var near := d > 0.0 and d <= band and _centre_distance(p) >= 0.4
			if near:
				in_band += 1
				if g["kind"] == K.REED:
					reeds_in_band += 1
			elif d > band or d < 0.0:
				assert_true(g["kind"] != K.REED or _is_marsh_reed(grid, p), "reed off the bank")
	var share := float(reeds_in_band) / maxi(in_band, 1)
	print("  bank reed share %.3f of %d" % [share, in_band])
	assert_true(in_band >= 30, "clumps in the band: %d" % in_band)
	assert_true(share >= 0.6 and share <= 0.8, "bank reed share %f" % share)


func _is_marsh_reed(grid: HexGrid, p: Vector3) -> bool:
	return grid.get_terrain(Hex.from_world(p, TerrainField.HEX_SIZE)) == Terrain.Type.MARSH


func test_bank_band_scales_with_metres_per_unit() -> void:
	var grid := _river_grid()
	var far := 0
	MapScale.metres_per_unit = MapScale.DEFAULT_METRES_PER_UNIT / 2.0
	var band := MapScale.to_units(10.0)
	for chunk in _chunks_of(grid):
		for g: Dictionary in _plan(grid, chunk):
			var p: Vector3 = g["position"]
			var d := FeatureRibbonPlanner.edge_distance(grid, RIVER, p.x, p.z)
			if g["kind"] == K.REED:
				assert_true(d <= band, "reed within the doubled band")
				if d > 0.0693 * 1.2:
					far += 1
	assert_true(far > 0, "reeds beyond the old band appear when the band doubles")


func test_urban_bank_has_no_reeds() -> void:
	var grid := _river_grid()
	for c in grid.coords():
		grid.set_terrain(c, Terrain.Type.URBAN)
	for chunk in _chunks_of(grid):
		for g: Dictionary in _plan(grid, chunk):
			assert_true(g["kind"] != K.REED)


func test_other_chunks_unchanged_by_reeds() -> void:
	var grid := Fixtures.plains_grid(5)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	grid.set_terrain(Vector2i(-1, 1), Terrain.Type.HILLS)
	var off := _meadow_without_reeds()
	for chunk in _chunks_of(grid):
		var a := _plan(grid, chunk)
		var b := _plan(grid, chunk, off)
		assert_eq(a.size(), b.size())
		for i in a.size():
			assert_eq(a[i]["position"], b[i]["position"])
			assert_eq(a[i]["kind"], b[i]["kind"])


func test_default_battle_has_no_reeds() -> void:
	var grid := Scenario.default_battle(12345).grid
	var off := _meadow_without_reeds()
	for chunk in _chunks_of(grid):
		var a := _plan(grid, chunk)
		var b := _plan(grid, chunk, off)
		assert_eq(a.size(), b.size())
		for i in a.size():
			assert_eq(a[i]["position"], b[i]["position"])
			assert_eq(a[i]["kind"], b[i]["kind"])


func test_kind_color_reed_follows_dry_noise() -> void:
	var m := LookPreset.meadow()
	var ground := Color(0.1, 0.2, 0.05)
	var green := GrassPlanner.kind_color(K.REED, ground, 0.5, m, 0.0)
	var dry := GrassPlanner.kind_color(K.REED, ground, 0.5, m, 1.0)
	assert_true(dry.r > green.r and dry.b >= green.b - 1e-6, "dry reeds are more yellow")
	assert_true(green != GrassPlanner.kind_color(K.SHORT, ground, 0.5, m))


func test_reed_card() -> void:
	var a := GrassTexture.reed_card(128, 5)
	var b := GrassTexture.reed_card(128, 5)
	assert_eq(a.get_data(), b.get_data())
	var covered := 0
	var top := 0
	var heads := 0
	for y in 128:
		for x in 128:
			var c := a.get_pixel(x, y)
			assert_true(c.a == 0.0 or c.a == 1.0)
			if c.a == 1.0:
				covered += 1
				if y < 13:
					top += 1
				if c.r - c.b > 0.05:
					heads += 1
	var share := float(covered) / (128 * 128)
	assert_true(share >= 0.08 and share <= 0.30, "coverage %f" % share)
	assert_true(top > 0, "blades reach the top rows")
	assert_true(heads > 0, "seed heads are brown")
