class_name GrassNear
extends Node3D
## Real-density grass close to the camera (TASK-135, ADR 0026; `true` VisualScale preset only):
## at real size a grass clump is 0.3-1 m, so GrassField's ~1 clump per 230 m² reads as bare ground
## up close. Within LookPreset.vegetation() "near_grass_range_m" of the camera this layer plants
## "near_grass_per_m2" clumps per m² of meadow (other terrain by GrassPlanner's density ratio:
## forest floor, fields, hills), with GrassField's clump mesh, materials, kinds and ground colours.
## A ChunkLayer ("grass_near") of MapView's camera-centred ChunkManager: small chunks around the
## camera's ground point, planned on the worker threads, each a MultiMesh hidden beyond the range
## (Godot's dithered range fade over the last RANGE_FADE share).
## Placement is deterministic without a random number generator: one jittered point per grid cell,
## its values integer hashes of (GrassField.SEED, cell) (ForestFill.unit); the clump stands on the
## drawn near surface (the TerrainSurface the caller passes).

const LAYER := &"grass_near"
const CHUNK := 0.25
const POINT_SALT := 0x6A55
const RANGE_FADE := 0.2

var _grass: GrassField
var _grid: HexGrid
var _surface: TerrainSurface
var _area := Rect2()
var _range := 0.0
var _spacing := 0.0
## Vector2i chunk -> Array[MultiMeshInstance3D].
var _chunks: Dictionary = {}
var _instances := 0
var _buffers: Dictionary = {}


## `grass` is the set-up GrassField (mesh, materials, colours, clearings), `surface` the drawn near
## surface, `area` the playable rectangle.
func setup(grass: GrassField, grid: HexGrid, surface: TerrainSurface, area: Rect2) -> void:
	clear()
	_grass = grass
	_grid = grid
	_surface = surface
	_area = area
	var values := LookPreset.vegetation()
	_range = MapScale.to_units(float(values["near_grass_range_m"]))
	_spacing = MapScale.to_units(1.0 / sqrt(float(values["near_grass_per_m2"])))


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_chunks.clear()
	_buffers.clear()
	_instances = 0


func chunk_layer() -> ChunkLayer:
	var result := ChunkLayer.new(LAYER, CHUNK, _area, build_chunk, free_chunk, plan_chunk)
	result.prepare = prepare
	return result


func prepare() -> void:
	_surface.prime()
	FeatureRibbonPlanner.is_clear(_grid, 0.0, 0.0)


## The draw range (world units, from the camera).
func draw_range() -> float:
	return _range


## The clumps of a chunk: [{position, yaw, scale, tint, kind, height}] (GrassPlanner.clump_at).
## Pure.
func plan_items(chunk: Vector2i) -> Array:
	var result: Array = []
	var rect := Rect2(Vector2(chunk) * CHUNK, Vector2.ONE * CHUNK)
	var look := _grass.clump_look()
	var meadow: Dictionary = look["meadow"]
	var parcels: ParcelMap = look["parcels"]
	var keeps := GrassPlanner.parcel_keeps(parcels)
	var a := _spacing
	var first := Vector2i((rect.position / a).floor())
	var last := Vector2i((rect.end / a).ceil())
	for j in range(first.y, last.y + 1):
		for i in range(first.x, last.x + 1):
			var h := ScatterPlanner.tile_seed(GrassField.SEED, Vector2i(i, j), POINT_SALT)
			var x := (i + 0.5 + 0.9 * (ForestFill.unit(h, 0) - 0.5)) * a
			var z := (j + 0.5 + 0.9 * (ForestFill.unit(h, 1) - 0.5)) * a
			if x < rect.position.x or x >= rect.end.x or z < rect.position.y or z >= rect.end.y:
				continue
			var clump := GrassPlanner.clump_at(
				x,
				z,
				ForestFill.unit(h, 2) * TAU,
				ForestFill.unit(h, 3),
				ForestFill.unit(h, 4),
				ForestFill.unit(h, 5),
				false,
				_grid,
				_surface,
				meadow,
				parcels,
				keeps
			)
			if not clump.is_empty():
				result.append(clump)
	return result


## {"grass": {"items", "buffer"}, "reeds": {"items", "buffer"}, "origin"}. Pure.
func plan_chunk(chunk: Vector2i) -> Dictionary:
	var clumps: Array = []
	var reeds: Array = []
	var total_y := 0.0
	for g: Dictionary in plan_items(chunk):
		total_y += (g["position"] as Vector3).y
		if g["kind"] == GrassPlanner.Kind.REED:
			reeds.append(g)
		else:
			clumps.append(g)
	var centre := (Vector2(chunk) + Vector2.ONE * 0.5) * CHUNK
	var count := clumps.size() + reeds.size()
	var origin := Vector3(centre.x, total_y / maxi(count, 1), centre.y)
	var cells := {}
	return {
		"origin": origin,
		"grass": {"items": clumps, "buffer": _grass.instance_buffer(clumps, origin, cells, false)},
		"reeds": {"items": reeds, "buffer": _grass.instance_buffer(reeds, origin, cells, true)},
	}


func build_chunk(chunk: Vector2i, plan: Dictionary) -> void:
	free_chunk(chunk)
	var origin: Vector3 = plan["origin"]
	var nodes: Array[MultiMeshInstance3D] = []
	for kind: String in ["grass", "reeds"]:
		var part: Dictionary = plan[kind]
		var items: Array = part["items"]
		var buffer: PackedFloat32Array = part["buffer"]
		var kept := items.filter(
			func(item: Dictionary) -> bool: return not _grass.is_cleared(item["position"])
		)
		if kept.size() != items.size():
			buffer = _grass.instance_buffer(kept, origin, {}, kind == "reeds")
		if kept.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = _grass.clump_look()["mesh"]
		multi.instance_count = kept.size()
		multi.buffer = buffer
		var node := MultiMeshInstance3D.new()
		node.name = "NearGrass_%s_%d_%d" % [kind, chunk.x, chunk.y]
		node.multimesh = multi
		node.material_override = _grass.clump_look()["reeds" if kind == "reeds" else "grass"]
		node.position = origin
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.layers = MapView.GRASS_LAYER_MASK
		node.visibility_range_end = _range
		node.visibility_range_end_margin = _range * RANGE_FADE
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(node)
		_buffers[node] = buffer
		_instances += kept.size()
		nodes.append(node)
	_chunks[chunk] = nodes


func free_chunk(chunk: Vector2i) -> void:
	for node: MultiMeshInstance3D in _chunks.get(chunk, []):
		_instances -= node.multimesh.instance_count
		_buffers.erase(node)
		remove_child(node)
		node.queue_free()
	_chunks.erase(chunk)


func instance_count() -> int:
	return _instances


func nodes() -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for list: Array in _chunks.values():
		result.append_array(list)
	return result


## World positions of the clumps of one of this layer's nodes.
func instance_positions(node: MultiMeshInstance3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	var buffer: PackedFloat32Array = _buffers.get(node, PackedFloat32Array())
	for k in range(0, buffer.size(), GrassField.STRIDE):
		result.append(node.position + Vector3(buffer[k + 3], buffer[k + 7], buffer[k + 11]))
	return result
