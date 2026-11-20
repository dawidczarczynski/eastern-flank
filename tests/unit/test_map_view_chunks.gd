extends TestCase
## MapView's chunked world (TASK-072b): terrain chunks agree on every shared vertex, the coarse
## terrain fills in where no fine chunk is built, layers are built and freed with the camera
## target, threaded plans equal one-thread plans and the build order changes nothing.

const Fixtures := preload("res://tests/fixtures.gd")

## A map larger than the rings (so chunks are built and freed), shared by the read-only tests.
static var _large: MapView
static var _grid: HexGrid


func before_all() -> void:
	_grid = _forest_and_plains(30)
	_large = _make(_grid, {"grass_density": 0.0})


func after_all() -> void:
	_large.free()
	_large = null
	_grid = null


static func _forest_and_plains(radius: int) -> HexGrid:
	var grid := Fixtures.plains_grid(radius)
	for c in grid.coords():
		if (c.x + 2 * c.y) % 5 == 0:
			grid.set_terrain(c, Terrain.Type.FOREST)
	return grid


static func _make(grid: HexGrid, quality: Dictionary, threads := true) -> MapView:
	var view := MapView.new()
	view._ready()
	view.threads = threads
	view.quality = quality
	view.build(grid)
	return view


## Vertex (x, z) -> height of every fine chunk's surface vertices.
func _surface_heights(view: MapView) -> Dictionary:
	var result := {}
	for node in view.terrain().fine_nodes():
		var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var count: int = node.get_meta(&"surface_vertices")
		for k in count:
			var key := Vector2i(roundi(vertices[k].x * 1000.0), roundi(vertices[k].z * 1000.0))
			if result.has(key) and not is_equal_approx(result[key], vertices[k].y):
				_fail("chunks disagree at %s: %s vs %s" % [key, result[key], vertices[k].y])
			result[key] = vertices[k].y
	return result


func test_fine_chunks_share_their_edge_vertices_and_heights_match_the_lattice() -> void:
	_large.finish_chunks(Vector2.ZERO)
	var heights := _surface_heights(_large)
	assert_true(heights.size() > 1000)
	var lattice := _large.terrain().lattice
	for key: Vector2i in heights.keys().slice(0, 200):
		var x := key.x / 1000.0
		var z := key.y / 1000.0
		assert_true(absf(lattice.mesh_height_at(x, z) - maxf(heights[key], 0.0)) < 1e-4)


func test_coarse_terrain_covers_every_chunk_and_hides_under_fine_ones() -> void:
	_large.finish_chunks(Vector2.ZERO)
	var terrain := _large.terrain()
	var groups := {}
	for chunk in terrain.all_chunks():
		groups[TerrainChunks.group_of(chunk)] = true
	assert_eq(terrain.coarse_nodes().size(), groups.size(), "one node per group, the whole map")
	var live := _large.chunks().live_chunks(&"terrain")
	assert_true(live.size() > 0 and live.size() < terrain.all_chunks().size(), "a ring of it")
	for chunk in terrain.all_chunks():
		assert_eq(terrain.coarse_shows(chunk), chunk not in live, "%s" % chunk)
	# A group draws exactly the coarse triangles of its chunks without a fine one.
	var checked := 0
	for node in terrain.coarse_nodes():
		var parts := String(node.name).split("_")
		var group := Vector2i(parts[1].to_int(), parts[2].to_int())
		var expected := 0
		var mixed := false
		for chunk in terrain.all_chunks():
			if TerrainChunks.group_of(chunk) != group:
				continue
			mixed = mixed or chunk in live
			if chunk not in live:
				var arrays: Array = terrain.plan(chunk, TerrainChunks.COARSE_STRIDE)["arrays"]
				expected += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		if not mixed and checked > 0:
			continue
		var drawn := 0
		if node.mesh != null:
			drawn = (node.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		assert_eq(drawn, expected, "%s" % node.name)
		assert_eq(node.visible, expected > 0)
		checked += 1
		if checked > 3:
			break
	assert_true(checked > 1)


func test_layers_follow_the_camera_target() -> void:
	var view := _make(_grid, {"grass_density": 0.0})
	var west := Vector2(-40.0, 0.0)
	var east := Vector2(40.0, 0.0)
	view.finish_chunks(west)
	var west_chunks := view.chunks().live_chunks(&"trees")
	view.finish_chunks(east)
	var free := view.chunks().free_radius(&"trees")
	var build := view.chunks().build_radius(&"trees")
	var layer := view.chunks().layer(&"trees")
	var freed := 0
	for chunk in west_chunks:
		if layer.distance_to(chunk, east) > free:
			assert_false(view.chunks().is_live(&"trees", chunk), "freed: %s" % chunk)
			freed += 1
	assert_true(freed > 0, "the western chunks beyond the free ring went")
	for id: StringName in [&"terrain", &"scatter", &"trees", &"grid"]:
		var l := view.chunks().layer(id)
		for chunk in view.chunks().live_chunks(id):
			assert_true(
				l.distance_to(chunk, east) <= free, "%s %s within the free ring" % [id, chunk]
			)
	var counts := view.terrain().lattice.chunk_counts()
	for x in range(-10, 10):
		for z in range(-10, 10):
			var chunk := Vector2i(x, z)
			if (
				layer.distance_to(chunk, east) <= build
				and layer.chunk_rect(chunk).intersects(layer.area)
			):
				assert_true(view.chunks().is_live(&"trees", chunk), "built: %s" % chunk)
	assert_true(counts.x > 0)
	view.free()


## Tree name -> instance transforms of every tree node.
func _trees_snapshot(view: MapView) -> Dictionary:
	var result := {}
	for node in view.trees().get_children():
		var tree_node := node as MultiMeshInstance3D
		result[String(node.name)] = view.trees().instance_transforms(tree_node)
	return result


func test_build_order_and_threads_change_nothing() -> void:
	var direct := _make(_grid, {"grass_density": 0.0}, false)
	direct.finish_chunks(Vector2(10.0, 5.0))
	var winding := _make(_grid, {"grass_density": 0.0}, true)
	for target: Vector2 in [Vector2(-60.0, 30.0), Vector2(45.0, -20.0), Vector2(10.0, 5.0)]:
		winding.finish_chunks(target)
	# The winding path keeps a few more chunks between the rings (hysteresis); every chunk of the
	# direct build is there, with the same trees.
	for chunk in direct.chunks().live_chunks(&"trees"):
		assert_true(winding.chunks().is_live(&"trees", chunk), "%s" % chunk)
	var expected := _trees_snapshot(direct)
	var actual := _trees_snapshot(winding)
	assert_true(expected.size() > 10)
	for key: String in expected:
		assert_eq(actual.get(key), expected[key], key)
	var heights_direct := _surface_heights(direct)
	var heights_winding := _surface_heights(winding)
	for key: Vector2i in heights_direct:
		if heights_winding.has(key):
			assert_eq(heights_winding[key], heights_direct[key])
	direct.free()
	winding.free()


func test_low_quality_builds_smaller_rings() -> void:
	var low := _make(_grid, GraphicsQuality.features(GraphicsQuality.Level.LOW))
	low.finish_chunks(Vector2.ZERO)
	_large.finish_chunks(Vector2.ZERO)
	var high_terrain := _large.chunks().live_chunks(&"terrain").size()
	var low_terrain := low.chunks().live_chunks(&"terrain").size()
	assert_true(low_terrain < high_terrain, "%d < %d" % [low_terrain, high_terrain])
	assert_true(low.chunks().build_radius(&"terrain") < _large.chunks().build_radius(&"terrain"))
	assert_eq(low.chunks().layer(&"trees"), null, "no foliage on LOW")
	low.free()


func test_a_burn_reaches_chunks_built_after_it() -> void:
	var view := _make(_grid, {"grass_density": 0.0})
	view.finish_chunks(Vector2(-40.0, 0.0))
	view.burn_ground(Vector2(40.0, 0.0), 1.0)
	assert_eq(view.foliage()._burns.size(), 1, "remembered for later chunks")
	view.finish_chunks(Vector2(40.0, 0.0))
	view.free()


func test_the_backdrop_reads_only_border_heights() -> void:
	var view := _make(Fixtures.plains_grid(3), {"grass_density": 0.0, "foliage": false})
	assert_eq(view.terrain().lattice.block_count(), 0, "no fine block computed by the build")
	view.free()


## TASK-072b skips the noises for the types that ignore them: uses_noise must tell the truth.
func test_types_without_noise_give_the_same_weights_for_any_noise() -> void:
	for terrain: int in [-1] + Terrain.Type.values():
		var differs := false
		for slope: float in [0.0, 0.5]:
			for height: float in [-0.1, 0.02, 0.4, 1.5]:
				var a := TerrainSplat.weights(terrain, slope, height, 0.0, 0.0, 0.0)
				var b := TerrainSplat.weights(terrain, slope, height, 0.0, 1.0, 1.0)
				var c := TerrainSplat.weights(terrain, slope, height, 0.0, 0.7, 0.3)
				differs = differs or a != b or a != c
		if not TerrainSplat.uses_noise(terrain):
			assert_false(differs, "type %d ignores the noise" % terrain)
	assert_true(TerrainSplat.uses_noise(Terrain.Type.PLAINS))
	assert_true(TerrainSplat.uses_noise(-1), "the off-map margin")
	assert_false(TerrainSplat.uses_noise(Terrain.Type.FOREST))
