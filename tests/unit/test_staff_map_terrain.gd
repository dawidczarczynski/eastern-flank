extends TestCase
## Staff map terrain from the graphic layers (TASK-126): one textured surface, no per-hex terrain
## fill or edge lines, the hex grid a thin optional helper, the v0 hex look for maps without
## layers. tests/fixtures/maps/sample_op_map.tres is the importer's synthetic operational sample.

const SAMPLE_OP_PATH := "res://tests/fixtures/maps/sample_op_map.tres"
const SAMPLE_PATH := "res://tests/fixtures/maps/sample_map.tres"
## Per-hex terrain nodes of the v0 look that the layered terrain must not have.
const HEX_TERRAIN_NODES := ["EdgeForest", "EdgeUrban", "Shore"]

var _palette: StaffMapPalette


func before_each() -> void:
	_palette = load(StaffMapPalette.PATH) as StaffMapPalette


func _sample() -> ImportedMap:
	return load(SAMPLE_OP_PATH) as ImportedMap


func _view(map: ImportedMap, grid: HexGrid = null) -> StaffMapView:
	var view := StaffMapView.new()
	view.build(grid if grid != null else map.to_grid(), _palette, map.hex_spacing_m, map)
	return view


func _ground_arrays(view: StaffMapView) -> Array:
	return (view.get_node("Ground") as MeshInstance3D).mesh.surface_get_arrays(0)


func test_layered_map_draws_one_textured_surface_without_hex_fills() -> void:
	var map := _sample()
	var view := _view(map)
	view.build_countries(map)
	assert_true(view.uses_graphic_layers())
	var ground := view.get_node("Ground") as MeshInstance3D
	assert_eq(ground.mesh.get_surface_count(), 1, "one surface")
	var material := ground.material_override as ShaderMaterial
	assert_eq(material.shader, StaffMapTerrain.SHADER)
	for uniform in [&"water_tex", &"cover_tex", &"relief_tex"]:
		assert_true(material.get_shader_parameter(uniform) is ImageTexture, String(uniform))
	assert_true(_ground_arrays(view)[Mesh.ARRAY_COLOR] == null, "no per-hex vertex colours")
	for node_name in HEX_TERRAIN_NODES:
		assert_true(view.get_node_or_null(node_name) == null, "no %s" % node_name)
	for node_name in ["RiverMinor", "RoadT1", "Grid", "HoverOutline", "Countries"]:
		assert_true(view.get_node_or_null(node_name) != null, "%s still drawn" % node_name)
	view.free()


func test_terrain_draw_path_does_not_read_the_hex_terrain() -> void:
	var map := _sample()
	var plain := map.to_grid()
	var changed := map.to_grid()
	for c in changed.coords():
		match changed.get_terrain(c):
			Terrain.Type.PLAINS:
				changed.set_terrain(c, Terrain.Type.FOREST)
			Terrain.Type.FOREST, Terrain.Type.URBAN, Terrain.Type.MARSH:
				changed.set_terrain(c, Terrain.Type.PLAINS)
	var a := _view(map, plain)
	var b := _view(map, changed)
	assert_eq(
		_ground_arrays(a)[Mesh.ARRAY_VERTEX],
		_ground_arrays(b)[Mesh.ARRAY_VERTEX],
		"same surface whatever the land hexes are"
	)
	a.free()
	b.free()


func test_layer_textures_are_built_once() -> void:
	var view := _view(_sample())
	var terrain := view.terrain()
	var water := terrain.water_texture
	view.set_zoom_level(0)
	view.set_view_scale(30.0, 35.0)
	view._advance(1.0)
	assert_true(terrain.water_texture == water)
	assert_eq(terrain.material.get_shader_parameter(&"water_tex"), water)
	view.free()


## The drawn shoreline (0.5 contour of the bilinear water mask) crosses the line between a land
## hex and a water hex away from their shared edge: it follows the real coast, not the hexes.
## On the real theatre (Baltic coast, lagoons, lakes): at the time of writing 110 of 125 crossings
## lie at least one layer pixel (250 m) off the edge.
func test_coast_transition_is_off_the_hex_edges() -> void:
	var map := ImportedMap.find(&"suwalki_theatre")
	var grid := map.to_grid()
	var terrain := StaffMapTerrain.from_map(map, _palette)
	var pixel := map.layer_pixel_world_size()
	var crossings := 0
	var off_edge := 0
	for c in grid.coords():
		if grid.get_terrain(c) == Terrain.Type.WATER:
			continue
		for d in Hex.DIRECTIONS:
			var n: Vector2i = c + d
			if not grid.has_tile(n) or grid.get_terrain(n) != Terrain.Type.WATER:
				continue
			var from := _centre(c)
			var to := _centre(n)
			var previous := terrain.water_at(from)
			for k in range(1, 201):
				var t := k / 200.0
				var value := terrain.water_at(from.lerp(to, t))
				if (previous < 0.5) != (value < 0.5):
					crossings += 1
					# The shared hex edge is the perpendicular bisector: t = 0.5.
					if absf(t - 0.5) * from.distance_to(to) >= pixel:
						off_edge += 1
					break
				previous = value
	assert_true(crossings >= 50, "coast hex edges sampled: %d" % crossings)
	assert_true(
		off_edge * 10 >= crossings * 8,
		"%d of %d coast crossings at least 1 px off the hex edge" % [off_edge, crossings]
	)


func test_shoreline_is_smooth_not_stepped() -> void:
	var view := _view(_sample())
	var terrain := view.terrain()
	var rect := terrain.layer_rect
	# Somewhere the bilinear mask takes an intermediate value: edges are interpolated, not steps.
	var intermediate := false
	for j in 40:
		for i in 60:
			var world := rect.position + rect.size * Vector2((i + 0.37) / 60.0, (j + 0.61) / 40.0)
			var value := terrain.water_at(world)
			if value > 0.2 and value < 0.8:
				intermediate = true
	assert_true(intermediate)
	view.free()


func test_hex_grid_is_a_thin_helper_off_by_default() -> void:
	var view := _view(_sample())
	var grid := view.get_node("Grid") as MeshInstance3D
	assert_false(view.grid_visible(), "hidden by default")
	var material := grid.material_override as ShaderMaterial
	assert_true(float(material.get_shader_parameter(&"width_px")) <= 1.0, "<= 1 px")
	var colour: Color = material.get_shader_parameter(&"line_color")
	assert_true(colour.a <= 0.25, "<= 25 %% alpha: %f" % colour.a)
	assert_true(grid.material_override.render_priority > 0, "above the terrain")
	view.set_grid_visible(true)
	assert_true(view.grid_visible())
	view.set_grid_visible(false)
	assert_false(view.grid_visible())
	view.free()


func test_map_without_layers_falls_back_to_the_hex_look() -> void:
	var tactical := load(SAMPLE_PATH) as ImportedMap
	assert_false(tactical.has_graphic_layers())
	StaffMapView._fallback_warned = false
	var view := _view(tactical)
	assert_false(view.uses_graphic_layers())
	assert_true(view.terrain() == null)
	assert_true(view.get_node_or_null("Shore") != null, "v0 hex edges")
	var material := (view.get_node("Ground") as MeshInstance3D).material_override as ShaderMaterial
	assert_eq(material.shader, StaffMapView.GROUND_SHADER)
	assert_true(StaffMapView._fallback_warned, "warned once")
	view.free()


static func _centre(c: Vector2i) -> Vector2:
	var w := Hex.to_world(c, 1.0)
	return Vector2(w.x, w.z)
