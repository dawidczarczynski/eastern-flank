class_name GrassField
extends Node3D
## The grass of a MapView (TASK-057): one MultiMeshInstance3D per GrassPlanner chunk. Since
## TASK-072b the chunks are a layer of MapView's ChunkManager ("grass" ring): planned on the
## worker threads (clumps, their ground colours and the MultiMesh buffers: `plan_chunk`), made
## into nodes on the main thread (`build_chunk`) and freed again beyond the free ring
## (`free_chunk`). A chunk is hidden beyond RANGE from the camera and fades out over the
## visibility_range_end_margin MARGIN around that distance (Godot dithers the fade). The range is
## measured from the chunk node's origin, which sits at the chunk centre, so whole chunks pop in
## and out of range, not single clumps. Grass casts no shadows. Meadow flowers (TASK-070) are a
## second MultiMesh node per chunk ("Flowers_<x>_<z>") with the same ranges; reeds (TASK-108e)
## likewise ("Reeds_<x>_<z>", own card).

const SEED := 7919
const RANGE := 14.0
const MARGIN := 3.0
## Instance-colour range of the per-clump tint, and the cell size of the cached ground colour.
const COLOR_CELL := 0.5
const CARD_WIDTH := 0.07
const CARD_HEIGHT := 0.05
const CARD_SIZE := 128
const CARD_SEED := 31
const FLOWER_CARD_SEED := 43
const REED_CARD_SEED := 47
## Upper bound of the flower share of a plains area, for the instance estimate only.
const FLOWER_ESTIMATE_SHARE := 0.3
const SHADER := preload("res://assets/shaders/grass.gdshader")
## MultiMesh buffer floats per instance: TRANSFORM_3D (12) and the colour (4).
const STRIDE := 16
const KINDS: Array[String] = ["grass", "flowers", "reeds"]

var _grid: HexGrid
var _parcels: ParcelMap
var _surface: TerrainSurface
var _density := 0.0
## Callable(position: Vector3) -> Color: the linear ground colour under a clump (evaluated once
## per COLOR_CELL cell of a chunk, on the planning threads: it must only read).
var _color_of: Callable
var _mesh: ArrayMesh
var _material: ShaderMaterial
var _flower_material: ShaderMaterial
var _reed_material: ShaderMaterial
## LookPreset.meadow() of the last setup.
var _meadow: Dictionary = {}
## Vector2i chunk -> flower MultiMeshInstance3D (only chunks that have flowers).
var _flower_chunks: Dictionary = {}
## Vector2i chunk -> reed MultiMeshInstance3D (only chunks that have reeds).
var _reed_chunks: Dictionary = {}
## Vector2i chunk -> MultiMeshInstance3D (null for a chunk without clumps), the built chunks.
var _chunks: Dictionary = {}
var _instances := 0
## Bare ground (burnt around wrecks): Vector3(x, radius, z) – no clump or flower grows inside.
var _clearings: Array[Vector3] = []
## The playable tiles' rectangle of the last setup.
var _map_rect := Rect2()
## Callable(id: StringName, rect: Rect2): rebuilds the chunks a clearing touches
## (ChunkManager.invalidate); unset, the touched chunks are only dropped.
var _invalidate := Callable()


## Prepares the field for a map. `requested` is the quality density; it is cut so that the grass
## that can be built at once stays within GrassPlanner.INSTANCE_BUDGET: the whole map, or only
## `live_area` (world units², the free ring of the chunked world) of it when that is smaller.
## `map_rect` covers the playable tiles.
func setup(
	grid: HexGrid,
	surface: TerrainSurface,
	map_rect: Rect2,
	requested: float,
	color_of: Callable,
	budget: int = GrassPlanner.INSTANCE_BUDGET,
	parcels: ParcelMap = null,
	live_area := INF
) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_grid = grid
	_surface = surface
	_color_of = color_of
	_parcels = parcels
	_map_rect = map_rect
	_chunks.clear()
	_flower_chunks.clear()
	_reed_chunks.clear()
	_clearings.clear()
	_instances = 0
	_density = 0.0
	if requested <= 0.0:
		return
	var estimate := _estimate(requested)
	var map_area := (
		grid.coords().size() * 1.5 * Hex.SQRT3 * TerrainField.HEX_SIZE * TerrainField.HEX_SIZE
	)
	if live_area < map_area:
		estimate *= live_area / map_area
	_density = requested
	if estimate > budget:
		_density = requested * budget / estimate
		push_warning("Grass density cut to %.2f to stay in the instance budget" % _density)
	var scale_k := VisualScale.grass_scale()
	_mesh = GrassMesh.clump(CARD_WIDTH * scale_k, CARD_HEIGHT * scale_k)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(
		&"card", ImageTexture.create_from_image(GrassTexture.card(CARD_SIZE, CARD_SEED))
	)
	_meadow = LookPreset.meadow()
	_flower_material = ShaderMaterial.new()
	_flower_material.shader = SHADER
	_flower_material.set_shader_parameter(
		&"card",
		ImageTexture.create_from_image(GrassTexture.flower_card(CARD_SIZE, FLOWER_CARD_SEED))
	)
	_flower_material.set_shader_parameter(&"flower_mode", true)
	_flower_material.set_shader_parameter(
		&"stem_color", (_meadow["flower_stem_color"] as Color).srgb_to_linear()
	)
	_reed_material = ShaderMaterial.new()
	_reed_material.shader = SHADER
	_reed_material.set_shader_parameter(
		&"card", ImageTexture.create_from_image(GrassTexture.reed_card(CARD_SIZE, REED_CARD_SEED))
	)
	_reed_material.set_shader_parameter(&"reed_mode", true)


## The grass as a chunk layer ("grass" ring) over the playable tiles; `invalidate` is
## ChunkManager.invalidate, used by add_clearing.
func chunk_layer(invalidate := Callable()) -> ChunkLayer:
	_invalidate = invalidate
	var result := ChunkLayer.new(
		&"grass", GrassPlanner.CHUNK_SIZE, _map_rect, build_chunk, free_chunk, plan_chunk
	)
	result.prepare = prepare
	return result


## Main thread, before plans run on the worker threads: fills the lazy caches they read.
func prepare() -> void:
	_surface.prime()
	FeatureRibbonPlanner.is_clear(_grid, 0.0, 0.0)


## Height of the tallest clump (largest random scale, the largest height multiplier of the active
## meadow, current VisualScale) plus the wind sway.
static func max_clump_height() -> float:
	var meadow := LookPreset.meadow()
	var tallest := maxf(
		maxf(meadow["tall_height"], meadow["dry_stalk_height"]),
		maxf(meadow["nettle_height"], (meadow["flower_height"] as Vector2).y)
	)
	tallest = maxf(tallest, meadow["reed_height"])
	return (
		(
			CARD_HEIGHT
			* VisualScale.grass_scale()
			* (GrassPlanner.SCALE_MIN + GrassPlanner.SCALE_RANGE)
			* maxf(tallest, 1.0)
		)
		+ Wind.MAX_OFFSET
	)


func is_active() -> bool:
	return _density > 0.0


## The density actually used (the requested one, cut back to the instance budget).
func density() -> float:
	return _density


## Keeps the ground within `radius` of `center` (XZ) bare: chunks built later skip it, built
## chunks it touches are built again.
func add_clearing(center: Vector2, radius: float) -> void:
	_clearings.append(Vector3(center.x, radius, center.y))
	if _density <= 0.0:
		return
	var area := Rect2(center - Vector2.ONE * radius, Vector2.ONE * 2.0 * radius)
	if _invalidate.is_valid():
		_invalidate.call(&"grass", area)
		return
	for chunk: Vector2i in GrassPlanner.chunks_covering(area):
		free_chunk(chunk)


## True when `position` (XZ plane) lies inside one of the clearings.
func is_cleared(position: Vector3) -> bool:
	for clearing in _clearings:
		if Vector2(position.x - clearing.x, position.z - clearing.z).length() < clearing.y:
			return true
	return false


## Drops the nodes of `chunk`.
func free_chunk(chunk: Vector2i) -> void:
	for chunks: Dictionary in [_chunks, _flower_chunks, _reed_chunks]:
		var node: MultiMeshInstance3D = chunks.get(chunk)
		if node != null:
			_instances -= node.multimesh.instance_count
			remove_child(node)
			node.queue_free()
		chunks.erase(chunk)


func instance_count() -> int:
	return _instances


## The flower nodes built so far (chunks without flowers have none).
func flower_nodes() -> Array[MultiMeshInstance3D]:
	var nodes: Array[MultiMeshInstance3D] = []
	for node: Variant in _flower_chunks.values():
		nodes.append(node)
	return nodes


## The reed nodes built so far (chunks without reeds have none).
func reed_nodes() -> Array[MultiMeshInstance3D]:
	var nodes: Array[MultiMeshInstance3D] = []
	for node: Variant in _reed_chunks.values():
		nodes.append(node)
	return nodes


func chunk_nodes() -> Array[MultiMeshInstance3D]:
	var nodes: Array[MultiMeshInstance3D] = []
	for node: Variant in _chunks.values():
		if node != null:
			nodes.append(node)
	return nodes


func built_chunks() -> int:
	return _chunks.size()


## Builds every chunk of `rect` at once on this thread (tests, tools without a ChunkManager).
func build_rect(rect: Rect2) -> void:
	if _density <= 0.0:
		return
	for chunk in GrassPlanner.chunks_covering(rect):
		if not _chunks.has(chunk):
			build_chunk(chunk, plan_chunk(chunk))


## Clump estimate of the whole map at `density` from the terrain shares.
func _estimate(density: float) -> float:
	var total := 0.0
	for c in _grid.coords():
		total += GrassPlanner.density_of(_grid.get_terrain(c))
	var area := 1.5 * Hex.SQRT3 * TerrainField.HEX_SIZE * TerrainField.HEX_SIZE
	var meadow := LookPreset.meadow()
	for c in _grid.coords():
		if _grid.get_terrain(c) == Terrain.Type.PLAINS:
			total += float(meadow["flower_density"]) * FLOWER_ESTIMATE_SHARE
		elif _grid.get_terrain(c) == Terrain.Type.MARSH:
			total += GrassPlanner.PLAINS_DENSITY * (float(meadow["marsh_density"]) - 1.0)
	return total * area * density


## The planned flowers, reeds and clumps of a chunk with their MultiMesh buffers: {kind: {"items":
## planned dictionaries, "buffer": PackedFloat32Array}} for KINDS. Pure (reads the grid, surface,
## parcels, look and the colour callable only), so it runs on the worker threads.
func plan_chunk(chunk: Vector2i) -> Dictionary:
	if _density <= 0.0:
		return {}
	var flowers := GrassPlanner.plan_flowers(
		chunk, _grid, _surface, SEED, _density, _meadow, _parcels
	)
	var all := GrassPlanner.plan_chunk(chunk, _grid, _surface, SEED, _density, _meadow, _parcels)
	var clumps: Array = []
	var reeds: Array = []
	for g: Dictionary in all:
		if g["kind"] == GrassPlanner.Kind.REED:
			reeds.append(g)
		else:
			clumps.append(g)
	var origin := _chunk_origin(chunk)
	var cells := {}
	return {
		"grass": {"items": clumps, "buffer": _buffer(clumps, origin, cells, false)},
		"flowers": {"items": flowers, "buffer": _buffer(flowers, origin, cells, false, true)},
		"reeds": {"items": reeds, "buffer": _buffer(reeds, origin, cells, true)},
	}


## Adds the nodes of a planned chunk (main thread); clearings made after the plan are cut out here.
func build_chunk(chunk: Vector2i, plan: Dictionary) -> void:
	free_chunk(chunk)
	if plan.is_empty():
		return
	var origin := _chunk_origin(chunk)
	var rect := GrassPlanner.chunk_rect(chunk)
	var cleared := false
	for clearing in _clearings:
		var center := Vector2(clearing.x, clearing.z)
		if center.distance_to(center.clamp(rect.position, rect.end)) < clearing.y:
			cleared = true
	var nodes := {}
	for kind: String in KINDS:
		var part: Dictionary = plan[kind]
		var items: Array = part["items"]
		var buffer: PackedFloat32Array = part["buffer"]
		if cleared:
			items = items.filter(
				func(item: Dictionary) -> bool: return not is_cleared(item["position"])
			)
			buffer = _buffer(items, origin, {}, kind == "reeds", kind == "flowers")
		if items.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = _mesh
		multi.instance_count = items.size()
		multi.buffer = buffer
		var node_name := {"grass": "Grass", "flowers": "Flowers", "reeds": "Reeds"}[kind] as String
		var material := (
			_flower_material
			if kind == "flowers"
			else (_reed_material if kind == "reeds" else _material)
		)
		nodes[kind] = _new_instance(
			"%s_%d_%d" % [node_name, chunk.x, chunk.y], multi, material, origin
		)
		_instances += items.size()
	_chunks[chunk] = nodes.get("grass")
	if nodes.has("flowers"):
		_flower_chunks[chunk] = nodes["flowers"]
	if nodes.has("reeds"):
		_reed_chunks[chunk] = nodes["reeds"]


func _chunk_origin(chunk: Vector2i) -> Vector3:
	var rect := GrassPlanner.chunk_rect(chunk)
	return Vector3(rect.get_center().x, 0.0, rect.get_center().y)


## MultiMesh buffer (STRIDE floats per item: transform relative to `origin`, then the linear
## colour). Clumps and reeds take the ground colour (cached per COLOR_CELL in `cells`), reeds
## also the dryness; flowers their own colour.
func _buffer(
	items: Array, origin: Vector3, cells: Dictionary, reeds: bool, flowers := false
) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(items.size() * STRIDE)
	for i in items.size():
		var g: Dictionary = items[i]
		var t := clump_transform(g, origin)
		var color: Color
		if flowers:
			color = (g["color"] as Color).srgb_to_linear()
		else:
			var p: Vector3 = g["position"]
			var cell := Vector2i((Vector2(p.x, p.z) / COLOR_CELL).floor())
			if not cells.has(cell):
				cells[cell] = _color_of.call(p)
			var dry := GrassPlanner.dry_k(p.x, p.z) if reeds else -1.0
			color = (
				GrassPlanner.kind_color(g["kind"], cells[cell], g["tint"], _meadow, dry)
				if reeds
				else GrassPlanner.kind_color(g["kind"], cells[cell], g["tint"], _meadow)
			)
		var o := i * STRIDE
		var b := t.basis
		buffer[o] = b.x.x
		buffer[o + 1] = b.y.x
		buffer[o + 2] = b.z.x
		buffer[o + 3] = t.origin.x
		buffer[o + 4] = b.x.y
		buffer[o + 5] = b.y.y
		buffer[o + 6] = b.z.y
		buffer[o + 7] = t.origin.y
		buffer[o + 8] = b.x.z
		buffer[o + 9] = b.y.z
		buffer[o + 10] = b.z.z
		buffer[o + 11] = t.origin.z
		buffer[o + 12] = color.r
		buffer[o + 13] = color.g
		buffer[o + 14] = color.b
		buffer[o + 15] = color.a
	return buffer


## Transform of a planned clump relative to the chunk node at `origin`: yaw, then the scale
## (s, s * height, s) – the vertical multiplier of tall grass, stalks, nettle and flowers.
static func clump_transform(g: Dictionary, origin: Vector3) -> Transform3D:
	var s: float = g["scale"]
	var h: float = g["height"]
	var basis := Basis(Vector3.UP, g["yaw"]) * Basis.from_scale(Vector3(s, s * h, s))
	return Transform3D(basis, (g["position"] as Vector3) - origin)


## The node sits at the chunk centre: the visibility range measures from the node's origin.
func _new_instance(
	node_name: String, multi: MultiMesh, material: ShaderMaterial, origin: Vector3
) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi
	instance.material_override = material
	instance.position = origin
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.layers = MapView.GRASS_LAYER_MASK
	instance.visibility_range_end = RANGE
	instance.visibility_range_end_margin = MARGIN
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(instance)
	return instance
