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
	for tree in ForestFill.plan_rect(grid, _flat, SEED, rect):
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
	assert_eq(view.vegetation().grass_near.nodes().size(), 0)
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
	var first := ForestFill.plan_rect(grid, _flat, SEED, rect)
	assert_eq(ForestFill.plan_rect(grid, _flat, SEED, rect), first, "same seed, same trees")
	var halves := ForestFill.plan_rect(grid, _flat, SEED, Rect2(-1.0, -1.0, 1.0, 2.0))
	halves.append_array(ForestFill.plan_rect(grid, _flat, SEED, Rect2(0.0, -1.0, 1.0, 2.0)))
	assert_eq(halves.size(), first.size(), "chunks add up to the whole")
	assert_true(ForestFill.plan_rect(grid, _flat, SEED + 1, rect) != first, "another seed")
	var surface := BackdropSurface.new(grid, _flat)
	var balanced := ScatterPlanner.plan(grid, surface, SEED)
	VisualScale.apply(VisualScale.TRUE_PRESET)
	assert_eq(
		ScatterPlanner.plan(grid, surface, SEED), balanced, "the planned scatter is unchanged"
	)


func test_thinned_fill_keeps_every_other_cell_of_the_full_fill() -> void:
	# Far impostor chunks plan half the trees (wider crowns make up for it): the same trees, no new.
	var grid := _forest_grid(3)
	var rect := Rect2(-1.0, -1.0, 2.0, 2.0)
	var full := ForestFill.plan_rect(grid, _flat, SEED, rect)
	var thin := ForestFill.plan_rect(grid, _flat, SEED, rect, null, {}, true)
	assert_true(
		thin.size() > full.size() * 0.4 and thin.size() < full.size() * 0.6,
		"about half: %d of %d" % [thin.size(), full.size()]
	)
	for tree in thin:
		assert_true(full.has(tree), "a thinned tree is one of the full fill")


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


func test_near_grass_is_real_size_within_100_m_of_the_camera() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var near := _view.vegetation().grass_near
	var nodes := near.nodes()
	assert_true(nodes.size() > 0, "near grass is built around the camera")
	var range_m := near.draw_range() * MapScale.metres_per_unit
	assert_true(absf(range_m - 100.0) < 0.01, "%.1f m" % range_m)
	var card_m := GrassField.CARD_HEIGHT * VisualScale.grass_scale() * MapScale.metres_per_unit
	var count := 0
	for node in nodes:
		assert_true(is_equal_approx(node.visibility_range_end, near.draw_range()))
		var buffer: PackedFloat32Array = near._buffers[node]
		for k in range(0, buffer.size(), GrassField.STRIDE):
			var height_m := Vector3(buffer[k + 1], buffer[k + 5], buffer[k + 9]).length() * card_m
			assert_true(height_m >= 0.3 and height_m <= 1.5, "%.2f m clump" % height_m)
			count += 1
	# Real density: about near_grass_per_m2 clumps per m² of forest floor x its density share.
	var area_m2 := 0.0
	for node in nodes:
		area_m2 += pow(GrassNear.CHUNK * MapScale.metres_per_unit, 2.0)
	var expected: float = (
		float(LookPreset.vegetation()["near_grass_per_m2"])
		* GrassPlanner.FOREST_DENSITY
		/ GrassPlanner.PLAINS_DENSITY
	)
	assert_true(count / area_m2 > expected * 0.5, "%.3f clumps per m²" % (count / area_m2))
