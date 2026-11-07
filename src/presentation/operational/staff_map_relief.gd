class_name StaffMapRelief
extends RefCounted
## The stylised relief of the staff map (TASK-125), pure: per-hex ground height (hex units, the
## exaggerated height over the mean land height) and hillshade, interpolated linearly over the
## lattice of hex centres (the triangles StaffMapLayers uses), so the surface is continuous across
## hexes. Picking casts the camera ray against this surface.

const SQRT3 := 1.7320508
## A ray this close above the surface counts as touching it (grazes a peak), hex units.
const HIT_EPSILON := 0.001

var min_height := 0.0
var max_height := 0.0
var _heights := {}  # Vector2i -> float, hex units
var _shades := {}  # Vector2i -> float, hillshade minus the flat-ground value


## `unit_m`: metres per hex unit (hex spacing / sqrt 3); `exaggeration` over true scale; light
## azimuth / altitude in degrees, `z_factor` the slope exaggeration of the shading only.
func _init(
	grid: HexGrid,
	unit_m: float,
	exaggeration: float,
	azimuth := 315.0,
	altitude := 38.0,
	z_factor := 1.0
) -> void:
	var tiles := grid.coords()
	var base := 0.0
	var land := 0
	for c in tiles:
		if grid.get_terrain(c) != Terrain.Type.WATER:
			base += height_m(grid, c)
			land += 1
	base = base / land if land > 0 else 0.0
	var first := true
	for c in tiles:
		var h := (height_m(grid, c) - base) * exaggeration / unit_m
		_heights[c] = h
		min_height = h if first else minf(min_height, h)
		max_height = h if first else maxf(max_height, h)
		first = false
	var az := deg_to_rad(azimuth)
	var alt := deg_to_rad(altitude)
	# Towards the light in (east, south, up).
	var light := Vector3(cos(alt) * sin(az), -cos(alt) * cos(az), sin(alt))
	var spacing_m := unit_m * SQRT3
	for c in tiles:
		if grid.get_terrain(c) == Terrain.Type.WATER:
			_shades[c] = 0.0
			continue
		var g := _gradient(grid, c) / spacing_m * z_factor
		var normal := Vector3(-g.x, -g.y, 1.0).normalized()
		_shades[c] = maxf(normal.dot(light), 0.0) - sin(alt)


## Height of a hex in metres (imported maps) or from the game elevation.
static func height_m(grid: HexGrid, c: Vector2i) -> float:
	return grid.elevation_m(c) if grid.has_elevation_m(c) else grid.elevation(c) * 1000.0


func height_of(c: Vector2i) -> float:
	return _heights.get(c, 0.0)


func shade_of(c: Vector2i) -> float:
	return _shades.get(c, 0.0)


## Surface height at a map point (hex units, x east / y south).
func height_at(point: Vector2) -> float:
	return _sample(_heights, point)


## Hillshade offset at a map point (0 = flat ground, > 0 lit, < 0 shaded).
func shade_at(point: Vector2) -> float:
	return _sample(_shades, point)


func surface_point(point: Vector2) -> Vector3:
	return Vector3(point.x, height_at(point), point.y)


## Where a downward ray meets the surface, as a map point (x / z): marched between the highest and
## lowest relief, refined by bisection.
func raycast(origin: Vector3, direction: Vector3) -> Vector2:
	if direction.y > -0.0001:
		return Vector2(origin.x, origin.z)
	var t_top := (origin.y - max_height) / -direction.y
	var t_bottom := (origin.y - min_height) / -direction.y
	var horizontal := Vector2(direction.x, direction.z).length()
	var steps := clampi(ceili((t_bottom - t_top) * horizontal / 0.1), 1, 400)
	var dt := (t_bottom - t_top) / steps
	var previous := t_top
	for i in range(0, steps + 1):  # i = 0: a ray touching the highest point
		var t := t_top + dt * i
		if _above(origin, direction, t) <= HIT_EPSILON:
			var low := previous
			var high := t
			for _k in 24:
				var mid := (low + high) * 0.5
				if _above(origin, direction, mid) > HIT_EPSILON:
					low = mid
				else:
					high = mid
			var hit := origin + direction * high
			return Vector2(hit.x, hit.z)
		previous = t
	var end := origin + direction * t_bottom
	return Vector2(end.x, end.z)


## The three lattice nodes around a map point and their barycentric weights:
## [Vector2i, Vector2i, Vector2i, Vector3 weights]. Same split as StaffMapLayers._triangles.
static func lattice_weights(point: Vector2) -> Array:
	var rf := point.y / 1.5
	var qf := point.x / SQRT3 - rf * 0.5
	var q0 := floori(qf)
	var r0 := floori(rf)
	var fq := qf - q0
	var fr := rf - r0
	var c := Vector2i(q0, r0)
	if fq + fr < 1.0:
		return [c, c + Vector2i(1, 0), c + Vector2i(0, 1), Vector3(1.0 - fq - fr, fq, fr)]
	return [
		c + Vector2i(1, 1),
		c + Vector2i(1, 0),
		c + Vector2i(0, 1),
		Vector3(fq + fr - 1.0, 1.0 - fr, 1.0 - fq)
	]


func _above(origin: Vector3, direction: Vector3, t: float) -> float:
	var p := origin + direction * t
	return p.y - height_at(Vector2(p.x, p.z))


## Weighted value of the lattice nodes on the map (missing nodes are left out, weights renormed).
func _sample(values: Dictionary, point: Vector2) -> float:
	var lw := lattice_weights(point)
	var weights: Vector3 = lw[3]
	var sum := 0.0
	var total := 0.0
	for i in 3:
		var c: Vector2i = lw[i]
		if values.has(c):
			sum += float(values[c]) * weights[i]
			total += weights[i]
	return sum / total if total > 0.000001 else 0.0


## Height gradient in metres per hex step (east, south): least squares over the neighbours.
func _gradient(grid: HexGrid, c: Vector2i) -> Vector2:
	var here := height_m(grid, c)
	var slope := Vector2.ZERO
	var count := 0
	for d in Hex.DIRECTIONS:
		var n := c + d
		if not grid.has_tile(n):
			continue
		var w := Hex.to_world(d, 1.0)
		slope += Vector2(w.x, w.z).normalized() * (height_m(grid, n) - here)
		count += 1
	# Six directions: sum of dir * dir^T = 3 * identity; scale a partial ring the same way.
	return slope / (0.5 * count) if count > 0 else Vector2.ZERO
