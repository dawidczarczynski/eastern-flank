extends TestCase
## The GPU-compacted full forest trees (TASK-221, ADR 0027 amendment 2): ForestFullTrees holds one
## MultiMesh per model whose buffer a compute pass fills every frame, the GDScript reference
## (ForestField.full_trees_around) is the fill trees of the cells in range, and the lists are large
## enough for a forest on every cell. The compute pass itself needs a RenderingDevice (not
## headless): here its shader must compile and its parameter block must hold what it reads.

const Fixtures := preload("res://tests/fixtures.gd")

## A small all-forest map at the `true` preset with the camera low over its centre.
static var _view: MapView
static var _camera := Vector3.ZERO
## A camera just above the ground at the target: trees stand within the full range of it.
static var _low := Vector3.ZERO


func before_all() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	_view = MapView.new()
	_view._ready()
	_view.quality = GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	var grid := Fixtures.plains_grid(4)
	for c in grid.coords():
		grid.set_terrain(c, Terrain.Type.FOREST)
	_view.build(grid)
	var c := _view.center()
	var target := Vector2(c.x + 0.3, c.z + 0.2)
	var ground := _view.vegetation_ground_height(target.x, target.y)
	_camera = Vector3(target.x, ground, target.y) + CameraMath.camera_offset(0.4, 1.2)
	_low = Vector3(target.x, ground + MapScale.to_units(3.0), target.y)
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


## One MultiMesh per model (species x variant) with custom data, sized by the list capacity; the
## compute lists add up to a small multiple of the cells in range, not 15 times them (the point of
## the compaction).
func test_one_multimesh_per_model_sized_by_its_list_capacity() -> void:
	var field := _view.vegetation().forest.full_trees_field()
	var nodes := field.nodes()
	assert_eq(nodes.size(), TreeSpecies.all().size() * TreeMeshes.VARIANTS)
	var capacities := field.capacities()
	var total := 0
	for n in nodes.size():
		var multimesh := nodes[n].multimesh
		assert_true(multimesh.use_custom_data, "custom data")
		assert_eq(multimesh.instance_count, capacities[n])
		var species := TreeSpecies.all()[n / TreeMeshes.VARIANTS]
		assert_true(multimesh.mesh == TreeMeshes.lod0(species, n % TreeMeshes.VARIANTS))
		total += capacities[n]
	var cells := PI * pow(field.reach() / _view.vegetation().forest.fill().spacing, 2.0)
	assert_true(total > cells * 0.5, "%d instances for %d cells" % [total, cells])
	assert_true(total < cells * 4.0, "%d instances for %d cells" % [total, cells])


## The reference's trees are the fill trees of the cells in range at the drawn near surface, each
## inside its own point of its species' band; the lists are large enough for them.
func test_the_reference_trees_are_the_fill_trees_in_range_and_fit_their_lists() -> void:
	var forest := _view.vegetation().forest
	var field := forest.full_trees_field()
	var trees := forest.full_trees_around(_low)
	assert_true(trees.size() > 10, "%d full trees" % trees.size())
	var sink := TreeField.sink(&"pine", LookPreset.vegetation())
	var per_model := PackedInt32Array()
	per_model.resize(TreeSpecies.all().size() * TreeMeshes.VARIANTS)
	for tree in trees:
		var at: Vector3 = (forest.fill().cell_tree(tree["cell"]))["position"]
		var t: Transform3D = tree["transform"]
		assert_eq(tree["position"], t.origin)
		assert_true(Vector2(t.origin.x, t.origin.z).distance_to(Vector2(at.x, at.z)) < 1.0e-6)
		assert_true(absf(t.origin.y - (forest.drawn_ground(at.x, at.z) - sink)) < 1.0e-6)
		var factors := ForestField._variant_scale(
			tree["species"], tree["variant"], LookPreset.vegetation()
		)
		assert_true(absf(t.basis.get_scale().x - tree["scale"] * factors.x) < 1.0e-5)
		assert_true(absf(t.basis.get_scale().y - tree["height_scale"] * factors.y) < 1.0e-5)
		assert_true(Vector2(at.x, at.z).distance_to(Vector2(_low.x, _low.z)) < field.reach())
		var model := TreeSpecies.all().find(tree["species"]) * TreeMeshes.VARIANTS
		per_model[model + int(tree["variant"])] += 1
	var capacities := field.capacities()
	for m in per_model.size():
		assert_true(
			per_model[m] <= capacities[m], "model %d: %d of %d" % [m, per_model[m], capacities[m]]
		)


## A burnt circle takes the full trees inside it (the compute pass skips them as the impostors do).
func test_a_burnt_circle_clears_the_reference_trees_inside_it() -> void:
	var forest := _view.vegetation().forest
	var saved: Array[Vector3] = forest._burns.duplicate()
	var trees := forest.full_trees_around(_low)
	var victim: Vector3 = trees[0]["position"]
	forest.burn(Vector2(victim.x, victim.z), 0.001)
	var after := forest.full_trees_around(_low)
	assert_eq(after.size(), trees.size() - 1)
	forest._burns = saved
	forest._push_burns()


## The compute shader compiles (glslang at import) and the parameter block has the size the shader
## declares, its fields where the shader reads them.
func test_the_compute_shader_compiles_and_its_parameter_block_has_the_shaders_layout() -> void:
	var file := load(ForestFullTrees.SHADER_PATH) as RDShaderFile
	assert_true(file != null, "forest_cells.glsl imported")
	assert_eq(file.get_spirv().compile_error_compute, "")
	var field := _view.vegetation().forest.full_trees_field()
	var burns: Array[Vector3] = [Vector3(1.5, 0.25, 2.5)]
	var params := field._params(_camera, Vector2i(-3, 4), Vector2i(50, 60), burns)
	assert_eq(params.size(), ForestFullTrees.PARAMS_BYTES)
	assert_eq(params.decode_u32(12), 1, "burn count")
	assert_eq(params.decode_s32(16), -3)
	assert_eq(params.decode_s32(20), 4)
	assert_eq(params.decode_s32(24), 50)
	assert_eq(params.decode_s32(28), 60)
	assert_true(is_equal_approx(params.decode_float(48), _camera.x))
	assert_true(is_equal_approx(params.decode_float(60), _view.vegetation().forest.fill().spacing))
	# The last block is the burnt circles (x, z, radius).
	var at := ForestFullTrees.PARAMS_BYTES - ForestFullTrees.MAX_BURNS * 16
	assert_eq(params.decode_float(at), 1.5)
	assert_eq(params.decode_float(at + 4), 2.5)
	assert_eq(params.decode_float(at + 8), 0.25)


## Without a RenderingDevice the field draws nothing and the impostors start at the camera.
func test_without_a_gpu_the_impostors_take_the_trees_from_the_camera() -> void:
	var forest := _view.vegetation().forest
	var field := forest.full_trees_field()
	var cap: float = forest._impostor_material.get_shader_parameter(&"full_cap")
	assert_eq(cap == 0.0, not field.gpu())
