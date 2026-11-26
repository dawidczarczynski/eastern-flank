extends TestCase
## ShrubField, the GPU-placed shrub layers (TASK-217a, ADR 0033): instant chunk layers without
## worker plans or instance data, LOD ranges from LookPreset.vegetation(), the LOW quality's
## 150 m reach, nothing under `balanced`, and the CPU shrub sources off under `true`.

const Fixtures := preload("res://tests/fixtures.gd")

## A small map (forest ring, fields, plains) at the `true` preset, camera low over its centre.
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
	_view.set_camera_position(
		Vector3(_target.x, ground, _target.y) + CameraMath.camera_offset(0.4, 1.2)
	)
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
		var d := Hex.distance(Vector2i.ZERO, c)
		if d == 2:
			grid.set_terrain(c, Terrain.Type.FOREST)
		elif d == 4 and c.x > 0:
			grid.set_terrain(c, Terrain.Type.FIELDS)
	return grid


func test_shrub_chunks_are_instant_and_carry_no_instance_data() -> void:
	var shrubs := _view.vegetation().shrubs
	var far := shrubs.impostor_nodes()
	var near := shrubs.near_nodes()
	assert_true(far.size() > 0 and near.size() > 0, "%d / %d chunks" % [far.size(), near.size()])
	var shared := far[0].multimesh
	assert_false(shared.use_colors or shared.use_custom_data, "no per-instance colour or custom")
	for node in far:
		assert_true(node.multimesh == shared, "one MultiMesh for every impostor chunk")
	var layers := shrubs.layers()
	for k in 2:
		var layer: GpuVegetationLayer = layers[k]
		for node in near if k == 0 else far:
			var chunk: Vector2i = node.get_meta(&"chunk")
			var cells := layer.cells(chunk)
			assert_eq(
				node.get_instance_shader_parameter(&"cells"),
				Vector4(cells.position.x, cells.position.y, cells.size.x, cells.size.y)
			)
			assert_true(cells.size.x * cells.size.y <= node.multimesh.instance_count)
	# A near chunk's identity instances are shared too (one MultiMesh per model variant).
	var near_multi := near[0].multimesh
	assert_false(near_multi.use_colors or near_multi.use_custom_data)
	for layer: ChunkLayer in [shrubs.near_layer(), shrubs.impostor_layer()]:
		assert_true(
			layer.instant and not layer.plan_chunk.is_valid(), "%s: no worker plan" % layer.id
		)
	# Some shrubs stand in the built chunks (the reference the shaders follow).
	var count := 0
	for node in far:
		count += shrubs.chunk_shrubs(layers[1], node.get_meta(&"chunk")).size()
	assert_true(count > 100, "%d shrubs drawn by the impostor chunks" % count)


func test_200_chunks_build_without_worker_plans_within_the_instant_budget() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var source := _view.vegetation().shrubs
	var field := ShrubField.new()
	field.setup_with(
		source.masks, _view._lattice, 7, null, GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	)
	var manager := ChunkManager.new()
	manager.register(field.near_layer())
	manager.register(field.impostor_layer())
	var worst_ms := 0.0
	var worst_scan_ms := 0.0
	var area := source.masks.area
	var k := 0
	while manager.built_total() < 200 and k < 400:
		var t := float(k) / 400.0
		var target := area.position + area.size * Vector2(fmod(t * 7.0, 1.0), t)
		# The scan builds the nearest new chunks within the same budget as process().
		var started := Time.get_ticks_usec()
		manager.update(target)
		worst_scan_ms = maxf(worst_scan_ms, (Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		manager.process()
		worst_ms = maxf(worst_ms, (Time.get_ticks_usec() - started) / 1000.0)
		k += 1
	var stats := manager.stats()
	print(
		(
			"Shrub chunks: %d built, worst process() %.2f ms, worst scan %.2f ms"
			% [manager.built_total(), worst_ms, worst_scan_ms]
		)
	)
	assert_true(manager.built_total() >= 200, "%d chunks built" % manager.built_total())
	for id: StringName in [ShrubField.NEAR_LAYER, ShrubField.IMPOSTOR_LAYER]:
		assert_eq(float((stats[id] as Dictionary)["plan_ms"]), 0.0, "%s: no worker plan" % id)
	# The instant budget (4 ms), plus at most the one chunk that always runs.
	assert_true(worst_ms <= 4.5, "worst process() %.2f ms" % worst_ms)
	field.free()


func test_lod_ranges_are_look_values() -> void:
	var values := LookPreset.vegetation()
	assert_eq(float(values["shrub_mesh_range_m"]), 60.0)
	assert_eq(float(values["shrub_impostor_range_m"]), 600.0)
	var shrubs := _view.vegetation().shrubs
	assert_eq(shrubs.ranges_m(), Vector2(60.0, 600.0), "mesh to 60 m, impostors to 600 m")
	var near := shrubs.near_layer()
	var far := shrubs.impostor_layer()
	assert_eq(near.reach_m, 60.0)
	assert_eq(far.reach_m, 600.0)
	var manager := _view.vegetation().chunks
	assert_true(
		is_equal_approx(manager.build_radius(far.id), MapScale.to_units(600.0) * 1.5),
		"the impostor ring follows the range"
	)
	assert_true(manager.build_radius(near.id) >= MapScale.to_units(60.0 * 1.08))
	var impostor := shrubs.impostor_nodes()[0]
	var m := impostor.material_override as ShaderMaterial
	assert_true(
		is_equal_approx(float(m.get_shader_parameter(&"mesh_reach")), MapScale.to_units(60.0))
	)
	assert_true(
		is_equal_approx(float(m.get_shader_parameter(&"impostor_reach")), MapScale.to_units(600.0))
	)
	# Nothing beyond: the nodes are culled past the impostor band.
	assert_true(impostor.visibility_range_end < MapScale.to_units(600.0 * 1.08) + 4.0)


func test_low_quality_keeps_shrubs_within_150_m() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var source := _view.vegetation().shrubs
	var counts := {}
	for level: GraphicsQuality.Level in [GraphicsQuality.Level.LOW, GraphicsQuality.Level.HIGH]:
		var features := GraphicsQuality.features(level)
		var field := ShrubField.new()
		field.setup_with(source.masks, _view._lattice, 7, null, features)
		var ranges := field.ranges_m()
		var layer := field.impostor_layer()
		if level == GraphicsQuality.Level.LOW:
			assert_true(ranges.y <= 150.0, "LOW shrubs to %.0f m" % ranges.y)
			assert_true(layer.reach_m <= 150.0, "LOW ring %.0f m" % layer.reach_m)
		var gpu: GpuVegetationLayer = field.layers()[1]
		gpu.build_chunk(Vector2i(0, 0))
		counts[level] = gpu.node(Vector2i(0, 0)).multimesh.instance_count
		field.free()
	assert_true(counts[GraphicsQuality.Level.LOW] <= counts[GraphicsQuality.Level.HIGH])
	assert_eq(float(GraphicsQuality.features(GraphicsQuality.Level.LOW)["shrub_range_m"]), 150.0)


func test_balanced_builds_no_shrub_layer() -> void:
	var view := Fixtures.map_view(_grid(), GraphicsQuality.features(GraphicsQuality.Level.HIGH))
	var vegetation := view.vegetation()
	assert_true(vegetation.chunks.layer(ShrubField.IMPOSTOR_LAYER) == null, "no impostor layer")
	assert_true(vegetation.chunks.layer(ShrubField.NEAR_LAYER) == null, "no near layer")
	assert_eq(vegetation.shrubs.get_child_count(), 0, "no shrub node")
	assert_false(view.foliage().gpu_shrubs, "the CPU shrubs stay")
	var bushes := 0
	for node in view.foliage().scatter_nodes():
		if node.name.begins_with("Bushes"):
			bushes += node.multimesh.instance_count
	assert_true(bushes > 0, "%d CPU bushes under balanced" % bushes)
	view.free()


## Under `true` the old CPU shrub sources plan nothing and draw nothing (no shrub is drawn twice):
## ScatterChunks' bushes, ScatterPlanner's edge shrubs and thickets, the hedge and riparian
## shrubs. The same chunks plan shrubs with the switch off.
func test_the_cpu_shrub_sources_are_off_under_true() -> void:
	var foliage := _view.foliage()
	assert_true(foliage.gpu_shrubs, "the GPU shrubs replace the CPU ones")
	for node in foliage.scatter_nodes():
		if node.name.begins_with("Bushes") or node.name.begins_with("BackdropBushes"):
			assert_eq(node.multimesh.instance_count, 0, "%s draws no bush" % node.name)
	var on := 0
	var off := 0
	for chunk: Vector2i in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		foliage.gpu_shrubs = true
		var plan := foliage._plan_source(chunk)
		foliage.gpu_shrubs = false
		var before := foliage._plan_source(chunk)
		foliage.gpu_shrubs = true
		for part: String in ["map", "backdrop"]:
			for key in FoliageChunks.SHRUB_KEYS:
				on += ((plan[part] as Dictionary).get(key, []) as Array).size()
				off += ((before[part] as Dictionary).get(key, []) as Array).size()
			assert_eq(
				(plan[part]["trees"] as Array).size(),
				(before[part]["trees"] as Array).size(),
				"the trees stay"
			)
	assert_eq(on, 0, "no CPU-planned shrub under true")
	assert_true(off > 0, "%d CPU shrubs with the switch off" % off)
