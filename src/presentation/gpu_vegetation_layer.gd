class_name GpuVegetationLayer
extends RefCounted
## One GPU-placed vegetation chunk layer (TASK-217a, ADR 0033; generalised from the forest
## impostors of TASK-189 / ADR 0027): an `instant` ChunkLayer whose chunk is one
## MultiMeshInstance3D sharing a MultiMesh with one instance per grid cell of the largest chunk and
## no per-instance data (or, for meshes drawn in local space, one shared identity buffer). The
## chunk's first cell and cell counts are the instance uniform `cells`; the vertex shader derives
## every plant from its cell (vegetation_hash.gdshaderinc) and collapses the cells that hold none.
## Building a chunk is creating a node: no worker plan, no buffer, so a chunk exists the frame the
## camera reaches it. Culling bounds come from `bounds` (the lattice heights under the chunk).
##
## A layer is configured by its owner (ShrubField; 217b grass, 217c crops) and handed to a
## ChunkManager with chunk_layer().

## Ring id (ChunkRings / ChunkLayer.reach_m).
var id: StringName
var chunk_size := 1.0
var area := Rect2()
## Grid spacing of the cells (world units).
var spacing := 1.0
## Draw reach in metres for the chunk manager (ChunkLayer.reach_m; 0: ChunkRings).
var reach_m := 0.0
## Where the nodes go.
var parent: Node3D
var name_prefix := "Vegetation"
## Callable(chunk: Vector2i) -> MultiMesh: the shared MultiMesh a chunk draws (one per model
## variant, say); null skips the chunk (nothing can grow there).
var multimesh_for := Callable()
## The material every chunk node draws with (null: the mesh's own surface materials).
var material: Material
## Callable(rect: Rect2) -> AABB in the node's frame (origin at the chunk's corner).
var bounds := Callable()
var visibility_end := 0.0
var cast_shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
## The nodes' render layers (VisualInstance3D.layers).
var layers := 1
## Planning order on the manager (ChunkLayer.priority).
var priority := 0

## Vector2i chunk -> MultiMeshInstance3D.
var _nodes: Dictionary = {}


func chunk_layer() -> ChunkLayer:
	var result := ChunkLayer.new(id, chunk_size, area, build_chunk, free_chunk)
	result.instant = true
	result.priority = priority
	result.reach_m = reach_m
	return result


func chunk_rect(chunk: Vector2i) -> Rect2:
	return Rect2(Vector2(chunk) * chunk_size, Vector2.ONE * chunk_size)


## The cells a chunk draws (those whose centre lies in it).
func cells(chunk: Vector2i) -> Rect2i:
	return VegetationHash.cells_of(chunk_rect(chunk), spacing)


## Main thread: one node with the chunk's shared MultiMesh, its cells as an instance uniform.
func build_chunk(chunk: Vector2i, _plan: Variant = null) -> void:
	free_chunk(chunk)
	var multi: MultiMesh = multimesh_for.call(chunk)
	if multi == null:
		return
	var rect := chunk_rect(chunk)
	var range_cells := cells(chunk)
	var node := MultiMeshInstance3D.new()
	node.name = "%s_%d_%d" % [name_prefix, chunk.x, chunk.y]
	node.multimesh = multi
	if material != null:
		node.material_override = material
	node.position = Vector3(rect.position.x, 0.0, rect.position.y)
	node.cast_shadow = cast_shadow
	node.layers = layers
	if visibility_end > 0.0:
		node.visibility_range_end = visibility_end
	if bounds.is_valid():
		node.custom_aabb = bounds.call(rect)
	node.set_instance_shader_parameter(
		&"cells",
		Vector4(
			range_cells.position.x, range_cells.position.y, range_cells.size.x, range_cells.size.y
		)
	)
	node.set_meta(&"chunk", chunk)
	parent.add_child(node)
	_nodes[chunk] = node


func free_chunk(chunk: Vector2i) -> void:
	var node: MultiMeshInstance3D = _nodes.get(chunk)
	if node == null:
		return
	parent.remove_child(node)
	node.queue_free()
	_nodes.erase(chunk)


func clear() -> void:
	for chunk: Vector2i in _nodes.keys():
		free_chunk(chunk)


func nodes() -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for node: MultiMeshInstance3D in _nodes.values():
		result.append(node)
	return result


func node(chunk: Vector2i) -> MultiMeshInstance3D:
	return _nodes.get(chunk)


## A MultiMesh of `count` instances without any instance data (shaders that place every vertex
## in world space, world_vertex_coords: the impostor quads).
static func bare_multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	return multi


## A MultiMesh of `count` identity instances (built once per map and shared by every chunk):
## shaders that keep local vertices (a real mesh with normals) place them themselves.
static func identity_multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var multi := bare_multimesh(mesh, count)
	var buffer := PackedFloat32Array()
	buffer.resize(count * 12)
	for k in count:
		buffer[k * 12] = 1.0
		buffer[k * 12 + 5] = 1.0
		buffer[k * 12 + 10] = 1.0
	multi.buffer = buffer
	return multi


## Lowest (x) and highest (y) value of a row-major height grid (`size` vertices from `origin`,
## `step` apart, at least `floor_height`) over `rect`.
static func height_span(
	heights: PackedFloat32Array,
	origin: Vector2,
	size: Vector2i,
	step: float,
	rect: Rect2,
	floor_height: float
) -> Vector2:
	var lo := ((rect.position - origin) / step).floor()
	var hi := ((rect.end - origin) / step).ceil()
	var i0 := clampi(int(lo.x), 0, size.x - 1)
	var i1 := clampi(int(hi.x), 0, size.x - 1)
	var j0 := clampi(int(lo.y), 0, size.y - 1)
	var j1 := clampi(int(hi.y), 0, size.y - 1)
	var result := Vector2(INF, -INF)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var h := maxf(heights[j * size.x + i], floor_height)
			result = Vector2(minf(result.x, h), maxf(result.y, h))
	return result
