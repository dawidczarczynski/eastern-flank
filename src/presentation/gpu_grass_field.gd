class_name GpuGrassField
extends Node3D
## The GPU-placed near grass of the real-scale countryside (TASK-217b, ADR 0033; only under the
## `true` VisualScale preset and the HIGH quality): real clump cards (GrassMesh, the three cards of
## GrassField: grass, flowers, reeds) within `grass_range_m` (LookPreset.vegetation(), 40 m) of the
## camera. Nothing is planned on the CPU: one `instant` GpuVegetationLayer on MapView's
## camera-centred ChunkManager derives every clump from its grid cell in the vertex shader
## (grass_gpu.gdshader, GrassRules is its GDScript reference). A chunk is one node sharing one
## MultiMesh of identity instances, one per cell, whose mesh carries one surface per card kind; the
## cell's kind picks the surface that draws it. Beyond the ring there is no instance: the terrain
## shader's own grass tone carries the ground (TerrainGround.set_grass_tone).
## The masks, the lattice heights and the drawn near heights are the shrubs' (ShrubField).

const LAYER := &"grass_gpu"
## Chunk size (world units): 18 m at the default scale, so the ring wastes few cells.
const CHUNK := 0.125
const SHADER := preload("res://assets/shaders/grass_gpu.gdshader")
## Share of the ring where the clumps start to thin out.
const FADE_FROM := 0.6
## Burnt circles kept (as ShrubField).
const MAX_BURNS := 128
## The drawn near terrain lies up to ~3 m off the lattice the bounds are built from (metres).
const HEIGHT_SLACK_M := 4.0
## Card kinds (the surfaces, grass_gpu.gdshader `mode`).
const MODES := 3

var rules: GrassRules

var _shrubs: ShrubField
var _layer: GpuVegetationLayer
var _materials: Array[ShaderMaterial] = []
var _multimesh: MultiMesh
var _ring_m := 0.0
var _burns: Array[Vector3] = []
var _tallest := 0.0
var _widest := 0.0


## Prepares the grass over the maps of `shrubs` (a set-up ShrubField: masks, lattice heights, the
## drawn near heights). `ground_colours` are the linear average colours [grass layer, dry grass
## layer] of the ground textures, `satellite` the map's SatelliteColour (null: none), `quality` the
## GraphicsQuality features: without "gpu_grass" nothing is built. Returns whether the layer exists.
func setup(
	shrubs: ShrubField,
	seed_value: int,
	parcels: ParcelMap,
	ground_colours: Array,
	satellite: SatelliteColour,
	quality: Dictionary
) -> bool:
	clear()
	if shrubs == null or shrubs.rules == null or not bool(quality.get("gpu_grass", true)):
		return false
	_shrubs = shrubs
	var values := LookPreset.vegetation()
	_ring_m = float(values["grass_range_m"])
	var lattice := shrubs.lattice()
	rules = GrassRules.new(
		shrubs.masks, lattice.mesh_height_at, lattice.origin, seed_value, parcels, values
	)
	_setup_materials(ground_colours, satellite)
	var scale_k := VisualScale.grass_scale()
	var width := GrassField.CARD_WIDTH * scale_k
	var height := GrassField.CARD_HEIGHT * scale_k
	var mesh := ArrayMesh.new()
	var source := GrassMesh.clump(width, height)
	for m in _materials:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(0))
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)
	_multimesh = GpuVegetationLayer.identity_multimesh(
		mesh, VegetationHash.max_cells(CHUNK, rules.spacing)
	)
	var meadow := LookPreset.meadow()
	var tallest_k := maxf(
		maxf(float(meadow["tall_height"]), float(meadow["dry_stalk_height"])),
		maxf(float(meadow["nettle_height"]), float(meadow["reed_height"]))
	)
	tallest_k = maxf(tallest_k, (meadow["flower_height"] as Vector2).y)
	_tallest = (
		height * (GrassPlanner.SCALE_MIN + GrassPlanner.SCALE_RANGE) * maxf(tallest_k, 1.0)
		+ Wind.MAX_OFFSET
	)
	_widest = width * (GrassPlanner.SCALE_MIN + GrassPlanner.SCALE_RANGE) + rules.spacing
	_layer = GpuVegetationLayer.new()
	_layer.id = LAYER
	_layer.chunk_size = CHUNK
	_layer.area = shrubs.masks.area
	_layer.spacing = rules.spacing
	# The chunk manager builds within build_factor x the reach: the build ring is the grass ring.
	_layer.reach_m = _ring_m / ChunkRings.load_default().build_factor
	_layer.parent = self
	_layer.name_prefix = "Grass"
	_layer.layers = MapView.GRASS_LAYER_MASK
	_layer.visibility_end = MapScale.to_units(_ring_m) + CHUNK * 1.5
	_layer.bounds = _bounds
	_layer.multimesh_for = func(_chunk: Vector2i) -> MultiMesh: return _multimesh
	_push_burns()
	return true


func _setup_materials(ground_colours: Array, satellite: SatelliteColour) -> void:
	var meadow := LookPreset.meadow()
	var cards: Array[Image] = [
		GrassTexture.card(GrassField.CARD_SIZE, GrassField.CARD_SEED),
		GrassTexture.flower_card(GrassField.CARD_SIZE, GrassField.FLOWER_CARD_SEED),
		GrassTexture.reed_card(GrassField.CARD_SIZE, GrassField.REED_CARD_SEED),
	]
	var grass: Color = ground_colours[0]
	var dry: Color = ground_colours[1]
	var cache := _shrubs.near_heights()
	_materials.clear()
	for mode in MODES:
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter(&"card", ImageTexture.create_from_image(cards[mode]))
		m.set_shader_parameter(&"mode", mode)
		m.set_shader_parameter(&"ground_grass", Vector3(grass.r, grass.g, grass.b))
		m.set_shader_parameter(&"ground_dry", Vector3(dry.r, dry.g, dry.b))
		m.set_shader_parameter(&"grass_reach", MapScale.to_units(_ring_m))
		m.set_shader_parameter(&"fade_from", FADE_FROM)
		if mode == 1:
			m.set_shader_parameter(
				&"stem_color", (meadow["flower_stem_color"] as Color).srgb_to_linear()
			)
		_shrubs.bind_terrain(m)
		rules.bind(m)
		SatelliteColour.apply(m, satellite)
		if cache != null:
			cache.bind(m)
		_materials.append(m)


## Culling bounds of a chunk (node frame: origin at its corner): the lattice heights under it
## (and the drawn near terrain's slack), the tallest clump, the widest clump and a cell around.
func _bounds(rect: Rect2) -> AABB:
	var span := _shrubs.height_range(rect)
	var slack := MapScale.to_units(HEIGHT_SLACK_M)
	var bottom := span.x - slack
	var top := span.y + slack + _tallest
	return AABB(
		Vector3(-_widest, bottom, -_widest),
		Vector3(rect.size.x + 2.0 * _widest, top - bottom, rect.size.y + 2.0 * _widest)
	)


## The grass ring in metres (LookPreset.vegetation() "grass_range_m"; 0 when not built).
func ring_m() -> float:
	return _ring_m if _layer != null else 0.0


## The draw ring in world units.
func ring() -> float:
	return MapScale.to_units(ring_m())


func is_built() -> bool:
	return _layer != null


func layer() -> GpuVegetationLayer:
	return _layer


func chunk_layer() -> ChunkLayer:
	return _layer.chunk_layer() if _layer != null else null


func nodes() -> Array[MultiMeshInstance3D]:
	return _layer.nodes() if _layer != null else ([] as Array[MultiMeshInstance3D])


func materials() -> Array[ShaderMaterial]:
	return _materials


## What the shader draws for a chunk, by the GDScript reference: the clumps of its cells
## (GrassRules.cell_clump). Pure; tests.
func chunk_clumps(chunk: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cells := _layer.cells(chunk)
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			var clump := rules.cell_clump(Vector2i(i, j))
			if not clump.is_empty():
				result.append(clump)
	return result


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_layer = null
	rules = null
	_multimesh = null
	_materials.clear()
	_burns.clear()
	_shrubs = null
	_ring_m = 0.0


## Remembers a burnt circle (BurntGround): no clump grows in it.
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
	for m in _materials:
		m.set_shader_parameter(&"burns", circles)
		m.set_shader_parameter(&"burn_count", _burns.size())
