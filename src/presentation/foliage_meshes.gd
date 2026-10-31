class_name FoliageMeshes
extends RefCounted
## Pure procedural foliage geometry (TASK-028): lumpy lobed deciduous crowns, jagged tiered
## conifers, bushes, trunks and rocks. Meshes are built with SurfaceTool, cached in a static var
## and fully deterministic (a position hash, no random number generator). Crowns carry bent
## normals and baked ambient occlusion in vertex colours (darker towards the bottom).
## Reference: docs/design/v2/game_screen.scene.js `foliageGeo` / `rockGeo`.

## Deciduous lobes as [x, y, z, radius].
const LOBES: Array[Array] = [
	[0.0, 0.15, 0.0, 0.072],
	[0.042, 0.13, 0.02, 0.054],
	[-0.036, 0.135, 0.03, 0.054],
	[0.01, 0.128, -0.045, 0.054],
	[-0.01, 0.198, 0.004, 0.05],
]
const LOBE_SUBDIVISIONS := 2
## The far bush (`bush_far`): the same lobes one subdivision coarser (400 instead of 1600
## triangles), drawn beyond ScatterChunks.BUSH_LOD_DISTANCE where a bush is a few pixels wide.
const FAR_LOBE_SUBDIVISIONS := 1
const LOBE_JITTER := 0.4
const CONIFER_TIERS := 4
const CONIFER_SIDES := 10
const CONIFER_JITTER := 0.5
const DECIDUOUS_CENTER_Y := 0.15
const CONIFER_CENTER_Y := 0.16
const BUSH_VARIANT := 3
const TRUNK_SIDES := 6
const TRUNK_HEIGHT := 0.12
const TRUNK_RADIUS_BOTTOM := 0.014
const TRUNK_RADIUS_TOP := 0.008
const ROCK_RADIUS := 0.05
const ROCK_SUBDIVISIONS := 1

static var _cache: Dictionary = {}
static var _unit_spheres: Dictionary = {}


static func deciduous(variant: int) -> ArrayMesh:
	var key := "d%d" % variant
	if not _cache.has(key):
		_cache[key] = build_deciduous(variant)
	return _cache[key]


static func conifer(variant: int) -> ArrayMesh:
	var key := "c%d" % variant
	if not _cache.has(key):
		_cache[key] = build_conifer(variant)
	return _cache[key]


static func bush() -> ArrayMesh:
	return deciduous(BUSH_VARIANT)


static func bush_far() -> ArrayMesh:
	if not _cache.has("bush_far"):
		_cache["bush_far"] = build_deciduous(BUSH_VARIANT, FAR_LOBE_SUBDIVISIONS)
	return _cache["bush_far"]


static func trunk() -> ArrayMesh:
	if not _cache.has("trunk"):
		_cache["trunk"] = _build_trunk()
	return _cache["trunk"]


static func rock() -> ArrayMesh:
	if not _cache.has("rock"):
		_cache["rock"] = _build_rock()
	return _cache["rock"]


## Deterministic hash of a position into [0, 1).
static func hash3(x: float, y: float, z: float) -> float:
	var s := sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453
	return s - floor(s)


static func _smooth(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Unit icosphere as a flat list of triangle vertices (3 per triangle).
static func _unit_sphere(subdivisions: int) -> PackedVector3Array:
	if _unit_spheres.has(subdivisions):
		return _unit_spheres[subdivisions]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array[Vector3] = []
	for p: Vector3 in [
		Vector3(-1, t, 0),
		Vector3(1, t, 0),
		Vector3(-1, -t, 0),
		Vector3(1, -t, 0),
		Vector3(0, -1, t),
		Vector3(0, 1, t),
		Vector3(0, -1, -t),
		Vector3(0, 1, -t),
		Vector3(t, 0, -1),
		Vector3(t, 0, 1),
		Vector3(-t, 0, -1),
		Vector3(-t, 0, 1),
	]:
		v.append(p.normalized())
	var faces: Array[int] = [
		0,
		11,
		5,
		0,
		5,
		1,
		0,
		1,
		7,
		0,
		7,
		10,
		0,
		10,
		11,
		1,
		5,
		9,
		5,
		11,
		4,
		11,
		10,
		2,
		10,
		7,
		6,
		7,
		1,
		8,
		3,
		9,
		4,
		3,
		4,
		2,
		3,
		2,
		6,
		3,
		6,
		8,
		3,
		8,
		9,
		4,
		9,
		5,
		2,
		4,
		11,
		6,
		2,
		10,
		8,
		6,
		7,
		9,
		8,
		1,
	]
	var tris := PackedVector3Array()
	for i in range(0, faces.size(), 3):
		tris.append_array([v[faces[i]], v[faces[i + 1]], v[faces[i + 2]]])
	for _s in subdivisions:
		var next := PackedVector3Array()
		for i in range(0, tris.size(), 3):
			var a := tris[i]
			var b := tris[i + 1]
			var c := tris[i + 2]
			var ab := ((a + b) * 0.5).normalized()
			var bc := ((b + c) * 0.5).normalized()
			var ca := ((c + a) * 0.5).normalized()
			next.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
		tris = next
	_unit_spheres[subdivisions] = tris
	return tris


## One triangle with the reference direction (outward from its solid) used to orient the winding.
class Tri:
	var a: Vector3
	var b: Vector3
	var c: Vector3
	var outward: Vector3

	func _init(pa: Vector3, pb: Vector3, pc: Vector3, ref: Vector3) -> void:
		a = pa
		b = pb
		c = pc
		outward = ref

	## Outward face normal; also swaps b and c so the triangle is front-facing in Godot
	## (clockwise seen from outside).
	func orient() -> Vector3:
		var n := (b - a).cross(c - a)
		if n.dot(outward) > 0.0:
			var tmp := b
			b = c
			c = tmp
			n = -n
		return (-n).normalized()


## Uncached builder (the cached accessor is `deciduous`).
static func build_deciduous(variant: int, subdivisions: int = LOBE_SUBDIVISIONS) -> ArrayMesh:
	var tris: Array[Tri] = []
	var sphere := _unit_sphere(subdivisions)
	for li in LOBES.size():
		var lobe: Array = LOBES[li]
		var center := Vector3(lobe[0], lobe[1], lobe[2])
		var radius: float = lobe[3]
		var pts := PackedVector3Array()
		for u in sphere:
			var p := u * radius
			var f := (
				1.0 + (hash3(p.x * 90.0 + li, p.y * 90.0, p.z * 90.0 + variant) - 0.5) * LOBE_JITTER
			)
			pts.append(p * f + center)
		for i in range(0, pts.size(), 3):
			var mid := (pts[i] + pts[i + 1] + pts[i + 2]) / 3.0
			tris.append(Tri.new(pts[i], pts[i + 1], pts[i + 2], mid - center))
	return _finish_crown(tris, DECIDUOUS_CENTER_Y, false, variant)


## Uncached builder (the cached accessor is `conifer`).
static func build_conifer(variant: int) -> ArrayMesh:
	var tris: Array[Tri] = []
	for i in CONIFER_TIERS:
		var r := 0.085 - 0.018 * i
		var h := 0.12 - 0.012 * i
		var base := 0.08 + 0.052 * i
		var apex := Vector3(0.0, base + h, 0.0)
		var ring: Array[Vector3] = []
		for s in CONIFER_SIDES:
			var f := 1.0 + (hash3(s, i, variant) - 0.5) * CONIFER_JITTER
			var ang := TAU * s / CONIFER_SIDES
			ring.append(Vector3(cos(ang) * r * f, base, sin(ang) * r * f))
		for s in CONIFER_SIDES:
			var p0 := ring[s]
			var p1 := ring[(s + 1) % CONIFER_SIDES]
			var mid := (p0 + p1 + apex) / 3.0
			tris.append(Tri.new(p0, p1, apex, Vector3(mid.x, 0.0, mid.z)))
	return _finish_crown(tris, CONIFER_CENTER_Y, true, variant)


## Bent normals and baked AO vertex colours, then the SurfaceTool commit.
static func _finish_crown(
	tris: Array[Tri], center_y: float, conifer: bool, variant: int
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in tris:
		var face := tri.orient()
		for p: Vector3 in [tri.a, tri.b, tri.c]:
			var radial := Vector3(
				p.x, (p.y - center_y) * (0.4 if conifer else 1.0) + (0.04 if conifer else 0.0), p.z
			)
			var n := (radial.normalized() * 0.75 + face * 0.25).normalized()
			var ao := (
				0.5
				+ (
					0.5
					* _smooth(0.06, 0.24, p.y)
					* (0.7 + 0.3 * hash3(p.x * 200.0, p.y * 200.0, p.z * 200.0 + variant))
				)
			)
			var lh := 0.85 + 0.3 * hash3(p.x * 40.0, p.y * 40.0, p.z * 40.0)
			st.set_color(Color(ao * lh, ao * lh, ao))
			st.set_normal(n)
			st.add_vertex(p)
	return st.commit()


static func _build_trunk() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in TRUNK_SIDES:
		var a0 := TAU * s / TRUNK_SIDES
		var a1 := TAU * (s + 1) / TRUNK_SIDES
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var b0 := d0 * TRUNK_RADIUS_BOTTOM
		var b1 := d1 * TRUNK_RADIUS_BOTTOM
		var t0 := d0 * TRUNK_RADIUS_TOP + Vector3(0.0, TRUNK_HEIGHT, 0.0)
		var t1 := d1 * TRUNK_RADIUS_TOP + Vector3(0.0, TRUNK_HEIGHT, 0.0)
		for corners: Array in [[b0, t0, t1], [b0, t1, b1]]:
			var tri := Tri.new(corners[0], corners[1], corners[2], d0 + d1)
			tri.orient()
			for p: Vector3 in [tri.a, tri.b, tri.c]:
				st.set_normal(Vector3(p.x, 0.0, p.z).normalized())
				st.add_vertex(p)
	return st.commit()


static func _build_rock() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sphere := _unit_sphere(ROCK_SUBDIVISIONS)
	var pts := PackedVector3Array()
	for u in sphere:
		var p := u * ROCK_RADIUS
		pts.append(p * (0.75 + hash3(p.x * 80.0, p.y * 80.0, p.z * 80.0) * 0.5))
	for i in range(0, pts.size(), 3):
		var mid := (pts[i] + pts[i + 1] + pts[i + 2]) / 3.0
		var tri := Tri.new(pts[i], pts[i + 1], pts[i + 2], mid)
		var face := tri.orient()
		for p: Vector3 in [tri.a, tri.b, tri.c]:
			st.set_normal(face)
			st.add_vertex(p)
	return st.commit()
