class_name ForestField
extends Node3D
## The dense real-scale forest (TASK-135, ADR 0026; only under the `true` VisualScale preset): the
## ForestFill trees (with ScatterPlanner's planned trees ~2 000 per forest hex) as two chunk
## layers of MapView.
##
## - "forest_full" (FULL_CHUNK chunks, on MapView's camera-centred ChunkManager): full 3D trees
##   (TreeMeshes LOD0, one MultiMesh per species and variant), planned on the worker threads from
##   the ForestFill reference and standing on the drawn near surface, each drawn up to its full
##   range (VegetationRanges, scaled by the species' height) – the same per-tree hand-over band as
##   TreeField.
## - "forest" (IMPOSTOR_CHUNK chunks, on the camera-target ChunkManager): GPU-placed impostors
##   (TASK-189, ADR 0027). An `instant` layer: a chunk is one MultiMeshInstance3D sharing one
##   MultiMesh without instance data (one instance per fill cell), its cell range an instance
##   uniform; assets/shaders/forest_impostor.gdshader derives every tree from its cell as
##   ForestFill.cell_tree does, from the full range to the impostor range, where the canopy shell
##   (ForestShell) takes over. Nothing is planned on the CPU, so a chunk exists the frame the
##   camera target reaches it.
##
## The full-tree budget (update(), every frame): the built full chunks within the full range are
## taken nearest first while their tree count stays within LookPreset.vegetation()
## "full_tree_cap" (VegetationRanges.budget_reach); the rest is hidden and the reach caps the
## LOD0 materials' `lod_cap` and the impostors' `full_reach`, so the dropped trees – the farthest
## – are drawn as impostors instead, tree by tree, with no gap and no double draw. A full chunk
## the camera manager has not built yet (or never builds: layer off) caps the reach the same way.

const FULL_LAYER := &"forest_full"
const IMPOSTOR_LAYER := &"forest"
const FULL_CHUNK := 1.0
const IMPOSTOR_CHUNK := 2.0
const NO_CAP := 1.0e9
## Burnt circles the field keeps (full trees and impostors alike; the oldest drop out beyond
## this): a battle leaves a few dozen wrecks. The shader's `burns` array has this size.
const MAX_BURNS := 128

var _grid: HexGrid
## The drawn near surface (full trees; thread-safe).
var _ground := Callable()
var _fill: ForestFill
var _seed := 0
var _area := Rect2()
var _values: Dictionary = {}
## The largest full band end of any species (world units): chunks farther away hold no full tree.
var _max_full := 0.0
var _max_impostor := 0.0
## Vector2i full chunk -> {"nodes": Array[MultiMeshInstance3D], "count": int, "low": float,
## "high": float (lowest / highest tree base)} – also for chunks without trees.
var _full: Dictionary = {}
## Vector2i impostor chunk -> MultiMeshInstance3D (only chunks with forest on the stand mask).
var _impostors: Dictionary = {}
## Impostor chunks whose cells can hold a tree (the stand mask) -> true.
var _forest_chunks: Dictionary = {}
## The shared impostor MultiMesh (one instance per cell of the largest chunk, no instance data).
var _impostor_multimesh: MultiMesh
## The lattice heights (row-major, (cells + 1)^2) and their layout, for the chunks' bounds.
var _heights := PackedFloat32Array()
var _height_origin := Vector2.ZERO
var _height_size := Vector2i.ZERO
## Tallest impostor picture above its base and widest impostor quad (world units), for the
## chunks' bounds.
var _tallest := 0.0
var _widest := 0.0
## Node -> its MultiMesh buffer (tests: the headless renderer keeps no instance data).
var _buffers: Dictionary = {}
var _full_materials: Dictionary = {}
var _impostor_material: ShaderMaterial
var _reach := INF
var _applied_cap := -1.0
var _camera := Vector3.INF
var _visible_full := 0
var _burns: Array[Vector3] = []
## Built impostor chunks as a mask over the area (one pixel per chunk, 255 = built) for the canopy
## shell: over a chunk not built yet the shell stays drawn at any distance, so a forest whose
## impostors are not there yet shows as canopy, never as bare ground.
var _coverage: Image
var _coverage_texture: ImageTexture
var _coverage_dirty := false
var _coverage_origin := Vector2i.ZERO


## Prepares the field for a map: `ground` is Callable(x, z) -> float (the drawn near surface,
## thread-safe), `lattice` the drawn terrain lattice (its heights decide which cells hold a tree
## and carry the impostors), `area` the rectangle the forest may cover (the playable mesh). `look`
## (TASK-108g): the forest stands on the land-cover raster's forest instead of the forest hexes.
func setup(
	grid: HexGrid,
	ground: Callable,
	seed_value: int,
	area: Rect2,
	lattice: TerrainLattice,
	parcels: ParcelMap = null,
	look: CoverLook = null
) -> void:
	clear()
	_grid = grid
	_ground = ground
	_seed = seed_value
	_area = area
	_values = LookPreset.vegetation()
	var source: ForestMaskSource = null
	if look != null:
		var clearing_m := float(VegetationRanges.values(_values)["forest_clearing_m"])
		source = LandCoverForestMaskSource.new(look, MapScale.to_units(clearing_m))
	_fill = ForestFill.new(grid, lattice.mesh_height_at, seed_value, area, parcels, _values, source)
	_max_full = 0.0
	_max_impostor = 0.0
	for species in TreeSpecies.all():
		var height_m := VegetationRanges.species_height_m(species)
		_max_full = maxf(
			_max_full, VegetationRanges.band(VegetationRanges.full_range(height_m, _values)).y
		)
		_max_impostor = maxf(
			_max_impostor,
			VegetationRanges.band(VegetationRanges.impostor_range(height_m, _values)).y
		)
		var material := TreeField.new_material(species, TreeField.Lod.NEAR)
		material.set_shader_parameter(&"lod_out", TreeField.true_bands(species)["out"])
		_full_materials[species] = material
	_setup_impostors(lattice)
	_coverage_origin = Vector2i(
		floori(area.position.x / IMPOSTOR_CHUNK), floori(area.position.y / IMPOSTOR_CHUNK)
	)
	var last := Vector2i(floori(area.end.x / IMPOSTOR_CHUNK), floori(area.end.y / IMPOSTOR_CHUNK))
	var cells := last - _coverage_origin + Vector2i.ONE
	_coverage = Image.create(cells.x, cells.y, false, Image.FORMAT_L8)
	_coverage_texture = ImageTexture.create_from_image(_coverage)
	_coverage_dirty = false
	_applied_cap = -1.0
	_set_reach(INF)


## The impostor material with the map's textures and tables, the shared MultiMesh and the impostor
## chunks that touch forest.
func _setup_impostors(lattice: TerrainLattice) -> void:
	_impostor_material = TreeImpostors.material(_values["band_share"], TreeImpostors.FOREST_SHADER)
	_fill.bind(_impostor_material)
	var heights := ForestFill.height_image(lattice)
	_heights = heights.get_data().to_float32_array()
	_height_origin = lattice.origin
	_height_size = heights.get_size()
	var m := _impostor_material
	m.set_shader_parameter(&"heights", ImageTexture.create_from_image(heights))
	m.set_shader_parameter(&"height_origin", lattice.origin)
	m.set_shader_parameter(&"height_step", TerrainLattice.STEP)
	m.set_shader_parameter(&"height_cells", lattice.cells)
	m.set_shader_parameter(&"water_surface", TerrainSurface.WATER_SURFACE)
	m.set_shader_parameter(&"sink", _impostor_sink())
	var ranges := PackedVector2Array()
	var sizes := PackedVector3Array()
	var leaves := PackedVector3Array()
	var cull := Vector2(INF, 0.0)
	var crown := MapScale.to_units(float(_values["forest_crown_width_m"]))
	_tallest = 0.0
	var max_quad := 0.0
	for species in TreeSpecies.all():
		var data := _impostor_species_data(species, crown)
		ranges.append(Vector2(data[0], data[1]))
		var share := float(_values["band_share"])
		cull = Vector2(minf(cull.x, data[0] * (1.0 - share)), maxf(cull.y, data[1] * (1.0 + share)))
		for variant in TreeMeshes.VARIANTS:
			var size: Vector2 = (data[2] as Array)[variant]
			var row := TreeImpostors.row(species, variant)
			sizes.append(Vector3(size.x * float(row[1]), size.y, float(row[0])))
			max_quad = maxf(max_quad, size.x * float(row[1]))
			_tallest = maxf(_tallest, size.y)
		var leaf := TreeImpostors.leaf_color(species)
		leaves.append(Vector3(leaf.r, leaf.g, leaf.b))
	m.set_shader_parameter(&"species_ranges", ranges)
	m.set_shader_parameter(&"variant_sizes", sizes)
	m.set_shader_parameter(&"leaf_colors", leaves)
	m.set_shader_parameter(&"cull", cull)
	m.set_shader_parameter(&"thin_from", MapScale.to_units(float(_values["impostor_thin_from_m"])))
	m.set_shader_parameter(&"thin_widen", float(_values["impostor_thin_widen"]))
	# Largest scale x height scale, the picture's span above the base; the widest quad (largest
	# scale, widened far crowns).
	var max_scale := ForestFill.SCALE_MIN + ForestFill.SCALE_RANGE
	_tallest *= max_scale * 1.2 * TreeImpostors.VERTICAL_SPAN
	_widest = max_quad * max_scale * float(_values["impostor_thin_widen"])
	_push_burns()
	var side := ceili(IMPOSTOR_CHUNK / _fill.spacing) + 1
	_impostor_multimesh = MultiMesh.new()
	_impostor_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_impostor_multimesh.mesh = TreeImpostors.mesh()
	_impostor_multimesh.instance_count = side * side
	# Chunks whose cells can hold a tree: the stand mask over the chunk, a cell's jitter wider.
	_forest_chunks.clear()
	var first := Vector2i((_area.position / IMPOSTOR_CHUNK).floor())
	var last := Vector2i((_area.end / IMPOSTOR_CHUNK).floor())
	for x in range(first.x, last.x + 1):
		for z in range(first.y, last.y + 1):
			var rect := _chunk_rect(Vector2i(x, z), IMPOSTOR_CHUNK).grow(_fill.spacing)
			if _fill.mask_any(rect):
				_forest_chunks[Vector2i(x, z)] = true


## How far below the lattice height an impostor's base sits (world units).
func _impostor_sink() -> float:
	return TreeField.sink(&"pine", _values) + MapScale.to_units(float(_values["impostor_sink_m"]))


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_full.clear()
	_impostors.clear()
	_buffers.clear()
	_burns.clear()
	_visible_full = 0
	# Nothing of the previous map survives (setup() builds it all again).
	_grid = null
	_fill = null
	_forest_chunks.clear()
	_impostor_multimesh = null
	_impostor_material = null
	_heights = PackedFloat32Array()
	_height_size = Vector2i.ZERO
	_full_materials.clear()
	_coverage = null
	_coverage_texture = null
	_coverage_dirty = false
	_reach = INF
	_applied_cap = -1.0
	_camera = Vector3.INF


func full_layer() -> ChunkLayer:
	var result := ChunkLayer.new(FULL_LAYER, FULL_CHUNK, _area, _build_full, _free_full, _plan_full)
	result.prepare = _prepare
	# Before the near grass on the camera manager (see ChunkLayer.priority).
	result.priority = 1
	return result


## The GPU-placed impostors: an instant layer (no plan, the chunk is built in the scan).
func impostor_layer() -> ChunkLayer:
	var result := ChunkLayer.new(
		IMPOSTOR_LAYER, IMPOSTOR_CHUNK, _area, _build_impostors, _free_impostors
	)
	result.instant = true
	return result


## Main thread, before full-tree plans run on the worker threads: fills the lazy caches they read.
func _prepare() -> void:
	TreeField.prime_sizes()


## The largest full band end (x) and impostor band end (y) of any species (world units).
func max_ranges() -> Vector2:
	return Vector2(_max_full, _max_impostor)


## The fill reference (ForestFill) of this map.
func fill() -> ForestFill:
	return _fill


## World transform of a fill tree: its real size (VisualScale.tree_size), the crown narrowed to
## forest_crown_width_m, the base sunk by `sink` into the ground at its position.
static func _fill_transform(
	tree: Dictionary, pick: Dictionary, sink: float, values: Dictionary
) -> Transform3D:
	var species: StringName = pick["species"]
	var variant: int = pick["variant"]
	var size := VisualScale.tree_size(species, variant)
	var model := TreeField.model_size(species, variant)
	var width := maxf(model.x, model.z) * size
	var narrow := clampf(
		MapScale.to_units(float(values["forest_crown_width_m"])) / maxf(width, 1.0e-6), 0.2, 1.0
	)
	var s: float = tree["scale"] * size
	var h: float = tree["height_scale"] * size
	var basis := (
		Basis(Vector3.UP, tree["yaw"]) * Basis.from_scale(Vector3(s * narrow, h, s * narrow))
	)
	var p: Vector3 = tree["position"]
	return Transform3D(basis, Vector3(p.x, p.y - sink, p.z))


static func _chunk_rect(chunk: Vector2i, size: float) -> Rect2:
	return Rect2(Vector2(chunk) * size, Vector2.ONE * size)


static func _chunk_origin(rect: Rect2, y: float) -> Vector3:
	var c := rect.get_center()
	return Vector3(c.x, y, c.y)


## Full trees of a chunk: {"count", "low", "high", "groups": [{species, variant, buffer, count}]}.
## Pure.
func _plan_full(chunk: Vector2i) -> Dictionary:
	var rect := _chunk_rect(chunk, FULL_CHUNK)
	var sink := TreeField.sink(&"pine", _values)
	var trees: Array = []
	for tree: Dictionary in _fill.plan_rect(rect, _ground):
		trees.append([tree, tree, _fill_transform(tree, tree, sink, _values)])
	var low := INF
	var high := -INF
	for entry: Array in trees:
		var y: float = (entry[2] as Transform3D).origin.y
		low = minf(low, y)
		high = maxf(high, y)
	var origin := _chunk_origin(rect, 0.0 if trees.is_empty() else 0.5 * (low + high))
	var groups: Dictionary = {}
	for entry: Array in trees:
		var pick: Dictionary = entry[1]
		var key := "%s_%d" % [pick["species"], pick["variant"]]
		var t: Transform3D = entry[2]
		var group: Dictionary = (
			groups
			. get_or_add(
				key,
				{
					"species": pick["species"],
					"variant": pick["variant"],
					"local": [] as Array[Transform3D],
					"customs": [],
				}
			)
		)
		(group["local"] as Array[Transform3D]).append(Transform3D(t.basis, t.origin - origin))
		(group["customs"] as Array).append(pick["custom"])
	var keys := groups.keys()
	keys.sort()
	var sorted: Array = []
	for key: String in keys:
		var group: Dictionary = groups[key]
		(
			sorted
			. append(
				{
					"species": group["species"],
					"variant": group["variant"],
					"count": (group["local"] as Array).size(),
					"buffer": TreeField.instance_buffer(group["local"], group["customs"]),
				}
			)
		)
	return {"count": trees.size(), "low": low, "high": high, "origin": origin, "groups": sorted}


func _build_full(chunk: Vector2i, plan: Dictionary) -> void:
	_free_full(chunk)
	var nodes: Array[MultiMeshInstance3D] = []
	for group: Dictionary in plan["groups"]:
		var species: StringName = group["species"]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_custom_data = true
		multi.mesh = TreeMeshes.lod0(species, group["variant"])
		multi.instance_count = group["count"]
		multi.buffer = group["buffer"]
		var node := MultiMeshInstance3D.new()
		node.name = "Forest_%d_%d_%s_%d" % [chunk.x, chunk.y, species, group["variant"]]
		node.multimesh = multi
		node.material_override = _full_materials[species]
		node.position = plan["origin"]
		node.set_meta(&"species", species)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.visible = false
		add_child(node)
		_buffers[node] = group["buffer"]
		nodes.append(node)
	_full[chunk] = {
		"nodes": nodes, "count": plan["count"], "low": plan["low"], "high": plan["high"]
	}
	_burn_nodes(nodes)
	if _camera != Vector3.INF:
		update(_camera)


func _free_full(chunk: Vector2i) -> void:
	var entry: Dictionary = _full.get(chunk, {})
	if entry.is_empty():
		return
	for node: MultiMeshInstance3D in entry["nodes"]:
		_buffers.erase(node)
		remove_child(node)
		node.queue_free()
	_full.erase(chunk)


## [full range, impostor range, per variant Vector2(crown width, height) at tree scale 1] of a
## species (`crown`: forest_crown_width_m in world units) – the numbers _fill_transform works with.
func _impostor_species_data(species: StringName, crown: float) -> Array:
	var height_m := VegetationRanges.species_height_m(species)
	var sizes: Array = []
	for variant in TreeMeshes.VARIANTS:
		var size := VisualScale.tree_size(species, variant)
		var model := TreeField.model_size(species, variant)
		var natural := maxf(model.x, model.z) * size
		sizes.append(Vector2(minf(natural, crown), model.y * size))
	return [
		VegetationRanges.full_range(height_m, _values),
		VegetationRanges.impostor_range(height_m, _values),
		sizes,
	]


## The fill cells an impostor chunk draws (ForestFill.cells_of its rectangle).
func impostor_cells(chunk: Vector2i) -> Rect2i:
	return _fill.cells_of(_chunk_rect(chunk, IMPOSTOR_CHUNK))


## What the impostor shader draws for a chunk, by the GDScript reference: the trees of its cells
## (ForestFill.cell_tree, base at the lattice height minus _impostor_sink()). Pure; tests.
func impostor_trees(chunk: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cells := impostor_cells(chunk)
	var sink := _impostor_sink()
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			var tree := _fill.cell_tree(Vector2i(i, j))
			if not tree.is_empty():
				var p: Vector3 = tree["position"]
				tree["position"] = Vector3(p.x, p.y - sink, p.z)
				result.append(tree)
	return result


## Main thread, < 0.5 ms: one node with the shared MultiMesh, its cell range as an instance
## uniform and its bounds from the lattice heights. Chunks without forest on the stand mask get
## no node.
func _build_impostors(chunk: Vector2i, _plan: Variant) -> void:
	_free_impostors(chunk)
	_set_covered(chunk, true)
	if not _forest_chunks.has(chunk):
		return
	var rect := _chunk_rect(chunk, IMPOSTOR_CHUNK)
	var cells := impostor_cells(chunk)
	var span := _height_span(rect)
	var node := MultiMeshInstance3D.new()
	node.name = "ForestImpostors_%d_%d" % [chunk.x, chunk.y]
	node.multimesh = _impostor_multimesh
	node.material_override = _impostor_material
	node.position = Vector3(rect.position.x, 0.0, rect.position.y)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = _max_impostor + IMPOSTOR_CHUNK
	# Quads reach past the chunk border (a quad turns with the camera: the larger of its height and
	# width, with margin); the picture starts below_base x its height under the sunk base.
	var margin := maxf(_tallest, _widest) * 0.7
	var bottom := span.x - _impostor_sink() - TreeImpostors.BELOW_BASE * _tallest
	node.custom_aabb = AABB(
		Vector3(-margin, bottom, -margin),
		Vector3(
			IMPOSTOR_CHUNK + 2.0 * margin, span.y + _tallest - bottom, IMPOSTOR_CHUNK + 2.0 * margin
		)
	)
	node.set_instance_shader_parameter(
		&"cells", Vector4(cells.position.x, cells.position.y, cells.size.x, cells.size.y)
	)
	node.set_meta(&"chunk", chunk)
	add_child(node)
	_impostors[chunk] = node


## Lowest (x) and highest (y) lattice height over `rect`.
func _height_span(rect: Rect2) -> Vector2:
	var step := TerrainLattice.STEP
	var lo := ((rect.position - _height_origin) / step).floor()
	var hi := ((rect.end - _height_origin) / step).ceil()
	var i0 := clampi(int(lo.x), 0, _height_size.x - 1)
	var i1 := clampi(int(hi.x), 0, _height_size.x - 1)
	var j0 := clampi(int(lo.y), 0, _height_size.y - 1)
	var j1 := clampi(int(hi.y), 0, _height_size.y - 1)
	var result := Vector2(INF, -INF)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var h := maxf(_heights[j * _height_size.x + i], TerrainSurface.WATER_SURFACE)
			result = Vector2(minf(result.x, h), maxf(result.y, h))
	return result


func _free_impostors(chunk: Vector2i) -> void:
	_set_covered(chunk, false)
	var node: MultiMeshInstance3D = _impostors.get(chunk)
	if node == null:
		return
	remove_child(node)
	node.queue_free()
	_impostors.erase(chunk)


func _set_covered(chunk: Vector2i, built: bool) -> void:
	if _coverage == null:
		return
	var p := chunk - _coverage_origin
	if p.x < 0 or p.y < 0 or p.x >= _coverage.get_width() or p.y >= _coverage.get_height():
		return
	_coverage.set_pixel(p.x, p.y, Color.WHITE if built else Color.BLACK)
	_coverage_dirty = true


## Whether the impostor chunk is built (the coverage mask the canopy shell reads).
func is_covered(chunk: Vector2i) -> bool:
	var p := chunk - _coverage_origin
	if _coverage == null or p.x < 0 or p.y < 0:
		return false
	if p.x >= _coverage.get_width() or p.y >= _coverage.get_height():
		return false
	return _coverage.get_pixel(p.x, p.y).r > 0.5


## Hands the coverage mask to the canopy shell's material (see `_coverage`).
func bind_shell(material: ShaderMaterial) -> void:
	if material == null or _coverage_texture == null:
		return
	material.set_shader_parameter(&"coverage", _coverage_texture)
	material.set_shader_parameter(&"use_coverage", 1.0)
	material.set_shader_parameter(&"coverage_origin", Vector2(_coverage_origin) * IMPOSTOR_CHUNK)
	material.set_shader_parameter(
		&"coverage_extent", Vector2(_coverage.get_size()) * IMPOSTOR_CHUNK
	)


## The full-tree budget for a camera at `camera` (world): which full chunks are drawn and from
## which distance the impostors take over (see the class comment). Main thread, every frame.
func update(camera: Vector3) -> void:
	_camera = camera
	if _grid == null:
		return
	if _coverage_dirty:
		_coverage_dirty = false
		_coverage_texture.update(_coverage)
	var cap := int(_values["full_tree_cap"])
	var entries: Array[Vector2] = []
	var distances: Dictionary = {}
	for chunk: Vector2i in _full:
		# As the 32-bit float budget_reach compares and returns (a chunk at the reach is out).
		var d := Vector2(_distance(chunk, camera), 0.0).x
		distances[chunk] = d
		if d < _max_full:
			entries.append(Vector2(d, (_full[chunk] as Dictionary)["count"]))
	var reach := minf(VegetationRanges.budget_reach(entries, cap), _unbuilt_reach(camera))
	_visible_full = 0
	for chunk: Vector2i in _full:
		var entry: Dictionary = _full[chunk]
		var on: bool = distances[chunk] < minf(reach, _max_full)
		for node: MultiMeshInstance3D in entry["nodes"]:
			node.visible = on
		if on:
			_visible_full += int(entry["count"])
	_set_reach(reach)


## The nearest distance of a full chunk within the full range that is not built (its trees
## would otherwise be drawn by neither LOD), INF if there is none.
func _unbuilt_reach(camera: Vector3) -> float:
	var result := INF
	var first := Vector2i(
		floori((camera.x - _max_full) / FULL_CHUNK), floori((camera.z - _max_full) / FULL_CHUNK)
	)
	var last := Vector2i(
		floori((camera.x + _max_full) / FULL_CHUNK), floori((camera.z + _max_full) / FULL_CHUNK)
	)
	for x in range(first.x, last.x + 1):
		for z in range(first.y, last.y + 1):
			var chunk := Vector2i(x, z)
			if _full.has(chunk) or not _chunk_rect(chunk, FULL_CHUNK).intersects(_area):
				continue
			var rect := _chunk_rect(chunk, FULL_CHUNK)
			var flat := Vector2(camera.x, camera.z)
			var d := flat.distance_to(flat.clamp(rect.position, rect.end))
			if d < _max_full:
				result = minf(result, d)
	return result


## Distance from the camera to the nearest tree base a full chunk can hold.
func _distance(chunk: Vector2i, camera: Vector3) -> float:
	var entry: Dictionary = _full[chunk]
	var rect := _chunk_rect(chunk, FULL_CHUNK)
	var flat := Vector2(camera.x, camera.z)
	var dxz := flat.distance_to(flat.clamp(rect.position, rect.end))
	if int(entry["count"]) == 0:
		return dxz
	var dy := camera.y - clampf(camera.y, entry["low"], entry["high"])
	return sqrt(dxz * dxz + dy * dy)


func _set_reach(reach: float) -> void:
	var cap := minf(reach, NO_CAP)
	_reach = reach
	if is_equal_approx(cap, _applied_cap):
		return
	_applied_cap = cap
	for material: ShaderMaterial in _full_materials.values():
		material.set_shader_parameter(&"lod_cap", cap)
	if _impostor_material != null:
		_impostor_material.set_shader_parameter(&"full_reach", cap)


## The budget's reach of the last update() (INF: every full chunk in range is drawn).
func reach() -> float:
	return _reach


## Full trees submitted by the last update() (the visible full chunks' instances).
func visible_full_count() -> int:
	return _visible_full


## Full nodes of the built chunks (visible or not).
func full_nodes() -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for entry: Dictionary in _full.values():
		result.append_array(entry["nodes"])
	return result


func impostor_nodes() -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for node: MultiMeshInstance3D in _impostors.values():
		result.append(node)
	return result


## World positions of the trees of one of this field's nodes (tree bases): a full node's
## instances, or what the shader draws for an impostor node (impostor_trees, all bands).
func instance_positions(node: MultiMeshInstance3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	if node.has_meta(&"chunk"):
		for tree in impostor_trees(node.get_meta(&"chunk")):
			result.append(tree["position"])
		return result
	var buffer: PackedFloat32Array = _buffers.get(node, PackedFloat32Array())
	for k in range(0, buffer.size(), TreeField.BUFFER_STRIDE):
		result.append(node.position + Vector3(buffer[k + 3], buffer[k + 7], buffer[k + 11]))
	return result


## Remembers a burnt circle (BurntGround): burns the built full nodes it touches and hands it to
## the impostor shader. The field keeps the last MAX_BURNS circles for both (full chunks built
## later and the impostors); an older circle stays burnt only on full chunks built before it
## dropped out.
func burn(center: Vector2, radius: float) -> void:
	_burns.append(Vector3(center.x, radius, center.y))
	if _burns.size() > MAX_BURNS:
		_burns.pop_front()
	_burn_nodes(full_nodes())
	_push_burns()


func _burn_nodes(nodes: Array) -> void:
	for burn_circle in _burns:
		BurntGround.burn_instances(nodes, Vector2(burn_circle.x, burn_circle.z), burn_circle.y)


func _push_burns() -> void:
	if _impostor_material == null:
		return
	var circles := PackedVector4Array()
	circles.resize(MAX_BURNS)
	for n in _burns.size():
		var c := _burns[n]
		circles[n] = Vector4(c.x, c.z, c.y, 0.0)
	_impostor_material.set_shader_parameter(&"burns", circles)
	_impostor_material.set_shader_parameter(&"burn_count", _burns.size())


## The burnt circles the impostor shader keeps free (x, z, radius), oldest first.
func impostor_burns() -> PackedVector4Array:
	var result := PackedVector4Array()
	if _impostor_material == null:
		return result
	var circles: PackedVector4Array = _impostor_material.get_shader_parameter(&"burns")
	for n in int(_impostor_material.get_shader_parameter(&"burn_count")):
		result.append(circles[n])
	return result
