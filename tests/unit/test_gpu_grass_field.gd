extends TestCase
## GpuGrassField, the GPU-placed near grass (TASK-217b, ADR 0033): an instant chunk layer without
## worker plans or instance data, the ring from LookPreset.vegetation(), none on LOW, the CPU grass
## planning nothing under `true` (and as before under `balanced`), and the terrain shader's far
## grass tone (on under `true`, off under `balanced`).

const Fixtures := preload("res://tests/fixtures.gd")

static var _view: MapView
static var _target := Vector2.ZERO


func before_all() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	_view = MapView.new()
	_view._ready()
	_view.quality = GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	_view.build(_grid())
	var c := _view.center()
	_target = Vector2(c.x + 0.3, c.z + 0.2)
	var ground := _view.vegetation_ground_height(_target.x, _target.y)
	_view.set_camera_position(Vector3(_target.x, ground + 0.003, _target.y))
	_view.finish_chunks(_target)
	VisualScale.reset()


func after_all() -> void:
	_view.free()
	_view = null
	VisualScale.reset()
	MapScale.reset()


func after_each() -> void:
	VisualScale.reset()
	MapScale.reset()


static func _grid() -> HexGrid:
	var grid := Fixtures.plains_grid(4)
	for c in grid.coords():
		if Hex.distance(Vector2i.ZERO, c) == 2:
			grid.set_terrain(c, Terrain.Type.FOREST)
	return grid


static func _gap(rect: Rect2, point: Vector2) -> float:
	return point.distance_to(point.clamp(rect.position, rect.end))


func test_grass_chunks_are_instant_and_carry_no_instance_data() -> void:
	var grass := _view.vegetation().grass
	var nodes := grass.nodes()
	assert_true(grass.is_built() and nodes.size() > 0, "%d grass chunks" % nodes.size())
	var shared := nodes[0].multimesh
	assert_false(shared.use_colors or shared.use_custom_data, "no per-instance colour or custom")
	assert_eq(shared.mesh.get_surface_count(), GpuGrassField.MODES, "grass, flower, reed cards")
	for node in nodes:
		assert_true(node.multimesh == shared, "one MultiMesh for every chunk")
		var chunk: Vector2i = node.get_meta(&"chunk")
		var cells := grass.layer().cells(chunk)
		assert_eq(
			node.get_instance_shader_parameter(&"cells"),
			Vector4(cells.position.x, cells.position.y, cells.size.x, cells.size.y)
		)
		assert_true(cells.size.x * cells.size.y <= shared.instance_count)
		assert_eq(node.layers, MapView.GRASS_LAYER_MASK)
	var layer := grass.chunk_layer()
	assert_true(layer.instant and not layer.plan_chunk.is_valid(), "no worker plan")


func test_the_ring_is_the_look_value_and_no_chunk_lies_beyond_it() -> void:
	var values := LookPreset.vegetation()
	var ring_m := float(values["grass_range_m"])
	assert_true(ring_m >= 30.0 and ring_m <= 50.0, "%.0f m ring" % ring_m)
	var grass := _view.vegetation().grass
	assert_eq(grass.ring_m(), ring_m)
	var camera := _view.vegetation().camera_position
	var at := Vector2(camera.x, camera.z)
	for node in grass.nodes():
		var rect := grass.layer().chunk_rect(node.get_meta(&"chunk"))
		var gap := _gap(rect, at)
		assert_true(gap <= grass.ring() + GpuGrassField.CHUNK, "chunk %.3f units off" % gap)
	assert_true(_view.vegetation().chunks.layer(GpuGrassField.LAYER) != null)
	for m in grass.materials():
		assert_eq(float(m.get_shader_parameter(&"grass_reach")), grass.ring())


func test_100_chunks_build_without_worker_plans_within_the_instant_budget() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var source := _view.vegetation().shrubs
	var field := GpuGrassField.new()
	var features := GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	assert_true(field.setup(source, 7, null, [Color.GREEN, Color.YELLOW], null, features))
	var manager := ChunkManager.new()
	manager.register(field.chunk_layer())
	var worst_ms := 0.0
	var area := source.masks.area
	var k := 0
	while manager.built_total() < 100 and k < 400:
		var t := float(k) / 400.0
		manager.update(area.position + area.size * Vector2(fmod(t * 7.0, 1.0), t))
		var started := Time.get_ticks_usec()
		manager.process()
		worst_ms = maxf(worst_ms, (Time.get_ticks_usec() - started) / 1000.0)
		k += 1
	assert_true(manager.built_total() >= 100, "%d chunks built" % manager.built_total())
	assert_eq(float((manager.stats()[GpuGrassField.LAYER] as Dictionary)["plan_ms"]), 0.0)
	assert_true(worst_ms <= 4.5, "worst process() %.2f ms" % worst_ms)
	field.free()


func test_low_quality_builds_no_grass_layer_but_high_does() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var source := _view.vegetation().shrubs
	var low := GpuGrassField.new()
	var low_features := GraphicsQuality.features(GraphicsQuality.Level.LOW)
	assert_false(bool(low_features["gpu_grass"]))
	assert_false(low.setup(source, 7, null, [Color.GREEN, Color.YELLOW], null, low_features))
	assert_false(low.is_built())
	assert_true(low.chunk_layer() == null and low.nodes().is_empty())
	var high := GpuGrassField.new()
	var high_features := GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	assert_true(bool(high_features["gpu_grass"]))
	assert_true(high.setup(source, 7, null, [Color.GREEN, Color.YELLOW], null, high_features))
	low.free()
	high.free()
	# The far tone is the terrain's, on whatever the quality: set_grass_tone has no quality input.
	var ground := ShaderMaterial.new()
	TerrainGround.set_grass_tone(ground)
	assert_true(ground.get_shader_parameter(&"grass_tone_on"), "tone on under true")


func test_the_cpu_grass_plans_nothing_under_true_and_the_terrain_tone_is_off_under_balanced(
) -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	assert_eq(_view.grass().instance_count(), 0, "no CPU grass instance")
	assert_false(_view.grass().is_active())
	assert_eq(_view.grass().plan_chunk(Vector2i(0, 0)), {}, "no CPU plan")
	VisualScale.reset()
	var ground := ShaderMaterial.new()
	TerrainGround.set_grass_tone(ground)
	assert_false(ground.get_shader_parameter(&"grass_tone_on"), "tone off under balanced")
	var view := Fixtures.map_view(_grid(), GraphicsQuality.features(GraphicsQuality.Level.HIGH))
	assert_true(view.vegetation().chunks.layer(GpuGrassField.LAYER) == null, "no GPU layer")
	assert_false(view.vegetation().grass.is_built())
	assert_true(view.grass().is_active(), "the CPU grass as before")
	view.free()


func test_the_terrain_shader_carries_the_tone_uniforms_off_by_default() -> void:
	var text := FileAccess.get_file_as_string("res://assets/shaders/terrain.gdshader")
	assert_true(text.contains("uniform bool grass_tone_on = false;"))
	var material := TerrainGround.material(GraphicsQuality.features(GraphicsQuality.Level.HIGH))
	assert_true(material.get_shader_parameter(&"grass_tone_on") != true, "off until set")


func test_the_materials_carry_the_rules_uniforms() -> void:
	var grass := _view.vegetation().grass
	for m in grass.materials():
		assert_eq(float(m.get_shader_parameter(&"grass_spacing")), grass.rules.spacing)
		assert_eq(float(m.get_shader_parameter(&"spacing")), grass.rules.ground.spacing)
		assert_true(m.get_shader_parameter(&"habitat") != null, "masks bound")
		assert_true(m.get_shader_parameter(&"grass_seed") != null)
		assert_true(grass.rules.spacing > 0.0)
