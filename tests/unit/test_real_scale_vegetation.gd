extends TestCase
## Real-scale vegetation (TASK-135, ADR 0026): forest density from MapScale, metre ranges that
## scale with the tree size, the full-tree budget (farthest first), deterministic scatter without
## new random streams, real-size near grass within ~100 m, and `balanced` left alone.

const Fixtures := preload("res://tests/fixtures.gd")
const SEED := 20240518

## A small all-forest map at the `true` preset with the camera low over its centre.
static var _view: MapView
static var _camera := Vector3.ZERO


func before_all() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	_view = MapView.new()
	_view._ready()
	_view.quality = GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	_view.build(_forest_grid(4))
	var c := _view.center()
	var target := Vector2(c.x + 0.3, c.z + 0.2)
	var ground := _view.vegetation_ground_height(target.x, target.y)
	_camera = Vector3(target.x, ground, target.y) + CameraMath.camera_offset(0.4, 1.2)
	_view.set_camera_position(_camera)
	_view.finish_chunks(target)
	VisualScale.reset()


func after_all() -> void:
	_view.free()
	_view = null
	VisualScale.reset()
	MapScale.reset()


func after_each() -> void:
	VisualScale.reset()
	MapScale.reset()


static func _forest_grid(radius: int) -> HexGrid:
	var grid := Fixtures.plains_grid(radius)
	for c in grid.coords():
		grid.set_terrain(c, Terrain.Type.FOREST)
	return grid


static func _flat(_x: float, _z: float) -> float:
	return 0.5


func test_a_forest_hex_holds_about_2000_trees_derived_from_the_map_scale() -> void:
	var grid := _forest_grid(3)
	var surface := BackdropSurface.new(grid, _flat)
	var c := Vector2i(0, 0)
	var centre := Hex.to_world(c, TerrainField.HEX_SIZE)
	var rect := Rect2(Vector2(centre.x, centre.z) - Vector2.ONE * 1.2, Vector2.ONE * 2.4)
	var count := 0
	for tree in ForestFill.new(grid, _flat, SEED, rect).plan_rect(rect):
		if Hex.from_world(tree["position"], TerrainField.HEX_SIZE) == c:
			count += 1
	var planned: Array = (
		ScatterPlanner.plan(grid, surface, SEED, null, [c] as Array[Vector2i])["trees"]
	)
	count += planned.size()
	var expected := VegetationRanges.trees_per_hex()
	assert_true(absf(expected - 2000.0) < 50.0, "%.0f trees per hex at the 250 m hex" % expected)
	assert_true(absf(count - 2000.0) <= 200.0, "%d visual trees in a forest hex" % count)
	# The density is per hectare: a map at another scale keeps it (a quarter of the hex area).
	MapScale.metres_per_unit = MapScale.DEFAULT_METRES_PER_UNIT * 0.5
	assert_true(absf(VegetationRanges.trees_per_hex() - expected * 0.25) < 1.0)


func test_balanced_draws_no_real_scale_forest() -> void:
	var view := Fixtures.map_view(
		_forest_grid(2), GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	)
	view.set_camera_position(view.center() + Vector3(0.0, 1.0, 1.0))
	view.finish_chunks()
	assert_eq(view.vegetation().forest.full_nodes().size(), 0)
	assert_eq(view.vegetation().forest.impostor_nodes().size(), 0)
	assert_eq(view.vegetation().grass.nodes().size(), 0)
	assert_eq(view.trees().impostor_nodes().size(), 0)
	assert_true(view.find_child(ForestShell.NODE, true, false) == null, "no canopy shell")
	assert_true(view.trees().lod1_nodes().size() > 0, "the balanced LODs as before")
	view.free()


func test_ranges_are_metres_and_scale_with_the_tree_size() -> void:
	var tall := VegetationRanges.full_range(24.0)
	var short := VegetationRanges.full_range(12.0)
	assert_true(absf(tall * MapScale.metres_per_unit - 250.0) < 0.01, "full range 250 m")
	assert_true(absf(tall - 2.0 * short) < 1.0e-6, "half the height, half the range")
	var far := VegetationRanges.impostor_range(24.0)
	assert_true(absf(far * MapScale.metres_per_unit - 1400.0) < 0.01, "impostors to 1.4 km")
	assert_true(absf(far - 2.0 * VegetationRanges.impostor_range(12.0)) < 1.0e-6)
	# Small scrub keeps a floor; off-forest items keep their impostor until it is ~2 px.
	assert_true(VegetationRanges.full_range(0.8) * MapScale.metres_per_unit >= 30.0 - 1.0e-3)
	assert_true(VegetationRanges.vanish_range(3.0) > VegetationRanges.impostor_range(3.0))


func test_the_budget_drops_the_farthest_chunks_first() -> void:
	var chunks: Array[Vector2] = [
		Vector2(0.9, 400), Vector2(0.1, 500), Vector2(1.4, 300), Vector2(0.5, 600)
	]
	var reach := VegetationRanges.budget_reach(chunks, 1100)
	assert_true(is_equal_approx(reach, 0.9), "0.1 + 0.5 fit, 0.9 does not: %f" % reach)
	assert_eq(VegetationRanges.budget_reach(chunks, 5000), INF, "all fit")
	reach = VegetationRanges.budget_reach(chunks, 100)
	assert_true(is_equal_approx(reach, 0.1), "not even the nearest fits: %f" % reach)


func test_the_full_tree_cap_holds_for_a_synthetic_camera() -> void:
	var forest := _view.vegetation().forest
	var saved: int = forest._values["full_tree_cap"]
	forest.update(_camera)
	var uncapped := forest.visible_full_count()
	assert_true(uncapped > 0, "full trees near the camera")
	var cap := uncapped / 2
	forest._values["full_tree_cap"] = cap
	forest.update(_camera)
	assert_true(forest.visible_full_count() <= cap, "%d <= %d" % [forest.visible_full_count(), cap])
	assert_true(forest.reach() < INF)
	var nearest_hidden := INF
	var farthest_shown := 0.0
	for chunk: Vector2i in forest._full:
		var nodes: Array = forest._full[chunk]["nodes"]
		if nodes.is_empty():
			continue
		var d := forest._distance(chunk, _camera)
		if (nodes[0] as MultiMeshInstance3D).visible:
			farthest_shown = maxf(farthest_shown, d)
		elif d < forest.max_ranges().x:
			nearest_hidden = minf(nearest_hidden, d)
	assert_true(farthest_shown <= nearest_hidden, "%f <= %f" % [farthest_shown, nearest_hidden])
	# The dropped trees become impostors: their lod cap is the budget's reach.
	var material := forest.full_nodes()[0].material_override as ShaderMaterial
	assert_eq(material.get_shader_parameter(&"lod_cap"), forest.reach())
	forest._values["full_tree_cap"] = saved
	forest.update(_camera)


func test_scatter_is_deterministic_and_the_true_preset_adds_no_draws() -> void:
	var grid := _forest_grid(3)
	var rect := Rect2(-1.0, -1.0, 2.0, 2.0)
	var fill := ForestFill.new(grid, _flat, SEED, Rect2(-4.0, -4.0, 8.0, 8.0))
	var first := fill.plan_rect(rect)
	assert_true(first.size() > 1000, "%d trees" % first.size())
	assert_eq(fill.plan_rect(rect), first, "same seed, same trees")
	var halves := fill.plan_rect(Rect2(-1.0, -1.0, 1.0, 2.0))
	halves.append_array(fill.plan_rect(Rect2(0.0, -1.0, 1.0, 2.0)))
	assert_eq(halves.size(), first.size(), "chunks add up to the whole")
	var other := ForestFill.new(grid, _flat, SEED + 1, Rect2(-4.0, -4.0, 8.0, 8.0))
	assert_true(other.plan_rect(rect) != first, "another seed")
	var surface := BackdropSurface.new(grid, _flat)
	var balanced := ScatterPlanner.plan(grid, surface, SEED)
	VisualScale.apply(VisualScale.TRUE_PRESET)
	assert_eq(
		ScatterPlanner.plan(grid, surface, SEED), balanced, "the planned scatter is unchanged"
	)


func test_real_size_summer_greens_replace_the_looks_yellowed_leaves() -> void:
	# At real size thousands of crowns show the leaf colour: the look's yellowed birch and its
	# autumn share read as a beige forest, so `true` has its own greens (TASK-135 playtest).
	var balanced := LookPreset.leaf_color(&"birch", TreeField.LEAF_COLORS[&"birch"])
	var autumn := LookPreset.autumn_share(TreeSpecies.AUTUMN_SHARE)
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var real := LookPreset.leaf_color(&"birch", TreeField.LEAF_COLORS[&"birch"])
	assert_true(real != balanced, "own birch colour")
	assert_true(real.g > real.r * 1.15, "birch reads green, not beige: %s" % real)
	assert_true(LookPreset.autumn_share(TreeSpecies.AUTUMN_SHARE) < autumn, "fewer autumn trees")
	VisualScale.reset()
	assert_eq(LookPreset.leaf_color(&"birch", TreeField.LEAF_COLORS[&"birch"]), balanced)


func test_real_size_air_hazes_the_distance_blue() -> void:
	# Aerial perspective (look reference, 2026-11-21): at real size the haze starts within a few
	# km and is bluer than the balanced fog; balanced keeps its own.
	var balanced := Environment.new()
	LookPreset.apply_to_environment(balanced)
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var real := Environment.new()
	LookPreset.apply_to_environment(real)
	var begin_m := real.fog_depth_begin * MapScale.metres_per_unit
	assert_true(begin_m > 500.0 and begin_m < 2000.0, "haze from %d m" % begin_m)
	assert_true(real.fog_depth_end < balanced.fog_depth_end, "dense before the balanced end")
	assert_true(real.fog_light_color.b > real.fog_light_color.r, "bluish haze")
	assert_true(real.fog_aerial_perspective >= 0.8, "takes the sky's colour")
	VisualScale.reset()
	var again := Environment.new()
	LookPreset.apply_to_environment(again)
	assert_eq(again.fog_depth_begin, balanced.fog_depth_begin)


func test_real_size_broadleaf_cards_carry_small_leaves() -> void:
	# A real-size crown card is metres wide: the balanced cluster's 5 broad leaves would be a metre
	# each, so `true` uses a card of many small leaves.
	var balanced := TreeField.leaf_texture(false)
	var balanced_needles := TreeField.leaf_texture(true)
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var real := TreeField.leaf_texture(false)
	assert_true(real != balanced, "own card")
	assert_true(TreeField.leaf_texture(true) != balanced_needles, "own needle card too")
	var needles := LeafTexture.small_needles(TreeField.LEAF_TEXTURE_SIZE, TreeField.NEEDLE_SEED)
	assert_true(LeafTexture.coverage(needles) > 0.3, "a dense needle card")
	var image := LeafTexture.small_leaves(TreeField.LEAF_TEXTURE_SIZE, TreeField.CLUSTER_SEED)
	var opaque := 0
	var n := image.get_width()
	for y in range(0, n, 2):
		for x in range(0, n, 2):
			if (
				Vector2(x, y).distance_to(Vector2(n, n) * 0.5) < n * 0.35
				and image.get_pixel(x, y).a > 0.5
			):
				opaque += 1
	var disc := PI * pow(n * 0.35 / 2.0, 2.0)
	assert_true(opaque > disc * 0.45, "a dense crown card: %d of %d" % [opaque, int(disc)])


func test_near_grass_is_gpu_placed_within_the_ring_and_the_cpu_grass_plans_nothing() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grass := _view.vegetation().grass
	assert_true(grass.is_built(), "the GPU grass layer exists under true on HIGH")
	assert_true(grass.nodes().size() > 0, "near grass is built around the camera")
	assert_eq(grass.ring_m(), 40.0)
	assert_eq(_view.grass().instance_count(), 0, "no CPU grass instance under true")
	assert_false(_view.grass().is_active())
	assert_eq(_view.grass().chunk_nodes().size(), 0)


## TASK-189 (ADR 0027): an impostor chunk is one node sharing one MultiMesh without instance
## data; its cells travel as an instance uniform and the shader derives the trees.
func test_impostor_chunks_carry_no_instance_data_and_build_in_under_half_a_millisecond() -> void:
	var forest := _view.vegetation().forest
	var nodes := forest.impostor_nodes()
	assert_true(nodes.size() > 4, "%d impostor chunks" % nodes.size())
	var shared := nodes[0].multimesh
	assert_false(shared.use_colors or shared.use_custom_data, "no per-instance colour or custom")
	for node in nodes:
		assert_true(node.multimesh == shared, "one MultiMesh for every chunk")
		var chunk: Vector2i = node.get_meta(&"chunk")
		var cells := forest.impostor_cells(chunk)
		assert_eq(
			node.get_instance_shader_parameter(&"cells"),
			Vector4(cells.position.x, cells.position.y, cells.size.x, cells.size.y)
		)
		assert_true(cells.size.x * cells.size.y <= shared.instance_count, "fits the instances")
	# The layer plans nothing (instant) and a build is a node.
	var layer := forest.impostor_layer()
	assert_true(layer.instant and not layer.plan_chunk.is_valid())
	var chunks: Array[Vector2i] = []
	for node in nodes:
		chunks.append(node.get_meta(&"chunk"))
	# The best of a few rounds (a loaded test machine only makes a round slower).
	var best_ms := INF
	for round in 5:
		var started := Time.get_ticks_usec()
		for chunk in chunks:
			layer.build_chunk.call(chunk, null)
		best_ms = minf(best_ms, (Time.get_ticks_usec() - started) / 1000.0 / chunks.size())
	assert_true(best_ms < 0.5, "%.3f ms per impostor chunk" % best_ms)
	assert_eq(forest.impostor_nodes().size(), nodes.size(), "rebuilt in place")


## The full trees come from the worker plans (MultiMesh buffers), the impostor positions from the
## reference the shader follows; both derive from ForestFill.cell_tree, so this checks the full
## layer's planning, ownership and grounding, not the GPU: every full tree has its impostor cell
## at the same point, and the height gap is exactly near surface - lattice + the extra sink.
func test_every_full_tree_has_its_impostor_cell_at_the_same_point() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var forest := _view.vegetation().forest
	var a := forest.fill().spacing
	var full := {}
	for node in forest.full_nodes():
		for p in forest.instance_positions(node):
			# A point keeps a tenth of a cell off its cell's border.
			full[Vector2i(floori(p.x / a), floori(p.z / a))] = p
	assert_true(full.size() > 500, "%d full trees" % full.size())
	var extra := MapScale.to_units(float(LookPreset.vegetation()["impostor_sink_m"]))
	var matched := 0
	for node in forest.impostor_nodes():
		for p in forest.instance_positions(node):
			var key := Vector2i(floori(p.x / a), floori(p.z / a))
			if not full.has(key):
				continue
			matched += 1
			var at: Vector3 = full[key]
			assert_true(Vector2(at.x, at.z).distance_to(Vector2(p.x, p.z)) < 1.0e-5)
			var near := _view.vegetation_ground_height(p.x, p.z)
			var lattice := _view.mesh_height_at(p.x, p.z)
			var gap := at.y - p.y
			assert_true(absf(gap - (near - lattice + extra)) < 1.0e-4, "gap %.4f" % gap)
	assert_eq(matched, full.size(), "every full tree has its impostor cell")


## The shader's inputs line up with the reference: every lattice height texel is the lattice
## vertex (orientation, no off-by-one) and every stand mask texel is mask_allows at its centre.
func test_the_height_and_mask_textures_match_the_reference() -> void:
	var lattice: TerrainLattice = _view._lattice
	var heights := ForestFill.height_image(lattice)
	assert_eq(heights.get_size(), lattice.cells + Vector2i.ONE)
	for j in heights.get_height():
		for i in heights.get_width():
			assert_eq(heights.get_pixel(i, j).r, lattice.height(i, j), "vertex (%d, %d)" % [i, j])
	var fill := _view.vegetation().forest.fill()
	var mask := fill.mask_image()
	var origin := fill.area.position
	var on := 0
	for j in range(0, mask.get_height(), 3):
		for i in range(0, mask.get_width(), 3):
			var x := origin.x + (i + 0.5) / ForestFill.MASK_PER_UNIT
			var z := origin.y + (j + 0.5) / ForestFill.MASK_PER_UNIT
			var allowed := mask.get_pixel(i, j).r > 0.5
			assert_eq(fill.mask_allows(x, z), allowed, "texel (%d, %d)" % [i, j])
			if allowed:
				on += 1
	assert_true(on > 100, "%d forest texels checked" % on)


## The GLSL twin of ForestFill keeps the reference's expressions (a drift fails here; the values
## are fixed by test_forest_fill).
func test_the_shader_keeps_the_reference_expressions() -> void:
	var include := FileAccess.get_file_as_string("res://assets/shaders/forest_hash.gdshaderinc")
	var shader := FileAccess.get_file_as_string("res://assets/shaders/forest_impostor.gdshader")
	for expression in [
		"(float(h & 65535u) / 65536.0 - 0.5)",
		"(float((h >> 16u) & 65535u) / 65536.0 - 0.5)",
		"return float(x & 16777215u) / 16777216.0;",
		"uint x = h ^ (uint(part + 1) * FOREST_UNIT_MULTIPLIER);",
		"h = forest_mix(h ^ uint(cell.x));",
	]:
		assert_true(include.contains(expression), "include: %s" % expression)
	for expression in [
		"FOREST_SCALE_RANGE * float(values_hash & 1023u) / 1024.0",
		"float k = float((values_hash >> 10u) & 1023u) / 1024.0;",
		"float conifer_roll = float((values_hash >> 20u) & 1023u) / 1024.0;",
		"float height_scale = s * (0.9 + k * 0.3);",
		"k * 6.0",
		"((cell.x + cell.y) & 1) != 0",
		"vec2 p = forest_point(point_hash, cell, spacing);",
		"ivec2(int(cells.x) + INSTANCE_ID % nx, int(cells.y) + INSTANCE_ID / nx)",
	]:
		assert_true(shader.contains(expression), "shader: %s" % expression)


## The field keeps the last MAX_BURNS circles, for the full trees and the impostors alike.
func test_burns_beyond_the_cap_drop_the_oldest_for_both_paths() -> void:
	var forest := _view.vegetation().forest
	var saved: Array[Vector3] = forest._burns.duplicate()
	for n in ForestField.MAX_BURNS + 5:
		forest.burn(Vector2(-100.0 - n, -100.0), 0.01)
	var burns := forest.impostor_burns()
	assert_eq(burns.size(), ForestField.MAX_BURNS)
	assert_eq(forest._burns.size(), ForestField.MAX_BURNS, "full trees keep the same circles")
	assert_true(is_equal_approx(burns[0].x, -105.0), "the oldest five dropped: %s" % burns[0])
	forest._burns = saved
	forest._push_burns()


func test_a_burn_reaches_the_impostor_shader() -> void:
	var forest := _view.vegetation().forest
	var before := forest.impostor_burns().size()
	forest.burn(Vector2(_camera.x, _camera.z), 0.05)
	var burns := forest.impostor_burns()
	assert_eq(burns.size(), before + 1)
	assert_true(is_equal_approx(burns[burns.size() - 1].z, 0.05))
