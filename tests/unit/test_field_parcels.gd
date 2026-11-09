extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

const SHARES := {
	&"wheat": 0.24,
	&"maize": 0.1,
	&"potato": 0.1,
	&"green": 0.16,
	&"stubble": 0.15,
	&"ploughed": 0.16,
	&"meadow": 0.09,
}


func after_each() -> void:
	MapScale.reset()
	LookPreset.reset()


## Hex disc of `terrain` around the origin.
func _disc(radius: int, terrain: Terrain.Type) -> HexGrid:
	var grid := Fixtures.plains_grid(radius)
	for c in grid.coords():
		grid.set_terrain(c, terrain)
	return grid


func _rect(grid: HexGrid) -> Rect2:
	var rect := Rect2(0, 0, 0, 0)
	for c in grid.coords():
		var p := Hex.to_world(c, 1.0)
		rect = rect.expand(Vector2(p.x, p.z))
	return rect.grow(1.0)


func test_kind_is_deterministic() -> void:
	for i in 50:
		var x := i * 37.3 - 700.0
		var z := i * 91.1 + 20.0
		assert_eq(FieldParcels.kind(x, z, SHARES), FieldParcels.kind(x, z, SHARES))


func test_crop_shares_by_area_over_many_regions() -> void:
	var areas := {}
	var total := 0.0
	for bx in range(-20, 20):
		for bz in range(-20, 20):
			for p: Dictionary in FieldParcels.parcels_of_block(bx, bz):
				var rect: Rect2 = p["rect"]
				var k := FieldParcels.crop_of(p["key"], SHARES)
				areas[k] = areas.get(k, 0.0) + rect.get_area()
				total += rect.get_area()
	for k in FieldParcels.CROP_KINDS:
		var share: float = areas.get(k, 0.0) / total
		var wanted: float = SHARES[FieldParcels.CROPS[k]]
		assert_true(
			absf(share - wanted) < 0.07, "%s: %.2f vs %.2f" % [FieldParcels.CROPS[k], share, wanted]
		)


func test_strips_are_wide_and_long_with_one_orientation_per_region() -> void:
	var widths: Array[float] = []
	var lengths: Array[float] = []
	for bx in range(-6, 6):
		for bz in range(-6, 6):
			var along := -1
			for p: Dictionary in FieldParcels.parcels_of_block(bx, bz):
				var rect: Rect2 = p["rect"]
				var is_x: bool = p["along_x"]
				assert_true(along == -1 or along == int(is_x), "one orientation per region")
				along = int(is_x)
				widths.append(minf(rect.size.x, rect.size.y))
				lengths.append(maxf(rect.size.x, rect.size.y))
	widths.sort()
	lengths.sort()
	var median_w := widths[widths.size() / 2]
	var median_l := lengths[lengths.size() / 2]
	assert_true(median_w >= 150.0 and median_w <= 400.0, "median width %.0f" % median_w)
	assert_true(median_l >= 1200.0, "median length %.0f" % median_l)
	assert_true(widths[0] >= 149.0, "narrowest strip %.0f" % widths[0])


func test_parcel_edges_are_straight() -> void:
	# Inside each block the parcels tile it exactly with axis-aligned rectangles.
	for b in [Vector2i(0, 0), Vector2i(-3, 2), Vector2i(5, -1)]:
		var area := 0.0
		for p: Dictionary in FieldParcels.parcels_of_block(b.x, b.y):
			var rect: Rect2 = p["rect"]
			area += rect.get_area()
			var centre := rect.get_center()
			assert_eq(FieldParcels.parcel_at(centre.x, centre.y)["key"], p["key"])
		assert_true(absf(area - FieldParcels.BLOCK_M * FieldParcels.BLOCK_M) < 10.0)


func test_balk_is_a_thin_strip_on_the_parcel_edge() -> void:
	var balk := 0
	var total := 0
	for j in 300:
		for i in 300:
			if FieldParcels.parcel_at(i * 5.0, j * 5.0)["balk"]:
				balk += 1
			total += 1
	var share := balk / float(total)
	assert_true(share > 0.01 and share < 0.12, "balk share %.3f" % share)


func test_no_texture_without_fields() -> void:
	var grid := _disc(3, Terrain.Type.PLAINS)
	assert_true(FieldParcels.bake(grid, 1.0, _rect(grid)) == null)


func test_bake_size_and_pixel_is_kind_at_centre() -> void:
	var grid := _disc(4, Terrain.Type.FIELDS)
	var rect := Rect2(-2.0, -2.0, 4.0, 4.0)  # inside the all-field disc
	var map := FieldParcels.bake(grid, 1.0, rect, 5.0, SHARES)
	var size_m := 4.0 * MapScale.metres_per_unit
	assert_eq(map.size_px(), Vector2i(ceili(size_m / 5.0), ceili(size_m / 5.0)))
	var checked := 0
	for j in range(0, map.size_px().y, 3):
		for i in range(0, map.size_px().x, 3):
			var x := map.origin_m.x + (i + 0.5) * 5.0
			var z := map.origin_m.y + (j + 0.5) * 5.0
			assert_eq(roundi(map.image.get_pixel(i, j).r * 255.0), FieldParcels.kind(x, z, SHARES))
			assert_eq(map.kind_at_metres(x, z), FieldParcels.kind(x, z, SHARES))
			checked += 1
	assert_true(checked > 100)


func test_majority_rule_spills_into_plains_and_skips_minority_fields() -> void:
	# Left half of the map FIELDS, right half PLAINS: parcels are decided as a whole, so the
	# painted area follows parcel rectangles and reaches over the tile border.
	var grid := _disc(5, Terrain.Type.PLAINS)
	for c in grid.coords():
		if Hex.to_world(c, 1.0).x < 0.0:
			grid.set_terrain(c, Terrain.Type.FIELDS)
	var map := FieldParcels.bake(grid, 1.0, _rect(grid), 5.0, SHARES)
	var painted_plains := 0
	var painted_fields := 0
	for j in map.size_px().y:
		for i in map.size_px().x:
			if map.image.get_pixel(i, j).r == 0.0:
				continue
			var p := map.origin_m + Vector2(i + 0.5, j + 0.5) * 5.0
			var c := Hex.from_world(Vector3(p.x, 0, p.y) / MapScale.metres_per_unit, 1.0)
			if grid.has_tile(c) and grid.get_terrain(c) == Terrain.Type.FIELDS:
				painted_fields += 1
			elif grid.has_tile(c):
				painted_plains += 1
	assert_true(painted_fields > 1000, "fields painted: %d" % painted_fields)
	assert_true(painted_plains > 0, "a parcel spills onto plains")
	assert_true(painted_plains < painted_fields, "most of the paint stays on the field half")


func test_forbidden_terrain_is_never_painted() -> void:
	var grid := _disc(5, Terrain.Type.FIELDS)
	var forbidden := {}
	var types := [Terrain.Type.FOREST, Terrain.Type.WATER, Terrain.Type.URBAN, Terrain.Type.MARSH]
	var n := 0
	for c in grid.coords():
		if (c.x + 3 * c.y) % 3 == 0 and c != Vector2i.ZERO:
			grid.set_terrain(c, types[n % 4])
			forbidden[c] = true
			n += 1
	var map := FieldParcels.bake(grid, 1.0, _rect(grid), 5.0, SHARES)
	var checked := 0
	for j in map.size_px().y:
		for i in map.size_px().x:
			var p := map.origin_m + Vector2(i + 0.5, j + 0.5) * 5.0
			var c := Hex.from_world(Vector3(p.x, 0, p.y) / MapScale.metres_per_unit, 1.0)
			if forbidden.has(c):
				checked += 1
				assert_eq(map.image.get_pixel(i, j).r, 0.0)
	assert_true(checked > 1000)


func test_look_shares_sum_to_one() -> void:
	var total := 0.0
	for v in FieldParcels.shares_of(LookPreset.fields()).values():
		total += v
	assert_true(absf(total - 1.0) < 0.001)
