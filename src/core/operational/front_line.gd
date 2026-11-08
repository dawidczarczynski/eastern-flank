class_name FrontLine
extends RefCounted
## The front line of the staff map (TASK-093c, GDD "Operational map view" → "Front line"): pure
## and deterministic, derived from the formations alone – a display, never a rule.
##
## Every land hex within `OperationalState.front_range` hexes of a formation belongs to the player
## of the nearest formation; a tie, water and unreached hexes belong to nobody. The line runs
## along the hex edges between the blocs. Where a band of tied hexes separates them it is drawn
## on the edge towards player 0's zone, so there is always exactly one line.

const DEFAULT_RANGE := 3
const _KEY_SCALE := 1000.0


## Hex -> player for every owned land hex (ties, water and unreached hexes are missing).
static func ownership(state: OperationalState) -> Dictionary:
	var result := {}
	var classes := _classify(state)
	for coord: Vector2i in classes:
		var owner: int = classes[coord]
		if owner >= 0:
			result[coord] = owner
	return result


## The front as polylines of hex-unit points (x, z of `Hex.to_world(c, 1.0)`), each one running
## so that player 0's zone is on its right (x to the right, z down). Open lines first (sorted by
## start point), then closed loops (first point == last point).
static func edges(state: OperationalState) -> Array:
	var classes := _classify(state)
	var starts := {}  # corner key -> Array of segments [from, to] leaving that corner
	var ends := {}  # corner key -> number of segments arriving there
	var keys: Array[Vector2i] = []
	for coord: Vector2i in classes:
		if classes[coord] == 0:
			keys.append(coord)
	keys.sort_custom(_coord_before)
	for coord in keys:
		for direction in Hex.DIRECTIONS:
			var other: Vector2i = coord + direction
			if not classes.has(other) or classes[other] == 0:
				continue
			var segment := _segment(coord, direction)
			var from_key := _key(segment[0])
			if not starts.has(from_key):
				starts[from_key] = []
			(starts[from_key] as Array).append(segment)
			var to_key := _key(segment[1])
			ends[to_key] = int(ends.get(to_key, 0)) + 1
	var lines: Array = []
	var open_keys: Array = starts.keys().filter(func(k: Vector2i) -> bool: return not ends.has(k))
	open_keys.sort_custom(_coord_before)
	for key: Vector2i in open_keys:
		while not (starts[key] as Array).is_empty():
			lines.append(_walk(starts, key))
	var all_keys: Array = starts.keys()
	all_keys.sort_custom(_coord_before)
	for key: Vector2i in all_keys:
		while not (starts[key] as Array).is_empty():
			lines.append(_walk(starts, key))
	return lines


## Normal pointing to the right of the direction a → b (x right, z down): player 0's side.
static func right_normal(a: Vector2, b: Vector2) -> Vector2:
	var d := (b - a).normalized()
	return Vector2(-d.y, d.x)


## The smoothed variant: segment midpoints (ends kept) then Chaikin corner cutting, same ends.
static func smooth(line: PackedVector2Array, iterations := 3) -> PackedVector2Array:
	if line.size() < 3:
		return line
	var closed := line[0].is_equal_approx(line[line.size() - 1])
	var points := PackedVector2Array()
	if not closed:
		points.append(line[0])
	for i in line.size() - 1:
		points.append((line[i] + line[i + 1]) * 0.5)
	if not closed:
		points.append(line[line.size() - 1])
	for _i in iterations:
		points = _chaikin(points, closed)
	if closed:
		points.append(points[0])
	return points


static func _chaikin(points: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := points.size()
	if not closed:
		out.append(points[0])
	var last := n if closed else n - 1
	for i in last:
		var a := points[i]
		var b := points[(i + 1) % n]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	if not closed:
		out.append(points[n - 1])
	return out


## Hex -> owner (0 / 1 …), -1 for a tie. Water and unreached hexes are not in the result.
static func _classify(state: OperationalState) -> Dictionary:
	var best := {}  # coord -> nearest distance
	var owner := {}  # coord -> owner or -1
	var reach := state.front_range
	for f in state.formations:
		for dq in range(-reach, reach + 1):
			for dr in range(maxi(-reach, -dq - reach), mini(reach, -dq + reach) + 1):
				var coord := f.coord + Vector2i(dq, dr)
				if not state.grid.has_tile(coord):
					continue
				if state.grid.get_terrain(coord) == Terrain.Type.WATER:
					continue
				var d := Hex.distance(f.coord, coord)
				if not best.has(coord) or d < int(best[coord]):
					best[coord] = d
					owner[coord] = f.owner_id
				elif d == int(best[coord]) and int(owner[coord]) != f.owner_id:
					owner[coord] = -1
	return owner


## The edge of `coord` towards `direction`, from corner A to corner B clockwise on screen, which
## keeps the hex on the right of the travel.
static func _segment(coord: Vector2i, direction: Vector2i) -> Array:
	var centre := Hex.to_world(coord, 1.0)
	var towards := Hex.to_world(coord + direction, 1.0) - centre
	var angle := atan2(towards.z, towards.x)
	var a := _corner(centre, angle - PI / 6.0)
	var b := _corner(centre, angle + PI / 6.0)
	return [a, b]


static func _corner(centre: Vector3, angle: float) -> Vector2:
	return Vector2(centre.x + cos(angle), centre.z + sin(angle))


static func _walk(starts: Dictionary, first: Vector2i) -> PackedVector2Array:
	var line := PackedVector2Array()
	var key := first
	while starts.has(key) and not (starts[key] as Array).is_empty():
		var segment: Array = (starts[key] as Array).pop_front()
		if line.is_empty():
			line.append(segment[0])
		line.append(segment[1])
		key = _key(segment[1])
	return line


static func _key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * _KEY_SCALE), roundi(p.y * _KEY_SCALE))


static func _coord_before(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)
