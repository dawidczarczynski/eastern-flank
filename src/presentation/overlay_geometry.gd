class_name OverlayGeometry
extends RefCounted
## Pure geometry for map overlays (reach wash, rings, path dots, hover pulse).
## Port of patchGeo / ringGeo / the path curve in docs/design/game_screen.scene.js.
## Hexes are pointy-top with corners at 60°·i − 30°, like Hex.to_world.

const _SAMPLES_PER_SEGMENT := 32
const MAX_DOTS_POINTS := 80
const SKIPPED_POINTS := 2


static func _corner_dir(i: int) -> Vector2:
	var a := deg_to_rad(60.0 * i - 30.0)
	return Vector2(cos(a), sin(a))


## Filled hexagon as a triangle list in XZ: 6 sectors, each subdivided n×n.
static func hex_patch(center: Vector2, scale: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for s in 6:
		var b := _corner_dir(s) * scale
		var c := _corner_dir(s + 1) * scale
		for i in n:
			for j in n - i:
				out.append(center + (b * i + c * j) / n)
				out.append(center + (b * (i + 1) + c * j) / n)
				out.append(center + (b * i + c * (j + 1)) / n)
				if j < n - i - 1:
					out.append(center + (b * (i + 1) + c * j) / n)
					out.append(center + (b * (i + 1) + c * (j + 1)) / n)
					out.append(center + (b * i + c * (j + 1)) / n)
	return out


## Hexagonal ring between radii r0 and r1 as a triangle list in XZ.
static func hex_ring(center: Vector2, r0: float, r1: float, segments: int) -> PackedVector2Array:
	var total := 6 * segments
	var dirs := PackedVector2Array()
	for k in total:
		var s := k / segments
		var t := float(k % segments) / segments
		dirs.append(_corner_dir(s).lerp(_corner_dir(s + 1), t))
	var out := PackedVector2Array()
	for k in total:
		var d0 := dirs[k]
		var d1 := dirs[(k + 1) % total]
		var a := center + d0 * r0
		var b := center + d0 * r1
		var c := center + d1 * r0
		var d := center + d1 * r1
		out.append_array([a, c, b, b, c, d])
	return out


## Lifts XZ points onto the surface: y = ground_height + lift.
static func drape(
	points: PackedVector2Array, surface: TerrainSurface, lift: float
) -> PackedVector3Array:
	return drape_with(points, surface.ground_height, lift)


## Same as drape() with any height function (x: float, z: float) -> float, e.g. the cheaper
## height of the drawn terrain mesh.
static func drape_with(
	points: PackedVector2Array, height: Callable, lift: float
) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(points.size())
	for i in points.size():
		var p := points[i]
		out[i] = Vector3(p.x, float(height.call(p.x, p.y)) + lift, p.y)
	return out


## Uniform Catmull-Rom through `centers` (end points duplicated), resampled to count + 1
## points at equal arc length.
static func curve_points(centers: PackedVector2Array, count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if centers.is_empty():
		return out
	if centers.size() == 1 or count <= 0:
		out.append(centers[0])
		return out
	var dense := PackedVector2Array()
	var last := centers.size() - 1
	for seg in last:
		var p0 := centers[maxi(seg - 1, 0)]
		var p1 := centers[seg]
		var p2 := centers[seg + 1]
		var p3 := centers[mini(seg + 2, last)]
		for k in _SAMPLES_PER_SEGMENT:
			var t := float(k) / _SAMPLES_PER_SEGMENT
			dense.append(_catmull_rom(p0, p1, p2, p3, t))
	dense.append(centers[last])
	var lengths := PackedFloat64Array([0.0])
	for i in range(1, dense.size()):
		lengths.append(lengths[i - 1] + dense[i].distance_to(dense[i - 1]))
	var total := lengths[lengths.size() - 1]
	var idx := 1
	for k in count + 1:
		var target := total * k / count
		while idx < dense.size() - 1 and lengths[idx] < target:
			idx += 1
		var span := lengths[idx] - lengths[idx - 1]
		var f := 0.0 if span <= 0.0 else clampf((target - lengths[idx - 1]) / span, 0.0, 1.0)
		out.append(dense[idx - 1].lerp(dense[idx], f))
	return out


static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return (
		0.5
		* (
			2.0 * p1
			+ (p2 - p0) * t
			+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3
		)
	)


## Number of dots drawn for a path of `tiles` tiles (unit tile included).
static func path_dot_count(tiles: int) -> int:
	return maxi(0, mini(MAX_DOTS_POINTS, (tiles - 1) * 5) - 1)


## Hover ring opacity: 0.6 + 0.25·sin(t / 260 ms).
static func hover_alpha(time_ms: float) -> float:
	return 0.6 + 0.25 * sin(time_ms / 260.0)


## Outer boundary of a set of hex tiles: every tile edge whose neighbour is not in `coords`,
## as consecutive point pairs (a0, b0, a1, b1, ...) in XZ. `size` is the hex corner distance.
static func boundary_edges(coords: Array[Vector2i], size: float) -> PackedVector2Array:
	var members := {}
	for c in coords:
		members[c] = true
	var out := PackedVector2Array()
	for c in coords:
		var w := Hex.to_world(c, size)
		var center := Vector2(w.x, w.z)
		for d in Hex.DIRECTIONS:
			if members.has(c + d):
				continue
			var edge := _edge_towards(d)
			out.append(center + _corner_dir(edge) * size)
			out.append(center + _corner_dir(edge + 1) * size)
	return out


## Index i of the edge (between corner i and i + 1) facing the neighbour in direction `d`.
## Edge i faces the angle 60°·i.
static func _edge_towards(d: Vector2i) -> int:
	var w := Hex.to_world(d, 1.0)
	return posmod(roundi(rad_to_deg(atan2(w.z, w.x)) / 60.0), 6)


## Thin ribbon (triangle list in XZ) along each edge pair from boundary_edges(), `width` wide,
## each edge split into `subdivisions` pieces so the draped ribbon follows the terrain. Pieces
## overlap by half a width so corners stay closed.
static func edge_ribbons(
	edges: PackedVector2Array, width: float, subdivisions: int
) -> PackedVector2Array:
	var out := PackedVector2Array()
	var half := width / 2.0
	for e in edges.size() / 2:
		var a := edges[e * 2]
		var b := edges[e * 2 + 1]
		var dir := (b - a).normalized()
		var normal := Vector2(-dir.y, dir.x) * half
		for s in subdivisions:
			var p0 := a.lerp(b, float(s) / subdivisions)
			var p1 := a.lerp(b, float(s + 1) / subdivisions)
			if s == 0:
				p0 -= dir * half
			if s == subdivisions - 1:
				p1 += dir * half
			out.append_array([p0 - normal, p1 - normal, p0 + normal])
			out.append_array([p0 + normal, p1 - normal, p1 + normal])
	return out
