extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

## A small map without foliage for the layer tests, built on first use.
static var _map: MapView
var _view: GroundMarksView


func before_each() -> void:
	_view = GroundMarksView.new()


func after_each() -> void:
	_view.free()


func after_all() -> void:
	if _map != null:
		_map.free()
		_map = null


func _shared_map() -> MapView:
	if _map == null:
		_map = Fixtures.map_view(
			Fixtures.plains_grid(3), {"grass_density": 1.0, "wind": false, "foliage": false}
		)
	return _map


func _tracks(count: int) -> Array[Dictionary]:
	var points := PackedVector3Array()
	for i in count + 1:
		points.append(Vector3(i * 1.7, 0.0, 0.0))
	return GroundMarks.track_segments(points, &"tank")


func test_decals_project_only_onto_the_terrain_layer() -> void:
	_view.setup(8)
	var marks := _tracks(1)
	marks.append_array(GroundMarks.craters(1, Vector3.ZERO, 5, 3, false))
	marks.append(GroundMarks.death_scorch(1, Vector3.ZERO))
	_view.add_marks(marks, false)
	assert_true(_view.decals().size() >= 4, "decals created")
	for decal in _view.decals():
		assert_eq(decal.cull_mask & 1, 0, "not the default layer of units, trees, bushes and rocks")
		assert_true(decal.cull_mask & MapView.TERRAIN_LAYER_MASK != 0, "terrain")
		assert_eq(decal.cull_mask, MapView.TERRAIN_LAYER_MASK | MapView.GRASS_LAYER_MASK)


func test_zero_decals_max_creates_nothing() -> void:
	_view.setup(0)
	_view.add_marks(_tracks(3), false)
	assert_false(_view.is_active())
	assert_eq(_view.decal_count(), 0)
	assert_eq(_view.get_child_count(), 0)


func test_pool_limit_caps_the_decals() -> void:
	_view.setup(2)
	_view.add_marks(_tracks(5), false)
	assert_eq(_view.decal_count(), 2)


func test_decal_box_follows_the_mark() -> void:
	_view.setup(4)
	_view.add_marks(_tracks(1), false)
	var decal := _view.decals()[0]
	assert_true(absf(decal.size.z - 0.42) < 0.0001, "width")
	assert_true(decal.size.x > 1.7, "length plus overlap")
	assert_true(absf(decal.size.y - GroundMarksView.BOX_HEIGHT) < 0.0001)


func test_grass_chunks_sit_on_the_grass_layer() -> void:
	var map := _shared_map()
	map.set_camera_target(Vector2.ZERO)
	map.grass().update(1000)
	assert_true(map.grass().chunk_nodes().size() > 0)
	for node in map.grass().chunk_nodes():
		assert_eq(node.layers, MapView.GRASS_LAYER_MASK)


func test_terrain_and_backdrop_sit_on_the_decal_layer() -> void:
	var map := _shared_map()
	var found := 0
	for node in map.find_children("*", "MeshInstance3D", true, false):
		if node.name == &"Terrain" or node.name == &"Backdrop":
			found += 1
			var mesh := node as MeshInstance3D
			assert_true(mesh.get_layer_mask_value(1), "still on the default layer")
			assert_true(mesh.get_layer_mask_value(MapView.TERRAIN_VISUAL_LAYER), "decal layer")
	assert_eq(found, 2)


func test_growing_tracks_are_hidden_until_revealed() -> void:
	_view.setup(8)
	var decals := _view.add_growing_tracks(_tracks(2))
	assert_eq(decals.size(), 2)
	assert_false(decals[0].visible)
	_view.set_reveal(decals[0], 0.5)
	assert_true(decals[0].visible)
	var half := decals[0].texture_albedo
	_view.set_reveal(decals[0], 0.75)
	assert_true(decals[0].texture_albedo != half, "other step, other texture")
	assert_eq(decals[0].size.x, decals[1].size.x, "the box never changes size")
	_view.set_reveal(decals[0], 1.0)
	assert_eq(decals[0].texture_albedo, GroundMarksView._texture(GroundMarks.KIND_TRACK))
	assert_eq(decals[0].cull_mask, GroundMarksView.CULL_MASK)
	assert_eq(_view.decal_count(), 2)


func test_set_reveal_ignores_evicted_decals() -> void:
	_view.setup(1)
	var decals := _view.add_growing_tracks(_tracks(2))
	_view.set_reveal(decals[0], 1.0)  # evicted by the second one: must not crash
	_view.set_reveal(null, 1.0)
	assert_eq(_view.decal_count(), 1)
