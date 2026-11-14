extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")
const Battle := preload("res://src/presentation/battle_controller.gd")

## The forest map at HIGH quality, built once for the tests that only read its trees.
static var _forest: MapView

var _view: MapView
var _view_is_shared := false


func before_each() -> void:
	_view = MapView.new()
	_view._ready()


func after_each() -> void:
	if not _view_is_shared:
		_view.free()
	VisualScale.reset()


func after_all() -> void:
	if _forest != null:
		_forest.free()
		_forest = null


func _forest_grid(radius: int) -> HexGrid:
	var grid := Fixtures.plains_grid(radius)
	for c in grid.coords():
		grid.set_terrain(c, Terrain.Type.FOREST)
	return grid


func _use_forest() -> void:
	if _forest == null:
		_forest = Fixtures.map_view(
			_forest_grid(2), GraphicsQuality.features(GraphicsQuality.Level.HIGH)
		)
	_view.free()
	_view = _forest
	_view_is_shared = true


func _world_aabb(tree: Dictionary) -> AABB:
	var field := TreeField.new()
	field.setup([tree], [], Rect2(-5, -5, 10, 10))
	var node := field.lod0_nodes()[0]
	var t := node.global_transform if node.is_inside_tree() else node.transform
	var world := t * field.instance_transforms(node)[0]
	var aabb := world * node.multimesh.mesh.get_aabb()
	field.free()
	return aabb


func test_instance_size_follows_tree_scale() -> void:
	var tree := {
		"position": Vector3(1.3, 0.2, -2.1),
		"scale": 0.9,
		"height_scale": 1.0,
		"yaw": 0.4,
		"conifer": false,
		"k": 0.3
	}
	VisualScale.apply_values({"tree_scale": 1.0})
	var small := _world_aabb(tree)
	VisualScale.apply_values({"tree_scale": 1.8})
	var big := _world_aabb(tree)
	assert_true(
		absf(big.size.y / small.size.y - 1.8) < 0.018, "ratio %f" % (big.size.y / small.size.y)
	)
	assert_true(absf(big.position.y - small.position.y) < 1e-4, "base unchanged")
	var field := TreeField.new()
	field.setup([tree], [], Rect2(-5, -5, 10, 10))
	var node := field.lod0_nodes()[0]
	var origin := node.position + field.instance_transforms(node)[0].origin
	assert_true(origin.is_equal_approx(tree["position"]), "position unchanged")
	field.free()


func _expected_shadow(node: MultiMeshInstance3D) -> GeometryInstance3D.ShadowCastingSetting:
	var species: StringName = node.get_meta(&"species")
	if species in TreeField.NO_SHADOW_SPECIES or node.get_meta(&"backdrop"):
		return GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## The LODs hand over per tree in the shader (lod_in / lod_out bands); the nodes' visibility
## ranges only cull whole chunks, RANGE_SLACK wider than the bands and without Godot's range fade.
func test_lod_bands_ranges_and_shadows() -> void:
	_use_forest()
	var trees := _view.trees()
	assert_true(trees.lod0_nodes().size() > 0)
	assert_true(trees.lod1_nodes().size() > 0)
	var none := GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for node in trees.lod0_nodes():
		var species: StringName = node.get_meta(&"species")
		var near := TreeField.lod_distance(species) + TreeField.lod_margin(species)
		assert_eq(node.visibility_range_end, near + TreeField.RANGE_SLACK)
		assert_eq(node.visibility_range_begin, 0.0)
		assert_eq(node.visibility_range_fade_mode, none)
		assert_eq(node.cast_shadow, _expected_shadow(node))
		assert_eq(_band(node, &"lod_in"), TreeField.NO_LOD_IN)
		assert_eq(_band(node, &"lod_out").y, near, "LOD0 ends where LOD1 has fully taken over")
	for node in trees.lod1_nodes():
		var species: StringName = node.get_meta(&"species")
		var near := TreeField.lod_distance(species) - TreeField.lod_margin(species)
		assert_eq(node.visibility_range_begin, maxf(near - TreeField.RANGE_SLACK, 0.0))
		assert_eq(node.visibility_range_fade_mode, none)
		assert_eq(node.cast_shadow, _expected_shadow(node))
		assert_eq(_band(node, &"lod_in").x, near, "the band LOD0 leaves by")
		var far := TreeField.LOD2_DISTANCE + TreeField.LOD2_MARGIN
		var end := far + TreeField.RANGE_SLACK if TreeField.has_lod2(species) else 0.0
		assert_eq(node.visibility_range_end, end, "LOD1 hands over to LOD2 (trees only)")
		if TreeField.has_lod2(species):
			assert_eq(_band(node, &"lod_out").y, far)
		else:
			assert_eq(_band(node, &"lod_out"), TreeField.NO_LOD_OUT)
	assert_true(trees.lod2_nodes().size() > 0)
	for node in trees.lod2_nodes():
		var species: StringName = node.get_meta(&"species")
		assert_true(TreeField.has_lod2(species), "no LOD2 for scrub")
		var far := TreeField.LOD2_DISTANCE - TreeField.LOD2_MARGIN
		assert_eq(node.visibility_range_begin, far - TreeField.RANGE_SLACK)
		assert_eq(node.visibility_range_end, 0.0)
		assert_eq(_band(node, &"lod_in").x, far)
		assert_eq(_band(node, &"lod_out"), TreeField.NO_LOD_OUT)
		assert_eq(node.cast_shadow, _expected_shadow(node))
		assert_true(node.multimesh.mesh == TreeMeshes.lod2(species))
	for node in trees.far_nodes():
		assert_eq(node.visibility_range_begin, 0.0)
		assert_eq(node.visibility_range_end, 0.0)
		assert_eq(node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "backdrop")


## Neighbouring LODs share their band, so exactly one of them draws each tree.
func test_neighbouring_lods_share_their_switch_band() -> void:
	for species: StringName in [&"pine", &"birch", &"shrub"]:
		var near: Dictionary = TreeField.lod_bands(species, TreeField.Lod.NEAR)
		var mid: Dictionary = TreeField.lod_bands(species, TreeField.Lod.FAR_RANGE)
		assert_eq(near["out"], mid["in"], "%s LOD0 -> LOD1" % species)
		if TreeField.has_lod2(species):
			var distant: Dictionary = TreeField.lod_bands(species, TreeField.Lod.DISTANT)
			assert_eq(mid["out"], distant["in"], "%s LOD1 -> LOD2" % species)


func _band(node: MultiMeshInstance3D, param: StringName) -> Vector2:
	return (node.material_override as ShaderMaterial).get_shader_parameter(param)


func test_chunk_origins_and_instances_inside_the_chunk() -> void:
	_use_forest()
	var half := TreeField.CHUNK_SIZE * 0.5 + 1e-4
	for node: MultiMeshInstance3D in _view.trees().get_children():
		var p := node.position
		var chunk := TreeField.chunk_of(p)
		assert_true(p.is_equal_approx(TreeField.chunk_center(chunk)), "origin %s" % p)
		var transforms := _view.trees().instance_transforms(node)
		assert_eq(transforms.size(), node.multimesh.instance_count)
		for t in transforms:
			var local := t.origin
			if absf(local.x) > half or absf(local.z) > half:
				_fail("%s: instance %s outside the chunk" % [node.name, local])
				return


func test_every_planned_tree_once_per_lod() -> void:
	_use_forest()
	var trees := _view.trees()
	assert_true(trees.backdrop_count() > 0, "backdrop trees too")
	var far := TreeField.instance_total(trees.far_nodes())
	var lod0 := TreeField.instance_total(trees.lod0_nodes())
	var lod1 := TreeField.instance_total(trees.lod1_nodes())
	assert_eq(lod0 + far, trees.planned_count(), "LOD0 (+ far backdrop)")
	assert_eq(lod1 + far, trees.planned_count(), "LOD1 (+ far backdrop)")
	var with_lod2 := 0
	for node in trees.lod1_nodes():
		if TreeField.has_lod2(node.get_meta(&"species")):
			with_lod2 += node.multimesh.instance_count
	assert_eq(TreeField.instance_total(trees.lod2_nodes()), with_lod2, "LOD2 = LOD1 trees")


func test_no_tree_nodes_without_foliage() -> void:
	var quality := GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	quality["foliage"] = false
	_view.quality = quality
	_view.build(_forest_grid(1))
	assert_eq(_view.trees().get_child_count(), 0)


func test_wind_off_after_build() -> void:
	var quality := GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	quality["wind"] = false
	_view.quality = quality
	_view.build(_forest_grid(1))
	assert_eq(Wind.strength(), 0.0)


func test_lod0_triangle_budget_on_the_default_map() -> void:
	var grid := Scenario.default_battle(Battle.MAP_SEED).grid
	_view.quality = GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	_view.quality["grass_density"] = 0.0
	_view.build(grid)
	var worst := 0
	for c in grid.coords():
		var w := Hex.to_world(c, 1.0)
		worst = maxi(
			worst, _view.trees().lod0_triangles_within(Vector2(w.x, w.z), TreeField.BUDGET_RADIUS)
		)
	print(
		(
			"  LOD0 triangles within %.0f units (worst tile): %d; trees %d (backdrop %d, far %d)"
			% [
				TreeField.BUDGET_RADIUS,
				worst,
				_view.trees().planned_count(),
				_view.trees().backdrop_count(),
				TreeField.instance_total(_view.trees().far_nodes())
			]
		)
	)
	assert_true(worst <= TreeField.LOD0_TRIANGLE_BUDGET, "LOD0 triangles %d" % worst)


func test_meadow_scrub_budget_on_the_default_map() -> void:
	var grid := Scenario.default_battle(Battle.MAP_SEED).grid
	var plan := ScatterPlanner.plan(grid, TerrainSurface.new(grid), MapView.SCATTER_SEED)
	var scrub: Array = plan["meadow_scrub"]
	var triangles := 0
	for tree: Dictionary in scrub:
		var pick := TreeSpecies.pick(tree)
		triangles += TreeMeshes.triangle_count(TreeMeshes.lod0(pick["species"], pick["variant"]))
	print("  meadow scrub: %d instances, %d LOD0 triangles" % [scrub.size(), triangles])
	assert_true(scrub.size() > 0)
	assert_true(triangles <= 25000, "meadow scrub LOD0 triangles %d" % triangles)


func test_low_quality_has_no_meadow_scrub_or_flowers() -> void:
	var grid := Scenario.default_battle(Battle.MAP_SEED).grid
	_view.quality = GraphicsQuality.features(GraphicsQuality.Level.LOW)
	_view.build(grid)
	_view.set_camera_target(Vector2.ZERO)
	_view.grass().update(1000)
	assert_eq(_view.trees().planned_count(), 0)
	assert_eq(_view.grass().instance_count(), 0)
	assert_eq(_view.grass().flower_nodes().size(), 0)


## The card shader (LOD0) and the opaque solid-crown one (LOD1 / LOD2) share one body.
func test_foliage_shaders_load_with_their_uniforms() -> void:
	var body := FileAccess.get_file_as_string("res://assets/shaders/foliage_body.gdshaderinc")
	assert_true(body.contains("wind.gdshaderinc"), "shared wind include")
	for path: String in [
		"res://assets/shaders/foliage.gdshader", "res://assets/shaders/foliage_solid.gdshader"
	]:
		var shader := load(path) as Shader
		assert_true(shader != null, "%s loads" % path)
		assert_eq(shader.get_mode(), Shader.MODE_SPATIAL)
		assert_true(shader.code.contains("foliage_body.gdshaderinc"), "shared body")
		var names: Array[String] = []
		for u: Dictionary in shader.get_shader_uniform_list():
			names.append(u["name"])
		for uniform in ["leaf_color", "bark_color", "tree_height", "lod_in", "lod_out"]:
			assert_true(names.has(uniform), "%s: %s uniform" % [path, uniform])
	# Leaf cards stay in the opaque pass (depth prepass): alpha scissor only, no alpha antialiasing.
	var cards := (load("res://assets/shaders/foliage.gdshader") as Shader).code
	assert_false(cards.contains("alpha_to_coverage"), "no alpha to coverage")
	assert_false(body.contains("ALPHA_ANTIALIASING_EDGE"), "no alpha antialiasing")
	var solid := (load("res://assets/shaders/foliage_solid.gdshader") as Shader).code
	assert_true(solid.contains("#define SOLID_CROWN"), "solid variant")


func test_wind_offset_unchanged() -> void:
	var include := FileAccess.get_file_as_string("res://assets/shaders/wind.gdshaderinc")
	var expected := (
		"vec3 wind_offset(vec3 world_pos, float h, float phase) {\n"
		+ "\tvec2 dir = normalize(wind_direction);\n"
		+ "\tfloat wave = sin(TIME * wind_speed + dot(world_pos.xz, dir) * 2.3 + phase);\n"
		+ "\treturn vec3(dir.x, 0.0, dir.y) * (wind_strength * 0.012 * wave * h * h);\n"
		+ "}"
	)
	assert_true(include.contains(expected), "wind_offset as in TASK-057")
	assert_true(include.contains("vec3 wind_flutter("), "leaf flutter")
