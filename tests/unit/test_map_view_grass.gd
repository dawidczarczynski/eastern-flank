extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var _view: MapView


func before_each() -> void:
	_view = MapView.new()
	_view._ready()


func after_each() -> void:
	_view.free()


func _build(quality: Dictionary) -> void:
	_view.quality = quality
	_view.build(Fixtures.plains_grid(4))
	_view.set_camera_target(Vector2.ZERO)
	_view.grass().update(1000)


func test_density_zero_creates_no_grass() -> void:
	_build({"grass_density": 0.0, "wind": false})
	assert_eq(_view.grass().instance_count(), 0)
	assert_eq(_view.grass().chunk_nodes().size(), 0)
	assert_false(_view.grass().is_active())
	assert_eq(_view.grass().get_child_count(), 0, "no grass nodes")


func test_full_density_creates_faded_unshadowed_chunks() -> void:
	_build({"grass_density": 1.0, "wind": true})
	var nodes := _view.grass().chunk_nodes()
	assert_true(nodes.size() > 0, "chunk nodes")
	assert_true(_view.grass().instance_count() > 0)
	for node in nodes:
		assert_eq(node.visibility_range_end, 14.0)
		assert_eq(node.visibility_range_end_margin, 3.0)
		assert_eq(node.visibility_range_fade_mode, GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF)
		assert_eq(node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_chunks_are_built_lazily_near_the_camera_target() -> void:
	_view.quality = {"grass_density": 1.0, "wind": true}
	_view.build(Fixtures.plains_grid(4))
	_view.grass().update(1000)
	assert_eq(_view.grass().chunk_nodes().size(), 0, "no target yet")
	_view.set_camera_target(Vector2(-100, -100))
	_view.grass().update(1000)
	assert_eq(_view.grass().chunk_nodes().size(), 0, "target far away")
	_view.set_camera_target(Vector2.ZERO)
	_view.grass().update(1)
	assert_eq(_view.grass().built_chunks(), 1, "at most the per-frame count")


func test_wind_parameters_exist_and_follow_quality() -> void:
	_build({"grass_density": 1.0, "wind": true})
	# The headless dummy renderer keeps no global parameters; check them only on a real one.
	if DisplayServer.get_name() != "headless":
		for param in [&"wind_direction", &"wind_strength", &"wind_speed"]:
			assert_true(
				RenderingServer.global_shader_parameter_get(param) != null, "%s registered" % param
			)
	assert_true(Wind.strength() > 0.0)
	_build({"grass_density": 0.0, "wind": false})
	assert_eq(Wind.strength(), 0.0)


func test_density_is_cut_back_to_a_tiny_budget() -> void:
	var grid := Fixtures.plains_grid(4)
	var field := GrassField.new()
	var budget := 5000
	field.setup(
		grid,
		TerrainSurface.new(grid),
		Rect2(-8, -8, 16, 16),
		1.0,
		func(_p: Vector3) -> Color: return Color.GREEN,
		budget
	)
	assert_true(field.density() < 1.0, "density cut: %s" % field.density())
	assert_true(field.density() > 0.0)
	field.set_target(Vector2.ZERO)
	field.update(1000)
	assert_true(
		field.instance_count() <= budget * 1.1, "within budget: %d" % field.instance_count()
	)
	field.free()


func test_grass_shader_loads_and_the_material_instantiates() -> void:
	var shader := load("res://assets/shaders/grass.gdshader") as Shader
	assert_true(shader != null, "shader loads")
	assert_eq(shader.get_mode(), Shader.MODE_SPATIAL)
	var names: Array[String] = []
	for u: Dictionary in shader.get_shader_uniform_list():
		names.append(u["name"])
	assert_true(names.has("card"), "card uniform")
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"card", ImageTexture.create_from_image(GrassTexture.card(16, 1)))
	assert_true(material.get_shader_parameter(&"card") != null)


func test_card_texture_is_neutral_grey() -> void:
	var image := GrassTexture.card(32, 1)
	for y in 32:
		for x in 32:
			var c := image.get_pixel(x, y)
			if c.a > 0.5:
				assert_true(absf(c.r - c.g) < 0.01 and absf(c.g - c.b) < 0.01, "grey")
				return
