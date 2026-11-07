extends TestCase
## Staff map view and card (TASK-093a): built from a hand-made grid, no scene tree.

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


func test_palette_resource_loads_and_plains_are_not_drawn() -> void:
	assert_true(_palette != null)
	assert_eq(_palette.fill(Terrain.Type.PLAINS).a, 0.0)
	assert_true(_palette.fill(Terrain.Type.FOREST).a > 0.0)


func test_view_builds_the_layers_and_toggles_the_grid() -> void:
	var view := StaffMapView.new()
	view.build(_grid(), _palette)
	for layer in ["Paper", "Hillshade", "MarshHatch", "Grid", "HoverOutline"]:
		assert_true(view.get_node_or_null(layer) != null, layer)
	assert_false(view.grid_visible())
	view.set_grid_visible(true)
	assert_true(view.grid_visible())
	view.free()


func test_view_world_bounds_and_hex_lookup_use_the_unit() -> void:
	var view := StaffMapView.new()
	view.build(_grid(), _palette)
	var bounds := view.world_bounds()
	assert_true(bounds.has_point(Vector2.ZERO))
	var c := Vector2i(1, 1)
	var w := Hex.to_world(c, 1.0)
	assert_eq(view.hex_at_world(Vector2(w.x, w.z) * StaffMapView.UNIT), c)
	assert_true(view.has_tile(c))
	assert_false(view.has_tile(Vector2i(50, 50)))
	view.free()


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
