class_name TerrainChunks
extends RefCounted
## MapView's chunked terrain ground (TASK-072b): the playable terrain rectangle split into
## TerrainLattice chunks (8 x 8 world units). Near the camera a chunk is drawn at full lattice
## resolution ("Terrain_<x>_<z>", a ChunkLayer the ChunkManager builds and frees); every chunk also
## has a coarse mesh (every COARSE_STRIDE-th vertex, no shadows) built up front, drawn while the
## fine one is not built – so the whole map always shows, at a cost that
## grows only slowly with its area. The coarse meshes of COARSE_GROUP x COARSE_GROUP chunks share
## one node ("TerrainFar_<gx>_<gz>", one draw instead of sixteen); a fine chunk's triangles are
## left out of its group's index buffer while the fine chunk is built. Vertex attributes are
## those of the former single mesh (normals by central differences, TerrainSplat weights from
## the jittered tile type smoothed over the
## neighbours, the off-map margin darkened), computed from the lattice alone so neighbouring chunks
## agree on every shared vertex. A skirt hangs from every chunk edge (SKIRT_DEPTH) and hides the
## slivers where a fine chunk meets a coarse one or the backdrop ring.
## The plans (`plan`) are pure and run on the worker threads; the nodes are made on the main
## thread (`build_fine`, `build_coarse`).

const COARSE_STRIDE := 4
const COARSE_GROUP := 4
const SKIRT_DEPTH := 0.4
## Cells per side of the blocks a fine chunk's index buffer is split into: one block is the area
## of one near chunk (TerrainNear), left out while that one is built.
const BLOCK_CELLS := 4
const FINE_NODE := "Terrain"
const COARSE_NODE := "TerrainFar"

var lattice: TerrainLattice
## Parents of the fine and the coarse chunk nodes.
var fine_root := Node3D.new()
var coarse_root := Node3D.new()

var _grid: HexGrid
var _hex_size := 1.0
var _material: Material
## Vector2i chunk -> MeshInstance3D.
var _fine: Dictionary = {}
## Vector2i group -> {"node": MeshInstance3D, "arrays": merged vertex arrays, "indices":
## {chunk: PackedInt32Array (merged numbering)}}.
var _coarse: Dictionary = {}
## Vector2i chunk -> its full-resolution plan (kept to rebuild the index buffer around holes).
var _fine_plans: Dictionary = {}
## Vector2i chunk -> {block index: true}: the blocks a near chunk (TerrainNear) draws instead.
var _holes: Dictionary = {}


func _init(
	grid: HexGrid, hex_size: float, terrain_lattice: TerrainLattice, material: Material
) -> void:
	_grid = grid
	_hex_size = hex_size
	lattice = terrain_lattice
	_material = material
	fine_root.name = FINE_NODE
	coarse_root.name = COARSE_NODE


## The fine terrain as a chunk layer ("terrain" ring).
func chunk_layer() -> ChunkLayer:
	return ChunkLayer.new(
		&"terrain",
		TerrainLattice.CHUNK_SIZE,
		lattice.rect(),
		build_fine,
		free_fine,
		func(chunk: Vector2i) -> Dictionary: return plan(chunk, 1),
		lattice.origin
	)


## Every chunk of the lattice.
func all_chunks() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var counts := lattice.chunk_counts()
	for z in counts.y:
		for x in counts.x:
			result.append(Vector2i(x, z))
	return result


## Plans the coarse meshes of every chunk (on the worker threads when `threads`) and adds their
## group nodes. The coarse triangles of a chunk with a fine one built stay out.
func build_all_coarse(threads: bool) -> void:
	var chunks := all_chunks()
	var plans: Array = []
	plans.resize(chunks.size())
	var task := func(k: int) -> void: plans[k] = plan(chunks[k], COARSE_STRIDE)
	if threads:
		var id := WorkerThreadPool.add_group_task(task, chunks.size(), -1, true, "Coarse terrain")
		WorkerThreadPool.wait_for_group_task_completion(id)
	else:
		for k in chunks.size():
			task.call(k)
	var by_group: Dictionary = {}
	for k in chunks.size():
		(by_group.get_or_add(group_of(chunks[k]), []) as Array).append(k)
	var groups := by_group.keys()
	groups.sort()
	for group: Vector2i in groups:
		_build_group(group, by_group[group], chunks, plans)


## The coarse group of `chunk`.
static func group_of(chunk: Vector2i) -> Vector2i:
	return Vector2i(floori(float(chunk.x) / COARSE_GROUP), floori(float(chunk.y) / COARSE_GROUP))


func _build_group(group: Vector2i, members: Array, chunks: Array[Vector2i], plans: Array) -> void:
	var merged := []
	merged.resize(Mesh.ARRAY_MAX)
	var indices := {}
	var offset := 0
	for k: int in members:
		var arrays: Array = (plans[k] as Dictionary)["arrays"]
		for key in [
			Mesh.ARRAY_VERTEX,
			Mesh.ARRAY_NORMAL,
			Mesh.ARRAY_TANGENT,
			Mesh.ARRAY_TEX_UV,
			Mesh.ARRAY_TEX_UV2,
			Mesh.ARRAY_COLOR,
			Mesh.ARRAY_CUSTOM0
		]:
			if merged[key] == null:
				merged[key] = arrays[key]
			else:
				merged[key].append_array(arrays[key])
		var local: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var shifted := PackedInt32Array()
		shifted.resize(local.size())
		for i in local.size():
			shifted[i] = local[i] + offset
		indices[chunks[k]] = shifted
		offset += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var instance := MeshInstance3D.new()
	instance.name = "%s_%d_%d" % [COARSE_NODE, group.x, group.y]
	instance.set_layer_mask_value(MapView.TERRAIN_VISUAL_LAYER, true)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	coarse_root.add_child(instance)
	_coarse[group] = {"node": instance, "arrays": merged, "indices": indices}
	_refresh_group(group)


## Rebuilds the index buffer of a coarse group without the chunks whose fine mesh is built.
func _refresh_group(group: Vector2i) -> void:
	var entry: Dictionary = _coarse.get(group, {})
	if entry.is_empty():
		return
	var instance: MeshInstance3D = entry["node"]
	var indices := PackedInt32Array()
	var by_chunk: Dictionary = entry["indices"]
	var members := by_chunk.keys()
	members.sort()
	for chunk: Vector2i in members:
		if not _fine.has(chunk):
			indices.append_array(by_chunk[chunk])
	instance.visible = not indices.is_empty()
	if indices.is_empty():
		instance.mesh = null
		return
	var arrays: Array = (entry["arrays"] as Array).duplicate()
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	var format := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)
	mesh.surface_set_material(0, _material)
	instance.mesh = mesh


func build_fine(chunk: Vector2i, chunk_plan: Variant) -> void:
	var node := chunk_instance(chunk_plan, "%s_%d_%d" % [FINE_NODE, chunk.x, chunk.y], true)
	fine_root.add_child(node)
	_fine[chunk] = node
	_fine_plans[chunk] = chunk_plan
	if _holes.has(chunk):
		_refresh_fine(chunk)
	_refresh_group(group_of(chunk))


func free_fine(chunk: Vector2i) -> void:
	var node: MeshInstance3D = _fine.get(chunk)
	if node != null:
		fine_root.remove_child(node)
		node.queue_free()
	_fine.erase(chunk)
	_fine_plans.erase(chunk)
	_refresh_group(group_of(chunk))


## Leaves block `block` (row-major index of the BLOCK_CELLS blocks) of fine chunk `chunk` out of
## its mesh (`hole`) or puts it back: a near chunk (TerrainNear) draws that area. Remembered for a
## fine chunk built later.
func set_hole(chunk: Vector2i, block: int, hole: bool) -> void:
	var holes: Dictionary = _holes.get(chunk, {})
	if hole == holes.has(block):
		return
	if hole:
		holes[block] = true
		_holes[chunk] = holes
	else:
		holes.erase(block)
		if holes.is_empty():
			_holes.erase(chunk)
	if _fine.has(chunk):
		_refresh_fine(chunk)


## The blocks of `chunk` left out for near chunks.
func holes(chunk: Vector2i) -> Array:
	return (_holes.get(chunk, {}) as Dictionary).keys()


## Fine chunk and block index that hold the near chunk `near` (TerrainNear chunk coordinates).
static func block_of(near: Vector2i) -> Array:
	var per_chunk := TerrainLattice.CELLS_PER_CHUNK / BLOCK_CELLS
	var chunk := Vector2i(floori(float(near.x) / per_chunk), floori(float(near.y) / per_chunk))
	var local := near - chunk * per_chunk
	return [chunk, local.y * per_chunk + local.x]


## Rebuilds fine chunk `chunk`'s mesh without its hole blocks (hidden when every block is one).
func _refresh_fine(chunk: Vector2i) -> void:
	var node: MeshInstance3D = _fine[chunk]
	var chunk_plan: Dictionary = _fine_plans[chunk]
	var holes: Dictionary = _holes.get(chunk, {})
	var arrays: Array = (chunk_plan["arrays"] as Array).duplicate()
	if not holes.is_empty():
		var indices := PackedInt32Array()
		var blocks: Array[PackedInt32Array] = chunk_plan["blocks"]
		for k in blocks.size():
			if not holes.has(k):
				indices.append_array(blocks[k])
		if indices.is_empty():
			node.mesh = null
			node.visible = false
			return
		arrays[Mesh.ARRAY_INDEX] = indices
	node.visible = true
	node.mesh = mesh_of(arrays)


## Whether the coarse mesh of `chunk` is drawn (no fine chunk built there).
func coarse_shows(chunk: Vector2i) -> bool:
	return not _fine.has(chunk)


func fine_nodes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	result.assign(_fine.values())
	return result


## The coarse group nodes (the hidden ones too).
func coarse_nodes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for entry: Dictionary in _coarse.values():
		result.append(entry["node"])
	return result


## A triangle mesh of terrain `arrays` (weights in colour + custom0) with the ground material.
func mesh_of(arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var format := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)
	mesh.surface_set_material(0, _material)
	return mesh


func chunk_instance(chunk_plan: Dictionary, node_name: String, shadows: bool) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh_of(chunk_plan["arrays"])
	# The surface vertices come first, the skirt after them.
	instance.set_meta(&"surface_vertices", chunk_plan["vertices"])
	instance.set_layer_mask_value(MapView.TERRAIN_VISUAL_LAYER, true)
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	return instance


## Per-vertex attributes of the (nx + 1) x (nz + 1) lattice vertices (i0 + a * stride,
## j0 + b * stride), row-major: {"heights": PackedFloat32Array, "normals": PackedVector3Array,
## "weights": PackedFloat32Array (TerrainSplat.LAYER_COUNT per vertex, smoothed over the
## neighbours), "tints": PackedVector2Array (UV2)}. Every value is a function of the lattice index
## alone (normals by central differences, one-sided on the lattice border), so any window gives the
## same values for a shared vertex – the near terrain (TerrainNear) interpolates them. `block`
## (optional) is the lattice block whose corner is (i0, j0) (stride 1 only, saves the queries).
## Pure: reads the lattice, grid and noise only.
func vertex_attributes(
	i0: int, j0: int, nx: int, nz: int, stride: int, block := PackedFloat32Array()
) -> Dictionary:
	var c := TerrainLattice.CELLS_PER_CHUNK
	# Heights two vertices beyond the window (normals one beyond, their weights smooth the edge).
	var pad := 2
	var w := nx + 1 + 2 * pad
	var h := nz + 1 + 2 * pad
	var heights := PackedFloat32Array()
	heights.resize(w * h)
	var side := c + 1
	for b in h:
		var j := clampi(j0 + (b - pad) * stride, 0, lattice.cells.y)
		for a in w:
			var i := clampi(i0 + (a - pad) * stride, 0, lattice.cells.x)
			var la := i - i0
			var lb := j - j0
			if not block.is_empty() and la >= 0 and la <= c and lb >= 0 and lb <= c:
				heights[b * w + a] = block[lb * side + la]
			else:
				heights[b * w + a] = lattice.height(i, j)
	# Normals and raw weights for the window plus one vertex around it.
	var layers := TerrainSplat.LAYER_COUNT
	var rw := nx + 3
	var rh := nz + 3
	var normals_ring := PackedVector3Array()
	normals_ring.resize(rw * rh)
	var weights_ring := PackedFloat32Array()
	weights_ring.resize(rw * rh * layers)
	for b in rh:
		var j := j0 + (b - 1) * stride
		for a in rw:
			var i := i0 + (a - 1) * stride
			# Central differences, one-sided on the lattice border (as the single mesh had).
			var lo_i := maxi(i - stride, 0)
			var hi_i := mini(i + stride, lattice.cells.x)
			var lo_j := maxi(j - stride, 0)
			var hi_j := mini(j + stride, lattice.cells.y)
			var ha := a + pad - 1
			var hb := b + pad - 1
			var ci := clampi(i, 0, lattice.cells.x)
			var cj := clampi(j, 0, lattice.cells.y)
			var di := hi_i - lo_i
			var dj := hi_j - lo_j
			var left := heights[hb * w + ha - (ci - lo_i) / stride]
			var right := heights[hb * w + ha + (hi_i - ci) / stride]
			var up := heights[(hb - (cj - lo_j) / stride) * w + ha]
			var down := heights[(hb + (hi_j - cj) / stride) * w + ha]
			var dx := (right - left) / (di * TerrainLattice.STEP) if di > 0 else 0.0
			var dz := (down - up) / (dj * TerrainLattice.STEP) if dj > 0 else 0.0
			var n := Vector3(-dx, 1.0, -dz).normalized()
			normals_ring[b * rw + a] = n
			var v := Vector3(lattice.x_of(ci), heights[hb * w + ha], lattice.z_of(cj))
			var jittered := GroundNoise.jitter(v.x, v.z)
			var jc := Hex.from_world(Vector3(jittered.x, 0.0, jittered.y), _hex_size)
			var jittered_type := int(_grid.get_terrain(jc)) if _grid.has_tile(jc) else -1
			# The noises cost most of a vertex; forest, fields, villages and marsh ignore them.
			var noise := (
				MapView._splat_noise(v.x, v.z)
				if TerrainSplat.uses_noise(jittered_type)
				else Vector2.ZERO
			)
			var splat := MapView._splat(jittered_type, n.y, v, noise)
			for layer in layers:
				weights_ring[(b * rw + a) * layers + layer] = splat[layer]
	var count := (nx + 1) * (nz + 1)
	var out_heights := PackedFloat32Array()
	out_heights.resize(count)
	var normals := PackedVector3Array()
	normals.resize(count)
	var tints := PackedVector2Array()
	tints.resize(count)
	var weights := PackedFloat32Array()
	weights.resize(count * layers)
	for b in nz + 1:
		var j := j0 + b * stride
		for a in nx + 1:
			var i := i0 + a * stride
			var k := b * (nx + 1) + a
			out_heights[k] = heights[(b + pad) * w + a + pad]
			normals[k] = normals_ring[(b + 1) * rw + a + 1]
			var on_map := _grid.has_tile(
				Hex.from_world(Vector3(lattice.x_of(i), 0.0, lattice.z_of(j)), _hex_size)
			)
			tints[k] = Vector2(1.0 if on_map else MapView.OFF_MAP_VALUE, 1.0)
			# Blend across tile borders: the mean of the neighbours within one step (clamped to
			# the lattice, like TerrainSplat.smooth on the single mesh).
			var total := 0
			for nb in range(b, b + 3):
				var nj := j + (nb - b - 1) * stride
				if nj < 0 or nj > lattice.cells.y:
					continue
				for na in range(a, a + 3):
					var ni := i + (na - a - 1) * stride
					if ni < 0 or ni > lattice.cells.x:
						continue
					var o := (nb * rw + na) * layers
					for layer in layers:
						weights[k * layers + layer] += weights_ring[o + layer]
					total += 1
			for layer in layers:
				weights[k * layers + layer] /= total
	return {"heights": out_heights, "normals": normals, "weights": weights, "tints": tints}


## The tangent of a vertex with normal `n`: U runs along +x, so the tangent is the slope direction
## made perpendicular to the normal; w = +1 puts the binormal up the normal map image
## (DetailTexture's convention).
static func tangent_of(n: Vector3) -> Vector3:
	var t := Vector3(1.0, -n.x / maxf(n.y, 1e-6), 0.0)
	return (t - n * n.dot(t)).normalized()


## Triangle indices of an nx x nz cell grid of (nx + 1) x (nz + 1) row-major vertices, 6 per cell
## in row-major cell order, each cell split along its b–c diagonal (TerrainLattice.mesh_height_at).
static func grid_indices(nx: int, nz: int) -> PackedInt32Array:
	var indices := PackedInt32Array()
	indices.resize(nx * nz * 6)
	var p := 0
	var row := nx + 1
	for b in nz:
		for a in nx:
			var ia := b * row + a
			var ib := ia + 1
			var ic := ia + row
			var id := ic + 1
			# Clockwise seen from above (+Y): Godot's front-face winding.
			indices[p] = ia
			indices[p + 1] = ib
			indices[p + 2] = ic
			indices[p + 3] = ib
			indices[p + 4] = id
			indices[p + 5] = ic
			p += 6
	return indices


## The mesh arrays of `chunk` with every `stride`-th lattice vertex (1 = full resolution):
## {"arrays": Mesh arrays (vertex, normal, tangent, uv, uv2 = tint, colour + custom0 = weights,
## index), "vertices": surface vertex count (the skirt follows)}; at full resolution also
## "blocks": the index lists of the BLOCK_CELLS x BLOCK_CELLS cell blocks (row-major, each with its
## skirt quads), so a block under a near chunk (TerrainNear) can be left out. Pure: reads the
## lattice, grid and noise only.
func plan(chunk: Vector2i, stride: int) -> Dictionary:
	var c := TerrainLattice.CELLS_PER_CHUNK
	var i0 := chunk.x * c
	var j0 := chunk.y * c
	var i1 := mini(i0 + c, lattice.cells.x)
	var j1 := mini(j0 + c, lattice.cells.y)
	var nx := (i1 - i0) / stride
	var nz := (j1 - j0) / stride
	var block := lattice.block(chunk) if stride == 1 else PackedFloat32Array()
	var attributes := vertex_attributes(i0, j0, nx, nz, stride, block)
	var heights: PackedFloat32Array = attributes["heights"]
	var normals: PackedVector3Array = attributes["normals"]
	var tints: PackedVector2Array = attributes["tints"]
	var weights: PackedFloat32Array = attributes["weights"]
	var count := (nx + 1) * (nz + 1)
	var vertices := PackedVector3Array()
	vertices.resize(count)
	var tangents := PackedFloat32Array()
	tangents.resize(count * 4)
	var uvs := PackedVector2Array()
	uvs.resize(count)
	for b in nz + 1:
		var j := j0 + b * stride
		for a in nx + 1:
			var i := i0 + a * stride
			var k := b * (nx + 1) + a
			var v := Vector3(lattice.x_of(i), heights[k], lattice.z_of(j))
			vertices[k] = v
			var t := tangent_of(normals[k])
			tangents[k * 4] = t.x
			tangents[k * 4 + 1] = t.y
			tangents[k * 4 + 2] = t.z
			tangents[k * 4 + 3] = 1.0
			uvs[k] = Vector2(v.x, v.z) / MapView.DETAIL_TILE
	var indices := grid_indices(nx, nz)
	var owners := PackedInt32Array()
	add_skirt(
		nx, nz, vertices, normals, tangents, uvs, tints, weights, indices, SKIRT_DEPTH, owners
	)
	var packed := TerrainGround.pack_weights(weights)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = tints
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_COLOR] = packed[0]
	arrays[Mesh.ARRAY_CUSTOM0] = packed[1]
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := {"arrays": arrays, "vertices": count}
	if stride == 1:
		result["blocks"] = _blocks_of(nx, nz, indices, owners)
	return result


## Splits the index buffer of an nx x nz cell grid (grid_indices, then the skirt quads of
## add_skirt with their `owners` cells) into BLOCK_CELLS x BLOCK_CELLS cell blocks, row-major.
static func _blocks_of(
	nx: int, nz: int, indices: PackedInt32Array, owners: PackedInt32Array
) -> Array[PackedInt32Array]:
	var across := ceili(float(nx) / BLOCK_CELLS)
	var down := ceili(float(nz) / BLOCK_CELLS)
	var blocks: Array[PackedInt32Array] = []
	blocks.resize(across * down)
	for cell in nx * nz:
		var k := (cell / nx / BLOCK_CELLS) * across + (cell % nx) / BLOCK_CELLS
		blocks[k].append_array(indices.slice(cell * 6, cell * 6 + 6))
	var skirt := nx * nz * 6
	for s in owners.size():
		var cell := owners[s]
		var k := (cell / nx / BLOCK_CELLS) * across + (cell % nx) / BLOCK_CELLS
		blocks[k].append_array(indices.slice(skirt + s * 12, skirt + s * 12 + 12))
	return blocks


## Appends a skirt along the four edges of the (nx + 1) x (nz + 1) surface: a copy of each edge
## vertex `depth` lower with the same attributes, joined to the edge by quads drawn from both
## sides (cheaper to reason about than the winding of four edges, and never seen from the side).
## Edge order: z = 0 row, z = nz row, x = 0 column, x = nx column; edge e's copies start at
## surface count + e * (edge length). `owners` (optional) gets the row-major cell index each
## segment (12 indices) borders.
static func add_skirt(
	nx: int,
	nz: int,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	tangents: PackedFloat32Array,
	uvs: PackedVector2Array,
	tints: PackedVector2Array,
	weights: PackedFloat32Array,
	indices: PackedInt32Array,
	depth := SKIRT_DEPTH,
	owners := PackedInt32Array()
) -> void:
	var row := nx + 1
	var edges: Array[PackedInt32Array] = []
	for line in [[0, 0, 1, 0, nx], [0, nz, 1, 0, nx], [0, 0, 0, 1, nz], [nx, 0, 0, 1, nz]]:
		var edge := PackedInt32Array()
		for s in (line[4] as int) + 1:
			edge.append((line[1] + s * line[3]) * row + line[0] + s * line[2])
		edges.append(edge)
	var layers := TerrainSplat.LAYER_COUNT
	# The cell each edge's segment s borders.
	var cells: Array[Callable] = [
		func(s: int) -> int: return s,
		func(s: int) -> int: return (nz - 1) * nx + s,
		func(s: int) -> int: return s * nx,
		func(s: int) -> int: return s * nx + nx - 1,
	]
	for e in edges.size():
		var edge := edges[e]
		var first := vertices.size()
		for s in edge.size() - 1:
			owners.append(cells[e].call(s))
		for k in edge:
			vertices.append(vertices[k] - Vector3(0.0, depth, 0.0))
			normals.append(normals[k])
			tangents.append_array(tangents.slice(k * 4, k * 4 + 4))
			uvs.append(uvs[k])
			tints.append(tints[k])
			weights.append_array(weights.slice(k * layers, k * layers + layers))
		for s in edge.size() - 1:
			var top_a := edge[s]
			var top_b := edge[s + 1]
			var low_a := first + s
			var low_b := first + s + 1
			indices.append_array(
				PackedInt32Array(
					[
						top_a,
						top_b,
						low_a,
						top_b,
						low_b,
						low_a,
						top_a,
						low_a,
						top_b,
						top_b,
						low_a,
						low_b
					]
				)
			)
