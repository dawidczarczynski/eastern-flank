extends TestCase
## The near terrain LOD (TASK-134, TerrainNear): <= 5 m vertices within 3 units of the camera
## target, the 36 m lattice beyond ~8 units, crack-free ring borders (the near edge lies on the
## fine edge), the fine mesh leaves out exactly the near blocks, the drawn surface matches the core
## tile heights at tile centres, and the layer exists only for a close camera on HIGH quality.

const Fixtures := preload("res://tests/fixtures.gd")
## 1 mm and 0.1 m in world units.
const MM := 0.001 / MapScale.DEFAULT_METRES_PER_UNIT
const TENTH_M := 0.1 / MapScale.DEFAULT_METRES_PER_UNIT

static var _view: MapView
static var _grid: HexGrid
static var _target := Vector2.ZERO


func before_all() -> void:
	_grid = _hills(9)
	_view = MapView.new()
	_view._ready()
	_view.quality = {"grass_density": 0.0, "foliage": false}
	_view.build(_grid)
	var c := _view.center()
	_target = Vector2(c.x + 0.37, c.z - 0.21)
	_view.set_camera_distance(1.2)
	_view.finish_chunks(_target)


func after_all() -> void:
	_view.free()
	_view = null
	_grid = null


## Rolling authored elevation (imported-map style), a forest stripe for the splat.
static func _hills(radius: int) -> HexGrid:
	var grid := Fixtures.plains_grid(radius)
	grid.authored_elevation = true
	for c in grid.coords():
		grid.set_elevation(c, 0.5 + 0.3 * sin(c.x * 0.9) + 0.25 * cos(c.y * 1.3 + c.x * 0.4))
		if (c.x + 2 * c.y) % 5 == 0:
			grid.set_terrain(c, Terrain.Type.FOREST)
	return grid


func _near() -> TerrainNear:
	return _view.terrain_near()


func test_near_vertices_are_at_most_5_m_apart_within_3_units_of_the_target() -> void:
	assert_true(TerrainNear.STEP <= MapScale.to_units(5.0), "%f" % TerrainNear.STEP)
	var built := _near().built_chunks()
	assert_true(built.size() > 20, "%d near chunks" % built.size())
	var layer := _view.chunks().layer(TerrainNear.LAYER)
	for k in 64:
		var angle := k * TAU / 64.0
		for r: float in [0.0, 1.0, 2.0, 2.99]:
			var p := _target + Vector2(cos(angle), sin(angle)) * r
			var chunk := layer.chunk_at(p.x, p.y)
			assert_true(chunk in built, "near chunk at %s (r %.2f)" % [p, r])
	# The vertex spacing of a built near mesh.
	var vertices: PackedVector3Array = _near().nodes()[0].mesh.surface_get_arrays(0)[
		Mesh.ARRAY_VERTEX
	]
	assert_true(absf(vertices[1].x - vertices[0].x - TerrainNear.STEP) < 1e-5)


func test_beyond_8_units_the_terrain_is_the_36_m_lattice() -> void:
	assert_true(absf(MapScale.to_units(36.0) - TerrainLattice.STEP) < MapScale.to_units(1.0))
	var layer := _view.chunks().layer(TerrainNear.LAYER)
	for chunk in _near().built_chunks():
		assert_true(layer.distance_to(chunk, _target) < 8.0, "%s" % chunk)
	var far := 0
	for node in _view.terrain().fine_nodes():
		if node.visible:
			far += 1
	assert_true(far > 0, "fine chunks around the near ring")


## Ring border: an edge without a built near neighbour lies on the fine mesh's edge (its heights
## are the lattice edge interpolated); an edge with one equals the neighbour's edge.
func test_ring_borders_match_the_coarser_edge_within_a_millimetre() -> void:
	var near := _near()
	var lattice := _view.terrain().lattice
	var checked_fine := 0
	var checked_raw := 0
	var row := TerrainNear.CELLS + 1
	for chunk in near.built_chunks():
		var vertices: PackedVector3Array = _vertices_of(chunk)
		for e in 4:
			var neighbour := chunk + TerrainNear.NEIGHBOURS[e]
			var raw := near.edge_is_raw(chunk, e)
			assert_eq(raw, neighbour in near.built_chunks(), "%s edge %d" % [chunk, e])
			for s in row:
				var k := _edge_vertex(e, s)
				var v := vertices[k]
				if raw:
					var other := _vertices_of(neighbour)[_edge_vertex(e ^ 1, s)]
					assert_true(absf(other.y - v.y) < MM, "shared edge %s/%d" % [chunk, e])
					checked_raw += 1
				else:
					var fine := _fine_edge_height(lattice, v.x, v.z)
					assert_true(absf(fine - v.y) <= MM, "%s: %f vs %f" % [v, v.y, fine])
					checked_fine += 1
	assert_true(checked_fine > 100 and checked_raw > 100, "%d %d" % [checked_fine, checked_raw])


## The fine mesh height on a lattice cell edge (linear between its two lattice vertices).
func _fine_edge_height(lattice: TerrainLattice, x: float, z: float) -> float:
	var fx := (x - lattice.origin.x) / TerrainLattice.STEP
	var fz := (z - lattice.origin.y) / TerrainLattice.STEP
	var i := floori(fx + 1e-4)
	var j := floori(fz + 1e-4)
	var u := fx - i
	var v := fz - j
	if absf(u) < 1e-4:
		return lerpf(lattice.height(i, j), lattice.height(i, j + 1), v)
	return lerpf(lattice.height(i, j), lattice.height(i + 1, j), u)


func _edge_vertex(edge: int, s: int) -> int:
	var n := TerrainNear.CELLS
	var row := n + 1
	match edge:
		0:
			return s
		1:
			return n * row + s
		2:
			return s * row
	return s * row + n


func _vertices_of(chunk: Vector2i) -> PackedVector3Array:
	for node in _near().nodes():
		if String(node.name) == "%s_%d_%d" % [TerrainNear.NODE, chunk.x, chunk.y]:
			return node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return PackedVector3Array()


## No overlap and no gap: a fine chunk draws every cell except those under built near chunks.
func test_fine_chunks_leave_out_exactly_the_near_blocks() -> void:
	var near := _near()
	var built := {}
	for chunk in near.built_chunks():
		built[chunk] = true
	var layer := _view.chunks().layer(TerrainNear.LAYER)
	var holed := 0
	for node in _view.terrain().fine_nodes():
		if node.mesh == null:
			continue
		var arrays := node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var count: int = node.get_meta(&"surface_vertices")
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var surface := 0
		var covered := 0
		for t in range(0, indices.size(), 3):
			if indices[t] >= count or indices[t + 1] >= count or indices[t + 2] >= count:
				continue
			surface += 1
			var centroid := (
				(vertices[indices[t]] + vertices[indices[t + 1]] + vertices[indices[t + 2]]) / 3.0
			)
			if built.has(layer.chunk_at(centroid.x, centroid.z)):
				covered += 1
		assert_eq(covered, 0, "%s draws under a near chunk" % node.name)
		var parts := String(node.name).split("_")
		var chunk := Vector2i(parts[1].to_int(), parts[2].to_int())
		var per := TerrainLattice.CELLS_PER_CHUNK
		var lattice := _view.terrain().lattice
		var cells := (
			mini(per, lattice.cells.x - chunk.x * per) * mini(per, lattice.cells.y - chunk.y * per)
		)
		var block_cells := TerrainChunks.BLOCK_CELLS * TerrainChunks.BLOCK_CELLS
		var holes := _view.terrain().holes(chunk).size()
		assert_eq(surface, 2 * (cells - holes * block_cells), "%s" % node.name)
		if holes > 0:
			holed += 1
	assert_true(holed > 0)


func test_the_drawn_surface_meets_the_tile_heights_at_tile_centres() -> void:
	var checked := 0
	for c in _grid.coords():
		var centre := Hex.to_world(c, _view.hex_size)
		if Vector2(centre.x, centre.z).distance_to(_target) > 3.0:
			continue
		var drawn := _near().drawn_height_at(centre.x, centre.z)
		assert_false(is_nan(drawn), "near mesh under %s" % c)
		assert_true(
			absf(drawn - _grid.elevation(c)) <= TENTH_M,
			"%s: drawn %f vs tile %f" % [c, drawn, _grid.elevation(c)]
		)
		var unit_y := _view.surface().ground_height(centre.x, centre.z)
		assert_true(absf(unit_y - drawn) <= TENTH_M, "a unit at %s touches the ground" % c)
		checked += 1
	assert_true(checked >= 8, "%d tile centres" % checked)


func test_moving_away_frees_the_near_chunks_and_fills_the_holes() -> void:
	var view := MapView.new()
	view._ready()
	view.quality = {"grass_density": 0.0, "foliage": false}
	view.build(_grid)
	view.set_camera_distance(1.2)
	var c := view.center()
	view.finish_chunks(Vector2(c.x - 4.0, c.z))
	var first := view.terrain_near().built_chunks().size()
	assert_true(first > 0)
	view.finish_chunks(Vector2(c.x + 5.0, c.z + 1.0))
	var layer := view.chunks().layer(TerrainNear.LAYER)
	for chunk in view.terrain_near().built_chunks():
		assert_true(
			(
				layer.distance_to(chunk, Vector2(c.x + 5.0, c.z + 1.0))
				<= view.chunks().free_radius(TerrainNear.LAYER)
			)
		)
	# Every hole belongs to a built near chunk, and every near chunk has its hole.
	var holes := 0
	for chunk in view.terrain().all_chunks():
		holes += view.terrain().holes(chunk).size()
	assert_eq(holes, view.terrain_near().built_chunks().size())
	view.set_camera_distance(CameraRig.DEFAULT_DISTANCE)
	view.finish_chunks()
	assert_eq(view.terrain_near().built_chunks().size(), 0, "far camera: no near chunks")
	holes = 0
	for chunk in view.terrain().all_chunks():
		holes += view.terrain().holes(chunk).size()
	assert_eq(holes, 0, "the fine chunks are whole again")
	view.free()


func test_plans_are_pure() -> void:
	var chunk := _near().built_chunks()[0]
	var a: Dictionary = _near().plan(chunk)
	var b: Dictionary = _near().plan(chunk)
	assert_eq(a["arrays"][Mesh.ARRAY_VERTEX], b["arrays"][Mesh.ARRAY_VERTEX])
	assert_eq(a["arrays"][Mesh.ARRAY_COLOR], b["arrays"][Mesh.ARRAY_COLOR])


func test_low_quality_keeps_the_single_lattice_mesh() -> void:
	var quality := GraphicsQuality.features(GraphicsQuality.Level.LOW)
	assert_false(quality["terrain_lod"])
	assert_true(GraphicsQuality.features(GraphicsQuality.Level.HIGH)["terrain_lod"])
	var view := MapView.new()
	view._ready()
	view.quality = quality
	view.build(Fixtures.plains_grid(3))
	view.set_camera_distance(1.2)
	view.finish_chunks(Vector2.ZERO)
	assert_eq(view.terrain_near(), null)
	assert_eq(view.chunks().layer(TerrainNear.LAYER), null)
	view.free()


func test_the_layer_follows_the_camera_distance_with_hysteresis() -> void:
	assert_true(TerrainNear.wanted(TerrainNear.ENABLE_DISTANCE, false))
	assert_false(TerrainNear.wanted(TerrainNear.ENABLE_DISTANCE + 0.5, false))
	assert_true(TerrainNear.wanted(TerrainNear.ENABLE_DISTANCE + 0.5, true))
	assert_false(TerrainNear.wanted(TerrainNear.DISABLE_DISTANCE + 0.1, true))
	assert_true(TerrainNear.ENABLE_DISTANCE >= 7.0, "on at the default minimum distance")
	assert_true(TerrainNear.ENABLE_DISTANCE < CameraRig.DEFAULT_DISTANCE, "off at the default")
