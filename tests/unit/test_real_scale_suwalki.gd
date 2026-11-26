extends TestCase
## Real-scale vegetation on the Suwalki map (TASK-135, follow-up of TASK-134 / ADR 0025): the
## grass, the ground cover and the full trees within the near-terrain reach (3 units) stand on the
## drawn near surface (TerrainNear.drawn_height_at), not on the 36 m lattice – mean and max offset
## at most 0.1 m.

const TENTH_M := 0.1 / MapScale.DEFAULT_METRES_PER_UNIT
const NEAR_REACH := 3.0

static var _view: MapView
static var _target := Vector2.ZERO


func before_all() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grid := ImportedMap.find(Scenario.SUWALKI_MAP_ID).to_grid()
	_view = MapView.new()
	_view._ready()
	_view.quality = GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	_view.build(grid)
	# The forest tile nearest the map centre with forest all around it.
	var centre := _view.center()
	var best := INF
	for c in grid.coords():
		if grid.get_terrain(c) != Terrain.Type.FOREST:
			continue
		var w := Hex.to_world(c, _view.hex_size)
		var d := Vector2(w.x - centre.x, w.z - centre.z).length()
		if d < best:
			best = d
			_target = Vector2(w.x + 0.4, w.z - 0.3)
	var ground := _view.vegetation_ground_height(_target.x, _target.y)
	_view.set_camera_distance(1.2)
	_view.set_camera_position(
		Vector3(_target.x, ground, _target.y) + CameraMath.camera_offset(0.7, 1.2)
	)
	_view.finish_chunks(_target)


func after_all() -> void:
	_view.free()
	_view = null
	VisualScale.reset()


## Offsets (world units) of base points within the near reach to the drawn near surface.
func _offsets(points: PackedVector3Array, lift: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for p in points:
		if Vector2(p.x, p.z).distance_to(_target) > NEAR_REACH:
			continue
		var drawn := _view.terrain_near().drawn_height_at(p.x, p.z)
		if is_nan(drawn):
			continue
		result.append(absf(p.y + lift - drawn))
	return result


func _assert_on_surface(offsets: PackedFloat32Array, label: String, at_least: int) -> void:
	assert_true(offsets.size() >= at_least, "%s: %d checked" % [label, offsets.size()])
	var total := 0.0
	var worst := 0.0
	for o in offsets:
		total += o
		worst = maxf(worst, o)
	var mean := total / maxi(offsets.size(), 1)
	var scale := MapScale.DEFAULT_METRES_PER_UNIT
	assert_true(
		mean <= TENTH_M and worst <= TENTH_M,
		"%s: mean %.3f m, max %.3f m" % [label, mean * scale, worst * scale]
	)


func test_full_dense_trees_stand_on_the_near_surface() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var forest := _view.vegetation().forest
	var points := PackedVector3Array()
	for node in forest.full_nodes():
		points.append_array(forest.instance_positions(node))
	var sink := TreeField.sink(&"pine", LookPreset.vegetation())
	_assert_on_surface(_offsets(points, sink), "dense trees", 500)


func test_planned_trees_and_ground_cover_stand_on_the_near_surface() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var trees := _view.trees()
	var values := LookPreset.vegetation()
	var offsets := PackedFloat32Array()
	for node in trees.lod0_nodes():
		if node.get_meta(&"backdrop", false):
			continue
		var points := PackedVector3Array()
		for t in trees.instance_transforms(node):
			points.append(node.position + t.origin)
		offsets.append_array(_offsets(points, TreeField.sink(node.get_meta(&"species"), values)))
	_assert_on_surface(offsets, "planned trees and ground cover", 30)


func test_the_gpu_grass_reads_the_drawn_near_heights() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grass := _view.vegetation().grass
	assert_true(grass.is_built(), "the grass layer exists (its chunks wait for a low camera)")
	var cache := _view.vegetation().shrubs.near_heights()
	assert_true(cache != null, "the near height window exists")
	for m in grass.materials():
		assert_true(m.get_shader_parameter(&"use_near"), "the grass stands on the drawn near mesh")
	assert_eq(_view.grass().instance_count(), 0, "no CPU grass under true")


static func _gap(rect: Rect2, point: Vector2) -> float:
	return point.distance_to(point.clamp(rect.position, rect.end))


## TASK-217b: after a ~2 km camera jump every GPU grass chunk within the ring exists after the
## first frame (instant layer: no worker plan), and none is built beyond the ring.
func test_a_camera_jump_shows_the_grass_within_the_ring_in_the_first_frame() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grass := _view.vegetation().grass
	var grid := ImportedMap.find(Scenario.SUWALKI_MAP_ID).to_grid()
	var jump := MapScale.to_units(2000.0)
	var target := Vector2.INF
	for c in grid.coords():
		if grid.get_terrain(c) != Terrain.Type.PLAINS:
			continue
		var w := Hex.to_world(c, _view.hex_size)
		var p := Vector2(w.x + 0.1, w.z - 0.1)
		if absf(p.distance_to(_target) - jump) < absf(target.distance_to(_target) - jump):
			target = p
	assert_true(absf(target.distance_to(_target) - jump) < 1.0, "open land ~2 km away")
	var ground := _view.vegetation_ground_height(target.x, target.y)
	_view.set_camera_target(target)
	_view.set_camera_position(Vector3(target.x, ground + 0.003, target.y))
	_view._process(0.016)
	var ring := grass.ring()
	var layer := grass.layer()
	var built := {}
	for node in grass.nodes():
		built[node.get_meta(&"chunk")] = true
	var expected := 0
	var size := GpuGrassField.CHUNK
	for x in range(floori((target.x - ring) / size) - 1, floori((target.x + ring) / size) + 2):
		for z in range(floori((target.y - ring) / size) - 1, floori((target.y + ring) / size) + 2):
			var chunk := Vector2i(x, z)
			var inside := layer.chunk_rect(chunk).intersects(layer.area)
			if _gap(layer.chunk_rect(chunk), target) <= ring and inside:
				expected += 1
				assert_true(built.has(chunk), "grass chunk %s after one frame" % chunk)
	assert_true(expected >= 4, "%d grass chunks within the ring" % expected)
	for chunk: Vector2i in built:
		assert_true(
			_gap(layer.chunk_rect(chunk), target) <= ring + size,
			"no chunk beyond the ring + a chunk: %s" % chunk
		)


## TASK-189 (ADR 0027): after a ~2 km camera jump every impostor chunk within 1 km exists after
## the first frame (the GPU-placed layer builds in the scan), and the full trees follow.
func test_a_camera_jump_shows_the_impostors_within_1_km_in_the_first_frame() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var forest := _view.vegetation().forest
	var grid := ImportedMap.find(Scenario.SUWALKI_MAP_ID).to_grid()
	var jump := MapScale.to_units(2000.0)
	var target := Vector2.INF
	for c in grid.coords():
		if grid.get_terrain(c) != Terrain.Type.FOREST:
			continue
		var w := Hex.to_world(c, _view.hex_size)
		var p := Vector2(w.x + 0.4, w.z - 0.3)
		if absf(p.distance_to(_target) - jump) < absf(target.distance_to(_target) - jump):
			target = p
	assert_true(absf(target.distance_to(_target) - jump) < 1.0, "a forest ~2 km away")
	var ground := _view.vegetation_ground_height(target.x, target.y)
	var started := Time.get_ticks_usec()
	_view.set_camera_target(target)
	var scan_ms := (Time.get_ticks_usec() - started) / 1000.0
	_view.set_camera_position(
		Vector3(target.x, ground, target.y) + CameraMath.camera_offset(0.7, 1.2)
	)
	_view._process(0.016)
	var first_ms := (Time.get_ticks_usec() - started) / 1000.0
	var reach := MapScale.to_units(1000.0)
	var expected := 0
	var layer := forest.impostor_layer()
	var built := {}
	for node in forest.impostor_nodes():
		built[node.get_meta(&"chunk")] = true
	for x in range(floori((target.x - reach) / 2.0), floori((target.x + reach) / 2.0) + 1):
		for z in range(floori((target.y - reach) / 2.0), floori((target.y + reach) / 2.0) + 1):
			var chunk := Vector2i(x, z)
			if layer.distance_to(chunk, target) > reach:
				continue
			var rect := layer.chunk_rect(chunk)
			var forested := forest.fill().mask_any(rect.grow(forest.fill().spacing))
			if not rect.intersects(layer.area) or not forested:
				continue
			expected += 1
			assert_true(built.has(chunk), "impostor chunk %s after one frame" % chunk)
	assert_true(expected > 10, "%d forest chunks within 1 km" % expected)
	# The full trees around the camera (worker plans) follow within seconds.
	var camera_chunks := _view.vegetation().chunks
	var full_layer := camera_chunks.layer(ForestField.FULL_LAYER)
	var position := _view.vegetation().camera_position
	var centre := Vector2(position.x, position.z)
	var build := camera_chunks.build_radius(ForestField.FULL_LAYER)
	var wanted: Array[Vector2i] = []
	for x in range(floori(centre.x - build) - 1, floori(centre.x + build) + 1):
		for z in range(floori(centre.y - build) - 1, floori(centre.y + build) + 1):
			var chunk := Vector2i(x, z)
			if (
				full_layer.distance_to(chunk, centre) <= build
				and full_layer.chunk_rect(chunk).intersects(full_layer.area)
			):
				wanted.append(chunk)
	assert_true(wanted.size() > 4, "%d full chunks wanted" % wanted.size())
	# Frames of ~16 ms: the full trees are there within 2 s of play on 4 cores (measured ~70
	# frames); the bound leaves room for a loaded test machine.
	var missing := wanted.size()
	var frames := 1
	while missing > 0 and frames < 600:
		_view._process(0.016)
		OS.delay_usec(16000)
		frames += 1
		missing = 0
		for chunk in wanted:
			if not camera_chunks.is_live(ForestField.FULL_LAYER, chunk):
				missing += 1
	print(
		(
			"Forest jump: target update %.1f ms, first frame %.1f ms, full trees after %d frames"
			% [scan_ms, first_ms, frames]
		)
	)
	assert_eq(missing, 0, "every full chunk around the camera built")
	assert_true(frames <= 360, "full trees after %d frames" % frames)
	# Back to the shared view of the other tests.
	_view.set_camera_target(_target)
	var back := _view.vegetation_ground_height(_target.x, _target.y)
	_view.set_camera_position(
		Vector3(_target.x, back, _target.y) + CameraMath.camera_offset(0.7, 1.2)
	)
	_view.finish_chunks(_target)


## TASK-217a (ADR 0033): after a ~2 km camera jump every shrub chunk (near meshes and impostors)
## within 600 m of the camera exists after the first frame: the GPU-placed layers build in the
## scan and in process(), nothing is planned.
func test_a_camera_jump_shows_the_shrubs_within_600_m_in_the_first_frame() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var jump := MapScale.to_units(2000.0)
	var target := _target + Vector2(jump, 0.0)
	var rect := _view.vegetation().shrubs.masks.area
	if not rect.has_point(target):
		target = _target - Vector2(jump, 0.0)
	var ground := _view.vegetation_ground_height(target.x, target.y)
	var started := Time.get_ticks_usec()
	_view.set_camera_target(target)
	_view.set_camera_position(
		Vector3(target.x, ground, target.y) + CameraMath.camera_offset(0.7, 1.2)
	)
	_view._process(0.016)
	var first_ms := (Time.get_ticks_usec() - started) / 1000.0
	var camera_chunks := _view.vegetation().chunks
	var position := _view.vegetation().camera_position
	var centre := Vector2(position.x, position.z)
	var reach := MapScale.to_units(600.0)
	var expected := 0
	for id: StringName in [ShrubField.NEAR_LAYER, ShrubField.IMPOSTOR_LAYER]:
		var layer := camera_chunks.layer(id)
		var wanted := minf(reach, camera_chunks.build_radius(id))
		var first := layer.chunk_at(centre.x - wanted, centre.y - wanted)
		var last := layer.chunk_at(centre.x + wanted, centre.y + wanted)
		for x in range(first.x, last.x + 1):
			for z in range(first.y, last.y + 1):
				var chunk := Vector2i(x, z)
				if layer.distance_to(chunk, centre) > wanted:
					continue
				if not layer.chunk_rect(chunk).intersects(layer.area):
					continue
				expected += 1
				assert_true(
					camera_chunks.is_live(id, chunk), "%s chunk %s after one frame" % [id, chunk]
				)
	print("Shrub jump: first frame %.1f ms, %d chunks within 600 m" % [first_ms, expected])
	assert_true(expected > 20, "%d shrub chunks within 600 m" % expected)
	_view.set_camera_target(_target)
	var back := _view.vegetation_ground_height(_target.x, _target.y)
	_view.set_camera_position(
		Vector3(_target.x, back, _target.y) + CameraMath.camera_offset(0.7, 1.2)
	)
	_view.finish_chunks(_target)


## TASK-217a: on a map with rivers the riparian planner still plans shrubs, but under `true` the
## scatter chunks take none of them (the GPU shrubs stand on the banks instead); its alders stay.
func test_riparian_shrubs_are_left_to_the_gpu_layer() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var foliage := _view.foliage()
	assert_true(foliage.gpu_shrubs)
	var grid := ImportedMap.find(Scenario.SUWALKI_MAP_ID).to_grid()
	var checked := 0
	for line in FeatureRibbonPlanner.lines(grid, FeatureRibbonPlanner.Kind.RIVER):
		var p := line[line.size() / 2]
		var chunk := Vector2i((p / TreeField.CHUNK_SIZE).floor())
		var rect := Rect2(Vector2(chunk) * TreeField.CHUNK_SIZE, Vector2.ONE * TreeField.CHUNK_SIZE)
		var riparian := RiparianPlanner.plan(grid, _view.surface(), null, rect)
		if (riparian["edge_shrubs"] as Array).is_empty():
			continue
		var plan := foliage._plan_source(chunk)
		assert_eq((plan["map"]["edge_shrubs"] as Array).size(), 0, "chunk %s" % chunk)
		assert_eq((plan["map"]["bushes"] as Array).size(), 0, "chunk %s" % chunk)
		checked += 1
		if checked >= 2:
			break
	assert_true(checked > 0, "a chunk with riparian shrubs")


## TASK-217a: the shrub masks of the whole map are built once at load, cheaply (no per-shrub work).
func test_the_shrub_masks_build_once_and_fast() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var shrubs := _view.vegetation().shrubs
	var started := Time.get_ticks_usec()
	var masks := VegetationMasks.from_map(
		_view._grid,
		shrubs.masks.area,
		_view.vegetation().forest.fill(),
		_view.land_cover,
		_view._parcels
	)
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	print("Shrub masks: %d x %d texels in %.0f ms" % [masks.size.x, masks.size.y, ms])
	assert_eq(masks.habitat_image().get_data(), shrubs.masks.habitat_image().get_data())
	assert_true(ms < 3000.0, "masks built in %.0f ms" % ms)


## TASK-217a: the shrubs near the camera target stand on the drawn near terrain (the near-height
## window the shaders read), not on the lattice: the window's height equals the drawn near mesh.
func test_shrubs_stand_on_the_drawn_near_terrain() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var shrubs := _view.vegetation().shrubs
	var cache := shrubs.near_heights()
	assert_true(cache != null, "a near-height window")
	cache.update(_target)
	var rules := shrubs.rules
	var rect := Rect2(_target - Vector2.ONE * NEAR_REACH, Vector2.ONE * 2.0 * NEAR_REACH)
	var checked := 0
	var worst := 0.0
	for shrub in rules.plan_rect(rect.grow(-NEAR_REACH * 0.5)):
		var p: Vector3 = shrub["position"]
		var drawn := _view.terrain_near().drawn_height_at(p.x, p.z)
		var cached := cache.height_at(p.x, p.z)
		if is_nan(drawn) or is_nan(cached):
			continue
		worst = maxf(worst, absf(drawn - cached))
		checked += 1
	assert_true(checked > 50, "%d shrubs checked" % checked)
	assert_true(
		worst * MapScale.metres_per_unit < 0.1, "worst %.3f m" % (worst * MapScale.metres_per_unit)
	)
