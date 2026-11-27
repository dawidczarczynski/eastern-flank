class_name ShrubField
extends Node3D
## The GPU-placed shrubs of the real-scale countryside (TASK-217a, ADR 0033; only under the `true`
## VisualScale preset): forest edges and clearings, hedges, field edges and roadsides, river and
## marsh banks, heath and sparse meadow scrub, in four kinds (ShrubRules). Nothing is planned on
## the CPU: two `instant` GpuVegetationLayers on MapView's camera-centred ChunkManager derive every
## shrub from its grid cell in the vertex shader.
##
## - "shrubs_near" (NEAR_CHUNK chunks): the real LOD0 model of the kind's source species
##   (shrub_mesh.gdshader over foliage_body.gdshaderinc), up to `shrub_mesh_range_m`. One node per
##   chunk: identity instances (one per cell) of a mesh with one surface per source species of the
##   chunk's model variant (the juniper's only where the chunk has heath).
## - "shrubs" (IMPOSTOR_CHUNK chunks): impostor quads with the baked atlas of the same model
##   (shrub_impostor.gdshader, TreeImpostors' atlas and lighting) from the mesh range to
##   `shrub_impostor_range_m` (LookPreset.vegetation()), capped by the quality's `shrub_range_m`
##   (GraphicsQuality: LOW 150 m). Nothing beyond: the ground carries the far view.
## Each shrub hands over from mesh to impostor at its own point of the band around the mesh range
## (the forest's `band_share`), so exactly one of the two draws it.

const NEAR_LAYER := &"shrubs_near"
const IMPOSTOR_LAYER := &"shrubs"
const NEAR_CHUNK := 0.25
const IMPOSTOR_CHUNK := 2.0
## Burnt circles kept (as ForestField).
const MAX_BURNS := 128
const SHADER_MESH := preload("res://assets/shaders/shrub_mesh.gdshader")
const SHADER_IMPOSTOR := preload("res://assets/shaders/shrub_impostor.gdshader")
const DEFAULT_RANGE_M := 600.0

var rules: ShrubRules
var masks: VegetationMasks

var _values: Dictionary = {}
var _near: GpuVegetationLayer
var _far: GpuVegetationLayer
var _mesh_reach := 0.0
var _impostor_reach := 0.0
var _range_m := 0.0
var _sink := 0.0
var _band := 0.08
## Source index -> mesh material; impostor material.
var _mesh_materials: Array[ShaderMaterial] = []
var _impostor_material: ShaderMaterial
## "<variant>:<juniper>" -> shared identity MultiMesh of the combined source meshes.
var _near_multimeshes: Dictionary = {}
var _impostor_multimesh: MultiMesh
var _heights := PackedFloat32Array()
var _height_origin := Vector2.ZERO
var _height_size := Vector2i.ZERO
var _height_texture: ImageTexture
var _lattice: TerrainLattice
var _burns: Array[Vector3] = []
## The drawn near heights (null: the shrubs stand on the lattice everywhere).
var _near_heights: NearHeightCache


## Prepares the shrubs of a map over `area`: `lattice` the drawn terrain lattice (heights of the
## shrubs, as the forest impostors), `fill` the forest's ForestFill (its stand mask gives the forest
## edges; null: no forest), `land_cover` (heath, marsh, built-up land), `parcels` (crop interiors,
## balks, hedges), `quality` the GraphicsQuality features (its `shrub_range_m`).
func setup(
	grid: HexGrid,
	lattice: TerrainLattice,
	seed_value: int,
	area: Rect2,
	parcels: ParcelMap,
	land_cover: LandCover,
	fill: ForestFill,
	quality: Dictionary,
	ready_masks: VegetationMasks = null
) -> void:
	clear()
	masks = ready_masks
	if masks == null:
		masks = VegetationMasks.from_map(grid, area, fill, land_cover, parcels)
	setup_with(masks, lattice, seed_value, parcels, quality)


## As setup() with ready masks (tests: synthetic maps).
func setup_with(
	vegetation_masks: VegetationMasks,
	lattice: TerrainLattice,
	seed_value: int,
	parcels: ParcelMap,
	quality: Dictionary
) -> void:
	clear()
	masks = vegetation_masks
	_values = LookPreset.vegetation()
	rules = ShrubRules.new(masks, lattice.mesh_height_at, seed_value, parcels, _values, NEAR_CHUNK)
	_band = float(_values["band_share"])
	_range_m = minf(
		float(_values["shrub_impostor_range_m"]),
		float(quality.get("shrub_range_m", DEFAULT_RANGE_M))
	)
	_mesh_reach = MapScale.to_units(float(_values["shrub_mesh_range_m"]))
	_impostor_reach = MapScale.to_units(_range_m)
	_sink = MapScale.to_units(float(_values["shrub_sink_m"]))
	var heights := ForestFill.height_image(lattice)
	_heights = heights.get_data().to_float32_array()
	_height_origin = lattice.origin
	_height_size = heights.get_size()
	_lattice = lattice
	_height_texture = ImageTexture.create_from_image(heights)
	_setup_materials(lattice, _height_texture)
	_near = _layer(NEAR_LAYER, NEAR_CHUNK, masks.area, float(_values["shrub_mesh_range_m"]))
	_near.name_prefix = "ShrubsNear"
	_near.multimesh_for = _near_multimesh
	_near.visibility_end = _mesh_reach * (1.0 + _band) + NEAR_CHUNK * 1.5
	_near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_far = _layer(IMPOSTOR_LAYER, IMPOSTOR_CHUNK, masks.area, _range_m)
	_far.name_prefix = "ShrubImpostors"
	_far.material = _impostor_material
	_far.multimesh_for = func(_chunk: Vector2i) -> MultiMesh: return _impostor_multimesh
	_far.visibility_end = _impostor_reach * (1.0 + _band) + IMPOSTOR_CHUNK * 1.5
	_impostor_multimesh = GpuVegetationLayer.bare_multimesh(
		TreeImpostors.mesh(), VegetationHash.max_cells(IMPOSTOR_CHUNK, rules.spacing)
	)
	_push_burns()


func _layer(id: StringName, size: float, area: Rect2, reach_m: float) -> GpuVegetationLayer:
	var layer := GpuVegetationLayer.new()
	layer.id = id
	layer.chunk_size = size
	layer.area = area
	layer.spacing = rules.spacing
	layer.reach_m = reach_m
	layer.parent = self
	layer.bounds = _bounds
	return layer


func _setup_materials(lattice: TerrainLattice, heights: ImageTexture) -> void:
	TreeField.prime_sizes()
	var kind_source := PackedInt32Array(ShrubRules.KIND_SOURCE)
	_mesh_materials.clear()
	for n in ShrubRules.SOURCES.size():
		var species := ShrubRules.SOURCES[n]
		var m := TreeField.new_material(species, TreeField.Lod.NEAR)
		m.shader = SHADER_MESH
		_bind_common(m, lattice, heights, kind_source)
		m.set_shader_parameter(&"placed_source", n)
		var sizes := PackedVector2Array()
		for variant in TreeMeshes.VARIANTS:
			var model := TreeField.model_size(species, variant)
			sizes.append(Vector2(maxf(model.x, model.z), model.y))
		m.set_shader_parameter(&"placed_sizes", sizes)
		m.set_shader_parameter(&"hand_over_share", _band)
		_mesh_materials.append(m)
	_impostor_material = TreeImpostors.material(_band, SHADER_IMPOSTOR)
	_bind_common(_impostor_material, lattice, heights, kind_source)
	var source_sizes := PackedVector4Array()
	var leaves := PackedVector3Array()
	for species in ShrubRules.SOURCES:
		for variant in TreeMeshes.VARIANTS:
			var model := TreeField.model_size(species, variant)
			var row := TreeImpostors.row(species, variant)
			source_sizes.append(
				Vector4(maxf(model.x, model.z), model.y, float(row[0]), float(row[1]))
			)
		var leaf := TreeImpostors.leaf_color(species)
		leaves.append(Vector3(leaf.r, leaf.g, leaf.b))
	_impostor_material.set_shader_parameter(&"source_sizes", source_sizes)
	_impostor_material.set_shader_parameter(&"source_leaf", leaves)
	_impostor_material.set_shader_parameter(&"impostor_reach", _impostor_reach)


## Binds the lattice heights (the drawn terrain lattice, as the shrubs read it) to a material that
## includes shrub_rules.gdshaderinc (the GPU grass, TASK-217b): heights, height_origin,
## height_step, height_cells, water_surface.
func bind_terrain(m: ShaderMaterial) -> void:
	m.set_shader_parameter(&"heights", _height_texture)
	m.set_shader_parameter(&"height_origin", _lattice.origin)
	m.set_shader_parameter(&"height_step", TerrainLattice.STEP)
	m.set_shader_parameter(&"height_cells", _lattice.cells)
	m.set_shader_parameter(&"water_surface", TerrainSurface.WATER_SURFACE)


## The drawn terrain lattice of the last setup (null before).
func lattice() -> TerrainLattice:
	return _lattice


## Lowest (x) and highest (y) lattice height over `rect`.
func height_range(rect: Rect2) -> Vector2:
	return GpuVegetationLayer.height_span(
		_heights,
		_height_origin,
		_height_size,
		TerrainLattice.STEP,
		rect,
		TerrainSurface.WATER_SURFACE
	)


func _bind_common(
	m: ShaderMaterial, lattice: TerrainLattice, heights: ImageTexture, kind_source: PackedInt32Array
) -> void:
	rules.bind(m)
	m.set_shader_parameter(&"heights", heights)
	m.set_shader_parameter(&"height_origin", lattice.origin)
	m.set_shader_parameter(&"height_step", TerrainLattice.STEP)
	m.set_shader_parameter(&"height_cells", lattice.cells)
	m.set_shader_parameter(&"water_surface", TerrainSurface.WATER_SURFACE)
	m.set_shader_parameter(&"kind_source", kind_source)
	m.set_shader_parameter(&"mesh_reach", _mesh_reach)
	m.set_shader_parameter(&"sink", _sink)


## The shared MultiMesh of a near chunk: its model variant, with the juniper's surface only where
## the chunk has heath.
func _near_multimesh(chunk: Vector2i) -> MultiMesh:
	var variant := rules.chunk_variant(chunk)
	var rect := _near.chunk_rect(chunk).grow(rules.spacing)
	var juniper := masks.has_code(rect, VegetationMasks.Habitat.HEATH)
	var key := "%d:%s" % [variant, juniper]
	if not _near_multimeshes.has(key):
		var mesh := ArrayMesh.new()
		for n in ShrubRules.SOURCES.size():
			if n == ShrubRules.KIND_SOURCE[ShrubRules.Kind.JUNIPER] and not juniper:
				continue
			var source := TreeMeshes.lod0(ShrubRules.SOURCES[n], variant)
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(0))
			mesh.surface_set_material(mesh.get_surface_count() - 1, _mesh_materials[n])
		_near_multimeshes[key] = GpuVegetationLayer.identity_multimesh(
			mesh, VegetationHash.max_cells(NEAR_CHUNK, rules.spacing)
		)
	return _near_multimeshes[key]


## Culling bounds of a chunk (node frame: origin at its corner): the lattice heights under it,
## the tallest shrub and the widest crown (a quad turns with the camera).
func _bounds(rect: Rect2) -> AABB:
	var span := GpuVegetationLayer.height_span(
		_heights,
		_height_origin,
		_height_size,
		TerrainLattice.STEP,
		rect,
		TerrainSurface.WATER_SURFACE
	)
	var tallest := MapScale.to_units(ShrubRules.KIND_HEIGHT_M[ShrubRules.Kind.WILLOW].y)
	var margin := tallest * 1.5
	var bottom := span.x - _sink - TreeImpostors.BELOW_BASE * tallest - margin * 0.1
	var top := span.y + tallest * TreeImpostors.VERTICAL_SPAN
	return AABB(
		Vector3(-margin, bottom, -margin),
		Vector3(rect.size.x + 2.0 * margin, top - bottom, rect.size.y + 2.0 * margin)
	)


func near_layer() -> ChunkLayer:
	return _near.chunk_layer()


func impostor_layer() -> ChunkLayer:
	return _far.chunk_layer()


## The mesh / impostor hand-over (x) and the impostor end (y), metres.
func ranges_m() -> Vector2:
	return Vector2(float(_values.get("shrub_mesh_range_m", 0.0)), _range_m)


func near_nodes() -> Array[MultiMeshInstance3D]:
	return _near.nodes() if _near != null else ([] as Array[MultiMeshInstance3D])


func impostor_nodes() -> Array[MultiMeshInstance3D]:
	return _far.nodes() if _far != null else ([] as Array[MultiMeshInstance3D])


## The GpuVegetationLayers (near, far).
func layers() -> Array[GpuVegetationLayer]:
	return [_near, _far]


## What the shaders draw for a chunk of `layer`, by the GDScript reference: the shrubs of its
## cells (ShrubRules.cell_shrub). Pure; tests.
func chunk_shrubs(layer: GpuVegetationLayer, chunk: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cells := layer.cells(chunk)
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			var shrub := rules.cell_shrub(Vector2i(i, j))
			if not shrub.is_empty():
				result.append(shrub)
	return result


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	if _near != null:
		_near = null
	_far = null
	rules = null
	_near_multimeshes.clear()
	_impostor_multimesh = null
	_impostor_material = null
	_mesh_materials.clear()
	_burns.clear()
	_near_heights = null
	_height_texture = null
	_lattice = null


## Shrubs near the camera target stand on the drawn near terrain (TASK-217a): `cache` follows
## TerrainNear's chunks; update_near() keeps its window on the target.
func use_near_heights(cache: NearHeightCache) -> void:
	_near_heights = cache
	if cache == null:
		return
	for m in _mesh_materials:
		cache.bind(m)
	if _impostor_material != null:
		cache.bind(_impostor_material)


## Main thread, once a frame: the near height window follows the camera target.
func update_near(target: Vector2) -> void:
	if _near_heights != null:
		_near_heights.update(target)


func near_heights() -> NearHeightCache:
	return _near_heights


## Remembers a burnt circle (BurntGround): no shrub stands in it on either layer.
func burn(center: Vector2, radius: float) -> void:
	_burns.append(Vector3(center.x, radius, center.y))
	if _burns.size() > MAX_BURNS:
		_burns.pop_front()
	_push_burns()


func _push_burns() -> void:
	var circles := PackedVector4Array()
	circles.resize(MAX_BURNS)
	for n in _burns.size():
		var c := _burns[n]
		circles[n] = Vector4(c.x, c.z, c.y, 0.0)
	var materials: Array[ShaderMaterial] = _mesh_materials.duplicate()
	if _impostor_material != null:
		materials.append(_impostor_material)
	for m in materials:
		m.set_shader_parameter(&"burns", circles)
		m.set_shader_parameter(&"burn_count", _burns.size())
