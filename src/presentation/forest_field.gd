class_name ForestField
extends Node3D
## The dense real-scale forest (TASK-135, ADR 0026; only under the `true` VisualScale preset): the
## ForestFill trees (with ScatterPlanner's planned trees ~2 000 per forest hex), drawn two ways:
##
## - The full 3D trees (TASK-221, ADR 0027 amendment 2): ForestFullTrees. A compute pass derives
##   the tree of every cell around the camera every frame, exactly as the impostors do (the same
##   point, species, variant, size, yaw and colour: assets/shaders/forest_cells.glsl, the reference
##   of which is full_trees_around), and appends the ones inside their species' full range
##   (VegetationRanges, scaled by the species' height, `full_tree_range_m` at most) to the lists of
##   15 MultiMeshes, one per model. Nothing is planned on the CPU; a tree costs the vertices of its
##   own model. Each tree is drawn up to its own point of the per-tree hand-over band (band_share),
##   the impostors take it from there, judged by the distance of the impostor's base so exactly one
##   of the two draws it.
## - "forest" (IMPOSTOR_CHUNK chunks, on the camera-target ChunkManager): GPU-placed impostors
##   (TASK-189, ADR 0027), `instant` chunks of MapView: assets/shaders/forest_impostor.gdshader
##   derives every tree from its cell, from the full range to the impostor range, where the canopy
##   shell (ForestShell) takes over.
##
## Without a RenderingDevice (headless, Compatibility) there are no full trees: the impostors take
## the trees from the camera on.

const IMPOSTOR_LAYER := &"forest"
## Key of the full trees' on / off state in RealScaleVegetation (they are not a chunk layer).
const FULL_TREES := &"forest_full"
const IMPOSTOR_CHUNK := 2.0
## The drawn near surface lies up to ~3 m off the lattice the full trees' bounds are built from (m).
const HEIGHT_SLACK_M := 4.0
## Tallest height scale of a tree (ForestFill: scale 1.2 x height factor 1.2) and widest crown
## scale.
const MAX_HEIGHT_SCALE := 1.44
const MAX_WIDTH_SCALE := 1.2
## Burnt circles the field keeps (full trees and impostors alike; the oldest drop out beyond
## this): a battle leaves a few dozen wrecks. The shader's `burns` array has this size.
const MAX_BURNS := 128

var _grid: HexGrid
var _fill: ForestFill
var _seed := 0
var _area := Rect2()
var _values: Dictionary = {}
## The largest full band end of any species (world units), at most the range cap's band.
var _max_full := 0.0
var _max_impostor := 0.0
## The GPU full trees' range (world units, the centre of their band).
var _full_cap := 0.0
## The full trees' compute field (null before setup) and per species (TreeSpecies.all() order) the
## centre of its full band (world units).
var _full: ForestFullTrees
var _species_centres := PackedFloat32Array()
## The drawn near heights the full trees stand on (null: they stand on the lattice).
var _near_heights: NearHeightCache
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
var _impostor_material: ShaderMaterial
var _camera := Vector3.INF
var _burns: Array[Vector3] = []
## Built impostor chunks as a mask over the area (one pixel per chunk, 255 = built) for the canopy
## shell: over a chunk not built yet the shell stays drawn at any distance, so a forest whose
## impostors are not there yet shows as canopy, never as bare ground.
var _coverage: Image
var _coverage_texture: ImageTexture
var _coverage_dirty := false
var _coverage_origin := Vector2i.ZERO


## Prepares the field for a map: `lattice` the drawn terrain lattice (its heights decide which cells
## hold a tree and carry the impostors), `area` the rectangle the forest may cover (the playable
## mesh). `look` (TASK-108g): the forest stands on the land-cover raster's forest instead of the
## forest hexes. The full trees stand on the drawn near surface once use_near_heights() is given.
func setup(
	grid: HexGrid,
	seed_value: int,
	area: Rect2,
	lattice: TerrainLattice,
	parcels: ParcelMap = null,
	look: CoverLook = null
) -> void:
	clear()
	_grid = grid
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
	# The GPU full trees end at their range cap (LookPreset `full_tree_range_m`): no chunk beyond.
	_full_cap = MapScale.to_units(float(_values["full_tree_range_m"]))
	_max_full = minf(_max_full, _full_cap * (1.0 + float(_values["band_share"])))
	_setup_impostors(lattice)
	_setup_full_trees()
	_coverage_origin = Vector2i(
		floori(area.position.x / IMPOSTOR_CHUNK), floori(area.position.y / IMPOSTOR_CHUNK)
	)
	var last := Vector2i(floori(area.end.x / IMPOSTOR_CHUNK), floori(area.end.y / IMPOSTOR_CHUNK))
	var cells := last - _coverage_origin + Vector2i.ONE
	_coverage = Image.create(cells.x, cells.y, false, Image.FORMAT_L8)
	_coverage_texture = ImageTexture.create_from_image(_coverage)
	_coverage_dirty = false


## The impostor material with the map's textures and tables, the shared MultiMesh and the impostor
## chunks that touch forest.
func _setup_impostors(lattice: TerrainLattice) -> void:
	_impostor_material = TreeImpostors.material(_values["band_share"], TreeImpostors.FOREST_SHADER)
	_impostor_material.set_shader_parameter(&"full_cap", _full_cap)
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


## The full trees (TASK-221 and ADR 0027 amendment 2): the compute field (ForestFullTrees) that
## appends the trees of the cells around the camera to the lists of 15 MultiMeshes, one per model.
## Needs the impostor material (_setup_impostors): its map uniforms are the compute pass's.
func _setup_full_trees() -> void:
	TreeField.prime_sizes()
	var data: Array = []
	var top := 0.0
	_species_centres.clear()
	for species in TreeSpecies.all():
		var scales: Array = []
		for variant in TreeMeshes.VARIANTS:
			var factors := _variant_scale(species, variant, _values)
			scales.append(factors)
			var model := TreeField.model_size(species, variant)
			top = maxf(top, model.y * factors.y * MAX_HEIGHT_SCALE)
		var centre := VegetationRanges.full_range(
			VegetationRanges.species_height_m(species), _values
		)
		_species_centres.append(centre)
		data.append({"centre": centre, "scales": scales})
	_full = ForestFullTrees.new()
	_full.setup(
		self,
		_impostor_material,
		data,
		_full_cap,
		float(_values["band_share"]),
		TreeField.sink(&"pine", _values),
		_impostor_sink(),
		_height_span(_area),
		top,
		MapScale.to_units(HEIGHT_SLACK_M)
	)
	_full.use_near_heights(_near_heights)
	if not _full.gpu():
		# No compute pass here: the impostors take the trees from the camera on.
		_impostor_material.set_shader_parameter(&"full_cap", 0.0)


## The full trees stand on the drawn near surface of `cache` (null: on the lattice).
## update_near() keeps the cache's window on the camera target.
func use_near_heights(cache: NearHeightCache) -> void:
	_near_heights = cache
	if _full != null:
		_full.use_near_heights(cache)


## The base height of a full tree at (x, z) as the shader reads it: the near window's drawn
## surface where a near chunk is built, else the lattice.
func drawn_ground(x: float, z: float) -> float:
	if _near_heights != null:
		var h := _near_heights.height_at(x, z)
		if not is_nan(h):
			return h
	return _fill.lattice_height(x, z)


## Model-to-world scale of a species' variant at tree scale 1 as the full trees use it: x = z =
## real size (VisualScale.tree_size) with the crown narrowed to forest_crown_width_m, y = the real
## size. The shader's `variant_scale`.
static func _variant_scale(species: StringName, variant: int, values: Dictionary) -> Vector2:
	var size := VisualScale.tree_size(species, variant)
	var model := TreeField.model_size(species, variant)
	var width := maxf(model.x, model.z) * size
	var narrow := clampf(
		MapScale.to_units(float(values["forest_crown_width_m"])) / maxf(width, 1.0e-6), 0.2, 1.0
	)
	return Vector2(size * narrow, size)


## The full trees around `camera` by the GDScript reference of forest_cells.glsl:
## ForestFill.cell_tree of the cells in the compute window whose impostor-base distance is inside
## the tree's own point of its species' band (capped by the range cap; the impostors' hand-over),
## off the burnt circles,
## standing on drawn_ground() sunk by the tree sink, plus the model-to-world `transform` the pass
## builds. Pure; tests.
func full_trees_around(camera: Vector3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var reach := _full.reach()
	var spacing := _fill.spacing
	var first := Vector2i(
		floori((camera.x - reach) / spacing - 0.5), floori((camera.z - reach) / spacing - 0.5)
	)
	var last := Vector2i(
		ceili((camera.x + reach) / spacing - 0.5), ceili((camera.z + reach) / spacing - 0.5)
	)
	var sink := TreeField.sink(&"pine", _values)
	var band := float(_values["band_share"])
	var species_list := TreeSpecies.all()
	for j in range(first.y, last.y + 1):
		for i in range(first.x, last.x + 1):
			var tree := _fill.cell_tree(Vector2i(i, j))
			if tree.is_empty():
				continue
			var p: Vector3 = tree["position"]
			var phase: float = (tree["custom"] as Color).a
			var centre: float = _species_centres[species_list.find(tree["species"])]
			var lod_to := minf(
				lerpf(centre * (1.0 - band), centre * (1.0 + band), phase),
				lerpf(_full_cap * (1.0 - band), _full_cap * (1.0 + band), phase)
			)
			if Vector3(p.x, p.y - _impostor_sink(), p.z).distance_to(camera) >= lod_to:
				continue
			if _is_burnt(p.x, p.z):
				continue
			tree["position"] = Vector3(p.x, drawn_ground(p.x, p.z), p.z)
			tree["transform"] = _fill_transform(tree, tree, sink, _values)
			tree["position"] = (tree["transform"] as Transform3D).origin
			result.append(tree)
	return result


func _is_burnt(x: float, z: float) -> bool:
	for c in _burns:
		if Vector2(x, z).distance_to(Vector2(c.x, c.z)) <= c.y:
			return true
	return false


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	if _full != null:
		_full.free_all()
	_full = null
	_species_centres.clear()
	_near_heights = null
	_impostors.clear()
	_burns.clear()
	# Nothing of the previous map survives (setup() builds it all again).
	_grid = null
	_fill = null
	_forest_chunks.clear()
	_impostor_multimesh = null
	_impostor_material = null
	_heights = PackedFloat32Array()
	_height_size = Vector2i.ZERO
	_coverage = null
	_coverage_texture = null
	_coverage_dirty = false
	_camera = Vector3.INF


## The GPU-placed impostors: an instant layer (no plan, the chunk is built in the scan).
func impostor_layer() -> ChunkLayer:
	var result := ChunkLayer.new(
		IMPOSTOR_LAYER, IMPOSTOR_CHUNK, _area, _build_impostors, _free_impostors
	)
	result.instant = true
	return result


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
	var factors := _variant_scale(pick["species"], pick["variant"], values)
	var s: float = tree["scale"] * factors.x
	var h: float = tree["height_scale"] * factors.y
	var basis := Basis(Vector3.UP, tree["yaw"]) * Basis.from_scale(Vector3(s, h, s))
	var p: Vector3 = tree["position"]
	return Transform3D(basis, Vector3(p.x, p.y - sink, p.z))


static func _chunk_rect(chunk: Vector2i, size: float) -> Rect2:
	return Rect2(Vector2(chunk) * size, Vector2.ONE * size)


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
	# TASK-201a (ADR 0030): the impostors cast, turned to the sun in the shadow pass
	# (tree_impostor_view.gdshaderinc impostor_facing), so forest edges throw a stable shadow.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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


## The camera is at `camera` (world): the compute pass of the full trees runs for it (main thread,
## every frame).
func update(camera: Vector3) -> void:
	_camera = camera
	if _grid == null:
		return
	if _coverage_dirty:
		_coverage_dirty = false
		_coverage_texture.update(_coverage)
	_full.update(camera, _burns)


## Switches the GPU full trees on (the camera is low enough to see trees within their range) or off.
func set_full_active(on: bool) -> void:
	if _full != null:
		_full.set_active(on)


## The full trees' compute field (null before setup).
func full_trees_field() -> ForestFullTrees:
	return _full


func impostor_nodes() -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for node: MultiMeshInstance3D in _impostors.values():
		result.append(node)
	return result


## Remembers a burnt circle (BurntGround): hands it to the full-tree and impostor shaders. The
## field keeps the last MAX_BURNS circles; an older circle no longer burns.
func burn(center: Vector2, radius: float) -> void:
	_burns.append(Vector3(center.x, radius, center.y))
	if _burns.size() > MAX_BURNS:
		_burns.pop_front()
	_push_burns()


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
