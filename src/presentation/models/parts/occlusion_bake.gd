extends RefCounted
## Analytic ambient occlusion baked into MeshKit meshes (TASK-085): the caller describes the
## occluding volumes with a few proxies – capsules / spheres (limbs, torso, head, pack) and caps
## (helmet shells: dark under the rim) – and `bake` multiplies each vertex's openness mask
## (COLOR.g, ADR 0012; the paint shaders darken by it) by the light the proxies leave it. No ray
## casting: a capsule occludes like the sphere at its closest point (cosine-weighted solid angle,
## r² / d² towards the vertex normal), a cap like a disc over the vertices below its rim. Vertices
## inside a proxy (joint overlaps, hidden seams) get a fixed amount. Distinct vertices are
## evaluated once and only against the capsules whose reach overlaps their grid cell. Pure
## geometry, deterministic.
##
## Units: occluders in the caller's units (e.g. metres); `bake(mesh, scale)` takes the mesh units
## per caller unit (0.1 for soldiers built in metres with a 0.1 base scale).

## Lowest openness a bake leaves (keeps deep cavities from going black).
const MIN_OPENNESS := 0.2
## Occlusion of a vertex inside a proxy.
const INSIDE := 0.45
## A capsule stops occluding at FALLOFF times its radius from its axis.
const FALLOFF := 2.75
## Size of the capsule grid's cells (caller units).
const CELL := 0.08

var _a := PackedVector3Array()
var _b := PackedVector3Array()
var _r := PackedFloat32Array()
var _s := PackedFloat32Array()
var _cap_c := PackedVector3Array()
var _cap_u := PackedVector3Array()
var _cap_r := PackedFloat32Array()
var _cap_s := PackedFloat32Array()
## Per capsule: b − a, 1 / |b − a|² (0 for a sphere), r².
var _ab := PackedVector3Array()
var _inv_len2 := PackedFloat32Array()
var _r2 := PackedFloat32Array()
## Capsule indices per grid cell (x fastest), made on the first evaluation after a change.
var _cells: Array[PackedInt32Array] = []
var _grid_origin := Vector3.ZERO
var _grid_size := Vector3i.ZERO


## Sphere of radius `r` at `c`.
func sphere(c: Vector3, r: float, strength := 1.0) -> void:
	capsule(c, c, r, strength)


## Capsule of radius `r` around the segment `a`–`b`; `strength` scales its occlusion.
func capsule(a: Vector3, b: Vector3, r: float, strength := 1.0) -> void:
	_a.append(a)
	_b.append(b)
	_r.append(r)
	_s.append(strength)
	_ab.append(b - a)
	_inv_len2.append(1.0 / (b - a).length_squared() if a != b else 0.0)
	_r2.append(r * r)
	_cells = []


## Cap (a helmet shell): a disc of `radius` at `centre` (the rim plane) with `axis` pointing up into
## the cap; darkens what lies below the rim, most under its middle and on up-facing surfaces.
func cap(centre: Vector3, axis: Vector3, radius: float, strength := 1.0) -> void:
	_cap_c.append(centre)
	_cap_u.append(axis.normalized())
	_cap_r.append(radius)
	_cap_s.append(strength)


## Occluders added so far.
func size() -> int:
	return _r.size() + _cap_r.size()


## Every mesh of `meshes` ({role: ArrayMesh}) baked, the keys and their order kept.
func bake_all(meshes: Dictionary, scale: float) -> Dictionary:
	var baked := {}
	for role: Variant in meshes:
		baked[role] = bake(meshes[role], scale)
	return baked


## `mesh` (one surface with normals and colours) with COLOR.g multiplied by the openness. Each
## distinct vertex is evaluated once: an indexed mesh as it is, a triangle list after merging its
## vertices in the engine (SurfaceTool.index) and expanding them back (`deindex`).
func bake(mesh: ArrayMesh, scale: float) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var indexed: bool = arrays[Mesh.ARRAY_INDEX] != null
	if not indexed:
		var st := SurfaceTool.new()
		st.create_from(mesh, 0)
		st.index()
		arrays = st.commit_to_arrays()
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_shade(arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], colors, 1.0 / scale)
	arrays[Mesh.ARRAY_COLOR] = colors
	if indexed:
		var out := ArrayMesh.new()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return out
	var expand := SurfaceTool.new()
	expand.create_from_arrays(arrays)
	expand.deindex()
	return expand.commit()


## Multiplies `colors[i].g` by the openness of vertex i (`verts` scaled by `inv` to caller units):
## `openness` inlined, as this loop is most of a soldier's build time.
func _shade(
	verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, inv: float
) -> void:
	if _cells.is_empty() and not _r.is_empty():
		_sort_cells()
	# Locals: member access is slower in this loop.
	var cells := _cells
	var aa := _a
	var abab := _ab
	var inv_len2 := _inv_len2
	var r2s := _r2
	var rs := _r
	var ss := _s
	var origin := _grid_origin
	var size := Vector3(_grid_size)
	var sx := _grid_size.x
	var sxy := _grid_size.x * _grid_size.y
	var caps := _cap_r.size()
	var cap_c := _cap_c
	var cap_u := _cap_u
	var reach2 := FALLOFF * FALLOFF
	for i in verts.size():
		var p := verts[i] * inv
		var n := normals[i]
		var ao := 1.0
		var g := (p - origin) / CELL
		if (
			g.x >= 0.0
			and g.y >= 0.0
			and g.z >= 0.0
			and g.x < size.x
			and g.y < size.y
			and g.z < size.z
		):
			for k in cells[int(g.x) + sx * int(g.y) + sxy * int(g.z)]:
				var a := aa[k]
				var ab := abab[k]
				var v := a + ab * clampf((p - a).dot(ab) * inv_len2[k], 0.0, 1.0) - p
				var d2 := v.length_squared()
				var r2 := r2s[k]
				if d2 >= r2 * reach2:
					continue
				if d2 <= r2:
					ao *= 1.0 - INSIDE * ss[k]
					continue
				var facing := n.dot(v)
				if facing <= 0.0:
					continue
				var d := sqrt(d2)
				var reach := rs[k] * FALLOFF
				ao *= 1.0 - facing / d * r2 / d2 * (1.0 - smoothstep(reach * 0.5, reach, d)) * ss[k]
		for k in caps:
			# Above a cap's rim plane (most of the body is below it, the helmet above): nothing.
			if (p - cap_c[k]).dot(cap_u[k]) < 0.0:
				ao *= 1.0 - _cap_occlusion(k, p, n)
		if ao < 1.0:
			var c := colors[i]
			colors[i] = Color(c.r, c.g * maxf(ao, MIN_OPENNESS), c.b, c.a)


## Light left at `p` (caller units) with the unit normal `n`: 1 open .. MIN_OPENNESS.
func openness(p: Vector3, n: Vector3) -> float:
	if _cells.is_empty() and not _r.is_empty():
		_sort_cells()
	var ao := 1.0
	var cell := Vector3i(((p - _grid_origin) / CELL).floor())
	if (
		not _r.is_empty()
		and cell.x >= 0
		and cell.y >= 0
		and cell.z >= 0
		and cell.x < _grid_size.x
		and cell.y < _grid_size.y
		and cell.z < _grid_size.z
	):
		for k in _cells[cell.x + _grid_size.x * (cell.y + _grid_size.y * cell.z)]:
			ao *= 1.0 - _capsule_occlusion(k, p, n)
	for k in _cap_r.size():
		ao *= 1.0 - _cap_occlusion(k, p, n)
	return maxf(ao, MIN_OPENNESS)


## Occlusion (0..1) of cap `k` at `p` with the normal `n`.
func _cap_occlusion(k: int, p: Vector3, n: Vector3) -> float:
	var u := _cap_u[k]
	var rel := p - _cap_c[k]
	var depth := -rel.dot(u)
	if depth < 0.0:
		return 0.0
	var radius := _cap_r[k]
	var rho := (rel + u * depth).length()
	var inside := 1.0 - smoothstep(radius * 0.85, radius * 1.25, rho)
	var facing := clampf(0.5 + 0.5 * n.dot(u), 0.0, 1.0)
	var cover := radius * radius / (radius * radius + depth * depth)
	return cover * inside * facing * _cap_s[k]


## Occlusion (0..1) of capsule `k` at `p` with the normal `n`.
func _capsule_occlusion(k: int, p: Vector3, n: Vector3) -> float:
	var a := _a[k]
	var ab := _b[k] - a
	var t := 0.0
	var len2 := ab.length_squared()
	if len2 > 0.0:
		t = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	var v := a + ab * t - p
	var d2 := v.length_squared()
	var r := _r[k]
	var reach := r * FALLOFF
	if d2 >= reach * reach:
		return 0.0
	if d2 <= r * r:
		return INSIDE * _s[k]
	var d := sqrt(d2)
	var facing := n.dot(v) / d
	if facing <= 0.0:
		return 0.0
	return facing * r * r / d2 * (1.0 - smoothstep(reach * 0.5, reach, d)) * _s[k]


## Capsule indices per grid cell (every capsule in the cells its reach overlaps).
func _sort_cells() -> void:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for k in _r.size():
		var reach := Vector3.ONE * _r[k] * FALLOFF
		lo = lo.min(_a[k].min(_b[k]) - reach)
		hi = hi.max(_a[k].max(_b[k]) + reach)
	_grid_origin = lo
	_grid_size = Vector3i(((hi - lo) / CELL).ceil()).max(Vector3i.ONE)
	var lists := []
	lists.resize(_grid_size.x * _grid_size.y * _grid_size.z)
	for i in lists.size():
		lists[i] = []
	for k in _r.size():
		var reach := Vector3.ONE * _r[k] * FALLOFF
		var first := Vector3i(((_a[k].min(_b[k]) - reach - lo) / CELL).floor()).max(Vector3i.ZERO)
		var last := Vector3i(((_a[k].max(_b[k]) + reach - lo) / CELL).floor()).min(
			_grid_size - Vector3i.ONE
		)
		for z in range(first.z, last.z + 1):
			for y in range(first.y, last.y + 1):
				for x in range(first.x, last.x + 1):
					(lists[x + _grid_size.x * (y + _grid_size.y * z)] as Array).append(k)
	_cells = []
	for list: Array in lists:
		_cells.append(PackedInt32Array(list))
