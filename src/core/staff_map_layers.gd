class_name StaffMapLayers
extends RefCounted
## Pure map -> draw data for the staff map (TASK-093a, TASK-125). Everything is in "hex units": the
## centre-to-corner distance of a hex is 1, x grows east, y south (Hex.to_world with size 1).
##
## Smoothing of the land cover: the hex centres form a triangular lattice. Every lattice triangle
## (three mutually adjacent hexes) is split by the terrain of its three corners: all alike = the
## whole triangle, two alike = a trapezoid for the pair and a small triangle for the odd one (cut
## through the edge midpoints), all different = three kites meeting in the centroid. Class borders
## therefore run through edge midpoints instead of along hex edges, which rounds the hexagonal
## steps without any guesswork about land cover between the tiles. Roads and rivers are joined
## into polylines across hexes and rounded with Chaikin corner cutting. The hillshade is a
## per-hex shade value interpolated over the same triangles.

## Light comes from the north-west (unit vector towards the light, in map x / y).
const LIGHT := Vector2(-0.7071068, -0.7071068)
## Metres of height difference per hex step that give full shade.
const SHADE_FULL_M := 30.0
const _KEY_BIAS := 4096


## Fill class -> Array of convex PackedVector2Array polygons (triangle, trapezoid or kite). The
## class of a hex is its terrain type unless `classes` (Vector2i -> int) overrides it.
static func fills(grid: HexGrid, classes := {}) -> Dictionary:
	var result := {}
	for tri in _triangles(grid):
		var nodes: Array[Vector2i] = tri
		var p: Array[Vector2] = [_point(nodes[0]), _point(nodes[1]), _point(nodes[2])]
		var t: Array[int] = [
			_class(grid, classes, nodes[0]),
			_class(grid, classes, nodes[1]),
			_class(grid, classes, nodes[2])
		]
		_split(p, t, result)
	return result


## Fill class -> segment end points in pairs: the borders of that class's fill polygons against
## other classes (the cuts of `fills`, through edge midpoints); a border between two classes is in
## both lists. The outer edge of the lattice is not a border.
static func borders(grid: HexGrid, classes := {}) -> Dictionary:
	var result := {}
	for tri in _triangles(grid):
		var nodes: Array[Vector2i] = tri
		var p: Array[Vector2] = [_point(nodes[0]), _point(nodes[1]), _point(nodes[2])]
		var t: Array[int] = [
			_class(grid, classes, nodes[0]),
			_class(grid, classes, nodes[1]),
			_class(grid, classes, nodes[2])
		]
		if t[0] == t[1] and t[1] == t[2]:
			continue
		if t[0] != t[1] and t[1] != t[2] and t[0] != t[2]:
			var centre := (p[0] + p[1] + p[2]) / 3.0
			for i in 3:
				var j := (i + 1) % 3
				var mid := (p[i] + p[j]) * 0.5
				_add_segment(result, t[i], mid, centre)
				_add_segment(result, t[j], mid, centre)
		else:
			var odd := 0 if t[1] == t[2] else (1 if t[0] == t[2] else 2)
			var i := (odd + 1) % 3
			var j := (odd + 2) % 3
			var mi := (p[i] + p[odd]) * 0.5
			var mj := (p[j] + p[odd]) * 0.5
			_add_segment(result, t[odd], mi, mj)
			_add_segment(result, t[i], mi, mj)
	return result


## Water tiles that are sea: connected (over water) to a water tile on the map edge and not higher
## than `max_m` metres. Vector2i -> true.
static func sea_tiles(grid: HexGrid, max_m: float) -> Dictionary:
	var sea := {}
	var queue: Array[Vector2i] = []
	for c in _sorted(grid):
		if not _is_low_water(grid, c, max_m):
			continue
		for d in Hex.DIRECTIONS:
			if not grid.has_tile(c + d):
				sea[c] = true
				queue.append(c)
				break
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in Hex.DIRECTIONS:
			var n := c + d
			if not sea.has(n) and _is_low_water(grid, n, max_m):
				sea[n] = true
				queue.append(n)
	return sea


## Fan triangulation of convex polygons into a flat triangle vertex list.
static func triangulate(polygons: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for poly: PackedVector2Array in polygons:
		for i in range(1, poly.size() - 1):
			out.append(poly[0])
			out.append(poly[i])
			out.append(poly[i + 1])
	return out


## Horizontal hatch lines every `spacing` (aligned to the map, so neighbouring polygons join up):
## segment end points in pairs, each segment clipped to one convex polygon.
static func hatch(polygons: Array, spacing: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for poly: PackedVector2Array in polygons:
		var low := INF
		var high := -INF
		for p in poly:
			low = minf(low, p.y)
			high = maxf(high, p.y)
		var k := ceili(low / spacing)
		while k * spacing <= high:
			var y := k * spacing
			var x_min := INF
			var x_max := -INF
			for i in poly.size():
				var a := poly[i]
				var b := poly[(i + 1) % poly.size()]
				if (a.y - y) * (b.y - y) > 0.0 or a.y == b.y:
					continue
				var x := a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)
				x_min = minf(x_min, x)
				x_max = maxf(x_max, x)
			if x_max - x_min > 0.0001:
				out.append(Vector2(x_min, y))
				out.append(Vector2(x_max, y))
			k += 1
	return out


## Road polylines (links of HexGrid.road_links), Chaikin-smoothed `smoothing` times.
static func roads(grid: HexGrid, smoothing := 2) -> Array[PackedVector2Array]:
	return _polylines(grid, false, smoothing)


## River polylines (links of HexGrid.river_links).
static func rivers(grid: HexGrid, smoothing := 2) -> Array[PackedVector2Array]:
	return _polylines(grid, true, smoothing)


## Road (or river) strokes: chains of links that continue through a junction along the
## straightest pair of links (a turn of at most 60 degrees, straightest pairs first), so a through
## road stays one line and its side roads end at it. Array of {"points": PackedVector2Array
## (Chaikin-smoothed `smoothing` times), "steps": float (length in hex steps, unsmoothed)}; every
## link is in exactly one stroke. Deterministic.
static func strokes(grid: HexGrid, river: bool, smoothing := 2) -> Array[Dictionary]:
	var adjacency := _adjacency(grid, river)
	var keys: Array = adjacency.keys()
	keys.sort()
	var partners := {}  # node -> {neighbour: neighbour it continues to}
	for node: int in keys:
		partners[node] = _pair_links(node, adjacency[node])
	var used := {}
	var result: Array[Dictionary] = []
	for pass_index in 2:  # first strokes with a free end, then closed loops
		for start: int in keys:
			for next: int in adjacency[start]:
				if used.has(_edge(start, next)):
					continue
				if pass_index == 0 and (partners[start] as Dictionary).has(next):
					continue  # not a stroke end
				result.append(_trace_stroke(partners, used, start, next, smoothing))
	return result


## Triangle list of all `lines` as ribbons of `width` (one quad per segment, extended by half the
## width at both line ends so joints and ends close): lets thousands of polylines be one mesh.
static func ribbons(lines: Array, width: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var half := width * 0.5
	for line: PackedVector2Array in lines:
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var along := (b - a).normalized() * half
			if i == 0:
				a -= along
			if i == line.size() - 2:
				b += along
			var side := along.orthogonal()
			out.append_array([a + side, a - side, b + side, b + side, a - side, b - side])
	return out


## Chaikin corner cutting; the end points stay where they are.
static func smooth(line: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var current := line
	for _i in iterations:
		if current.size() < 3:
			break
		var next := PackedVector2Array()
		next.append(current[0])
		for i in current.size() - 1:
			var a := current[i]
			var b := current[i + 1]
			next.append(a.lerp(b, 0.25))
			next.append(a.lerp(b, 0.75))
		next.append(current[current.size() - 1])
		current = next
	return current


## Hillshade of the lattice: {"vertices": triangle list, "values": shade per vertex in -1..1}.
static func hillshade(grid: HexGrid) -> Dictionary:
	var vertices := PackedVector2Array()
	var values := PackedFloat32Array()
	var cache := {}
	for tri in _triangles(grid):
		var nodes: Array[Vector2i] = tri
		for c in nodes:
			if not cache.has(c):
				cache[c] = shade_at(grid, c)
			vertices.append(_point(c))
			values.append(cache[c])
	return {"vertices": vertices, "values": values}


## Shade of one hex, -1 (dark) .. 1 (lit): the ground slope against the light from the north-west,
## from the height differences to the six neighbours (metres when the map has them). Water is 0.
static func shade_at(grid: HexGrid, c: Vector2i) -> float:
	if not grid.has_tile(c) or grid.get_terrain(c) == Terrain.Type.WATER:
		return 0.0
	var here := _height(grid, c)
	var slope := Vector2.ZERO
	for d in Hex.DIRECTIONS:
		var n := c + d
		if not grid.has_tile(n):
			continue
		var w := Hex.to_world(d, 1.0)
		var dir := Vector2(w.x, w.z).normalized()
		slope += dir * (_height(grid, n) - here)
	slope /= 3.0  # six directions: sum of dir * dirT = 3 * identity
	return clampf(-slope.dot(LIGHT) / SHADE_FULL_M, -1.0, 1.0)


## Hex edges as segment end points in pairs; an edge shared by two hexes appears once.
static func grid_lines(grid: HexGrid) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c in _sorted(grid):
		for dir in 6:
			if dir > 2 and grid.has_tile(c + Hex.DIRECTIONS[dir]):
				continue
			var first := (6 - dir) % 6
			out.append(_corner(c, first))
			out.append(_corner(c, first + 1))
	return out


## Rectangle spanned by the hex centres (what the camera may show).
static func bounds(grid: HexGrid) -> Rect2:
	var rect := Rect2()
	var first := true
	for c in grid.coords():
		var p := _point(c)
		if first:
			rect = Rect2(p, Vector2.ZERO)
			first = false
		else:
			rect = rect.expand(p)
	return rect


## Largest rectangle the map fills completely: the lattice of centres zigzags by half a hex at
## the left / right edge (offset rows), so this is trimmed to the x range every row covers.
static func straight_rect(grid: HexGrid) -> Rect2:
	var low := {}
	var high := {}
	for c in grid.coords():
		var p := _point(c)
		low[c.y] = minf(low.get(c.y, INF), p.x)
		high[c.y] = maxf(high.get(c.y, -INF), p.x)
	var rect := bounds(grid)
	if low.is_empty():
		return rect
	var x_low := -INF
	var x_high := INF
	for row: int in low:
		x_low = maxf(x_low, low[row])
		x_high = minf(x_high, high[row])
	if x_high <= x_low:
		return rect
	return Rect2(x_low, rect.position.y, x_high - x_low, rect.size.y)


## Convex polygons clipped to `rect` (empty results dropped).
static func clip_polygons(polygons: Array, rect: Rect2) -> Array:
	var box := PackedVector2Array(
		[
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y)
		]
	)
	var out := []
	for poly: PackedVector2Array in polygons:
		for clipped: PackedVector2Array in Geometry2D.intersect_polygons(poly, box):
			if clipped.size() >= 3:
				out.append(clipped)
	return out


## Segment end points in pairs, each clipped to `rect` (Liang-Barsky); outside parts are dropped.
static func clip_segments(segments: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, segments.size() - 1, 2):
		var a := segments[i]
		var d := segments[i + 1] - a
		var t0 := 0.0
		var t1 := 1.0
		var ok := true
		for side in 4:
			var pv := [-d.x, d.x, -d.y, d.y][side] as float
			var qv := [a.x - rect.position.x, rect.end.x - a.x, a.y - rect.position.y, rect.end.y - a.y][side] as float
			if is_zero_approx(pv):
				if qv < 0.0:
					ok = false
					break
			else:
				var r := qv / pv
				if pv < 0.0:
					t0 = maxf(t0, r)
				else:
					t1 = minf(t1, r)
		if ok and t0 < t1:
			out.append(a + d * t0)
			out.append(a + d * t1)
	return out


## A polyline clipped to `rect`: the parts inside, as separate polylines.
static func clip_polyline(line: PackedVector2Array, rect: Rect2) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var piece := PackedVector2Array()
	for i in range(line.size() - 1):
		var seg := clip_segments(PackedVector2Array([line[i], line[i + 1]]), rect)
		if seg.is_empty():
			if piece.size() >= 2:
				out.append(piece)
			piece = PackedVector2Array()
			continue
		if piece.is_empty():
			piece.append(seg[0])
		elif not piece[piece.size() - 1].is_equal_approx(seg[0]):
			out.append(piece)
			piece = PackedVector2Array([seg[0]])
		piece.append(seg[1])
	if piece.size() >= 2:
		out.append(piece)
	return out


## The six corners of a hex, closed (first point repeated).
static func outline(c: Vector2i) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 7:
		out.append(_corner(c, k % 6))
	return out


## The hex under a map point.
static func hex_at(point: Vector2) -> Vector2i:
	return Hex.from_world(Vector3(point.x, 0.0, point.y), 1.0)


static func _height(grid: HexGrid, c: Vector2i) -> float:
	return grid.elevation_m(c) if grid.has_elevation_m(c) else grid.elevation(c) * 1000.0


static func _point(c: Vector2i) -> Vector2:
	var w := Hex.to_world(c, 1.0)
	return Vector2(w.x, w.z)


static func _corner(c: Vector2i, k: int) -> Vector2:
	var angle := deg_to_rad(60.0 * k - 30.0)
	return _point(c) + Vector2(cos(angle), sin(angle))


## Tiles in a fixed order (row by row), so every output is deterministic.
static func _sorted(grid: HexGrid) -> Array[Vector2i]:
	var tiles := grid.coords()
	tiles.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return tiles


## Lattice triangles whose three hexes are on the map: Array of Array[Vector2i] (3 tiles).
static func _triangles(grid: HexGrid) -> Array:
	var out := []
	for c in _sorted(grid):
		var east := c + Hex.DIRECTIONS[0]
		var south_east := c + Hex.DIRECTIONS[5]
		var south_west := c + Hex.DIRECTIONS[4]
		if grid.has_tile(east) and grid.has_tile(south_east):
			out.append([c, east, south_east] as Array[Vector2i])
		if grid.has_tile(south_east) and grid.has_tile(south_west):
			out.append([c, south_east, south_west] as Array[Vector2i])
	return out


static func _class(grid: HexGrid, classes: Dictionary, c: Vector2i) -> int:
	return classes.get(c, grid.get_terrain(c))


static func _is_low_water(grid: HexGrid, c: Vector2i, max_m: float) -> bool:
	return (
		grid.has_tile(c) and grid.get_terrain(c) == Terrain.Type.WATER and _height(grid, c) <= max_m
	)


static func _add_segment(result: Dictionary, fill_class: int, a: Vector2, b: Vector2) -> void:
	if not result.has(fill_class):
		result[fill_class] = PackedVector2Array()
	var list: PackedVector2Array = result[fill_class]
	list.append(a)
	list.append(b)
	result[fill_class] = list


static func _add(result: Dictionary, terrain: int, poly: Array[Vector2]) -> void:
	if not result.has(terrain):
		result[terrain] = []
	result[terrain].append(PackedVector2Array(poly))


static func _split(p: Array[Vector2], t: Array[int], result: Dictionary) -> void:
	if t[0] == t[1] and t[1] == t[2]:
		_add(result, t[0], [p[0], p[1], p[2]])
	elif t[0] != t[1] and t[1] != t[2] and t[0] != t[2]:
		var centre := (p[0] + p[1] + p[2]) / 3.0
		for i in 3:
			var j := (i + 1) % 3
			var k := (i + 2) % 3
			_add(result, t[i], [p[i], (p[i] + p[j]) * 0.5, centre, (p[i] + p[k]) * 0.5])
	else:
		var odd := 0 if t[1] == t[2] else (1 if t[0] == t[2] else 2)
		var i := (odd + 1) % 3
		var j := (odd + 2) % 3
		var mi := (p[i] + p[odd]) * 0.5
		var mj := (p[j] + p[odd]) * 0.5
		_add(result, t[i], [p[i], p[j], mj, mi])
		_add(result, t[odd], [p[odd], mi, mj])


static func _key(c: Vector2i, terminal: int) -> int:
	return ((c.y + _KEY_BIAS) << 20) | ((c.x + _KEY_BIAS) << 4) | terminal


static func _key_tile(key: int) -> Vector2i:
	return Vector2i(((key >> 4) & 0xFFFF) - _KEY_BIAS, (key >> 20) - _KEY_BIAS)


## Position of a graph node: a hex centre (terminal 0) or the edge midpoint of direction
## terminal - 1 (a link that leaves the map).
static func _node_point(key: int) -> Vector2:
	var c := _key_tile(key)
	var terminal := key & 15
	if terminal == 0:
		return _point(c)
	return (_point(c) + _point(c + Hex.DIRECTIONS[terminal - 1])) * 0.5


## Link graph: node key -> sorted Array[int] of neighbour keys.
static func _adjacency(grid: HexGrid, river: bool) -> Dictionary:
	var adjacency := {}
	for c in _sorted(grid):
		var mask := grid.river_links(c) if river else grid.road_links(c)
		for dir in 6:
			if mask & (1 << dir) == 0:
				continue
			var n := c + Hex.DIRECTIONS[dir]
			var to := _key(n, 0) if grid.has_tile(n) else _key(c, dir + 1)
			_connect(adjacency, _key(c, 0), to)
	return adjacency


## Which links of `node` continue into which (both ways): two links always pair, at a junction the
## straightest pairs first while the turn is at most 60 degrees.
static func _pair_links(node: int, neighbours: Array) -> Dictionary:
	var pairs := {}
	if neighbours.size() < 2:
		return pairs
	if neighbours.size() == 2:
		pairs[neighbours[0]] = neighbours[1]
		pairs[neighbours[1]] = neighbours[0]
		return pairs
	var here := _node_point(node)
	var candidates := []  # [cosine between the two links, a, b]
	for i in neighbours.size():
		for j in range(i + 1, neighbours.size()):
			var a: int = neighbours[i]
			var b: int = neighbours[j]
			var da := (_node_point(a) - here).normalized()
			var db := (_node_point(b) - here).normalized()
			if da.dot(db) < -0.4:  # 180 or 120 degrees apart
				candidates.append([da.dot(db), a, b])
	candidates.sort_custom(
		func(x: Array, y: Array) -> bool:
			if not is_equal_approx(x[0], y[0]):
				return x[0] < y[0]
			return x[1] < y[1] or (x[1] == y[1] and x[2] < y[2])
	)
	for pair: Array in candidates:
		if not pairs.has(pair[1]) and not pairs.has(pair[2]):
			pairs[pair[1]] = pair[2]
			pairs[pair[2]] = pair[1]
	return pairs


static func _trace_stroke(
	partners: Dictionary, used: Dictionary, start: int, first: int, smoothing: int
) -> Dictionary:
	var line := PackedVector2Array([_node_point(start)])
	var steps := 0.0
	var previous := start
	var current := first
	while true:
		used[_edge(previous, current)] = true
		line.append(_node_point(current))
		steps += _node_point(previous).distance_to(_node_point(current)) / Hex.SQRT3
		if current == start:
			break
		var through: Dictionary = partners[current]
		if not through.has(previous):
			break
		var next: int = through[previous]
		if used.has(_edge(current, next)):
			break
		previous = current
		current = next
	return {"points": smooth(line, smoothing), "steps": steps}


static func _polylines(grid: HexGrid, river: bool, smoothing: int) -> Array[PackedVector2Array]:
	var adjacency := _adjacency(grid, river)
	var keys: Array = adjacency.keys()
	keys.sort()
	var used := {}  # "a:b" of a traced edge, a < b
	var lines: Array[PackedVector2Array] = []
	for start: int in keys:
		if adjacency[start].size() == 2:
			continue
		for next: int in adjacency[start]:
			if not used.has(_edge(start, next)):
				lines.append(_trace(adjacency, used, start, next, smoothing))
	for start: int in keys:  # what is left are closed loops
		for next: int in adjacency[start]:
			if not used.has(_edge(start, next)):
				lines.append(_trace(adjacency, used, start, next, smoothing))
	return lines


static func _connect(adjacency: Dictionary, a: int, b: int) -> void:
	for pair: Array in [[a, b], [b, a]]:
		var list: Array = adjacency.get(pair[0], [])
		if not list.has(pair[1]):
			list.append(pair[1])
			list.sort()
		adjacency[pair[0]] = list


static func _edge(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


## Follows the chain from `start` over `first` until a junction, an end or the start again.
static func _trace(
	adjacency: Dictionary, used: Dictionary, start: int, first: int, smoothing: int
) -> PackedVector2Array:
	var line := PackedVector2Array([_node_point(start)])
	var previous := start
	var current := first
	while true:
		used[_edge(previous, current)] = true
		line.append(_node_point(current))
		var around: Array = adjacency[current]
		if around.size() != 2 or current == start:
			break
		var next: int = around[0] if around[0] != previous else around[1]
		if used.has(_edge(current, next)):
			break
		previous = current
		current = next
	return smooth(line, smoothing)
