class_name TerrainNear
extends RefCounted
## The near terrain LOD of MapView (TASK-134, ADR 0025): around the camera target the ground is
## drawn at SUBDIVISION x the lattice resolution (1/32 unit = 4.5 m instead of 36 m), in chunks of
## one TerrainChunks block (4 x 4 lattice cells = 1 world unit), a ChunkLayer ("terrain_near") the
## ChunkManager builds and frees like the others. A built near chunk punches its block out of the
## fine chunk under it (TerrainChunks.set_hole), so the two never overlap.
##
## Heights: inside a chunk every vertex samples the TerrainSurface (the function the core tile
## heights come from), so a unit standing at a tile centre touches the drawn ground. An edge has
## two variants, both planned on the worker threads: "raw" (surface heights, used where the
## neighbouring near chunk is built – both sides compute the same values) and "fine" (the lattice
## edge interpolated, used where the neighbour is the fine mesh – exactly the fine triangles' edge,
## so the ring border has neither gaps nor T-junction steps). Building or freeing a chunk switches
## the shared edge of its built neighbours (a mesh rebuild on the main thread). A shallow skirt
## covers the rasterisation slivers of the T-junctions.
## Ground weights, tints and the "fine" edge normals are the fine lattice's own per-vertex values
## (TerrainChunks.vertex_attributes) interpolated on its triangles, so the splat matches across the
## border; inner normals come from the surface at near spacing.

## Near cells per lattice cell side, lattice cells per chunk side.
const SUBDIVISION := 8
const LATTICE_CELLS := TerrainChunks.BLOCK_CELLS
const CELLS := SUBDIVISION * LATTICE_CELLS
const STEP := TerrainLattice.STEP / SUBDIVISION
const CHUNK_SIZE := TerrainLattice.STEP * LATTICE_CELLS
## Hides the T-junction slivers only (the heights match): far shallower than the fine skirt.
const SKIRT_DEPTH := 0.02
const LAYER := &"terrain_near"
const NODE := "TerrainNear"
## The layer is on while the camera is at most ENABLE_DISTANCE away from its target and goes off
## beyond DISABLE_DISTANCE (world units; hysteresis). Farther out a 4.5 m vertex is under a pixel.
const ENABLE_DISTANCE := 12.0
const DISABLE_DISTANCE := 14.0
## Neighbour across each edge, in TerrainChunks.add_skirt's edge order (z = 0 row, z = max row,
## x = 0 column, x = max column); the opposite edge of e is e ^ 1.
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)
]

var root := Node3D.new()

var _terrain: TerrainChunks
var _lattice: TerrainLattice
var _surface: TerrainSurface
## Vector2i chunk -> {"node": MeshInstance3D, "arrays": mesh arrays, "edges": plan edges,
## "raw": Array[bool] per edge}.
var _built: Dictionary = {}


func _init(terrain: TerrainChunks, surface: TerrainSurface) -> void:
	_terrain = terrain
	_lattice = terrain.lattice
	_surface = surface
	root.name = NODE


func chunk_layer() -> ChunkLayer:
	return ChunkLayer.new(
		LAYER, CHUNK_SIZE, _lattice.rect(), build_chunk, free_chunk, plan, _lattice.origin
	)


## Whether the layer should be on at camera distance `distance` when it is `on` now.
static func wanted(distance: float, on: bool) -> bool:
	return distance <= (DISABLE_DISTANCE if on else ENABLE_DISTANCE)


func x_of(gi: int) -> float:
	return _lattice.origin.x + gi * STEP


func z_of(gj: int) -> float:
	return _lattice.origin.y + gj * STEP


## Surface height at near vertex (gi, gj) (global near indices, clamped to the lattice); on a
## lattice vertex exactly the lattice height (its border rule included).
func raw_height(gi: int, gj: int) -> float:
	gi = clampi(gi, 0, _lattice.cells.x * SUBDIVISION)
	gj = clampi(gj, 0, _lattice.cells.y * SUBDIVISION)
	if gi % SUBDIVISION == 0 and gj % SUBDIVISION == 0:
		return _lattice.height(gi / SUBDIVISION, gj / SUBDIVISION)
	return _surface.height_at(x_of(gi), z_of(gj))


## The mesh of `chunk` with every edge in its "fine" variant, plus both variants of each edge:
## {"arrays", "vertices": surface vertex count, "edges": per edge {"indices": surface vertex
## indices along it, "raw_y", "raw_n", "fine_y", "fine_n"}}. Pure (worker threads).
func plan(chunk: Vector2i) -> Dictionary:
	var n := CELLS
	var row := n + 1
	var gi0 := chunk.x * n
	var gj0 := chunk.y * n
	# Surface heights with one vertex around the chunk (normals).
	var w := n + 3
	var raw := PackedFloat32Array()
	raw.resize(w * w)
	for b in w:
		for a in w:
			raw[b * w + a] = raw_height(gi0 + a - 1, gj0 + b - 1)
	# The fine lattice's attributes on the chunk's (LATTICE_CELLS + 1)^2 lattice vertices.
	var fine := _terrain.vertex_attributes(
		chunk.x * LATTICE_CELLS, chunk.y * LATTICE_CELLS, LATTICE_CELLS, LATTICE_CELLS, 1
	)
	var fine_heights: PackedFloat32Array = fine["heights"]
	var fine_normals: PackedVector3Array = fine["normals"]
	var fine_weights: PackedFloat32Array = fine["weights"]
	var fine_tints: PackedVector2Array = fine["tints"]
	var layers := TerrainSplat.LAYER_COUNT
	var count := row * row
	var vertices := PackedVector3Array()
	vertices.resize(count)
	var normals := PackedVector3Array()
	normals.resize(count)
	var tangents := PackedFloat32Array()
	tangents.resize(count * 4)
	var uvs := PackedVector2Array()
	uvs.resize(count)
	var tints := PackedVector2Array()
	tints.resize(count)
	var weights := PackedFloat32Array()
	weights.resize(count * layers)
	var fine_y := PackedFloat32Array()
	fine_y.resize(count)
	var fine_n := PackedVector3Array()
	fine_n.resize(count)
	var max_i := _lattice.cells.x * SUBDIVISION
	var max_j := _lattice.cells.y * SUBDIVISION
	for b in row:
		for a in row:
			var k := b * row + a
			var x := x_of(gi0 + a)
			var z := z_of(gj0 + b)
			vertices[k] = Vector3(x, raw[(b + 1) * w + a + 1], z)
			var dx := (raw[(b + 1) * w + a + 2] - raw[(b + 1) * w + a]) / (2.0 * STEP)
			var dz := (raw[(b + 2) * w + a + 1] - raw[b * w + a + 1]) / (2.0 * STEP)
			if gi0 + a <= 0 or gi0 + a >= max_i:
				dx *= 2.0
			if gj0 + b <= 0 or gj0 + b >= max_j:
				dz *= 2.0
			normals[k] = Vector3(-dx, 1.0, -dz).normalized()
			uvs[k] = Vector2(x, z) / MapView.DETAIL_TILE
			# The fine triangle the vertex lies on and its barycentric weights there.
			var ci := mini(a / SUBDIVISION, LATTICE_CELLS - 1)
			var cj := mini(b / SUBDIVISION, LATTICE_CELLS - 1)
			var u := float(a - ci * SUBDIVISION) / SUBDIVISION
			var v := float(b - cj * SUBDIVISION) / SUBDIVISION
			var fr := LATTICE_CELLS + 1
			var corners := PackedInt32Array()
			var bary := PackedFloat32Array()
			if u + v <= 1.0:
				corners = PackedInt32Array([cj * fr + ci, cj * fr + ci + 1, (cj + 1) * fr + ci])
				bary = PackedFloat32Array([1.0 - u - v, u, v])
			else:
				corners = PackedInt32Array(
					[(cj + 1) * fr + ci + 1, (cj + 1) * fr + ci, cj * fr + ci + 1]
				)
				bary = PackedFloat32Array([u + v - 1.0, 1.0 - u, 1.0 - v])
			var y := 0.0
			var nf := Vector3.ZERO
			var tint := Vector2.ZERO
			for c in 3:
				var corner := corners[c]
				var f := bary[c]
				y += fine_heights[corner] * f
				nf += fine_normals[corner] * f
				tint += fine_tints[corner] * f
				for layer in layers:
					weights[k * layers + layer] += fine_weights[corner * layers + layer] * f
			fine_y[k] = y
			fine_n[k] = nf.normalized()
			tints[k] = tint
	var edges: Array[Dictionary] = []
	for e in 4:
		var on_edge := PackedInt32Array()
		for s in row:
			match e:
				0:
					on_edge.append(s)
				1:
					on_edge.append(n * row + s)
				2:
					on_edge.append(s * row)
				_:
					on_edge.append(s * row + n)
		var raw_y := PackedFloat32Array()
		var raw_n := PackedVector3Array()
		var edge_fine_y := PackedFloat32Array()
		var edge_fine_n := PackedVector3Array()
		for k in on_edge:
			raw_y.append(vertices[k].y)
			raw_n.append(normals[k])
			edge_fine_y.append(fine_y[k])
			edge_fine_n.append(fine_n[k])
		var edge := {
			"indices": on_edge,
			"raw_y": raw_y,
			"raw_n": raw_n,
			"fine_y": edge_fine_y,
			"fine_n": edge_fine_n,
		}
		edges.append(edge)
	# Start with every edge on the fine mesh (no near neighbour).
	for edge in edges:
		var on_edge: PackedInt32Array = edge["indices"]
		var ys: PackedFloat32Array = edge["fine_y"]
		var ns: PackedVector3Array = edge["fine_n"]
		for s in on_edge.size():
			var k := on_edge[s]
			vertices[k].y = ys[s]
			normals[k] = ns[s]
	for k in count:
		var t := TerrainChunks.tangent_of(normals[k])
		tangents[k * 4] = t.x
		tangents[k * 4 + 1] = t.y
		tangents[k * 4 + 2] = t.z
		tangents[k * 4 + 3] = 1.0
	var indices := TerrainChunks.grid_indices(n, n)
	TerrainChunks.add_skirt(
		n, n, vertices, normals, tangents, uvs, tints, weights, indices, SKIRT_DEPTH
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
	return {"arrays": arrays, "vertices": count, "edges": edges}


func build_chunk(chunk: Vector2i, chunk_plan: Variant) -> void:
	var p: Dictionary = chunk_plan
	var raw: Array[bool] = [false, false, false, false]
	var entry := {"arrays": p["arrays"], "edges": p["edges"], "raw": raw, "count": p["vertices"]}
	for e in 4:
		raw[e] = _built.has(chunk + NEIGHBOURS[e])
	if raw.has(true):
		_apply_edges(entry)  # writes into p["arrays"] (the same Array)
	var node := _terrain.chunk_instance(p, "%s_%d_%d" % [NODE, chunk.x, chunk.y], true)
	entry["node"] = node
	root.add_child(node)
	_built[chunk] = entry
	for e in 4:
		if raw[e]:
			_set_edge(chunk + NEIGHBOURS[e], e ^ 1, true)
	var at := TerrainChunks.block_of(chunk)
	_terrain.set_hole(at[0], at[1], true)


func free_chunk(chunk: Vector2i) -> void:
	var entry: Dictionary = _built.get(chunk, {})
	if entry.is_empty():
		return
	var node: MeshInstance3D = entry["node"]
	root.remove_child(node)
	node.queue_free()
	_built.erase(chunk)
	for e in 4:
		if _built.has(chunk + NEIGHBOURS[e]):
			_set_edge(chunk + NEIGHBOURS[e], e ^ 1, false)
	var at := TerrainChunks.block_of(chunk)
	_terrain.set_hole(at[0], at[1], false)


## The built near chunk nodes.
func nodes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for entry: Dictionary in _built.values():
		result.append(entry["node"])
	return result


func built_chunks() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_built.keys())
	return result


## The drawn vertex heights of a built chunk ((CELLS + 1)^2, row-major from its first vertex, as
## drawn_height_at reads them), or empty when it is not built (TASK-217a: NearHeightCache).
func chunk_heights(chunk: Vector2i) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	var entry: Dictionary = _built.get(chunk, {})
	if entry.is_empty():
		return result
	var vertices: PackedVector3Array = (entry["arrays"] as Array)[Mesh.ARRAY_VERTEX]
	var count := (CELLS + 1) * (CELLS + 1)
	result.resize(count)
	for k in count:
		result[k] = vertices[k].y
	return result


## Whether edge `edge` of built chunk `chunk` uses the surface heights (its neighbour is built).
func edge_is_raw(chunk: Vector2i, edge: int) -> bool:
	return (_built[chunk]["raw"] as Array)[edge]


## Height of the drawn near mesh at (x, z) (its triangles, as they are built now), or NAN where no
## near chunk is built. Main thread.
func drawn_height_at(x: float, z: float) -> float:
	var fx := (x - _lattice.origin.x) / STEP
	var fz := (z - _lattice.origin.y) / STEP
	var gi := floori(fx)
	var gj := floori(fz)
	var chunk := Vector2i(floori(float(gi) / CELLS), floori(float(gj) / CELLS))
	var entry: Dictionary = _built.get(chunk, {})
	if entry.is_empty():
		return NAN
	var a := gi - chunk.x * CELLS
	var b := gj - chunk.y * CELLS
	var u := fx - gi
	var v := fz - gj
	var vertices: PackedVector3Array = (entry["arrays"] as Array)[Mesh.ARRAY_VERTEX]
	var row := CELLS + 1
	var ha := vertices[b * row + a].y
	var hb := vertices[b * row + a + 1].y
	var hc := vertices[(b + 1) * row + a].y
	var hd := vertices[(b + 1) * row + a + 1].y
	if u + v <= 1.0:
		return ha + u * (hb - ha) + v * (hc - ha)
	return hd + (1.0 - u) * (hc - hd) + (1.0 - v) * (hb - hd)


## Height of the near mesh at (x, z) as it is drawn wherever its edges are raw (inside the near
## ring: every edge but the outermost), computed from the surface instead of the built meshes, so
## it works for chunks not built yet. The same triangles and vertex heights as drawn_height_at.
## Pure: the planning threads place real-size vegetation with it (TASK-135).
func surface_height_at(x: float, z: float) -> float:
	var fx := (x - _lattice.origin.x) / STEP
	var fz := (z - _lattice.origin.y) / STEP
	var gi := floori(fx)
	var gj := floori(fz)
	var u := fx - gi
	var v := fz - gj
	var ha := raw_height(gi, gj)
	var hb := raw_height(gi + 1, gj)
	var hc := raw_height(gi, gj + 1)
	if u + v <= 1.0:
		return ha + u * (hb - ha) + v * (hc - ha)
	var hd := raw_height(gi + 1, gj + 1)
	return hd + (1.0 - u) * (hc - hd) + (1.0 - v) * (hb - hd)


## The surface height at (x, z) itself (one query instead of surface_height_at's three): within a
## few centimetres of the drawn triangles, for what is only seen from afar (tree impostors).
## Pure, thread-safe.
func surface_point_height(x: float, z: float) -> float:
	return _surface.height_at(x, z)


## Switches one edge of a built chunk between its variants and rebuilds its mesh.
func _set_edge(chunk: Vector2i, edge: int, raw: bool) -> void:
	var entry: Dictionary = _built[chunk]
	var flags: Array[bool] = entry["raw"]
	if flags[edge] == raw:
		return
	flags[edge] = raw
	_apply_edges(entry)
	(entry["node"] as MeshInstance3D).mesh = _terrain.mesh_of(entry["arrays"])


## Writes every edge's current variant into the chunk's arrays (surface vertex, normal, tangent and
## the skirt copy below it). A corner takes the surface normal only when both its edges are raw
## (its height is a lattice height either way).
func _apply_edges(entry: Dictionary) -> void:
	var arrays: Array = entry["arrays"]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var flags: Array[bool] = entry["raw"]
	var count: int = entry["count"]
	var edges: Array[Dictionary] = entry["edges"]
	var row := CELLS + 1
	# Corner index -> the two edges that meet there.
	var corners := {0: [0, 2], CELLS: [0, 3], CELLS * row: [1, 2], CELLS * row + CELLS: [1, 3]}
	for e in 4:
		var edge := edges[e]
		var on_edge: PackedInt32Array = edge["indices"]
		var key := "raw" if flags[e] else "fine"
		var ys: PackedFloat32Array = edge[key + "_y"]
		var ns: PackedVector3Array = edge[key + "_n"]
		for s in on_edge.size():
			var k := on_edge[s]
			var normal := ns[s]
			if corners.has(k):
				var pair: Array = corners[k]
				var both_raw: bool = flags[pair[0]] and flags[pair[1]]
				normal = (edge["raw_n"] if both_raw else edge["fine_n"])[s]
			vertices[k].y = ys[s]
			normals[k] = normal
			var t := TerrainChunks.tangent_of(normal)
			tangents[k * 4] = t.x
			tangents[k * 4 + 1] = t.y
			tangents[k * 4 + 2] = t.z
			# The skirt copy of this edge vertex.
			var low := count + e * row + s
			vertices[low] = Vector3(vertices[k].x, ys[s] - SKIRT_DEPTH, vertices[k].z)
			normals[low] = normal
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
