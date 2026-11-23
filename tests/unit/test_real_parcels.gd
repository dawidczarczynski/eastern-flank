extends TestCase
## Real field parcels (TASK-215b, RealParcels, FieldParcels.bake with polygons).

const Fixtures := preload("res://tests/fixtures.gd")
const HA := 10000.0
## The subdivision threshold of the acceptance criteria (the look's own is RealParcelLook).
const MAX_M2 := 15.0 * HA
const PLAIN := ImportedMap.PARCEL_EDGE_PLAIN
const HEDGE := ImportedMap.PARCEL_EDGE_HEDGE
const SHARES := {&"wheat": 0.3, &"green": 0.2, &"stubble": 0.2, &"ploughed": 0.2, &"meadow": 0.1}
## FieldParcels.bake digests (size, format, sha256 prefix) recorded before TASK-215b.
const DIGEST_GRID_BALANCED := "693 693 3 391f2caa200b37af"
const DIGEST_GRID_TRUE := "693 693 3 97d1d881daac8b20"
const DIGEST_SUWALKI_TRUE := "1987 1516 3 d145c1ceae81ae01"
const DIGEST_SUWALKI_BALANCED := "1987 1516 3 4bb4f74cb5a723d0"


func after_each() -> void:
	VisualScale.reset()
	MapScale.reset()
	LookPreset.reset()


static func _digest(map: ParcelMap) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(map.image.get_data())
	return (
		"%d %d %d %s"
		% [
			map.image.get_width(),
			map.image.get_height(),
			map.image.get_format(),
			ctx.finish().hex_encode().substr(0, 16)
		]
	)


static func _rect_ring(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x0, z1), Vector2(x1, z1), Vector2(x1, z0)])


static func _rings(ring: PackedVector2Array) -> Array[PackedVector2Array]:
	var rings: Array[PackedVector2Array] = [ring]
	return rings


## The default look with the acceptance criteria's 15 ha threshold (one parcel per test polygon).
static func _settings_15() -> RealParcelLook:
	var settings := RealParcelLook.load_default().duplicate() as RealParcelLook
	settings.large_parcel_ha = 15.0
	return settings


static func _plains_grid() -> HexGrid:
	return Fixtures.plains_grid(8)


static func _suwalki_rect(map: ImportedMap) -> Rect2:
	return map.hex_world_rect().grow(MapView.EXTENT + MapView.PARCEL_MARGIN)


static func _percentile(sorted: PackedFloat64Array, p: float) -> float:
	return sorted[clampi(roundi(p * (sorted.size() - 1)), 0, sorted.size() - 1)]


func test_a_40_ha_square_becomes_three_parcels_across_its_long_axis() -> void:
	var side := sqrt(40.0 * HA)
	var parts := RealParcels.subdivide(_rings(_rect_ring(0.0, 0.0, side, side)), MAX_M2)
	assert_eq(parts.size(), 3)
	var total := 0.0
	for part: Array[PackedVector2Array] in parts:
		var a := RealParcels.area(part)
		total += a
		assert_true(a >= 8.0 * HA and a <= 15.0 * HA, "part of %.2f ha" % (a / HA))
	assert_true(absf(total - 40.0 * HA) < 0.01 * 40.0 * HA, "areas sum to %.2f ha" % (total / HA))
	# A 1000 x 400 m field (40 ha) is cut across its long (x) side: each part spans the full 400 m.
	var long := RealParcels.subdivide(_rings(_rect_ring(0.0, 0.0, 1000.0, 400.0)), MAX_M2)
	assert_eq(long.size(), 3)
	for part: Array[PackedVector2Array] in long:
		var box := Rect2(part[0][0], Vector2.ZERO)
		for p in part[0]:
			box = box.expand(p)
		assert_true(absf(box.size.y - 400.0) < 0.01, "cut perpendicular to the long axis")
		assert_true(absf(box.size.x - 1000.0 / 3.0) < 1.0, "equal parts (%.1f m)" % box.size.x)


func test_a_10_ha_polygon_is_not_subdivided() -> void:
	var rings := _rings(_rect_ring(0.0, 0.0, 500.0, 200.0))
	var parts := RealParcels.subdivide(rings, MAX_M2)
	assert_eq(parts.size(), 1)
	assert_eq(parts[0], rings)


func test_subdivision_keeps_holes_and_area() -> void:
	var outer := _rect_ring(0.0, 0.0, 1200.0, 300.0)
	var hole := _rect_ring(500.0, 100.0, 700.0, 200.0)
	hole.reverse()
	var rings: Array[PackedVector2Array] = [outer, hole]
	var total := RealParcels.area(rings)
	assert_true(absf(total - 34.0 * HA) < 1.0)
	var parts := RealParcels.subdivide(rings, MAX_M2)
	assert_eq(parts.size(), 3)
	var sum := 0.0
	for part: Array[PackedVector2Array] in parts:
		sum += RealParcels.area(part)
	assert_true(absf(sum - total) < 0.01 * total, "%.2f vs %.2f ha" % [sum / HA, total / HA])


func test_subdivision_is_deterministic_and_keyed_by_polygon_id() -> void:
	var polygon := {"rings": _rings(_rect_ring(0.0, 0.0, 1100.0, 450.0)), "id": 7}
	var a := RealParcels.from_polygons([polygon], 99)
	var b := RealParcels.from_polygons([polygon], 99)
	var large_m2 := RealParcelLook.load_default().large_parcel_ha * HA
	assert_eq(a.pieces.size(), ceili(1100.0 * 450.0 / large_m2))
	assert_eq(a.pieces, b.pieces, "same polygon + seed: identical parcels")
	var differs := 0
	for id in range(8, 28):
		var other := RealParcels.from_polygons([{"rings": polygon["rings"], "id": id}], 99)
		var crop_a := FieldParcels.pick(a.pieces[0]["key"], SHARES, [])
		var crop_b := FieldParcels.pick(other.pieces[0]["key"], SHARES, [])
		if crop_a != crop_b or a.pieces[0]["angle"] != other.pieces[0]["angle"]:
			differs += 1
	assert_true(
		differs >= 10, "another polygon id gives another crop / row direction (%d)" % differs
	)


func test_rows_run_along_the_long_side_or_across_it() -> void:
	var across := 0
	for id in 40:
		var real := RealParcels.from_polygons(
			[{"rings": _rings(_rect_ring(0.0, 0.0, 300.0, 100.0)), "id": id}]
		)
		var angle: float = real.pieces[0]["angle"]
		assert_true(is_zero_approx(angle) or is_equal_approx(angle, PI * 0.5), "angle %f" % angle)
		if is_equal_approx(angle, PI * 0.5):
			across += 1
	assert_true(across > 0 and across < 20, "mostly along the long side (%d across)" % across)
	# The shader's code round-trips to within half a step.
	for angle: float in [0.0, 0.4, PI * 0.5, 2.9]:
		var back := FieldParcels.code_angle(FieldParcels.angle_code(angle))
		assert_true(absf(back - angle) <= PI / 254.0, "%f -> %f" % [angle, back])


func test_hedge_edges_get_a_balk_along_a_polyline() -> void:
	# A 300 x 300 m parcel at (200, 200) with a hedge on its first edge (x = 200, z 200..500).
	var ring := _rect_ring(200.0, 200.0, 500.0, 500.0)
	var edges := PackedByteArray([HEDGE, PLAIN, PLAIN, PLAIN])
	var real := RealParcels.from_polygons(
		[{"rings": _rings(ring), "edges": [edges]}], 0, 1.0, _settings_15()
	)
	var map := FieldParcels.bake(
		_plains_grid(), 1.0, Rect2(-1.0, -1.0, 6.0, 6.0), 5.0, {}, null, real
	)
	assert_true(map != null)
	var lines := map.hedge_lines()
	assert_eq(lines.size(), 1)
	assert_eq(lines[0], PackedVector2Array([Vector2(200.0, 200.0), Vector2(200.0, 500.0)]))
	for k in 11:
		var z := 210.0 + k * 28.0
		assert_eq(map.kind_at_metres(201.0, z), FieldParcels.Kind.BALK, "balk on the hedge")
		assert_eq(map.kind_at_metres(198.0, z), FieldParcels.Kind.BALK, "balk on both sides")
		assert_true(map.kind_at_metres(215.0, z) != FieldParcels.Kind.BALK, "BALK_M wide")
		assert_true(map.kind_at_metres(498.0, z) != FieldParcels.Kind.BALK, "plain edge: no balk")
		assert_true(map.is_real_at_metres(201.0, z))
	var crop := map.kind_at_metres(350.0, 350.0)
	assert_true(crop in FieldParcels.CROP_KINDS)
	assert_eq(crop, map.real_crops[0])


func test_neighbouring_parcels_get_distinct_crops() -> void:
	var polygons: Array = []
	for j in 6:
		for i in 6:
			var ring := _rect_ring(i * 120.0, j * 120.0, (i + 1) * 120.0, (j + 1) * 120.0)
			polygons.append(
				{"rings": _rings(ring), "landuse": &"meadow" if (i + j) % 4 == 0 else &"farmland"}
			)
	var real := RealParcels.from_polygons(polygons, 5)
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var map := FieldParcels.bake(
		_plains_grid(), 1.0, Rect2(-1.0, -1.0, 7.0, 7.0), 5.0, {}, null, real
	)
	for j in 6:
		for i in 6:
			var here := map.kind_at_metres(i * 120.0 + 60.0, j * 120.0 + 60.0)
			assert_eq(here, map.real_crops[j * 6 + i])
			if i < 5:
				assert_true(
					here != map.kind_at_metres(i * 120.0 + 180.0, j * 120.0 + 60.0),
					"x %d %d" % [i, j]
				)
			if j < 5:
				assert_true(
					here != map.kind_at_metres(i * 120.0 + 60.0, j * 120.0 + 180.0),
					"z %d %d" % [i, j]
				)
	assert_eq(map.real_neighbours[7], PackedInt32Array([1, 6, 8, 13]), "edge neighbours only")


func test_real_parcels_are_masked_by_forest_cover_not_by_the_field_outline() -> void:
	# West half forest, east half open land (no FIELD cover at all): the parcel shows on the open
	# half only.
	var n := 120
	var cell := 0.1
	var cells := PackedByteArray()
	cells.resize(n * n)
	for j in n:
		for i in n:
			cells[j * n + i] = LandCover.Kind.FOREST if i < n / 2 else LandCover.Kind.OPEN
	var origin := Vector2(-6.0 + 0.5 * cell, -6.0 + 0.5 * cell)
	var look := CoverLook.make(LandCover.from_cells(cells, n, n, origin, cell))
	var m := MapScale.metres_per_unit
	var ring := _rect_ring(-2.0 * m, -1.0 * m, 2.0 * m, 1.0 * m)
	var real := RealParcels.from_polygons([{"rings": _rings(ring)}])
	var map := FieldParcels.bake(
		_plains_grid(), 1.0, Rect2(-5.0, -5.0, 10.0, 10.0), 5.0, {}, look, real
	)
	assert_true(map != null, "real parcels bake without FIELD cover")
	assert_eq(map.kind_at(-1.0, 0.0), FieldParcels.Kind.NONE, "not under the forest")
	assert_true(map.kind_at(1.0, 0.0) in FieldParcels.CROP_KINDS, "on open land")
	assert_true(look.allows_parcel(1.0, 0.0))
	assert_false(look.allows_parcel(-1.0, 0.0))
	assert_true(look.allows_parcel(50.0, 0.0), "beyond the raster: open land")


func test_terrain_shader_parcel_mask_matches_the_cover_look() -> void:
	var shader := FileAccess.get_file_as_string("res://assets/shaders/terrain.gdshader")
	assert_true(shader.contains("COVER_PARCEL_MASK = %d;" % CoverLook.PARCEL_KINDS_MASK))
	assert_true(shader.contains("(angle_code - 0.5) / 254.0 * PI"), "FieldParcels.code_angle")
	assert_true(shader.contains("PARCEL_EDGE_TEXEL = %.1f;" % RealParcels.EDGE_TEXEL))
	assert_true(shader.contains("PARCEL_EDGE_RANGE_M = %.1f;" % RealParcels.EDGE_RANGE_M))


func test_bake_without_parcels_is_unchanged() -> void:
	var grid := Fixtures.plains_grid(6)
	for c in grid.coords():
		grid.set_terrain(c, Terrain.Type.FIELDS if (c.x + c.y) % 3 != 0 else Terrain.Type.PLAINS)
	var rect := Rect2(-12.0, -12.0, 24.0, 24.0)
	assert_eq(_digest(FieldParcels.bake(grid, 1.0, rect)), DIGEST_GRID_BALANCED)
	var map := ImportedMap.find(Scenario.SUWALKI_MAP_ID)
	var look := CoverLook.make(LandCover.from_imported(map))
	var suwalki := _suwalki_rect(map)
	assert_eq(
		_digest(FieldParcels.bake(grid, 1.0, suwalki, 5.0, {}, look)), DIGEST_SUWALKI_BALANCED
	)
	assert_eq(BattleCover.parcels_for_battle(null, "suwalki_battle", 1), null, "balanced: none")
	VisualScale.apply(VisualScale.TRUE_PRESET)
	assert_eq(_digest(FieldParcels.bake(grid, 1.0, rect)), DIGEST_GRID_TRUE)
	assert_eq(_digest(FieldParcels.bake(grid, 1.0, suwalki, 5.0, {}, look)), DIGEST_SUWALKI_TRUE)
	assert_eq(BattleCover.parcels_for_battle(null, "contact_battle", 1), null, "no polygons")


func test_suwalki_parcels_have_distinct_neighbours_and_real_sizes() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var imported := ImportedMap.find(Scenario.SUWALKI_MAP_ID)
	var t0 := Time.get_ticks_usec()
	var real := BattleCover.parcels_for_battle(null, "suwalki_battle", 1)
	assert_true(real != null)
	var t1 := Time.get_ticks_usec()
	var look := CoverLook.make(LandCover.from_imported(imported))
	var map := FieldParcels.bake(_plains_grid(), 1.0, _suwalki_rect(imported), 5.0, {}, look, real)
	var t2 := Time.get_ticks_usec()
	var same := 0
	var pairs := 0
	for i in real.pieces.size():
		for n in map.real_neighbours[i]:
			if n > i:
				pairs += 1
				if map.real_crops[n] == map.real_crops[i]:
					same += 1
	assert_eq(same, 0, "same-crop neighbour pairs (of %d)" % pairs)
	var settings := RealParcelLook.load_default()
	var osm := PackedFloat64Array()
	var fill := PackedFloat64Array()
	var large := 0
	for i in real.pieces.size():
		var a: float = real.pieces[i]["area_m2"]
		if i < real.osm_count:
			osm.append(a / HA)
			if a > settings.large_parcel_ha * HA * 1.001:
				large += 1
		else:
			fill.append(a / HA)
	osm.sort()
	fill.sort()
	assert_eq(large, 0, "no OSM parcel over %.1f ha" % settings.large_parcel_ha)
	assert_true(fill.size() > osm.size(), "the open land is filled (%d)" % fill.size())
	var all := osm + fill
	all.sort()
	var median := _percentile(all, 0.5)
	assert_true(median >= 1.0 and median <= 10.0, "median %.2f ha" % median)
	# Share of the open land (where a parcel may show) inside the map that a real parcel covers.
	var m := MapScale.metres_per_unit
	var hex_rect := imported.hex_world_rect()
	var open := 0
	var covered := 0
	for j in range(0, int(hex_rect.size.y * m), 50):
		for i in range(0, int(hex_rect.size.x * m), 50):
			var x := hex_rect.position.x * m + i
			var z := hex_rect.position.y * m + j
			if not look.allows_parcel(x / m, z / m):
				continue
			open += 1
			if map.kind_at_metres(x, z) != 0 and map.is_real_at_metres(x, z):
				covered += 1
	var share := float(covered) / maxi(open, 1)
	assert_true(share > 0.8, "open land covered %.2f" % share)
	var hedge_points := 0
	for line in map.hedge_lines():
		hedge_points += line.size()
	print(
		(
			(
				"REAL PARCELS suwalki: %d polygons -> %d OSM parcels (median %.2f ha, p10 %.2f,"
				+ " p90 %.2f, max %.2f) + %d fill parcels (median %.2f, p10 %.2f, p90 %.2f);"
				+ " all median %.2f ha; open land covered %.1f %%; %d neighbour pairs;"
				+ " %d hedge lines (%d points), %d track lines; build %.0f ms, bake %.0f ms"
			)
			% [
				imported.parcel_count(),
				osm.size(),
				_percentile(osm, 0.5),
				_percentile(osm, 0.1),
				_percentile(osm, 0.9),
				osm[osm.size() - 1],
				fill.size(),
				_percentile(fill, 0.5),
				_percentile(fill, 0.1),
				_percentile(fill, 0.9),
				median,
				share * 100.0,
				pairs,
				map.hedge_lines().size(),
				hedge_points,
				real.track_lines.size(),
				(t1 - t0) / 1000.0,
				(t2 - t1) / 1000.0,
			]
		)
	)


## Neighbours never share a crop, so the weakest contrast between touching parcels is the closest
## pair of crop colours: every pair of the `true` look's crops is clearly apart.
func test_true_crop_colours_contrast() -> void:
	var kinds := CropCatalog.load_default().kinds
	var weakest := INF
	for i in kinds.size():
		for j in range(i + 1, kinds.size()):
			var a: Color = kinds[i].colour
			var b: Color = kinds[j].colour
			var d := Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
			weakest = minf(weakest, d)
	assert_true(weakest >= 0.15, "closest crop colours %.3f apart (sRGB)" % weakest)


func test_slanted_edges_are_exact_lines_not_texel_steps() -> void:
	# Two parcels split by a line at about 17 degrees: 1 m on either side of it, along its whole
	# length, the label is the parcel on that side (a 5 m texel step would miss by up to 3.5 m).
	var a := Vector2(100.0, 100.0)
	var b := Vector2(600.0, 250.0)
	var left := PackedVector2Array([Vector2(100.0, 0.0), a, b, Vector2(600.0, 0.0)])
	var right := PackedVector2Array([a, Vector2(100.0, 400.0), Vector2(600.0, 400.0), b])
	var real := RealParcels.from_polygons(
		[{"rings": _rings(left)}, {"rings": _rings(right)}], 3, 1.0, _settings_15()
	)
	var map := FieldParcels.bake(
		_plains_grid(), 1.0, Rect2(-1.0, -1.0, 6.0, 6.0), 5.0, {}, null, real
	)
	assert_true(map.edges != null)
	assert_true(map.real_crops[0] != map.real_crops[1], "neighbours differ")
	var normal := (b - a).normalized().orthogonal()
	var wrong := 0
	for k in 100:
		var p := a.lerp(b, 0.05 + 0.9 * k / 100.0)
		var north := p - normal * 1.0 if normal.y > 0.0 else p + normal * 1.0
		var south := p + normal * 1.0 if normal.y > 0.0 else p - normal * 1.0
		if map.kind_at_metres(north.x, north.y) != map.real_crops[0]:
			wrong += 1
		if map.kind_at_metres(south.x, south.y) != map.real_crops[1]:
			wrong += 1
	assert_eq(wrong, 0, "labels 1 m off the slanted edge")
