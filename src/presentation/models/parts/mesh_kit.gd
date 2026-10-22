class_name MeshKit
extends RefCounted
## Mesh builder for one material (TASK-030, ADR 0012): chamfered and smooth primitives that write
## flat or smooth triangles, normals and the weathering vertex masks into one SurfaceTool. Port of
## the model detail study's kits (docs/design/showcase/); `MeshKits` holds one kit per material.
##
## Coordinates: primitives take the caller's units (usually metres). `xf` (rigid) places them;
## the optional base transform maps them into the pivot the mesh is added to: a `Frame` (vehicle
## metres -> model space, see vehicle_frame.gd; it mirrors x) followed by `base` (e.g.
## `Frame.to_local(turret)`, or a uniform scale such as 0.1 for soldiers built in metres). Normals
## use the inverse transpose of that map, and every triangle is wound after mapping, so mirrored
## frames stay correct: front faces are clockwise seen from outside, i.e.
## `(v2 - v0).cross(v1 - v0)` points along the vertex normals.
##
## Vertex colour (ARRAY_COLOR) = the mask contract with the paint shader:
## - `r` = chamfer / edge: 1 on chamfer bands, box corners, plate rims, short diagonal lathe
##   segments and tube end caps, 0 on faces – paint wear.
## - `g` = openness: 1 open, towards 0 in cavities – `openness` (set by the caller for recessed
##   parts), multiplied by `INNER_OPENNESS` on a lathe's inner wall (profile facing the axis) –
##   cavity darkening.
## - `b` = per-part tint seed in [0, 1): a hash of the part centre (after `xf`), constant over one
##   primitive call, deterministic (no RNG) – per-part tint.
## Channels are stored as 8-bit unorm (Godot's default vertex colour format): 256 levels each.
##
## Pure geometry: no scene tree, autoloads or randomness.

const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")
## Openness (vertex g factor) of a lathe's inner wall.
const INNER_OPENNESS := 0.35
## Triangles with a smaller squared cross product (in the caller's units) are dropped.
const MIN_CROSS_SQ := 1e-16
const _HASH_DIR := Vector3(12.9898, 78.233, 37.719)

## Placement of the primitives in the caller's units (rotation + translation only).
var xf := Transform3D.IDENTITY
## Vertex g of the following primitives (1 = open, lower = cavity).
var openness := 1.0
## Longest diagonal lathe profile segment that still counts as a chamfer (`r` = 1), caller units.
var chamfer_max := 0.06
## Triangles written so far.
var count := 0

var _st := SurfaceTool.new()
var _map := Transform3D.IDENTITY
var _normal_map := Basis.IDENTITY
var _tint := 0.5
var _inner := 1.0


## `frame` (optional) maps vehicle metres into model space, `base` then maps model space into the
## pivot the mesh is added to.
func _init(frame: Frame = null, base := Transform3D.IDENTITY) -> void:
	var to_model := Transform3D.IDENTITY
	if frame != null:
		var o := frame.p(0.0, 0.0, 0.0)
		to_model = Transform3D(
			Basis(
				frame.p(1.0, 0.0, 0.0) - o, frame.p(0.0, 1.0, 0.0) - o, frame.p(0.0, 0.0, 1.0) - o
			),
			o
		)
	_map = base * to_model
	_normal_map = _map.basis.inverse().transposed()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


## The triangles so far as one surface (vertex, normal, colour; not indexed).
func commit() -> ArrayMesh:
	return _st.commit()


## Deterministic tint seed in [0, 1) of a point (the part centre).
static func tint_seed(at: Vector3) -> float:
	return fposmod(sin(at.dot(_HASH_DIR)) * 43758.5453, 1.0)


# --- Faces ----------------------------------------------------------------------------------------


## One triangle with per-vertex normals `na`..`nc` (outward) and edge flag `e`; the winding is
## chosen from the normals.
func tri(
	a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, e := 0.0
) -> void:
	_set_tint((a + b + c) / 3.0)
	_tri(a, b, c, na, nb, nc, e)


## Flat convex polygon with outward normal `n`.
func poly(pts: Array, n: Vector3, e := 0.0) -> void:
	_set_tint(_centroid(pts))
	_poly(pts, n, e)


## Flat convex polygon, normal from its points, turned away from `inside`.
func poly_auto(pts: Array, inside: Vector3, e := 0.0) -> void:
	_set_tint(_centroid(pts))
	_poly_auto(pts, inside, e)


# --- Boxes and soft shapes ----------------------------------------------------------------------


## Chamfered box centred at `c` (size `s`, chamfer `b`, 0 = sharp), rotated by `rot`: 12 triangles
## sharp, plus chamfer bands (`r` = 1) and corner triangles when `b` > 0.
func cbox(c: Vector3, s: Vector3, b: float, rot := Basis.IDENTITY) -> void:
	var saved := xf
	xf = xf * Transform3D(rot, c)
	_set_tint(Vector3.ZERO)
	var h := s / 2.0
	b = clampf(b, 0.0, minf(h.x, minf(h.y, h.z)) * 0.9)
	var i := h - Vector3.ONE * b
	for a in 3:
		var u := (a + 1) % 3
		var v := (a + 2) % 3
		for sa: float in [-1.0, 1.0]:
			var pts := []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[a] = sa * h[a]
				p[u] = corner.x * i[u]
				p[v] = corner.y * i[v]
				pts.append(p)
			var n := Vector3.ZERO
			n[a] = sa
			_poly(pts, n)
	if b > 0.0:
		_cbox_chamfers(h, i)
	xf = saved


## Superellipsoid centred at `c` filling size `s` (rotated by `rot`): `e` = 1 is an ellipsoid
## (implicit exponent 2 / e = 2), smaller values are boxier with rounded, smooth-shaded edges
## (bags, tarps, pads). `rings` must be even and `sides` a multiple of 4 for the AABB to be `s`.
func pillow(
	c: Vector3, s: Vector3, rot := Basis.IDENTITY, e := 0.35, rings := 10, sides := 16
) -> void:
	var saved := xf
	xf = xf * Transform3D(rot, c)
	_set_tint(Vector3.ZERO)
	var h := s / 2.0
	var grid := []
	var normals := []
	for i in rings + 1:
		var lat := lerpf(-PI / 2.0, PI / 2.0, float(i) / rings)
		var row := []
		var nrow := []
		for j in sides:
			var lon := TAU * j / sides
			var d := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var q := Vector3(_spow(d.x, e), _spow(d.y, e), _spow(d.z, e))
			var n := Vector3(
				_spow(d.x, 2.0 - e) / h.x, _spow(d.y, 2.0 - e) / h.y, _spow(d.z, 2.0 - e) / h.z
			)
			row.append(q * h)
			nrow.append(n.normalized() if n.length_squared() > 1e-12 else d)
		grid.append(row)
		normals.append(nrow)
	_grid(grid, normals)
	xf = saved


## Box spanning x0..x1, h0..h1, z0 +- hw (vehicle axes), chamfer `b`.
func slab(x0: float, x1: float, h0: float, h1: float, hw: float, z0 := 0.0, b := 0.02) -> void:
	cbox(
		Vector3((x0 + x1) / 2.0, (h0 + h1) / 2.0, z0),
		Vector3(absf(x1 - x0), absf(h1 - h0), hw * 2.0),
		b
	)


## The same slab on both sides (z0 = +-z).
func pair(x0: float, x1: float, h0: float, h1: float, hw: float, z: float, b := 0.02) -> void:
	for s: float in [-1.0, 1.0]:
		slab(x0, x1, h0, h1, hw, s * z, b)


# --- Turned parts -------------------------------------------------------------------------------


## Lathe around local +Y of `rot` at `c`: `prof` = Vector2(radius, y), from the top down around the
## outside (a profile point with radius 0 closes the end). Diagonal segments shorter than
## `chamfer_max` are chamfers (`r` = 1); segments facing the axis are an inner wall (`g` lowered).
## `smooth` = false gives flat facets (bolt heads, nuts).
func lathe(c: Vector3, rot: Basis, prof: Array, sides: int, smooth := true) -> void:
	var saved := xf
	xf = xf * Transform3D(rot, c)
	_set_tint(Vector3.ZERO)
	for j in prof.size() - 1:
		var p0: Vector2 = prof[j]
		var p1: Vector2 = prof[j + 1]
		var d := p1 - p0
		if d.length() < 1e-6:
			continue
		var n2 := Vector2(-d.y, d.x).normalized()
		var e := 1.0 if absf(d.x) > 1e-5 and absf(d.y) > 1e-5 and d.length() < chamfer_max else 0.0
		_inner = INNER_OPENNESS if n2.x < -1e-3 else 1.0
		for k in sides:
			var t0 := TAU * k / sides
			var t1 := TAU * ((k + 1) % sides) / sides
			var c0 := Vector3(cos(t0), 0.0, sin(t0))
			var c1 := Vector3(cos(t1), 0.0, sin(t1))
			var v00 := c0 * p0.x + Vector3(0, p0.y, 0)
			var v01 := c1 * p0.x + Vector3(0, p0.y, 0)
			var v10 := c0 * p1.x + Vector3(0, p1.y, 0)
			var v11 := c1 * p1.x + Vector3(0, p1.y, 0)
			var n0 := c0 * n2.x + Vector3(0, n2.y, 0)
			var n1 := c1 * n2.x + Vector3(0, n2.y, 0)
			if not smooth:
				var cm := (c0 + c1).normalized()
				n0 = cm * n2.x + Vector3(0, n2.y, 0)
				n1 = n0
			_tri(v00, v01, v11, n0, n1, n1, e)
			_tri(v00, v11, v10, n0, n1, n0, e)
	_inner = 1.0
	xf = saved


## Closed cylinder of radius `r`, `length` along `dir`, centred at `c`, rims chamfered by `b`.
func rod(c: Vector3, dir: Vector3, r: float, length: float, sides := 12, b := 0.0) -> void:
	var hl := length / 2.0
	var prof: Array
	if b > 0.0:
		prof = [
			Vector2(0, hl),
			Vector2(r - b, hl),
			Vector2(r, hl - b),
			Vector2(r, -hl + b),
			Vector2(r - b, -hl),
			Vector2(0, -hl)
		]
	else:
		prof = [Vector2(0, hl), Vector2(r, hl), Vector2(r, -hl), Vector2(0, -hl)]
	lathe(c, Frame.axis_basis(dir), prof, sides)


## Hex bolt head (flat facets, open underside) on a surface at `c` facing `dir`.
func bolt(c: Vector3, dir: Vector3, r := 0.022) -> void:
	var hgt := r * 0.7
	lathe(c, Frame.axis_basis(dir), [Vector2(0, hgt), Vector2(r, hgt), Vector2(r, 0.0)], 6, false)


# --- Lofts and extrusions -----------------------------------------------------------------------


## Rings of points connected in order (same count, convex cross-sections), capped at both ends;
## `edges[i]` is the edge flag of the band between ring i and i + 1.
func stack(rings: Array, edges: Array) -> void:
	var centre := Vector3.ZERO
	var total := 0
	for ring: Array in rings:
		for p: Vector3 in ring:
			centre += p
			total += 1
	centre /= total
	_set_tint(centre)
	var n := (rings[0] as Array).size()
	for r in rings.size() - 1:
		var a: Array = rings[r]
		var b: Array = rings[r + 1]
		for i in n:
			var j := (i + 1) % n
			_poly_auto([a[i], a[j], b[j], b[i]], centre, edges[r])
	_poly_auto(rings[0], centre)
	_poly_auto(rings[rings.size() - 1], centre)


## Loft of convex plan outlines (Vector2(x, z), same count) from h0 to h1, the roof edge chamfered
## by `b`.
func loft(bottom: Array, top: Array, h0: float, h1: float, b: float) -> void:
	var inner := _offset(_ccw(top), -b)
	var lo := []
	var mid := []
	var hi := []
	for p: Vector2 in _ccw(bottom):
		lo.append(Vector3(p.x, h0, p.y))
	for p: Vector2 in _ccw(top):
		mid.append(Vector3(p.x, h1 - b, p.y))
	for p: Vector2 in inner:
		hi.append(Vector3(p.x, h1, p.y))
	stack([lo, mid, hi], [0.0, 1.0])


## Prism of an outline (any simple polygon, also non-convex: gears, skirts) in the (u, v) plane at
## `o`, from w0 to w1 along `w`, both rims chamfered by `b` (`r` = 1).
func plate(
	outline: Array, o: Vector3, u: Vector3, v: Vector3, w: Vector3, w0: float, w1: float, b := 0.0
) -> void:
	var ring := _ccw(outline)
	var inner := _offset(ring, -b) if b > 0.0 else ring
	var at := func(p: Vector2, depth: float) -> Vector3: return o + u * p.x + v * p.y + w * depth
	var mid := Vector2.ZERO
	for p: Vector2 in ring:
		mid += p
	_set_tint(at.call(mid / ring.size(), (w0 + w1) / 2.0))
	var n := ring.size()
	for i in n:
		var j := (i + 1) % n
		var d: Vector2 = (ring[j] as Vector2) - (ring[i] as Vector2)
		var n2 := Vector2(d.y, -d.x).normalized()
		var side := (u * n2.x + v * n2.y).normalized()
		_poly(
			[
				at.call(ring[i], w0 + b),
				at.call(ring[j], w0 + b),
				at.call(ring[j], w1 - b),
				at.call(ring[i], w1 - b)
			],
			side
		)
		if b > 0.0:
			_poly(
				[
					at.call(ring[i], w1 - b),
					at.call(ring[j], w1 - b),
					at.call(inner[j], w1),
					at.call(inner[i], w1)
				],
				(side + w).normalized(),
				1.0
			)
			_poly(
				[
					at.call(ring[i], w0 + b),
					at.call(ring[j], w0 + b),
					at.call(inner[j], w0),
					at.call(inner[i], w0)
				],
				(side - w).normalized(),
				1.0
			)
	var idx := Geometry2D.triangulate_polygon(PackedVector2Array(inner))
	if idx.is_empty():
		push_error("MeshKit.plate: the outline could not be triangulated (self-intersecting?)")
	for t in range(0, idx.size(), 3):
		var a: Vector2 = inner[idx[t]]
		var bb: Vector2 = inner[idx[t + 1]]
		var c: Vector2 = inner[idx[t + 2]]
		_poly([at.call(a, w1), at.call(bb, w1), at.call(c, w1)], w)
		_poly([at.call(a, w0), at.call(bb, w0), at.call(c, w0)], -w)


## Side profile (Vector2(x, h) in vehicle axes) extruded across z0 +- hw, rims chamfered by `b`.
func profile(points: Array, hw: float, z0 := 0.0, b := 0.03) -> void:
	plate(points, Vector3(0, 0, z0), Vector3.RIGHT, Vector3.UP, Vector3.BACK, -hw, hw, b)


# --- Swept shapes -------------------------------------------------------------------------------


## Smooth elliptic rings along the polyline `path`, capped (caps `r` = 0): `radii[i]` =
## Vector2(radius along the side axis, radius along the other axis). The side axis starts as
## `side0` (projected off the first tangent) and is parallel-transported along the path, so the
## rings do not twist. A radius of 0 closes the shape in a point (limbs, tapered straps).
func sweep(path: Array, radii: Array, sides := 12, side0 := Vector3.BACK) -> void:
	_sweep(path, radii, sides, side0, 0.0)


## Round tube of radius `r` along `path` (cables, rails, handles, straps), smooth, end caps flagged
## as edges (`r` = 1).
func tube(path: Array, r: float, sides := 8) -> void:
	if path.size() < 2:
		push_error("MeshKit.tube needs at least 2 path points")
		return
	var radii := []
	for p: Vector3 in path:
		radii.append(Vector2(r, r))
	var t := ((path[1] as Vector3) - (path[0] as Vector3)).normalized()
	_sweep(path, radii, sides, Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT, 1.0)


## Ring frames of a sweep: per path point [tangent, side axis] (unit, perpendicular). The tangent
## is the segment direction at the ends and the bisector of the two segments at inner points; the
## side axis is rotated from point to point by the minimal rotation between the tangents (parallel
## transport, no twist).
static func sweep_frames(path: Array, side0: Vector3) -> Array:
	assert(path.size() >= 2, "a sweep path needs at least 2 points")
	var frames := []
	var side := side0
	var prev := Vector3.ZERO
	for i in path.size():
		var t := _path_tangent(path, i)
		if i > 0:
			side = _transport(side, prev, t)
		side -= t * side.dot(t)
		if side.length_squared() < 1e-8:
			side = t.cross(Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT)
		side = side.normalized()
		frames.append([t, side])
		prev = t
	return frames


## Points of an arc: centre `c`, radius `r`, from angle a0 to a1 in the plane (e1, e2).
static func arc(
	c: Vector3, r: float, e1: Vector3, e2: Vector3, a0: float, a1: float, segments: int
) -> Array:
	var pts := []
	for i in segments + 1:
		var a := lerpf(a0, a1, float(i) / segments)
		pts.append(c + (e1 * cos(a) + e2 * sin(a)) * r)
	return pts


# --- Internals ----------------------------------------------------------------------------------


func _set_tint(at: Vector3) -> void:
	_tint = tint_seed(xf * at)


func _tri(
	a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, e: float
) -> void:
	var la := xf * a
	var lb := xf * b
	var lc := xf * c
	if (lb - la).cross(lc - la).length_squared() < MIN_CROSS_SQ:
		return
	var ma := _map * la
	var mb := _map * lb
	var mc := _map * lc
	var n0 := (_normal_map * (xf.basis * na)).normalized()
	var n1 := (_normal_map * (xf.basis * nb)).normalized()
	var n2 := (_normal_map * (xf.basis * nc)).normalized()
	if (mb - ma).cross(mc - ma).dot(n0 + n1 + n2) > 0.0:
		var t := mb
		mb = mc
		mc = t
		var tn := n1
		n1 = n2
		n2 = tn
	var col := Color(e, openness * _inner, _tint)
	_st.set_color(col)
	_st.set_normal(n0)
	_st.add_vertex(ma)
	_st.set_color(col)
	_st.set_normal(n1)
	_st.add_vertex(mb)
	_st.set_color(col)
	_st.set_normal(n2)
	_st.add_vertex(mc)
	count += 1


func _poly(pts: Array, n: Vector3, e := 0.0) -> void:
	for i in range(1, pts.size() - 1):
		_tri(pts[0], pts[i], pts[i + 1], n, n, n, e)


func _poly_auto(pts: Array, inside: Vector3, e := 0.0) -> void:
	var a: Vector3 = pts[0]
	var n := ((pts[1] as Vector3) - a).cross((pts[2] as Vector3) - a)
	if n.length_squared() < 1e-14 and pts.size() > 3:
		n = ((pts[2] as Vector3) - a).cross((pts[3] as Vector3) - a)
	if n.length_squared() < 1e-14:
		return
	if n.dot(_centroid(pts) - inside) < 0.0:
		n = -n
	_poly(pts, n.normalized(), e)


## Chamfer bands along the 12 edges and the 8 corner triangles of a box with half size `h` and
## inner half size `i`.
func _cbox_chamfers(h: Vector3, i: Vector3) -> void:
	for a in 3:
		var u := (a + 1) % 3
		var v := (a + 2) % 3
		for sa: float in [-1.0, 1.0]:
			for su: float in [-1.0, 1.0]:
				var p1 := Vector3.ZERO
				p1[a] = sa * h[a]
				p1[u] = su * i[u]
				var p2 := Vector3.ZERO
				p2[a] = sa * i[a]
				p2[u] = su * h[u]
				var q0 := p1
				var q1 := p2
				var q2 := p2
				var q3 := p1
				q0[v] = -i[v]
				q1[v] = -i[v]
				q2[v] = i[v]
				q3[v] = i[v]
				var n := Vector3.ZERO
				n[a] = sa
				n[u] = su
				_poly([q0, q1, q2, q3], n.normalized(), 1.0)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var pts := [
					Vector3(sx * h.x, sy * i.y, sz * i.z),
					Vector3(sx * i.x, sy * h.y, sz * i.z),
					Vector3(sx * i.x, sy * i.y, sz * h.z),
				]
				_poly(pts, Vector3(sx, sy, sz).normalized(), 1.0)


## Quads between consecutive rows of a point grid; each row wraps around.
func _grid(grid: Array, normals: Array) -> void:
	var sides := (grid[0] as Array).size()
	for i in grid.size() - 1:
		for j in sides:
			var k := (j + 1) % sides
			_tri(
				grid[i][j],
				grid[i][k],
				grid[i + 1][k],
				normals[i][j],
				normals[i][k],
				normals[i + 1][k],
				0.0
			)
			_tri(
				grid[i][j],
				grid[i + 1][k],
				grid[i + 1][j],
				normals[i][j],
				normals[i + 1][k],
				normals[i + 1][j],
				0.0
			)


func _sweep(path: Array, radii: Array, sides: int, side0: Vector3, cap_edge: float) -> void:
	var n := path.size()
	var centre := Vector3.ZERO
	for p: Vector3 in path:
		centre += p
	_set_tint(centre / n)
	var frames := sweep_frames(path, side0)
	var rings := []
	var normals := []
	for i in n:
		var t: Vector3 = frames[i][0]
		var side: Vector3 = frames[i][1]
		var other := side.cross(t)
		var r: Vector2 = radii[i]
		var apex := -t if i == 0 else t
		var ring := []
		var nr := []
		for k in sides:
			var a := TAU * k / sides
			ring.append((path[i] as Vector3) + side * cos(a) * r.x + other * sin(a) * r.y)
			# Ellipse normal (cos / rx, sin / ry), scaled by rx * ry so a zero radius stays finite.
			var nn := side * cos(a) * r.y + other * sin(a) * r.x
			nr.append(nn.normalized() if nn.length_squared() > 1e-20 else apex)
		rings.append(ring)
		normals.append(nr)
	_grid(rings, normals)
	var t0 := -(frames[0][0] as Vector3)
	var t1: Vector3 = frames[n - 1][0]
	for k in range(1, sides - 1):
		_tri(rings[0][0], rings[0][k], rings[0][k + 1], t0, t0, t0, cap_edge)
		_tri(rings[n - 1][0], rings[n - 1][k], rings[n - 1][k + 1], t1, t1, t1, cap_edge)


## sign(x) * |x|^e; |x| below 1e-9 (cos of a right angle) counts as 0, so poles and the rings
## extremes are exact.
static func _spow(x: float, e: float) -> float:
	if absf(x) < 1e-9:
		return 0.0
	return signf(x) * pow(absf(x), e)


static func _centroid(pts: Array) -> Vector3:
	var mid := Vector3.ZERO
	for p: Vector3 in pts:
		mid += p
	return mid / pts.size()


static func _path_tangent(path: Array, i: int) -> Vector3:
	var n := path.size()
	if i == 0:
		return ((path[1] as Vector3) - (path[0] as Vector3)).normalized()
	if i == n - 1:
		return ((path[i] as Vector3) - (path[i - 1] as Vector3)).normalized()
	var after := ((path[i + 1] as Vector3) - (path[i] as Vector3)).normalized()
	var before := ((path[i] as Vector3) - (path[i - 1] as Vector3)).normalized()
	var t := after + before
	return t.normalized() if t.length_squared() > 1e-8 else after


## `v` rotated by the minimal rotation that takes unit `from` to unit `to`.
static func _transport(v: Vector3, from: Vector3, to: Vector3) -> Vector3:
	var axis := from.cross(to)
	var s := axis.length()
	if s < 1e-9:
		return v
	return v.rotated(axis / s, atan2(s, from.dot(to)))


static func _ccw(outline: Array) -> Array:
	var area := 0.0
	for i in outline.size():
		area += (outline[i] as Vector2).cross(outline[(i + 1) % outline.size()])
	if area >= 0.0:
		return outline.duplicate()
	var reversed := outline.duplicate()
	reversed.reverse()
	return reversed


## Outline moved by `distance` along its outward normals (negative = inwards), miter limited.
static func _offset(path: Array, distance: float) -> Array:
	var result := []
	var n := path.size()
	for i in n:
		var before: Vector2 = (path[i] as Vector2) - (path[(i - 1 + n) % n] as Vector2)
		var after: Vector2 = (path[(i + 1) % n] as Vector2) - (path[i] as Vector2)
		var na := Vector2(before.y, -before.x).normalized()
		var nb := Vector2(after.y, -after.x).normalized()
		var bis := (na + nb).normalized()
		var scale := 1.0 / maxf(bis.dot(na), 0.35)
		result.append((path[i] as Vector2) + bis * distance * scale)
	return result
