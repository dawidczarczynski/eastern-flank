extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var _view: MapView


func before_each() -> void:
	_view = MapView.new()
	_view._ready()
	_view.build(Fixtures.plains_grid(1))


func after_each() -> void:
	_view.free()


func _mesh(node_name: String) -> ArrayMesh:
	return (_view._tiles_root.get_node(node_name) as MeshInstance3D).mesh as ArrayMesh


func _vertices(node_name: String) -> PackedVector3Array:
	return _mesh(node_name).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _height_at(vertices: PackedVector3Array, x: float, z: float) -> float:
	for v in vertices:
		if absf(v.x - x) < 0.001 and absf(v.z - z) < 0.001:
			return v.y
	return NAN


func test_backdrop_extends_the_playable_terrain_by_the_ring_width() -> void:
	var inner := _mesh("Terrain").get_aabb()
	var outer := _mesh("Backdrop").get_aabb()
	var width := MapView.BACKDROP_WIDTH
	assert_true(absf(inner.position.x - outer.position.x - width) < 0.5, "west")
	assert_true(absf(outer.end.x - inner.end.x - width) < 0.5, "east")
	assert_true(absf(inner.position.z - outer.position.z - width) < 0.5, "north")
	assert_true(absf(outer.end.z - inner.end.z - width) < 0.5, "south")


func test_backdrop_is_coarser_than_the_playable_mesh() -> void:
	var inner := _vertices("Terrain")
	var outer := _vertices("Backdrop")
	assert_true(outer.size() > 0)
	var area_outer := _mesh("Backdrop").get_aabb().size
	var area_inner := _mesh("Terrain").get_aabb().size
	var per_area_outer := outer.size() / (area_outer.x * area_outer.z)
	var per_area_inner := inner.size() / (area_inner.x * area_inner.z)
	assert_true(per_area_outer < per_area_inner * 0.6, "half the resolution")


func test_border_heights_match_the_playable_mesh() -> void:
	var inner := _vertices("Terrain")
	var outer := _vertices("Backdrop")
	var checked := 0
	for k in 5:
		var i := 2 * (k + 1)
		var x := _view._mesh_origin.x + i * _view._mesh_step.x
		var z := _view._mesh_origin.y  # north border row
		var a := _height_at(inner, x, z)
		var b := _height_at(outer, x, z)
		assert_true(not is_nan(a) and not is_nan(b), "vertex at %s on both meshes" % x)
		assert_true(absf(a - b) < 0.001, "height at %s: %s vs %s" % [x, a, b])
		checked += 1
	assert_eq(checked, 5)


func test_backdrop_has_no_cracks_at_the_seam() -> void:
	# Odd playable border vertices lie on the straight line between their even neighbours, so
	# the coarse backdrop edge and the fine playable edge coincide.
	var inner := _vertices("Terrain")
	var step := _view._mesh_step
	var origin := _view._mesh_origin
	for i in [1, 3, 5, 7]:
		var left := _height_at(inner, origin.x + (i - 1) * step.x, origin.y)
		var mid := _height_at(inner, origin.x + i * step.x, origin.y)
		var right := _height_at(inner, origin.x + (i + 1) * step.x, origin.y)
		assert_true(absf(mid - (left + right) * 0.5) < 0.001, "odd border vertex %d" % i)


func test_backdrop_uses_the_terrain_material() -> void:
	var material := _mesh("Backdrop").surface_get_material(0) as StandardMaterial3D
	assert_true(material.albedo_texture != null and material.normal_texture != null)
	assert_true(material.vertex_color_use_as_albedo)


func test_backdrop_colour_is_less_saturated_than_the_seam() -> void:
	var arrays := _mesh("Backdrop").surface_get_arrays(0)
	assert_eq(
		(arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size(),
		(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	)
	var x := 3.0
	var z := 4.0
	var k := TerrainColors.noise_k(x, z)
	var mac := TerrainColors.macro_k(x, z)
	var plains := int(Terrain.Type.PLAINS)
	var land := TerrainColors.color_at(0.5, 1.0, k, plains, true, mac)
	var margin := TerrainColors.color_at(0.5, 1.0, k, -1, false, mac)
	# At the seam: exactly the playable margin colour.
	assert_true(_view._backdrop_color(x, z, 0.5, 1.0, 0.0, 0, 0).is_equal_approx(margin))
	# Beyond the fade distance: the nearest tile's land colour, muted.
	var far: Color = _view._backdrop_color(x, z, 0.5, 1.0, MapView.BACKDROP_FADE + 1.0, 0, 0)
	assert_true(absf(far.s - land.s * MapView.BACKDROP_SATURATION) < 0.001, "saturation")
	assert_true(absf(far.v - land.v * MapView.BACKDROP_VALUE) < 0.001, "value")
	assert_true(far.s < land.s and far.v < land.v)


func test_water_covers_the_backdrop() -> void:
	var water := _view._tiles_root.get_node("Water") as MeshInstance3D
	var plane := Rect2(
		Vector2(water.position.x, water.position.z) - (water.mesh as PlaneMesh).size / 2.0,
		(water.mesh as PlaneMesh).size
	)
	var outer := _mesh("Backdrop").get_aabb()
	assert_true(
		plane.encloses(Rect2(outer.position.x, outer.position.z, outer.size.x, outer.size.z))
	)


func test_ray_over_the_backdrop_picks_no_tile() -> void:
	var outer := _mesh("Backdrop").get_aabb()
	var x := outer.end.x - 3.0
	assert_true(_view.pick_coord(Vector3(x, 20.0, 0.0), Vector3.DOWN) == null)
	# The same ray over the map picks a tile.
	assert_true(_view.pick_coord(Vector3(0.0, 20.0, 0.0), Vector3.DOWN) != null)


func test_hover_is_cleared_when_picking_off_the_map() -> void:
	_view.set_hover(Vector2i.ZERO)
	assert_true(_view._hover_ring.visible)
	var outer := _mesh("Backdrop").get_aabb()
	# The controller's path: pick_coord -> null -> set_hover(null).
	_view.set_hover(_view.pick_coord(Vector3(outer.end.x - 3.0, 20.0, 0.0), Vector3.DOWN))
	assert_false(_view._hover_ring.visible)


func test_visible_ground_height_never_below_water_inside_and_outside() -> void:
	var rect := Rect2(_view._mesh_origin, Vector2(_view._mesh_cells) * _view._mesh_step)
	assert_true(_view.visible_ground_height(0.0, 0.0) >= TerrainSurface.WATER_SURFACE)
	assert_true(
		(
			_view.visible_ground_height(rect.position.x + 1.0, rect.end.y - 1.0)
			>= TerrainSurface.WATER_SURFACE
		)
	)
	var outer := _mesh("Backdrop").get_aabb()
	for x in [outer.position.x + 0.5, outer.end.x - 0.5]:
		assert_true(_view.visible_ground_height(x, 0.0) >= TerrainSurface.WATER_SURFACE)


func test_grid_lines_stay_on_the_playable_rectangle() -> void:
	var rect := Rect2(_view._mesh_origin, Vector2(_view._mesh_cells) * _view._mesh_step)
	for v in _vertices("GridLines"):
		assert_true(rect.has_point(Vector2(v.x, v.z)), "grid line vertex %s" % v)


func test_overlays_stay_on_the_playable_rectangle() -> void:
	var rect := Rect2(_view._mesh_origin, Vector2(_view._mesh_cells) * _view._mesh_step)
	var coords: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 1)]
	_view.show_reach(coords, Color.WHITE, Vector2i.ZERO)
	_view.show_attack_targets(coords)
	_view.show_attack_range(coords)
	_view.set_hover(Vector2i(1, -1))
	for overlay in [
		_view._reach_line,
		_view._dim,
		_view._attack_fill,
		_view._attack_ring,
		_view._range_fill,
		_view._range_line,
		_view._hover_fill,
		_view._hover_ring
	]:
		var instance: MeshInstance3D = overlay
		if instance.mesh == null:
			continue
		var arrays := (instance.mesh as ArrayMesh).surface_get_arrays(0)
		for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			assert_true(rect.has_point(Vector2(v.x, v.z)), "overlay vertex %s" % v)


func test_backdrop_scatter_present_when_enabled() -> void:
	_view.quality = GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	_view.build(Fixtures.plains_grid(1))
	assert_true(_view._tiles_root.has_node("BackdropTrunks"))
	assert_true(_view._tiles_root.has_node("BackdropBushes"))


func test_backdrop_scatter_absent_when_disabled() -> void:
	var quality := GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	quality["backdrop_scatter"] = false
	_view.quality = quality
	_view.build(Fixtures.plains_grid(1))
	assert_false(_view._tiles_root.has_node("BackdropTrunks"))
	assert_false(_view._tiles_root.has_node("BackdropBushes"))
	assert_true(_view._tiles_root.has_node("Trunks"), "playable foliage unaffected")
	assert_true(_view._tiles_root.has_node("Backdrop"), "the ground is always built")


func test_visible_ground_height_follows_the_backdrop_off_the_map() -> void:
	var outer := _mesh("Backdrop").get_aabb()
	var h := _view.visible_ground_height(outer.end.x - 2.0, 0.0)
	assert_true(h >= TerrainSurface.WATER_SURFACE and h < 4.0)
