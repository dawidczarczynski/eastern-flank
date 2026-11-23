extends TestCase
## The river ribbon and bridges of a MapView (TASK-108c): the river shader, its flow switch and one
## Bridges node.

const Fixtures := preload("res://tests/fixtures.gd")
const HIGH := GraphicsQuality.Level.HIGH
const LOW := GraphicsQuality.Level.LOW

static var _shared: MapView


static func _features(level: GraphicsQuality.Level) -> Dictionary:
	var features := GraphicsQuality.features(level)
	features["foliage"] = false  # trees are not under test
	return features


static func _grid() -> HexGrid:
	var grid := Fixtures.plains_grid(4)
	for q in range(-3, 3):
		var a := Vector2i(q, 0)
		grid.set_road_links(a, grid.road_links(a) | 1)
		grid.set_road_links(a + Vector2i.RIGHT, grid.road_links(a + Vector2i.RIGHT) | (1 << 3))
	var down := Hex.DIRECTIONS.find(Vector2i(0, 1))
	for r in range(-3, 3):
		var a := Vector2i(0, r)
		var b := Vector2i(0, r + 1)
		grid.set_river_links(a, grid.river_links(a) | (1 << down))
		grid.set_river_links(b, grid.river_links(b) | (1 << ((down + 3) % 6)))
	return grid


func before_all() -> void:
	_shared = Fixtures.map_view(_grid(), _features(HIGH))


func after_all() -> void:
	_shared.free()


func before_each() -> void:
	Fixtures.reset_map_view(_shared)


func _material(view: MapView) -> ShaderMaterial:
	var rivers := view._tiles_root.get_node("Rivers") as MeshInstance3D
	return rivers.mesh.surface_get_material(0) as ShaderMaterial


func test_the_river_uses_the_river_shader_and_flows_on_high() -> void:
	var material := _material(_shared)
	assert_eq(material.shader.resource_path, "res://assets/shaders/river.gdshader")
	assert_true(material.get_shader_parameter(&"flow_speed") > 0.0)
	assert_true(material.render_priority < 0, "drawn below the road")


func test_low_keeps_the_ripples_still() -> void:
	var view := Fixtures.map_view(_grid(), _features(LOW))
	assert_eq(_material(view).get_shader_parameter(&"flow_speed"), 0.0)
	var bridges := view._tiles_root.get_node("Bridges") as MeshInstance3D
	assert_eq(bridges.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	view.free()


func test_one_bridges_node_with_a_shadow_on_high() -> void:
	var count := 0
	for child in _shared._tiles_root.get_children():
		if child.name == &"Bridges":
			count += 1
	assert_eq(count, 1)
	var bridges := _shared._tiles_root.get_node("Bridges") as MeshInstance3D
	assert_eq(bridges.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


func test_a_map_without_links_has_no_river_and_no_bridges() -> void:
	var view := Fixtures.map_view(Fixtures.plains_grid(2), _features(HIGH))
	assert_false(view._tiles_root.has_node("Rivers"))
	assert_false(view._tiles_root.has_node("Bridges"))
	view.free()
