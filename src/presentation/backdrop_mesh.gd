class_name BackdropMesh
extends RefCounted
## Lattice and mesh of the non-playable scenery ring around the playable terrain mesh
## (TASK-052). The lattice has twice the playable cell size and shares its border vertices:
## the ring's inner edge uses the playable border heights, so the seam has no cracks. Heights
## beyond the border come from BackdropHeights.

var _origin := Vector2.ZERO
var _step := Vector2.ONE
## Lattice cells in x and z, and the ring width in cells.
var _cells := Vector2i.ZERO
var _ring := Vector2i.ZERO
## Playable mesh cells / 2 (the inner part of the lattice).
var _inner := Vector2i.ZERO
var _heights := PackedFloat32Array()
var _distances := PackedFloat32Array()
var _uv_tile := 1.0


## `rect` is the playable mesh rectangle, `inner_cells` its (even) cell counts and
## `border_height(i, j)` the height of its vertex (i, j) (only border vertices are asked for:
## TASK-072b builds the playable mesh lazily, so the backdrop must not need all of it).
func _init(
	rect: Rect2, inner_cells: Vector2i, border_height: Callable, width: float, uv_tile: float
) -> void:
	_uv_tile = uv_tile
	_step = Vector2(rect.size.x / inner_cells.x, rect.size.y / inner_cells.y) * 2.0
	_inner = inner_cells / 2
	_ring = Vector2i(maxi(1, roundi(width / _step.x)), maxi(1, roundi(width / _step.y)))
	_cells = _inner + _ring * 2
	_origin = rect.position - Vector2(_ring.x * _step.x, _ring.y * _step.y)
	var row := _cells.x + 1
	_heights.resize(row * (_cells.y + 1))
	_distances.resize(_heights.size())
	# Border heights, each asked for once: Vector2i(ca, cb) -> height.
	var border := {}
	for b in _cells.y + 1:
		var ib := b - _ring.y
		var cb := clampi(ib, 0, _inner.y)
		for a in row:
			if _is_hidden(a, b):
				continue  # under the playable mesh: never drawn nor sampled
			var ia := a - _ring.x
			var ca := clampi(ia, 0, _inner.x)
			var key := Vector2i(ca, cb)
			if not border.has(key):
				border[key] = border_height.call(2 * ca, 2 * cb)
			var d := Vector2((ia - ca) * _step.x, (ib - cb) * _step.y).length()
			_distances[b * row + a] = d
			_heights[b * row + a] = BackdropHeights.height(
				border[key], d, _origin.x + a * _step.x, _origin.y + b * _step.y
			)


func outer_rect() -> Rect2:
	return Rect2(_origin, Vector2(_cells) * _step)


## Bilinear height at (x, z), clamped to the lattice.
func height_at(x: float, z: float) -> float:
	var fx := clampf((x - _origin.x) / _step.x, 0.0, _cells.x)
	var fz := clampf((z - _origin.y) / _step.y, 0.0, _cells.y)
	var i := mini(floori(fx), _cells.x - 1)
	var j := mini(floori(fz), _cells.y - 1)
	var u := fx - i
	var v := fz - j
	var row := _cells.x + 1
	var top := lerpf(_heights[j * row + i], _heights[j * row + i + 1], u)
	var bottom := lerpf(_heights[(j + 1) * row + i], _heights[(j + 1) * row + i + 1], u)
	return lerpf(top, bottom, v)


## The ring mesh (no material). `vertex_fn(x, z, height, normal_y, distance, border_a, border_b)`
## returns a PackedFloat32Array of TerrainSplat.LAYER_COUNT ground weights followed by a value
## and a saturation factor (stored in ARRAY_TEX_UV2); border_a/b are the inner-lattice indices
## of the nearest border vertex. `add_surface_fn(mesh, arrays, weights)` adds the surface and
## stores the weights (TerrainGround.add_surface). With `threads` the vertex_fn calls run on the
## WorkerThreadPool (TASK-072b: the ring of a large map has tens of thousands of vertices), so
## vertex_fn must then only read shared state; the mesh is the same either way.
func build_mesh(vertex_fn: Callable, add_surface_fn: Callable, threads := false) -> ArrayMesh:
	var row := _cells.x + 1
	# Only ring vertices are built; the lattice under the playable map is hidden.
	var remap := PackedInt32Array()
	remap.resize(_heights.size())
	remap.fill(-1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var lattice := PackedInt32Array()
	for b in _cells.y + 1:
		for a in row:
			if _is_hidden(a, b):
				continue
			# Central differences; one-sided at the lattice edge and towards the hidden part
			# (its heights are not computed).
			var a0 := maxi(a - 1, 0)
			var a1 := mini(a + 1, _cells.x)
			var b0 := maxi(b - 1, 0)
			var b1 := mini(b + 1, _cells.y)
			a0 = a if _is_hidden(a0, b) else a0
			a1 = a if _is_hidden(a1, b) else a1
			b0 = b if _is_hidden(a, b0) else b0
			b1 = b if _is_hidden(a, b1) else b1
			var idx := b * row + a
			remap[idx] = vertices.size()
			lattice.append(idx)
			var x := _origin.x + a * _step.x
			var z := _origin.y + b * _step.y
			vertices.append(Vector3(x, _heights[idx], z))
			uvs.append(Vector2(x, z) / _uv_tile)
			var dx := (_heights[b * row + a1] - _heights[b * row + a0]) / ((a1 - a0) * _step.x)
			var dz := (_heights[b1 * row + a] - _heights[b0 * row + a]) / ((b1 - b0) * _step.y)
			var n := Vector3(-dx, 1.0, -dz).normalized()
			normals.append(n)
			var t := Vector3(1.0, dx, 0.0)
			t = (t - n * n.dot(t)).normalized()
			tangents.append_array(PackedFloat32Array([t.x, t.y, t.z, 1.0]))
	# The per-vertex values, one slot per vertex.
	var values: Array = []
	values.resize(vertices.size())
	var task := func(k: int) -> void:
		var idx := lattice[k]
		var a := idx % row
		var b := idx / row
		values[k] = vertex_fn.call(
			vertices[k].x,
			vertices[k].z,
			_heights[idx],
			normals[k].y,
			_distances[idx],
			clampi(a - _ring.x, 0, _inner.x),
			clampi(b - _ring.y, 0, _inner.y)
		)
	if threads:
		var id := WorkerThreadPool.add_group_task(task, vertices.size(), -1, true, "Backdrop")
		WorkerThreadPool.wait_for_group_task_completion(id)
	else:
		for k in vertices.size():
			task.call(k)
	var layers := TerrainSplat.LAYER_COUNT
	var weights := PackedFloat32Array()
	weights.resize(vertices.size() * layers)
	var tints := PackedVector2Array()
	tints.resize(vertices.size())
	for k in vertices.size():
		var v: PackedFloat32Array = values[k]
		for layer in layers:
			weights[k * layers + layer] = v[layer]
		tints[k] = Vector2(v[layers], v[layers + 1])
	# Ring cells only: the lattice inside the playable rectangle is not drawn.
	var indices := PackedInt32Array()
	for b in _cells.y:
		for a in _cells.x:
			if a >= _ring.x and a < _ring.x + _inner.x and b >= _ring.y and b < _ring.y + _inner.y:
				continue
			var i0 := remap[b * row + a]
			var i1 := remap[(b + 1) * row + a]
			indices.append_array(
				PackedInt32Array(
					[
						i0,
						remap[b * row + a + 1],
						i1,
						remap[b * row + a + 1],
						remap[(b + 1) * row + a + 1],
						i1
					]
				)
			)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = tints
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	add_surface_fn.call(mesh, arrays, weights)
	return mesh


## Every border vertex (inner-lattice indices) a ring vertex can be nearest to.
func border_keys() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for ca in _inner.x + 1:
		result.append(Vector2i(ca, 0))
		result.append(Vector2i(ca, _inner.y))
	for cb in range(1, _inner.y):
		result.append(Vector2i(0, cb))
		result.append(Vector2i(_inner.x, cb))
	return result


## Lattice vertex strictly inside the playable rectangle (not on its border): never drawn.
func _is_hidden(a: int, b: int) -> bool:
	return a > _ring.x and a < _ring.x + _inner.x and b > _ring.y and b < _ring.y + _inner.y
