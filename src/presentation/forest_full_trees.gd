class_name ForestFullTrees
extends RefCounted
## The full 3D trees of the real-scale forest, compacted on the GPU (TASK-221 follow-up, ADR 0027
## amendment 2). Every frame a compute pass (assets/shaders/forest_cells.glsl) derives the tree of
## every fill cell around the camera and appends the ones inside their full range to the list of
## their model (species x variant); the lists are copied into the buffers of 15 MultiMeshes, one
## per model, drawn with the ordinary tree material (forest_tree.gdshader). A tree costs the
## vertices of its own model only: the vertex shader no longer derives it from a cell, so a cell is
## not paid for 15 models any more (35 ms at the old 255 m range, ADR 0027 decision 4).
##
## Nothing is planned on the CPU and nothing is read back: the lists have a fixed capacity per model
## (the worst case of a fully stood-on forest in range, plus margin), the unused instances of a
## list are zero (collapsed by the vertex shader). Without a RenderingDevice (headless, the
## Compatibility renderer) the field is not available: `available()` is false and the impostors
## take the trees from the camera on.
##
## The reference of the compute pass in GDScript: ForestField.full_trees_around (tests).

const SHADER_PATH := "res://assets/shaders/forest_cells.glsl"
const SHADER_TREE := preload("res://assets/shaders/forest_tree.gdshader")
const MODELS := 15
const MAX_BURNS := 128
## Bytes of an instance in a MultiMesh buffer: a 3D transform (12 floats) and custom data (4).
const INSTANCE_BYTES := 64
## Bytes of the compute pass's parameter block (see the shader's `Params`).
const PARAMS_BYTES := 2528
## The shader's work group is 8 x 8 cells.
const GROUP := 8
## Standard deviations of margin on a list's capacity.
const CAPACITY_SIGMAS := 5.0
## The instances drawn of a list: its count a few frames ago times this, plus this many (a camera
## that moves adds trees; an older count must not drop one).
const INSTANCE_MARGIN := 1.3
const INSTANCE_SLACK := 16
## Uniforms of the map the compute pass reads from the impostor material (ForestFill.bind and the
## lattice).
const MAP_UNIFORMS: Array[StringName] = [
	&"forest_seed",
	&"spacing",
	&"min_ground",
	&"high_ground",
	&"conifer_chance",
	&"shares",
	&"autumn_share",
	&"fill_area",
	&"mask_per_unit",
	&"use_parcels",
	&"parcel_origin_m",
	&"parcel_metres_per_pixel",
	&"metres_per_unit",
	&"height_origin",
	&"height_step",
	&"height_cells",
	&"water_surface",
]

var _parent: Node3D
## The map's uniforms and textures (the impostor material's).
var _map: ShaderMaterial
## Holds the near heights' texture and window origin (NearHeightCache.bind).
var _near := ShaderMaterial.new()
var _use_near := false
var _nodes: Array[MultiMeshInstance3D] = []
var _multimeshes: Array[MultiMesh] = []
## Per model the model-to-world scale (x, z, y).
var _scales := PackedVector2Array()
var _capacity := PackedInt32Array()
var _first := PackedInt32Array()
var _total := 0
var _spacing := 1.0
## The range of the trees now (the centre of their band) and the most it can get (the lists'
## capacity is sized for it): the view's far edge, see set_range().
var _cap := 0.0
var _cap_max := 0.0
var _band := 0.08
var _sink := 0.0
var _hand_over_sink := 0.0
## The widest reach of any species (world units): the window around the camera.
var _bounds_y := Vector2.ZERO
var _active := false
var _gpu := false
var _verify := false
## Render-thread resources (created on the first frame).
var _rd_ready := false
var _rd_failed := false
var _shader := RID()
var _pipeline := RID()
var _sampler := RID()
var _uniform_set := RID()
var _params_buffer := RID()
var _counts_buffer := RID()
var _out_buffer := RID()
var _list_buffers: Array[RID] = []
var _dummy_textures: Array[ImageTexture] = []
var _frames := 0
## The lists' tree counts of an earlier frame (see `_got_counts`); empty until the first arrives.
var _counts := PackedInt32Array()


## Whether the compute pass can run here: a RenderingDevice and the imported shader.
static func available() -> bool:
	if RenderingServer.get_rendering_device() == null:
		return false
	return ResourceLoader.exists(SHADER_PATH) and load(SHADER_PATH) is RDShaderFile


## The capacity of the list of a model: the expected count of cells that hold it in a disk of
## `radius` (a forest on every cell), plus margin.
static func list_capacity(radius: float, spacing: float, probability: float) -> int:
	var cells := PI * radius * radius / (spacing * spacing)
	var expected := cells * probability
	return ceili(expected + CAPACITY_SIGMAS * sqrt(expected) + 8.0)


## Upper bound of the share of cells that hold a tree of each species (TreeSpecies.all() order), by
## the fill's cumulative `shares` and conifer chances: ground that is all high or all low.
static func species_shares(shares: Vector4, conifer_chance: Vector2) -> PackedFloat32Array:
	var most := maxf(conifer_chance.x, conifer_chance.y)
	var least := minf(conifer_chance.x, conifer_chance.y)
	return PackedFloat32Array(
		[
			most * shares.x,
			most * (1.0 - shares.x),
			(1.0 - least) * shares.y,
			(1.0 - least) * (shares.z - shares.y),
			(1.0 - least) * (1.0 - shares.z),
		]
	)


## Builds the nodes and buffers. `map` is the material ForestFill.bind and the lattice uniforms
## went to; `species_data` per species (TreeSpecies.all() order): {"scales": Array of Vector2 per
## variant (x, z width scale, y height scale)}; `cap` the most the range of the trees can get
## (the centre of their band; set_range() moves it), `band` the band's half width (share), `sink`
## the base sink
## of a full tree, `hand_over_sink` the impostor's, `span` the lowest / highest lattice height of
## the map, `top` the tallest tree above its base (world units).
func setup(
	parent: Node3D,
	map: ShaderMaterial,
	species_data: Array,
	cap: float,
	band: float,
	sink: float,
	hand_over_sink: float,
	span: Vector2,
	top: float,
	slack: float
) -> void:
	free_all()
	_parent = parent
	_map = map
	_cap = cap
	_cap_max = cap
	_band = band
	_sink = sink
	_hand_over_sink = hand_over_sink
	_spacing = float(map.get_shader_parameter(&"spacing"))
	_bounds_y = Vector2(span.x - slack - sink, span.y + slack + top)
	_gpu = available()
	_verify = OS.get_environment("FOREST_FULL_VERIFY") != ""
	if _verify:
		print(
			(
				"Forest full trees: gpu=%s rd=%s"
				% [_gpu, RenderingServer.get_rendering_device() != null]
			)
		)
	var species := TreeSpecies.all()
	var shares: PackedFloat32Array = species_shares(
		map.get_shader_parameter(&"shares"), map.get_shader_parameter(&"conifer_chance")
	)
	_scales.resize(MODELS)
	_capacity.resize(MODELS)
	_first.resize(MODELS)
	_total = 0
	for s in species.size():
		var data: Dictionary = species_data[s]
		var radius := cap * (1.0 + band)
		var material := TreeField.new_material(species[s], TreeField.Lod.NEAR)
		material.shader = SHADER_TREE
		# The compute pass decides the range (tree by tree, by the impostor's own band).
		material.set_shader_parameter(&"lod_in", TreeField.NO_LOD_IN)
		material.set_shader_parameter(&"lod_out", TreeField.NO_LOD_OUT)
		for v in TreeMeshes.VARIANTS:
			var m := s * TreeMeshes.VARIANTS + v
			_scales[m] = (data["scales"] as Array)[v]
			_first[m] = _total
			_capacity[m] = list_capacity(radius, _spacing, shares[s] / float(TreeMeshes.VARIANTS))
			_total += _capacity[m]
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_custom_data = true
			multimesh.mesh = TreeMeshes.lod0(species[s], v)
			multimesh.instance_count = _capacity[m]
			var node := MultiMeshInstance3D.new()
			node.name = "ForestFull_%s_%d" % [species[s], v]
			node.multimesh = multimesh
			node.material_override = material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			node.visible = false
			parent.add_child(node)
			_multimeshes.append(multimesh)
			_nodes.append(node)


## Whether the trees stand on the drawn near surface (else on the lattice).
func uses_near_heights() -> bool:
	return _use_near


## Whether the GPU draws the full trees (else the impostors start at the camera).
func gpu() -> bool:
	return _gpu


## The reach of the trees now, world units (the compute window's radius); the widest it can get.
func reach_max() -> float:
	return _cap_max * (1.0 + _band)


func reach() -> float:
	return _cap * (1.0 + _band)


## Capacities and first instances of the lists (tests).
func capacities() -> PackedInt32Array:
	return _capacity


func nodes() -> Array[MultiMeshInstance3D]:
	return _nodes


## The trees stand on the drawn near surface of `cache` (null: on the lattice).
func use_near_heights(cache: NearHeightCache) -> void:
	_use_near = cache != null
	if cache != null:
		cache.bind(_near)


## The trees' range now (world units): they are full trees up to it, the impostors beyond (each
## tree at its own point of the band). Clamped to [`min_cap`, the setup's cap].
func set_range(cap: float, min_cap: float) -> void:
	_cap = clampf(cap, minf(min_cap, _cap_max), _cap_max)


## Switches the field on or off (off: nothing is computed, the nodes hide).
func set_active(on: bool) -> void:
	if _verify and on != _active:
		print("Forest full trees: active=%s" % on)
	if on == _active:
		return
	_active = on
	for node in _nodes:
		node.visible = on and _gpu


## One frame: the compute pass for a camera at `camera` (world) and the burnt circles `burns`
## (x, radius, z as ForestField keeps them).
func update(camera: Vector3, burns: Array[Vector3]) -> void:
	if not _gpu or not _active or _rd_failed or _nodes.is_empty():
		return
	var cells_first := Vector2i(
		floori((camera.x - reach()) / _spacing - 0.5), floori((camera.z - reach()) / _spacing - 0.5)
	)
	var cells_last := Vector2i(
		ceili((camera.x + reach()) / _spacing - 0.5), ceili((camera.z + reach()) / _spacing - 0.5)
	)
	var count := cells_last - cells_first + Vector2i.ONE
	_limit_instances()
	if _verify and _frames < 3:
		print("Forest full trees: camera %s" % camera)
	var params := _params(camera, cells_first, count, burns)
	var groups := Vector2i(ceili(float(count.x) / GROUP), ceili(float(count.y) / GROUP))
	RenderingServer.call_on_render_thread(_run.bind(params, groups))
	var reach := reach()
	var bounds := AABB(
		Vector3(camera.x - reach, _bounds_y.x, camera.z - reach),
		Vector3(2.0 * reach, _bounds_y.y - _bounds_y.x, 2.0 * reach)
	)
	for node in _nodes:
		node.custom_aabb = bounds


## Draws only as many instances of a list as it got trees a few frames ago, plus margin: the
## unused slots of a list would cost their model's vertices (collapsed, but still processed).
func _limit_instances() -> void:
	var counts := _counts
	if counts.size() < MODELS:
		return
	for m in MODELS:
		_multimeshes[m].visible_instance_count = clampi(
			ceili(counts[m] * INSTANCE_MARGIN) + INSTANCE_SLACK, 0, _capacity[m]
		)


## The parameter block of the compute pass (the shader's `Params`).
func _params(
	camera: Vector3, first: Vector2i, count: Vector2i, burns: Array[Vector3]
) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(PARAMS_BYTES)
	var at := 0
	var map := _map
	var burn_count := mini(burns.size(), MAX_BURNS)
	var use_parcels: bool = map.get_shader_parameter(&"use_parcels")
	# flags
	at = _u(b, at, int(map.get_shader_parameter(&"forest_seed")))
	at = _u(b, at, 1 if use_parcels else 0)
	at = _u(b, at, 1 if _use_near else 0)
	at = _u(b, at, burn_count)
	# window, height_cells
	at = _i4(b, at, first.x, first.y, count.x, count.y)
	var cells: Vector2i = map.get_shader_parameter(&"height_cells")
	at = _i4(b, at, cells.x, cells.y, 0, 0)
	at = _f4(b, at, Vector4(camera.x, camera.y, camera.z, _spacing))
	at = _f4(b, at, map.get_shader_parameter(&"fill_area"))
	at = _f4(
		b,
		at,
		Vector4(
			float(map.get_shader_parameter(&"min_ground")),
			float(map.get_shader_parameter(&"high_ground")),
			float(map.get_shader_parameter(&"water_surface")),
			float(map.get_shader_parameter(&"metres_per_unit"))
		)
	)
	var chance: Vector2 = map.get_shader_parameter(&"conifer_chance")
	at = _f4(
		b,
		at,
		Vector4(
			chance.x,
			chance.y,
			float(map.get_shader_parameter(&"autumn_share")),
			float(map.get_shader_parameter(&"mask_per_unit"))
		)
	)
	at = _f4(b, at, map.get_shader_parameter(&"shares"))
	var origin: Vector2 = map.get_shader_parameter(&"height_origin")
	at = _f4(
		b,
		at,
		Vector4(
			origin.x, origin.y, float(map.get_shader_parameter(&"height_step")), _hand_over_sink
		)
	)
	var near_origin: Vector2 = (
		_near.get_shader_parameter(&"near_origin") if _use_near else Vector2.ZERO
	)
	var near_step: float = float(_near.get_shader_parameter(&"near_step")) if _use_near else 1.0
	at = _f4(b, at, Vector4(near_origin.x, near_origin.y, near_step, _sink))
	var parcel_origin: Vector2 = (
		map.get_shader_parameter(&"parcel_origin_m") if use_parcels else Vector2.ZERO
	)
	var parcel_step: float = (
		float(map.get_shader_parameter(&"parcel_metres_per_pixel")) if use_parcels else 1.0
	)
	at = _f4(b, at, Vector4(parcel_origin.x, parcel_origin.y, parcel_step, _band))
	at = _f4(b, at, Vector4(_cap, 0.0, 0.0, 0.0))
	# Every species' full band is centred on the range (the view's far edge decides it).
	for n in 2:
		at = _f4(b, at, Vector4(_cap, _cap, _cap, _cap))
	for n in 8:
		var a := _scales[n * 2] if n * 2 < MODELS else Vector2.ZERO
		var c := _scales[n * 2 + 1] if n * 2 + 1 < MODELS else Vector2.ZERO
		at = _f4(b, at, Vector4(a.x, a.y, c.x, c.y))
	for n in 4:
		at = _i4(
			b,
			at,
			_cap_at(_capacity, n * 4),
			_cap_at(_capacity, n * 4 + 1),
			_cap_at(_capacity, n * 4 + 2),
			_cap_at(_capacity, n * 4 + 3)
		)
	for n in 4:
		at = _i4(
			b,
			at,
			_cap_at(_first, n * 4),
			_cap_at(_first, n * 4 + 1),
			_cap_at(_first, n * 4 + 2),
			_cap_at(_first, n * 4 + 3)
		)
	for n in MAX_BURNS:
		if n < burn_count:
			var c := burns[n]
			at = _f4(b, at, Vector4(c.x, c.z, c.y, 0.0))
		else:
			at = _f4(b, at, Vector4.ZERO)
	return b


static func _cap_at(values: PackedInt32Array, index: int) -> int:
	return values[index] if index < values.size() else 0


static func _u(b: PackedByteArray, at: int, value: int) -> int:
	b.encode_u32(at, value & 0xFFFFFFFF)
	return at + 4


static func _i4(b: PackedByteArray, at: int, x: int, y: int, z: int, w: int) -> int:
	b.encode_s32(at, x)
	b.encode_s32(at + 4, y)
	b.encode_s32(at + 8, z)
	b.encode_s32(at + 12, w)
	return at + 16


static func _f4(b: PackedByteArray, at: int, v: Vector4) -> int:
	b.encode_float(at, v.x)
	b.encode_float(at + 4, v.y)
	b.encode_float(at + 8, v.z)
	b.encode_float(at + 12, v.w)
	return at + 16


## Render thread: the compute pass and the copy of the lists into the MultiMesh buffers.
func _run(params: PackedByteArray, groups: Vector2i) -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null or _rd_failed:
		return
	if not _rd_ready and not _create(rd):
		_rd_failed = true
		return
	rd.buffer_update(_params_buffer, 0, params.size(), params)
	rd.buffer_clear(_counts_buffer, 0, 64)
	rd.buffer_clear(_out_buffer, 0, _total * INSTANCE_BYTES)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, _pipeline)
	rd.compute_list_bind_uniform_set(list, _uniform_set, 0)
	rd.compute_list_dispatch(list, groups.x, groups.y, 1)
	rd.compute_list_end()
	for m in MODELS:
		rd.buffer_copy(
			_out_buffer,
			_list_buffers[m],
			_first[m] * INSTANCE_BYTES,
			0,
			_capacity[m] * INSTANCE_BYTES
		)
	rd.buffer_get_data_async(_counts_buffer, _got_counts, 0, 64)
	_frames += 1
	if _verify and (_frames == 20 or _frames % 240 == 0):
		_report(rd)


## A few frames later: how many trees each list got (the lists' counts of a frame a few frames
## back; update() draws that many, with margin).
func _got_counts(data: PackedByteArray) -> void:
	_counts = data.to_int32_array()


## Debug (FOREST_FULL_VERIFY=1): prints what the pass produced, to compare with the reference.
func _report(rd: RenderingDevice) -> void:
	var counts := rd.buffer_get_data(_counts_buffer, 0, 64).to_int32_array()
	var sum := 0
	var overflow := 0
	for m in MODELS:
		sum += mini(counts[m], _capacity[m])
		overflow += maxi(counts[m] - _capacity[m], 0)
	print(
		(
			"Forest full trees (GPU): %d instances, %d over capacity, capacity %d"
			% [sum, overflow, _total]
		)
	)


## Render thread: the shader, the buffers and the uniform set.
func _create(rd: RenderingDevice) -> bool:
	var file := load(SHADER_PATH) as RDShaderFile
	if file == null:
		return false
	var spirv := file.get_spirv()
	if spirv == null or spirv.compile_error_compute != "":
		push_error(
			"forest_cells.glsl: %s" % (spirv.compile_error_compute if spirv else "not imported")
		)
		return false
	_shader = rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		return false
	_pipeline = rd.compute_pipeline_create(_shader)
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_sampler = rd.sampler_create(sampler_state)
	_params_buffer = rd.storage_buffer_create(PARAMS_BYTES)
	_counts_buffer = rd.storage_buffer_create(64)
	_out_buffer = rd.storage_buffer_create(maxi(_total, 1) * INSTANCE_BYTES)
	_list_buffers.clear()
	for multimesh in _multimeshes:
		_list_buffers.append(RenderingServer.multimesh_get_buffer_rd_rid(multimesh.get_rid()))
	var uniforms: Array[RDUniform] = []
	var textures: Array[Texture2D] = [
		_map.get_shader_parameter(&"forest_mask"),
		_parcels_texture(),
		_map.get_shader_parameter(&"heights"),
		_near_texture(),
	]
	for n in textures.size():
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u.binding = n
		u.add_id(_sampler)
		u.add_id(RenderingServer.texture_get_rd_texture(textures[n].get_rid()))
		uniforms.append(u)
	var buffers: Array[RID] = [_params_buffer, _counts_buffer, _out_buffer]
	for n in buffers.size():
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = 4 + n
		u.add_id(buffers[n])
		uniforms.append(u)
	_uniform_set = rd.uniform_set_create(uniforms, _shader, 0)
	_rd_ready = _uniform_set.is_valid()
	if _verify:
		print("Forest full trees: compute ready=%s, %d instances" % [_rd_ready, _total])
	return _rd_ready


func _parcels_texture() -> Texture2D:
	var texture: Texture2D = _map.get_shader_parameter(&"parcels")
	return texture if texture != null else _dummy(Image.FORMAT_R8)


func _near_texture() -> Texture2D:
	var texture: Texture2D = _near.get_shader_parameter(&"near_heights") if _use_near else null
	return texture if texture != null else _dummy(Image.FORMAT_RF)


func _dummy(format: Image.Format) -> ImageTexture:
	var texture := ImageTexture.create_from_image(Image.create(1, 1, false, format))
	_dummy_textures.append(texture)
	return texture


## Frees the nodes and the GPU resources.
func free_all() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	_nodes.clear()
	_multimeshes.clear()
	if _rd_ready:
		var rids: Array[RID] = [
			_uniform_set, _pipeline, _shader, _sampler, _params_buffer, _counts_buffer, _out_buffer
		]
		RenderingServer.call_on_render_thread(_free_rd.bind(rids))
	_rd_ready = false
	_rd_failed = false
	_active = false
	_dummy_textures.clear()
	_list_buffers.clear()


func _free_rd(rids: Array[RID]) -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		return
	for rid in rids:
		if rid.is_valid():
			rd.free_rid(rid)
