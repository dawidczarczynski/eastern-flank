extends TestCase
## The GPU-placed full forest trees (TASK-221, ADR 0027 amendment): ForestField's `forest_full`
## layer is plan-free and instant, its chunks share one MultiMesh without instance data, the
## GDScript reference (full_trees) is the fill trees of the chunk's cells, and the full range is
## capped by the nearest chunk that is not built.

const Fixtures := preload("res://tests/fixtures.gd")

## A small all-forest map at the `true` preset with the camera low over its centre.
static var _view: MapView
static var _camera := Vector3.ZERO


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


## TASK-221 (ADR 0027 amendment): the full trees are a plan-free instant layer. A chunk is one
## node sharing one MultiMesh of identity instances (no per-chunk instance data, no custom data),
## its cells an instance uniform; the shared mesh has one surface per species; nothing is planned.
func test_full_tree_chunks_carry_no_instance_data_and_are_planned_by_nobody() -> void:
	var forest := _view.vegetation().forest
	var nodes := forest.full_nodes()
	assert_true(nodes.size() > 4, "%d full chunks" % nodes.size())
	var shared := nodes[0].multimesh
	assert_false(shared.use_colors or shared.use_custom_data, "no per-instance colour or custom")
	assert_eq(shared.mesh.get_surface_count(), TreeSpecies.all().size(), "a surface per species")
	for node in nodes:
		assert_true(node.multimesh == shared, "one MultiMesh for every chunk")
		var chunk: Vector2i = node.get_meta(&"chunk")
		var cells := _full_cells(forest, chunk)
		assert_eq(
			node.get_instance_shader_parameter(&"cells"),
			Vector4(cells.position.x, cells.position.y, cells.size.x, cells.size.y)
		)
		assert_true(cells.size.x * cells.size.y <= shared.instance_count, "fits the instances")
	var layer := forest.full_layer()
	assert_true(layer.instant and not layer.plan_chunk.is_valid(), "instant, no worker plan")
	var stats: Dictionary = _view.vegetation().chunks.stats()[ForestField.FULL_LAYER]
	assert_eq(stats["plan_ms"], 0.0, "no plan time")
	assert_true(stats["live"] > 4, "%d live full chunks" % stats["live"])


static func _full_cells(forest: ForestField, chunk: Vector2i) -> Rect2i:
	return forest.fill().cells_of(
		Rect2(Vector2(chunk) * ForestField.FULL_CHUNK, Vector2.ONE * ForestField.FULL_CHUNK)
	)


## The full trees of a chunk by the reference: the cells of one chunk give the very trees of
## ForestFill.cell_tree (the impostors' trees), each sunk by the tree sink, the transform the
## shader builds (size, narrowed crown, yaw).
func test_the_full_tree_reference_is_the_fill_trees_of_the_chunks_cells() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var forest := _view.vegetation().forest
	var checked := 0
	var sink := TreeField.sink(&"pine", LookPreset.vegetation())
	for node in forest.full_nodes():
		var chunk: Vector2i = node.get_meta(&"chunk")
		var cells := _full_cells(forest, chunk)
		var trees := forest.full_trees(chunk)
		var expected := 0
		for j in range(cells.position.y, cells.end.y):
			for i in range(cells.position.x, cells.end.x):
				expected += 0 if forest.fill().cell_tree(Vector2i(i, j)).is_empty() else 1
		assert_eq(trees.size(), expected, "chunk %s" % chunk)
		for tree in trees:
			var t: Transform3D = tree["transform"]
			var at: Vector3 = forest.fill().cell_tree(tree["cell"])["position"]
			assert_eq(tree["position"], t.origin)
			assert_true(Vector2(t.origin.x, t.origin.z).distance_to(Vector2(at.x, at.z)) < 1.0e-6)
			assert_true(absf(t.origin.y - (forest.drawn_ground(at.x, at.z) - sink)) < 1.0e-6)
			var factors := ForestField._variant_scale(
				tree["species"], tree["variant"], LookPreset.vegetation()
			)
			assert_true(absf(t.basis.get_scale().x - tree["scale"] * factors.x) < 1.0e-5)
			assert_true(absf(t.basis.get_scale().y - tree["height_scale"] * factors.y) < 1.0e-5)
			checked += 1
	assert_true(checked > 100, "%d full trees checked" % checked)


## Every vertex of a species' full mesh carries its variant in the colour's alpha, and the three
## variant models follow one another (the shader's `tag`).
func test_the_full_tree_mesh_tags_every_vertex_with_its_variant() -> void:
	for species in TreeSpecies.all():
		var arrays := ForestField._species_arrays(species)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		assert_eq(colors.size(), vertices.size())
		var first := 0
		for variant in TreeMeshes.VARIANTS:
			var count := (
				(
					TreeMeshes.lod0(species, variant).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
					as PackedVector3Array
				)
				. size()
			)
			for k in range(first, first + count):
				assert_eq(
					roundi(colors[k].a * 255.0 / 127.5), variant, "%s vertex %d" % [species, k]
				)
			first += count
		assert_eq(first, vertices.size(), species)
		for index in arrays[Mesh.ARRAY_INDEX] as PackedInt32Array:
			assert_true(index >= 0 and index < vertices.size())


## The full range ends where the nearest full chunk is not built: the reach of the materials and of
## the impostors (one value, so exactly one of the two draws every tree); INF where all are built.
func test_the_full_reach_follows_the_unbuilt_chunks_and_caps_both_lods() -> void:
	var forest := _view.vegetation().forest
	forest.update(_camera)
	var reach := forest.reach()
	assert_true(reach > 0.0, "%f" % reach)
	var cap := minf(reach, ForestField.NO_CAP)
	for node in forest.full_nodes():
		for surface in node.multimesh.mesh.get_surface_count():
			var material := node.multimesh.mesh.surface_get_material(surface) as ShaderMaterial
			assert_eq(material.get_shader_parameter(&"full_reach"), cap)
		break
	assert_eq(forest._impostor_material.get_shader_parameter(&"full_reach"), cap)
	# A camera over a chunk that is not built caps it at that chunk.
	var far := Vector3(_camera.x + 1.2, _camera.y, _camera.z)
	forest.update(far)
	assert_true(forest.reach() < INF, "an unbuilt chunk beyond the ring caps the range")
	forest.update(_camera)
