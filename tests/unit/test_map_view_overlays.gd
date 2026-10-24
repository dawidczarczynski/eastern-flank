extends TestCase
## TASK-049: reach outline, outside dim, hover-only fill and the faint fading grid.

const Fixtures := preload("res://tests/fixtures.gd")
const COLOR := Color("#4a7fd0")

var _view: MapView


func _make(grid: HexGrid) -> void:
	_view = MapView.new()
	_view._ready()  # not in a scene tree in tests
	_view.build(grid)


func after_each() -> void:
	_view.free()


func _ring() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in Hex.DIRECTIONS:
		out.append(d)
	return out


func _vertex_count(instance: MeshInstance3D) -> int:
	if instance.mesh == null:
		return 0
	return (instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()


func test_reach_outline_has_one_ribbon_per_boundary_edge() -> void:
	_make(Fixtures.plains_grid(1))
	_view.show_reach(_ring(), COLOR, Vector2i.ZERO)
	var area := _ring()
	area.append(Vector2i.ZERO)
	var edges := OverlayGeometry.boundary_edges(area, _view.hex_size)
	assert_eq(edges.size() / 2, 18)
	var per_edge := (
		OverlayGeometry
		. edge_ribbons(edges.slice(0, 2), MapView.REACH_LINE_WIDTH, MapView.REACH_LINE_SEGMENTS)
		. size()
	)
	assert_eq(_vertex_count(_view._reach_line), 18 * per_edge)


func _visible_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in _view.get_children():
		var instance := child as MeshInstance3D
		if instance != null and instance.visible and instance.mesh != null:
			out.append(instance)
	return out


func test_reach_adds_only_the_outline_and_the_dim() -> void:
	_make(Fixtures.plains_grid(2))
	var before := _visible_meshes()
	_view.show_reach(_ring(), COLOR, Vector2i.ZERO)
	var added: Array[MeshInstance3D] = []
	for instance in _visible_meshes():
		if instance not in before:
			added.append(instance)
	assert_eq(added.size(), 2)
	assert_true(_view._reach_line in added)
	assert_true(_view._dim in added)


func test_dim_covers_land_outside_reach_only() -> void:
	var grid := Fixtures.plains_grid(2)
	grid.set_terrain(Vector2i(2, 0), Terrain.Type.WATER)
	_make(grid)
	_view.show_reach(_ring(), COLOR, Vector2i.ZERO)
	var land := grid.coords().size() - 1
	var patch := OverlayGeometry.hex_patch(Vector2.ZERO, 1.0, MapView.PATCH_SUBDIVISIONS).size()
	assert_true(_view._dim.visible)
	assert_eq(_vertex_count(_view._dim), (land - 7) * patch)
	_view.clear_highlights()
	assert_false(_view._dim.visible)


func test_hover_fill_only_inside_reach() -> void:
	_make(Fixtures.plains_grid(2))
	_view.set_hover(Vector2i(1, 0))
	assert_false(_view._hover_fill.visible, "no selection")
	assert_true(_view._hover_ring.visible)
	_view.show_reach(_ring(), COLOR, Vector2i.ZERO)
	assert_true(_view._hover_fill.visible, "hover moved into reach by selecting")
	var material := _view._hover_fill.material_override as ShaderMaterial
	assert_true(GroundOverlay.color_of(material).is_equal_approx(Color(COLOR, 0.18)))
	_view.set_hover(Vector2i(2, 0))
	assert_false(_view._hover_fill.visible, "outside reach")
	assert_true(_view._hover_ring.visible)
	_view.set_hover(Vector2i(0, 1))
	assert_true(_view._hover_fill.visible)
	_view.clear_highlights()
	assert_false(_view._hover_fill.visible)


func test_grid_mode_cycles_and_alpha_follows_camera() -> void:
	_make(Fixtures.plains_grid(1))
	var material := _view._grid_material
	_view.set_camera_distance(26.5)
	assert_true(_view._grid_lines.visible)
	assert_true(absf(material.albedo_color.a - 0.105) < 0.001)
	_view.show_reach(_ring(), COLOR, Vector2i.ZERO)
	assert_true(absf(material.albedo_color.a - 0.1575) < 0.001)
	_view.cycle_grid_mode()
	assert_false(_view._grid_lines.visible)
	_view.cycle_grid_mode()
	assert_true(_view._grid_lines.visible)


func test_grid_lines_stay_out_of_water() -> void:
	var grid := Fixtures.plains_grid(2)
	grid.set_terrain(Vector2i(0, 0), Terrain.Type.WATER)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.WATER)
	_make(grid)
	var vertices := (
		_view._grid_lines.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	)
	assert_true(vertices.size() > 0)
	for water: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
		var w := Hex.to_world(water, _view.hex_size)
		for v in vertices:
			var d := Vector2(v.x - w.x, v.z - w.z)
			var r := 0.0
			for i in 6:
				var a := deg_to_rad(60.0 * i)
				r = maxf(r, d.dot(Vector2(cos(a), sin(a))))
			assert_true(r / cos(deg_to_rad(30.0)) > 0.999, "vertex inside water tile")


func test_g_key_cycles_grid_mode() -> void:
	_make(Fixtures.plains_grid(1))
	var controller: Node3D = load("res://src/presentation/battle_controller.gd").new()
	controller.set("_map_view", _view)
	controller.set("is_built", true)
	var event := InputEventKey.new()
	event.keycode = KEY_G
	event.pressed = true
	controller.call("_unhandled_input", event)
	assert_false(_view._grid_lines.visible)
	controller.call("_unhandled_input", event)
	assert_true(_view._grid_lines.visible)
	# no simulation is set: reaching the turn/animation gate would raise, so G skips it
	controller.free()


func test_ground_overlays_share_the_depth_pulled_shader() -> void:
	_make(Fixtures.plains_grid(2))
	_view.show_reach(_ring(), COLOR, Vector2i.ZERO)
	for instance: MeshInstance3D in [_view._hover_ring, _view._reach_line]:
		var material := instance.material_override as ShaderMaterial
		assert_eq(material.shader.resource_path, "res://assets/shaders/ground_overlay.gdshader")
		assert_true(material.get_shader_parameter(&"depth_pull") > GrassField.max_clump_height())
		assert_false(material.get_shader_parameter(&"ground_only"))


## Fills cover the tile a unit stands on: a pull would tint the lower half of its model.
func test_ground_fills_are_not_depth_pulled() -> void:
	_make(Fixtures.plains_grid(2))
	_view.show_reach(_ring(), COLOR, Vector2i.ZERO)
	for instance: MeshInstance3D in [_view._hover_fill, _view._dim]:
		var material := instance.material_override as ShaderMaterial
		assert_eq(material.shader.resource_path, "res://assets/shaders/ground_overlay.gdshader")
		assert_eq(material.get_shader_parameter(&"depth_pull"), 0.0)
		assert_true(material.get_shader_parameter(&"ground_only"))
