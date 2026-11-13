extends TestCase
## MapView builds the rows of the terrain mesh on worker threads: same mesh as one thread.

const Fixtures := preload("res://tests/fixtures.gd")


func _terrain_arrays(threads: bool, grid: HexGrid) -> Array:
	var view := MapView.new()
	view._ready()
	view.terrain_threads = threads
	view.quality = {"foliage": false, "grass_density": 0.0, "wind": false}
	view.build(grid)
	var terrain := view._tiles_root.get_node("Terrain") as MeshInstance3D
	var arrays := terrain.mesh.surface_get_arrays(0)
	arrays.append(view._mesh_heights)
	view.free()
	return arrays


func test_threaded_rows_build_the_same_terrain_mesh() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var grid := MapGenerator.generate(8, 6, rng)
	var threaded := _terrain_arrays(true, grid)
	var single := _terrain_arrays(false, grid)
	var vertices: PackedVector3Array = threaded[Mesh.ARRAY_VERTEX]
	assert_true(vertices.size() > 1000, "the mesh has vertices (%d)" % vertices.size())
	assert_eq((threaded[Mesh.ARRAY_NORMAL] as PackedVector3Array).size(), vertices.size())
	assert_eq(threaded.size(), single.size())
	for i in threaded.size():
		assert_true(threaded[i] == single[i], "array %d differs" % i)
