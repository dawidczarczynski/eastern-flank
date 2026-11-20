extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var _view: MapView


func before_each() -> void:
	_view = MapView.new()
	_view._ready()


func after_each() -> void:
	LookPreset.reset()
	_view.free()


## Builds the view on a plains map of `radius` without the scatter: trees, bushes and rocks don't
## feed the grass and only slow the build down.
func _build_grass_only(quality: Dictionary, radius := 4) -> void:
	_view.quality = quality.merged({"foliage": false})
	_view.build(Fixtures.plains_grid(radius))


func _build(quality: Dictionary) -> void:
	_build_grass_only(quality)
	_view.finish_chunks(Vector2.ZERO)


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
	_build_grass_only({"grass_density": 1.0, "wind": true})
	_view.chunks().process()
	assert_eq(_view.grass().chunk_nodes().size(), 0, "no target yet")
	_view.finish_chunks(Vector2(-100, -100))
	assert_eq(_view.grass().chunk_nodes().size(), 0, "target far away")
	_view.chunks().threads = false
	_view.chunks().budget_usec = 0
	_view.set_camera_target(Vector2.ZERO)
	_view.chunks().process()
	assert_true(_view.grass().built_chunks() <= 1, "one chunk a frame on a zero budget")
	_view.finish_chunks()
	assert_true(_view.grass().built_chunks() > 1)
	var radius := _view.chunks().build_radius(&"grass")
	assert_true(absf(radius - 20.0) < 0.01, "the grass ring builds 20 units around the target")


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
	field.build_rect(Rect2(-8, -8, 16, 16))
	assert_true(
		field.instance_count() <= budget * 1.1, "within budget: %d" % field.instance_count()
	)
	field.free()


## On a map larger than the grass ring the budget is for what the ring can hold at once, not for
## the whole map (TASK-072b: the 16x map cut the density to 0.06).
func test_density_budget_is_for_the_live_ring_on_a_large_map() -> void:
	var grid := Fixtures.plains_grid(4)
	var budget := 5000
	var whole := GrassField.new()
	var ring := GrassField.new()
	for field: GrassField in [whole, ring]:
		field.setup(
			grid,
			TerrainSurface.new(grid),
			Rect2(-8, -8, 16, 16),
			1.0,
			func(_p: Vector3) -> Color: return Color.GREEN,
			budget,
			null,
			INF if field == whole else 10.0
		)
	assert_true(ring.density() > whole.density(), "%s > %s" % [ring.density(), whole.density()])
	whole.free()
	ring.free()


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


func _meadow_build() -> void:
	_build_grass_only({"grass_density": 1.0, "wind": false}, 8)
	_view.finish_chunks(Vector2.ZERO)


func test_flower_nodes_are_faded_unshadowed_flower_mode_chunks() -> void:
	_meadow_build()
	var nodes := _view.grass().flower_nodes()
	assert_true(nodes.size() > 0, "flower nodes")
	var flowers := 0
	for node in nodes:
		assert_true(node.name.begins_with("Flowers_"))
		assert_eq(node.visibility_range_end, 14.0)
		assert_eq(node.visibility_range_end_margin, 3.0)
		assert_eq(node.visibility_range_fade_mode, GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF)
		assert_eq(node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_eq(node.layers, MapView.GRASS_LAYER_MASK)
		assert_eq(
			(node.material_override as ShaderMaterial).get_shader_parameter(&"flower_mode"), true
		)
		flowers += node.multimesh.instance_count
	var grass := 0
	for node in _view.grass().chunk_nodes():
		grass += node.multimesh.instance_count
	assert_eq(_view.grass().instance_count(), grass + flowers)


func test_current_look_has_no_flower_nodes() -> void:
	LookPreset.apply(&"current")
	_meadow_build()
	assert_eq(_view.grass().flower_nodes().size(), 0)
	assert_true(_view.grass().chunk_nodes().size() > 0)


func test_tall_clump_transform_scales_the_height() -> void:
	var clump := {
		"position": Vector3(1, 0, 2),
		"yaw": 0.7,
		"scale": 1.2,
		"height": 1.5,
	}
	var t := GrassField.clump_transform(clump, Vector3(1, 0, 1))
	assert_true(absf(t.basis.y.length() - 1.2 * 1.5) < 1e-5)
	assert_true(absf(t.basis.x.length() - 1.2) < 1e-5)
	assert_eq(t.origin, Vector3(0, 0, 1))


func test_flower_mode_uniforms_and_card() -> void:
	var shader: Shader = GrassField.SHADER
	var names: Array[String] = []
	for u: Dictionary in shader.get_shader_uniform_list():
		names.append(u["name"])
	assert_true(names.has("flower_mode") and names.has("stem_color"))
	var image := GrassTexture.flower_card(128, 5)
	var blossoms := 0
	var stems := 0
	for y in 128:
		for x in 128:
			var c := image.get_pixel(x, y)
			if c.a > 0.5:
				assert_eq(c.b, 0.0)
				assert_true(c.r >= 0.45 and c.r <= 1.0, "shade %f" % c.r)
				if c.g > 0.5:
					blossoms += 1
					assert_true(y < 128 * 0.4, "blossoms in the top of the card")
				else:
					stems += 1
	assert_true(blossoms > 50 and stems > 100, "blossoms %d stems %d" % [blossoms, stems])


func test_clearing_removes_grass_and_flowers_inside_it() -> void:
	_build({"grass_density": 1.0, "wind": false})
	var before := _view.grass().instance_count()
	var center := Vector2(1.0, 1.0)
	_view.grass().add_clearing(center, 1.0)
	_view.finish_chunks()
	assert_true(_view.grass().instance_count() < before, "clumps inside are gone")
	var nodes := _view.grass().chunk_nodes() + _view.grass().flower_nodes()
	for node in nodes:
		for i in node.multimesh.instance_count:
			var p := node.position + node.multimesh.get_instance_transform(i).origin
			assert_true(Vector2(p.x, p.z).distance_to(center) >= 1.0, "bare ground")


func test_grass_is_settled_once_the_chunks_around_the_target_are_built() -> void:
	_build_grass_only({"grass_density": 1.0, "wind": false})
	assert_false(_view.chunks_settled(), "no target yet")
	_view.set_camera_target(Vector2.ZERO)
	assert_false(_view.chunks_settled())
	_view.finish_chunks()
	assert_true(_view.chunks_settled())


## Chunk name -> instance transforms of every grass node of the view.
func _grass_snapshot(view: MapView) -> Dictionary:
	var result := {}
	for node in view.grass().chunk_nodes():
		var transforms: Array[Transform3D] = []
		for i in node.multimesh.instance_count:
			transforms.append(node.multimesh.get_instance_transform(i))
		result[String(node.name)] = transforms
	return result


## The chunks are planned on worker threads behind the loading screen and in play: same grass as
## a build on one thread.
func test_threaded_chunks_build_the_same_grass_as_one_thread() -> void:
	_view.threads = false
	_build({"grass_density": 1.0, "wind": false})
	var expected := _grass_snapshot(_view)
	var expected_count := _view.grass().instance_count()
	var other := MapView.new()
	other._ready()
	other.quality = {"grass_density": 1.0, "wind": false, "foliage": false}
	other.build(Fixtures.plains_grid(4))
	other.set_camera_target(Vector2.ZERO)
	for i in 20000:
		other.chunks().process()
		if other.chunks_settled():
			break
		OS.delay_msec(1)
	assert_true(other.chunks_settled())
	assert_eq(other.grass().instance_count(), expected_count)
	assert_eq(_grass_snapshot(other), expected)
	other.free()


func test_the_grass_plan_carries_the_multimesh_buffer() -> void:
	_build_grass_only({"grass_density": 1.0, "wind": false})
	var plan := _view.grass().plan_chunk(Vector2i.ZERO)
	var part: Dictionary = plan["grass"]
	var items: Array = part["items"]
	assert_true(items.size() > 0)
	var buffer: PackedFloat32Array = part["buffer"]
	assert_eq(buffer.size(), items.size() * GrassField.STRIDE)
	var origin := Vector3(GrassPlanner.CHUNK_SIZE * 0.5, 0.0, GrassPlanner.CHUNK_SIZE * 0.5)
	var t := GrassField.clump_transform(items[0], origin)
	assert_true(is_equal_approx(buffer[3], t.origin.x), "origin x relative to the chunk centre")
	assert_true(is_equal_approx(buffer[11], t.origin.z))


## A wreck burns the ground while chunks are still being planned: those plans are dropped and the
## chunks planned again, so the clearing applies to them too.
func test_clearing_during_planning_still_clears() -> void:
	_build_grass_only({"grass_density": 1.0, "wind": false})
	_view.set_camera_target(Vector2.ZERO)
	_view.chunks().process()
	_view.grass().add_clearing(Vector2.ZERO, 1.0)
	_view.finish_chunks()
	assert_true(_view.chunks_settled())
	for node in _view.grass().chunk_nodes():
		for i in node.multimesh.instance_count:
			var p := node.position + node.multimesh.get_instance_transform(i).origin
			if Vector2(p.x, p.z).length() < 0.99:
				_fail("a clump at %s stands in the clearing" % p)
				return
