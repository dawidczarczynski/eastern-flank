extends TestCase
## Real field parcels (TASK-215a, ADR 0032): the OSM farmland / meadow / orchard polygons split by
## roads, tracks, hedges and fences, as ImportedMap loads them. tests/fixtures/maps/
## sample_parcel_map.tres is made by tools/test_import_map.py --make-fixtures from SYNTHETIC OSM
## data: the farmland of the sample map cut by a secondary road, a hedge and two tracks into 8.

const PARCEL_MAP := "res://tests/fixtures/maps/sample_parcel_map.tres"
const PLAIN_MAP := "res://tests/fixtures/maps/sample_map.tres"


func _map() -> ImportedMap:
	return load(PARCEL_MAP) as ImportedMap


static func _ring_area(ring: PackedVector2Array) -> float:
	var sum := 0.0
	for k in ring.size():
		var a := ring[k - 1]
		var b := ring[k]
		sum += a.x * b.y - b.x * a.y
	return sum * 0.5


func test_the_sample_has_eight_farmland_parcels() -> void:
	var map := _map()
	assert_eq(map.problem(), "")
	assert_true(map.has_parcels())
	assert_eq(map.parcel_count(), 8)
	for i in map.parcel_count():
		assert_eq(map.parcel_landuse(i), &"farmland")
		assert_eq(map.parcel_polygon(i).size(), 1, "no holes")
		assert_eq(map.parcel_polygon(i)[0].size(), 4, "four corners")


func test_vertices_are_whole_metres_x_east_z_south_of_tile_zero() -> void:
	var ring: PackedVector2Array = _map().parcel_polygon(0)[0]
	assert_eq(
		ring,
		PackedVector2Array(
			[Vector2(1253, 723), Vector2(1152, 730), Vector2(1160, 1032), Vector2(1249, 1030)]
		)
	)
	assert_true(_ring_area(ring) < 0.0, "counter-clockwise seen from above with north up")


func test_parcels_lie_on_the_fields_and_cover_the_farmland() -> void:
	var map := _map()
	var grid := map.to_grid()
	var on_fields := 0
	var on_map := 0
	var total := 0.0
	for i in map.parcel_count():
		var ring: PackedVector2Array = map.parcel_polygon(i)[0]
		total += absf(_ring_area(ring))
		var centre := Vector2.ZERO
		for p in ring:
			centre += p
		centre /= ring.size()
		var world := centre / map.metres_per_world_unit()
		var tile := Hex.from_world(Vector3(world.x, 0.0, world.y), TerrainField.HEX_SIZE)
		if grid.has_tile(tile):
			on_map += 1
			if grid.get_terrain(tile) == Terrain.Type.FIELDS:
				on_fields += 1
	# the farmland reaches past the map's east edge (some centres lie beyond it) and under the
	# village's hexes (one centre on an URBAN hex)
	assert_true(on_map >= 4, "%d parcel centres on the map" % on_map)
	assert_true(on_fields >= on_map - 1, "%d of %d on FIELDS hexes" % [on_fields, on_map])
	# the farmland way is ~456 m x ~611 m = 27.9 ha; roads, tracks and slivers take little of it
	assert_true(total > 240000.0 and total < 280000.0, "parcel area %.0f m2" % total)


func test_edge_kinds_one_per_edge() -> void:
	var map := _map()
	var seen := {}
	for i in map.parcel_count():
		var kinds: Array[PackedByteArray] = map.parcel_edge_kinds(i)
		assert_eq(kinds.size(), map.parcel_polygon(i).size())
		assert_eq(kinds[0].size(), map.parcel_polygon(i)[0].size())
		for kind in kinds[0]:
			seen[kind] = true
	assert_true(seen.has(ImportedMap.PARCEL_EDGE_PLAIN), "plain edges")
	assert_true(seen.has(ImportedMap.PARCEL_EDGE_TRACK), "track edges")
	assert_true(seen.has(ImportedMap.PARCEL_EDGE_HEDGE), "hedge edges")


func test_a_map_without_parcels_loads_as_before() -> void:
	var map := load(PLAIN_MAP) as ImportedMap
	assert_eq(map.problem(), "")
	assert_false(map.has_parcels())
	assert_eq(map.parcel_count(), 0)


func test_problem_reports_malformed_parcels() -> void:
	var map := _map().duplicate() as ImportedMap
	map.parcel_points = map.parcel_points.slice(0, map.parcel_points.size() - 2)
	assert_true(map.problem().contains("parcel"), map.problem())
	map = _map().duplicate() as ImportedMap
	var kinds := map.parcel_edge_codes.duplicate()
	kinds[0] = 7
	map.parcel_edge_codes = kinds
	assert_true(map.problem().contains("edge kind"), map.problem())
	map = _map().duplicate() as ImportedMap
	var landuse := map.parcel_landuse_codes.duplicate()
	landuse[0] = 9
	map.parcel_landuse_codes = landuse
	assert_true(map.problem().contains("landuse"), map.problem())
