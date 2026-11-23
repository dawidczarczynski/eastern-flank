extends TestCase
## Real tree features (TASK-199a): the OSM single trees, tree rows, orchards and farmyards as
## ImportedMap loads them. tests/fixtures/maps/sample_tree_map.tres is made by
## tools/test_import_map.py --make-fixtures from SYNTHETIC OSM data: five trees, one tree row,
## one orchard and one farmyard with a hole.

const TREE_MAP := "res://tests/fixtures/maps/sample_tree_map.tres"
const PLAIN_MAP := "res://tests/fixtures/maps/sample_map.tres"
const PARCEL_MAP := "res://tests/fixtures/maps/sample_parcel_map.tres"


func _map() -> ImportedMap:
	return load(TREE_MAP) as ImportedMap


func test_the_sample_has_the_four_kinds() -> void:
	var map := _map()
	assert_eq(map.problem(), "")
	assert_true(map.has_tree_features())
	assert_eq(map.tree_point_count(), 5)
	assert_eq(map.tree_row_count(), 1)
	assert_eq(map.orchard_count(), 1)
	assert_eq(map.farmyard_count(), 1)


func test_first_vertex_of_each_kind_in_whole_metres() -> void:
	var map := _map()
	assert_eq(map.tree_point(0), Vector2(698, 344))
	var row := map.tree_row_polyline(0)
	assert_eq(row.size(), 3)
	assert_eq(row[0], Vector2(367, 664))
	var orchard: Array[PackedVector2Array] = map.orchard_polygon(0)
	assert_eq(orchard.size(), 1)
	assert_eq(orchard[0].size(), 4)
	assert_eq(orchard[0][0], Vector2(1007, 202))
	var yard: Array[PackedVector2Array] = map.farmyard_polygon(0)
	assert_eq(yard.size(), 2, "outer ring and hole")
	assert_eq(yard[0][0], Vector2(1018, 591))
	assert_eq(yard[1][0], Vector2(967, 637))


func test_maps_without_the_layer_load_as_before() -> void:
	for path: String in [PLAIN_MAP, PARCEL_MAP]:
		var map := load(path) as ImportedMap
		assert_eq(map.problem(), "", path)
		assert_false(map.has_tree_features(), path)
		assert_eq(map.tree_point_count(), 0, path)
		assert_eq(map.tree_row_count(), 0, path)
		assert_eq(map.orchard_count(), 0, path)
		assert_eq(map.farmyard_count(), 0, path)


func test_problem_reports_mismatched_tree_arrays() -> void:
	var map := _map().duplicate() as ImportedMap
	map.tree_points = map.tree_points.slice(0, map.tree_points.size() - 1)
	assert_true(map.problem().contains("tree"), map.problem())
	map = _map().duplicate() as ImportedMap
	map.tree_row_points = map.tree_row_points.slice(0, map.tree_row_points.size() - 2)
	assert_true(map.problem().contains("tree row"), map.problem())
	map = _map().duplicate() as ImportedMap
	map.tree_row_sizes = PackedInt32Array([1])
	map.tree_row_points = PackedInt32Array([0, 0])
	assert_true(map.problem().contains("tree row"), map.problem())
	map = _map().duplicate() as ImportedMap
	map.orchard_points = map.orchard_points.slice(0, map.orchard_points.size() - 2)
	assert_true(map.problem().contains("orchard"), map.problem())
	map = _map().duplicate() as ImportedMap
	map.farmyard_ring_sizes = PackedInt32Array([4])
	assert_true(map.problem().contains("farmyard"), map.problem())
	map = _map().duplicate() as ImportedMap
	map.farmyard_rings = PackedInt32Array([0])
	assert_true(map.problem().contains("farmyard"), map.problem())
