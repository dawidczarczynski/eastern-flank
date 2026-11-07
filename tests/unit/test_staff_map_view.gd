extends TestCase
## Staff map view and card (TASK-093a, TASK-125): built from a hand-made grid, no scene tree.

const Fixtures := preload("res://tests/fixtures.gd")

var _palette: StaffMapPalette


func before_each() -> void:
	_palette = load(StaffMapPalette.PATH) as StaffMapPalette


func _grid() -> HexGrid:
	var grid := Fixtures.plains_grid(3)
	grid.set_terrain(Vector2i(1, 0), Terrain.Type.FOREST)
	grid.set_terrain(Vector2i(-1, 1), Terrain.Type.MARSH)
	grid.set_terrain(Vector2i(0, -1), Terrain.Type.WATER)
	grid.set_road_links(Vector2i.ZERO, 1)
	grid.set_river_links(Vector2i(2, 0), 1)
	return grid


func test_palette_has_the_reference_colours() -> void:
	assert_true(_palette != null)
	assert_eq(_palette.map_land, Color("#1d211c"))
	assert_eq(_palette.fill(Terrain.Type.PLAINS), _palette.map_land)
	assert_eq(_palette.fill(Terrain.Type.MARSH), _palette.map_land, "marsh = land + hatch")
	assert_eq(_palette.fill(Terrain.Type.FOREST), Color("#22302a"))
	assert_eq(_palette.fill(StaffMapPalette.SEA), Color("#0f1820"))
	assert_eq(_palette.road_t1_widths, PackedFloat32Array([1.3, 1.9, 2.4]))
	assert_eq(_palette.edge(Terrain.Type.PLAINS).a, 0.0)


func test_view_builds_the_layers_and_toggles_the_grid() -> void:
	var view := StaffMapView.new()
	view.build(_grid(), _palette)
	for layer in [
		"Ground",
		"EdgeForest",
		"Shore",
		"RoadT1",
		"RoadT1Casing",
		"RiverMinor",
		"Grid",
		"HoverOutline"
	]:
		assert_true(view.get_node_or_null(layer) != null, layer)
	assert_false(view.grid_visible())
	view.set_grid_visible(true)
	assert_true(view.grid_visible())
	view.free()


func test_zoom_levels_fade_layers_and_widths() -> void:
	var view := StaffMapView.new()
	view.build(_grid(), _palette)
	view.set_zoom_level(0, true)
	assert_eq(view.layer_opacity("RoadT3"), 0.0)
	assert_eq(view.layer_opacity("RoadT1"), 1.0)
	assert_true(absf(view.layer_width("RoadT1") - 1.3) < 0.001)
	assert_true(absf(view.hillshade_gain() - _palette.hillshade_far_gain) < 0.001)
	view.set_zoom_level(2)
	assert_eq(view.layer_opacity("RoadT3"), 0.0, "fades, does not jump")
	view._process(_palette.fade_seconds * 0.5)
	var half := view.layer_opacity("RoadT3")
	assert_true(half > 0.0 and half < 1.0, str(half))
	view._process(_palette.fade_seconds)
	assert_eq(view.layer_opacity("RoadT3"), 1.0)
	assert_true(absf(view.layer_width("RoadT1") - 2.4) < 0.001)
	assert_true(absf(view.layer_width("RoadT1Casing") - 2.4 - _palette.road_t1_casing_px) < 0.001)
	view.free()


func test_view_world_bounds_use_the_unit_and_hover_outlines_a_hex() -> void:
	var view := StaffMapView.new()
	view.build(_grid(), _palette)
	var bounds := view.world_bounds()
	assert_true(bounds.has_point(Vector2.ZERO))
	assert_true(bounds.size.x > 6.0 * StaffMapView.UNIT)
	assert_true(view.has_tile(Vector2i(1, 1)))
	assert_false(view.has_tile(Vector2i(50, 50)))
	view.highlight(Vector2i(1, 1))
	assert_eq(view.hovered(), Vector2i(1, 1))
	assert_true(view.get_node("HoverOutline").visible)
	view.highlight(Vector2i(50, 50))
	assert_false(view.get_node("HoverOutline").visible)
	view.free()


func test_line_mesh_is_a_quad_per_segment() -> void:
	var mesh := StaffMapLines.segments_mesh(
		PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)])
	)
	assert_eq(mesh.get_surface_count(), 1)
	var arrays := mesh.surface_get_arrays(0)
	assert_eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 12)


func test_card_info_names_terrain_elevation_and_flags() -> void:
	var grid := _grid()
	grid.set_elevation_m(Vector2i(1, 0), 143.4)
	var info := StaffMapCard.info(grid, Vector2i(1, 0))
	assert_eq(info["name"], "Forest")
	assert_eq(info["elevation"], "143 m")
	assert_false(info["road"])
	assert_false(info["river"])
	assert_true(StaffMapCard.info(grid, Vector2i.ZERO)["road"])
	assert_true(StaffMapCard.info(grid, Vector2i(2, 0))["river"])
	assert_eq(StaffMapCard.info(grid, Vector2i.ZERO)["hex"], "01·01")
