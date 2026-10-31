class_name GrassField
extends Node3D
## The grass of a MapView (TASK-057): one MultiMeshInstance3D per GrassPlanner chunk, built
## lazily the first time the camera target comes within BUILD_RADIUS of the chunk (at most
## `chunks_per_frame` per frame) and kept. A chunk is hidden beyond RANGE from the camera and
## fades out over the visibility_range_end_margin MARGIN around that distance (Godot dithers the
## fade; the exact start of the margin was not measured). The range is measured from the chunk
## node's origin, which sits at the chunk centre, so whole chunks pop in and out of range, not
## single clumps. Grass casts no shadows. Meadow flowers (TASK-070) are a second MultiMesh node per
## chunk ("Flowers_<x>_<z>") with the same ranges.

const SEED := 7919
const RANGE := 14.0
const MARGIN := 3.0
const BUILD_RADIUS := 20.0
## The pending chunks are only rescanned after the target moved this far (or a chunk was built).
const RESCAN_DISTANCE := 0.5
## Instance-colour range of the per-clump tint, and the cell size of the cached ground colour.
const COLOR_CELL := 0.5
const CARD_WIDTH := 0.07
const CARD_HEIGHT := 0.05
const CARD_SIZE := 128
const CARD_SEED := 31
const FLOWER_CARD_SEED := 43
## Upper bound of the flower share of a plains area, for the instance estimate only.
const FLOWER_ESTIMATE_SHARE := 0.3
const SHADER := preload("res://assets/shaders/grass.gdshader")

var chunks_per_frame := 1

var _grid: HexGrid
var _surface: TerrainSurface
var _density := 0.0
## Callable(position: Vector3) -> Color: the linear ground colour under a clump (evaluated once
## per COLOR_CELL cell of a chunk).
var _color_of: Callable
var _mesh: ArrayMesh
var _material: ShaderMaterial
var _flower_material: ShaderMaterial
## LookPreset.meadow() of the last setup.
var _meadow: Dictionary = {}
## Vector2i chunk -> flower MultiMeshInstance3D (only chunks that have flowers).
var _flower_chunks: Dictionary = {}
## Vector2i chunk -> MultiMeshInstance3D (null for a chunk without clumps), chunks built so far.
var _chunks: Dictionary = {}
var _pending: Array[Vector2i] = []
var _instances := 0
## Bare ground (burnt around wrecks): Vector3(x, radius, z) – no clump or flower grows inside.
var _clearings: Array[Vector3] = []
var _target := Vector2.ZERO
var _has_target := false
var _scan_needed := false
var _scanned_target := Vector2.ZERO


## Prepares the field for a map. `requested` is the quality density; it is cut so that the whole
## map stays within GrassPlanner.INSTANCE_BUDGET. `map_rect` covers the playable tiles.
func setup(
	grid: HexGrid,
	surface: TerrainSurface,
	map_rect: Rect2,
	requested: float,
	color_of: Callable,
	budget: int = GrassPlanner.INSTANCE_BUDGET
) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_grid = grid
	_surface = surface
	_color_of = color_of
	_chunks.clear()
	_flower_chunks.clear()
	_pending.clear()
	_clearings.clear()
	_instances = 0
	_density = 0.0
	_scan_needed = true
	if requested <= 0.0:
		return
	var estimate := _estimate(requested)
	_density = requested
	if estimate > budget:
		_density = requested * budget / estimate
		push_warning("Grass density cut to %.2f to stay in the instance budget" % _density)
	assert(_estimate(_density) <= budget * 1.001, "grass instance budget exceeded")
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
	_pending = GrassPlanner.chunks_covering(map_rect)


## Height of the tallest clump (largest random scale, the largest height multiplier of the active
## meadow, current VisualScale) plus the wind sway.
static func max_clump_height() -> float:
	var meadow := LookPreset.meadow()
	var tallest := maxf(
		maxf(meadow["tall_height"], meadow["dry_stalk_height"]),
		maxf(meadow["nettle_height"], (meadow["flower_height"] as Vector2).y)
	)
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


## Keeps the ground within `radius` of `center` (XZ) bare: chunks not built yet skip it, built
## chunks it touches are dropped and planned again.
func add_clearing(center: Vector2, radius: float) -> void:
	_clearings.append(Vector3(center.x, radius, center.y))
	if _density <= 0.0:
		return
	var area := Rect2(center - Vector2.ONE * radius, Vector2.ONE * 2.0 * radius)
	for chunk: Vector2i in GrassPlanner.chunks_covering(area):
		var built := _chunks.has(chunk) or _flower_chunks.has(chunk)
		_drop_chunk(chunk)
		if built and not _pending.has(chunk):
			_pending.append(chunk)
	_scan_needed = true


## True when `position` (XZ plane) lies inside one of the clearings.
func is_cleared(position: Vector3) -> bool:
	for clearing in _clearings:
		if Vector2(position.x - clearing.x, position.z - clearing.z).length() < clearing.y:
			return true
	return false


func _drop_chunk(chunk: Vector2i) -> void:
	for chunks: Dictionary in [_chunks, _flower_chunks]:
		var node: MultiMeshInstance3D = chunks.get(chunk)
		if node != null:
			_instances -= node.multimesh.instance_count
			node.free()
		chunks.erase(chunk)


func _without_cleared(items: Array) -> Array:
	if _clearings.is_empty():
		return items
	return items.filter(func(item: Dictionary) -> bool: return not is_cleared(item["position"]))


func set_target(target: Vector2) -> void:
	_target = target
	if not _has_target or target.distance_to(_scanned_target) > RESCAN_DISTANCE:
		_scan_needed = true
	_has_target = true


func instance_count() -> int:
	return _instances


## The flower nodes built so far (chunks without flowers have none).
func flower_nodes() -> Array[MultiMeshInstance3D]:
	var nodes: Array[MultiMeshInstance3D] = []
	for node: Variant in _flower_chunks.values():
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


func _process(_delta: float) -> void:
	update(chunks_per_frame)


## True when every chunk within BUILD_RADIUS of the target is built.
func is_settled() -> bool:
	return _density <= 0.0 or not _has_target or not _scan_needed


## Builds up to `max_chunks` pending chunks within BUILD_RADIUS of the target, nearest first.
func update(max_chunks: int) -> void:
	if _density <= 0.0 or not _has_target or not _scan_needed:
		return
	_scanned_target = _target
	for i in max_chunks:
		var best := -1
		var best_distance := BUILD_RADIUS
		for k in _pending.size():
			var d := _chunk_distance(_pending[k])
			if d <= best_distance:
				best_distance = d
				best = k
		if best < 0:
			_scan_needed = false
			return
		var chunk := _pending[best]
		_pending.remove_at(best)
		_chunks[chunk] = _build_chunk(chunk)


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
	return total * area * density


func _chunk_distance(chunk: Vector2i) -> float:
	var rect := GrassPlanner.chunk_rect(chunk)
	var nearest := _target.clamp(rect.position, rect.end)
	return nearest.distance_to(_target)


func _build_chunk(chunk: Vector2i) -> MultiMeshInstance3D:
	var flowers := _without_cleared(
		GrassPlanner.plan_flowers(chunk, _grid, _surface, SEED, _density, _meadow)
	)
	if not flowers.is_empty():
		_flower_chunks[chunk] = _build_flowers(chunk, flowers)
	var clumps := _without_cleared(
		GrassPlanner.plan_chunk(chunk, _grid, _surface, SEED, _density, _meadow)
	)
	if clumps.is_empty():
		return null
	var rect := GrassPlanner.chunk_rect(chunk)
	var origin := Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	var multi := _new_multimesh(clumps.size())
	var cells := {}
	for i in clumps.size():
		var g: Dictionary = clumps[i]
		var p: Vector3 = g["position"]
		multi.set_instance_transform(i, clump_transform(g, origin))
		var cell := Vector2i((Vector2(p.x, p.z) / COLOR_CELL).floor())
		if not cells.has(cell):
			cells[cell] = _color_of.call(p)
		multi.set_instance_color(
			i, GrassPlanner.kind_color(g["kind"], cells[cell], g["tint"], _meadow)
		)
	var instance := _new_instance("Grass_%d_%d" % [chunk.x, chunk.y], multi, _material, origin)
	_instances += clumps.size()
	return instance


## Transform of a planned clump relative to the chunk node at `origin`: yaw, then the scale
## (s, s * height, s) – the vertical multiplier of tall grass, stalks, nettle and flowers.
static func clump_transform(g: Dictionary, origin: Vector3) -> Transform3D:
	var s: float = g["scale"]
	var h: float = g["height"]
	var basis := Basis(Vector3.UP, g["yaw"]) * Basis.from_scale(Vector3(s, s * h, s))
	return Transform3D(basis, (g["position"] as Vector3) - origin)


func _build_flowers(chunk: Vector2i, flowers: Array) -> MultiMeshInstance3D:
	var rect := GrassPlanner.chunk_rect(chunk)
	var origin := Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	var multi := _new_multimesh(flowers.size())
	for i in flowers.size():
		var f: Dictionary = flowers[i]
		multi.set_instance_transform(i, clump_transform(f, origin))
		multi.set_instance_color(i, (f["color"] as Color).srgb_to_linear())
	_instances += flowers.size()
	return _new_instance("Flowers_%d_%d" % [chunk.x, chunk.y], multi, _flower_material, origin)


func _new_multimesh(count: int) -> MultiMesh:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = _mesh
	multi.instance_count = count
	return multi


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
