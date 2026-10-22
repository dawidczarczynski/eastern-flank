class_name GrassField
extends Node3D
## The grass of a MapView (TASK-057): one MultiMeshInstance3D per GrassPlanner chunk, built
## lazily the first time the camera target comes within BUILD_RADIUS of the chunk (at most
## `chunks_per_frame` per frame) and kept. A chunk is hidden beyond RANGE from the camera and
## fades out over the visibility_range_end_margin MARGIN around that distance (Godot dithers the
## fade; the exact start of the margin was not measured). The range is measured from the chunk
## node's origin, which sits at the chunk centre, so whole chunks pop in and out of range, not
## single clumps. Grass casts no shadows.

const SEED := 7919
const RANGE := 14.0
const MARGIN := 3.0
const BUILD_RADIUS := 20.0
## The pending chunks are only rescanned after the target moved this far (or a chunk was built).
const RESCAN_DISTANCE := 0.5
## Instance-colour range of the per-clump tint, and the cell size of the cached ground colour.
const TINT_MIN := 0.85
const TINT_MAX := 1.1
const COLOR_CELL := 0.5
const CARD_WIDTH := 0.07
const CARD_HEIGHT := 0.05
const CARD_SIZE := 128
const CARD_SEED := 31
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
## Vector2i chunk -> MultiMeshInstance3D (null for a chunk without clumps), chunks built so far.
var _chunks: Dictionary = {}
var _pending: Array[Vector2i] = []
var _instances := 0
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
	_pending.clear()
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
	_pending = GrassPlanner.chunks_covering(map_rect)


## Height of the tallest clump (largest random scale, current VisualScale) plus the wind sway.
static func max_clump_height() -> float:
	return (
		(
			CARD_HEIGHT
			* VisualScale.grass_scale()
			* (GrassPlanner.SCALE_MIN + GrassPlanner.SCALE_RANGE)
		)
		+ Wind.MAX_OFFSET
	)


func is_active() -> bool:
	return _density > 0.0


## The density actually used (the requested one, cut back to the instance budget).
func density() -> float:
	return _density


func set_target(target: Vector2) -> void:
	_target = target
	if not _has_target or target.distance_to(_scanned_target) > RESCAN_DISTANCE:
		_scan_needed = true
	_has_target = true


func instance_count() -> int:
	return _instances


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
		match _grid.get_terrain(c):
			Terrain.Type.PLAINS:
				total += GrassPlanner.PLAINS_DENSITY
			Terrain.Type.HILLS:
				total += GrassPlanner.HILLS_DENSITY
			Terrain.Type.FOREST:
				total += GrassPlanner.FOREST_DENSITY
	return total * 1.5 * Hex.SQRT3 * TerrainField.HEX_SIZE * TerrainField.HEX_SIZE * density


func _chunk_distance(chunk: Vector2i) -> float:
	var rect := GrassPlanner.chunk_rect(chunk)
	var nearest := _target.clamp(rect.position, rect.end)
	return nearest.distance_to(_target)


func _build_chunk(chunk: Vector2i) -> MultiMeshInstance3D:
	var clumps := GrassPlanner.plan_chunk(chunk, _grid, _surface, SEED, _density)
	if clumps.is_empty():
		return null
	# The node sits at the chunk centre: the visibility range measures from the node's origin.
	var rect := GrassPlanner.chunk_rect(chunk)
	var origin := Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = _mesh
	multi.instance_count = clumps.size()
	var cells := {}
	for i in clumps.size():
		var g: Dictionary = clumps[i]
		var p: Vector3 = g["position"]
		var s: float = g["scale"]
		var basis := Basis(Vector3.UP, g["yaw"]) * Basis.from_scale(Vector3(s, s, s))
		multi.set_instance_transform(i, Transform3D(basis, p - origin))
		var cell := Vector2i((Vector2(p.x, p.z) / COLOR_CELL).floor())
		if not cells.has(cell):
			cells[cell] = _color_of.call(p)
		var k := lerpf(TINT_MIN, TINT_MAX, g["tint"])
		var base: Color = cells[cell]
		multi.set_instance_color(i, Color(base.r * k, base.g * k, base.b * k))
	var instance := MultiMeshInstance3D.new()
	instance.name = "Grass_%d_%d" % [chunk.x, chunk.y]
	instance.multimesh = multi
	instance.material_override = _material
	instance.position = origin
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = RANGE
	instance.visibility_range_end_margin = MARGIN
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(instance)
	_instances += clumps.size()
	return instance
