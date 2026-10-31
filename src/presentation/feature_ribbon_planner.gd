class_name FeatureRibbonPlanner
extends RefCounted
## Pure geometry of the road and river ribbons (TASK-108). The per-tile link masks
## (HexGrid.road_links / river_links) become smooth centrelines instead of hex-shaped zigzags:
##
## 1. Pieces per tile: the two most opposite links form a through piece (side midpoint to side
##    midpoint), further exactly opposite pairs cross it as more through pieces, the remaining
##    links are spokes that end on the first through piece's midpoint (a junction), a lone link is
##    a dead end at the tile centre.
## 2. Chains: pieces that share a side midpoint ("port") are chained into one polyline; chains end
##    at spokes, dead ends and ports without a partner (map edge, shore); closed loops are kept.
## 3. Smoothing: every piece is a cubic Bézier between its two ends with Catmull-Rom-like tangents
##    at the ports (the direction from the previous to the next port, at most MAX_CROSSING_ANGLE
##    off the side normal, so it still crosses into the next tile), the same tangent on both sides
##    of a port (G1, no kink) and the inner control points clamped inside the hex: by the convex
##    hull property the curve stays in its tile and crosses the same side as the link.
## 4. Rivers get a gentle low-frequency meander and width variation from world-position value
##    noise (TerrainNoise, never GameState.rng), limited near the hex walls, and narrow towards a
##    dead-end source; road junctions and dead ends get a round disc.
## 5. Strips: each chain is one triangle strip with per-vertex normals from the neighbouring
##    vertices, so consecutive quads share their edges exactly (no gaps, overlaps or spikes).
##
## MapView drapes the triangles on the terrain mesh, one mesh per kind; scatter keeps clear of
## the same centrelines (`is_clear`). Look values, not balance data.

enum Kind { ROAD, RIVER }

## Centre to side midpoint: half the distance between neighbouring centres (√3/2 · HEX_SIZE).
const HALF_SEGMENT := Hex.SQRT3 / 2.0 * TerrainField.HEX_SIZE
const ROAD_WIDTH := 0.10
const RIVER_WIDTH := 0.15
## River width varies by ± this share along its course (low-frequency noise).
const RIVER_WIDTH_VARIATION := 0.25
## A river narrows to this share of its width towards a dead-end source, over SOURCE_TAPER.
const RIVER_SOURCE_WIDTH := 0.4
const SOURCE_TAPER := 1.2
## Sideways meander of a river: amplitude (world units) and wavelength of the noise.
const RIVER_MEANDER := 0.07
const MEANDER_WAVELENGTH := 1.7
const MEANDER_SEED := 61.0
const WIDTH_SEED := 67.0
const WIDTH_WAVELENGTH := 2.3
## Trees, rocks, bushes and grass keep this much space beyond a ribbon's half width.
const CLEARANCE := 0.04
const ROAD_COLOR := Color("#8a7f6a")
const RIVER_COLOR := Color("#3d5a66")
## The river catches a little light (slight specular); the road is matt (roughness 1).
const RIVER_ROUGHNESS := 0.35
const RIVER_SPECULAR := 0.7
## Lift above the drawn terrain mesh (below the grid lines and overlays); a road lies a little
## higher than a river, so it reads as crossing it (no depth fighting where they overlap).
const LIFT := 0.02
const ROAD_LIFT := 0.024
## Centreline sample spacing (world units); the ribbon follows the terrain mesh between samples.
const SAMPLE_STEP := 0.06
## Bézier handle length as a share of the piece's chord (1/3 = Catmull-Rom-like).
const HANDLE := 0.36
## A centreline crosses a side at most this far from the side normal.
const MAX_CROSSING_ANGLE := 0.8727  # 50°
## Sides of a junction / dead-end disc.
const DISC_SIDES := 12
## The meander fades out within this distance of a confluence (spoke end).
const JUNCTION_CALM := 0.6
## Meander and width noise keep this far from the hex walls a piece does not cross.
const WALL_MARGIN := 0.06

static var _plan_cache: Dictionary = {}
static var _index_grid := 0
static var _index_version := -1
static var _index: Dictionary = {}


static func links(grid: HexGrid, c: Vector2i, kind: Kind) -> int:
	return grid.road_links(c) if kind == Kind.ROAD else grid.river_links(c)


## Nominal width of a ribbon of `kind` (rivers vary around it).
static func width(kind: Kind) -> float:
	return ROAD_WIDTH if kind == Kind.ROAD else RIVER_WIDTH


static func lift(kind: Kind) -> float:
	return ROAD_LIFT if kind == Kind.ROAD else LIFT


## Largest half width a ribbon of `kind` reaches anywhere.
static func max_half_width(kind: Kind) -> float:
	return width(kind) / 2.0 * (1.0 + (RIVER_WIDTH_VARIATION if kind == Kind.RIVER else 0.0))


## Centrelines (world XZ) of `kind`, one polyline per chain; a closed loop repeats its first point
## at the end. Empty when the grid has no links of `kind`. Cached per grid and links_version.
static func lines(grid: HexGrid, kind: Kind) -> Array[PackedVector2Array]:
	return _plan(grid, kind)["lines"]


## Half width at every centreline vertex, parallel to `lines`.
static func half_widths(grid: HexGrid, kind: Kind) -> Array[PackedFloat32Array]:
	return _plan(grid, kind)["half_widths"]


## Junction and dead-end discs as Vector3(x, z, radius).
static func discs(grid: HexGrid, kind: Kind) -> PackedVector3Array:
	return _plan(grid, kind)["discs"]


## Indexed flat mesh of the whole ribbon of `kind`: {points: PackedVector2Array (world XZ),
## indices: PackedInt32Array (triangles, clockwise seen from above like the terrain)} – one strip
## per centreline (neighbouring quads share their corner points) plus the discs.
static func mesh(grid: HexGrid, kind: Kind) -> Dictionary:
	var points := PackedVector2Array()
	var indices := PackedInt32Array()
	var all_lines := lines(grid, kind)
	var widths := half_widths(grid, kind)
	for i in all_lines.size():
		_append_strip(points, indices, all_lines[i], widths[i])
	for disc in discs(grid, kind):
		_append_disc(points, indices, Vector2(disc.x, disc.y), disc.z)
	return {"points": points, "indices": indices}


## The same triangles as flat point triples (`mesh` expanded).
static func triangles(grid: HexGrid, kind: Kind) -> PackedVector2Array:
	var indexed := mesh(grid, kind)
	var points: PackedVector2Array = indexed["points"]
	var result := PackedVector2Array()
	for index: int in indexed["indices"]:
		result.append(points[index])
	return result


## Distance from world (x, z) to the nearest centreline of `kind`; INF when none is near (only
## the pieces registered for the tile under the point are checked, see `is_clear`).
static func distance(grid: HexGrid, kind: Kind, x: float, z: float) -> float:
	return _nearest(grid, kind, x, z, false)


## Distance from world (x, z) to the nearest ribbon edge of `kind` (negative on the ribbon); INF
## when none is near.
static func edge_distance(grid: HexGrid, kind: Kind, x: float, z: float) -> float:
	return _nearest(grid, kind, x, z, true)


## Whether scatter (trees, rocks, bushes, grass) may stand at (x, z): farther than the local half
## width + CLEARANCE from every road and river ribbon. Always true on grids without links.
static func is_clear(grid: HexGrid, x: float, z: float) -> bool:
	if not grid.has_links():
		return true
	for kind: Kind in Kind.values():
		if _nearest(grid, kind, x, z, true) < CLEARANCE:
			return false
	return true


## `items` (dictionaries with a Vector3 "position") without those on a ribbon (`is_clear`).
static func without_ribbons(grid: HexGrid, items: Array) -> Array:
	if not grid.has_links():
		return items
	var result: Array = []
	for item: Dictionary in items:
		var p: Vector3 = item["position"]
		if is_clear(grid, p.x, p.z):
			result.append(item)
	return result


static func _nearest(grid: HexGrid, kind: Kind, x: float, z: float, to_edge: bool) -> float:
	if not grid.has_links():
		return INF
	var tiles: Dictionary = _clearance_index(grid)[kind]
	var coord := Hex.from_world(Vector3(x, 0.0, z), TerrainField.HEX_SIZE)
	if not tiles.has(coord):
		return INF
	var entry: Array = tiles[coord]
	var pairs: PackedVector2Array = entry[0]
	var halves: PackedFloat32Array = entry[1]
	var p := Vector2(x, z)
	var best := INF
	for i in halves.size():
		var d := _segment_distance(p, pairs[2 * i], pairs[2 * i + 1])
		best = minf(best, d - halves[i] if to_edge else d)
	return best


## Kind -> {tile -> [segment pairs, half width per segment]}: every centreline piece and disc
## (as a zero-length segment) registered in the tile of its midpoint and that tile's neighbours
## (a point within reach of a piece is always in one of them); cached per grid and links_version.
static func _clearance_index(grid: HexGrid) -> Dictionary:
	if grid.get_instance_id() == _index_grid and grid.links_version() == _index_version:
		return _index
	_index = {}
	_index_grid = grid.get_instance_id()
	_index_version = grid.links_version()
	for kind: Kind in Kind.values():
		var tiles: Dictionary = {}
		var all_lines := lines(grid, kind)
		var widths := half_widths(grid, kind)
		for li in all_lines.size():
			var line := all_lines[li]
			var w := widths[li]
			for i in line.size() - 1:
				_register(tiles, line[i], line[i + 1], maxf(w[i], w[i + 1]))
		for disc in discs(grid, kind):
			var c := Vector2(disc.x, disc.y)
			_register(tiles, c, c, disc.z)
		_index[kind] = tiles
	return _index


static func _register(tiles: Dictionary, a: Vector2, b: Vector2, half: float) -> void:
	var mid := (a + b) * 0.5
	var coord := Hex.from_world(Vector3(mid.x, 0.0, mid.y), TerrainField.HEX_SIZE)
	for t: Vector2i in [coord] + Hex.neighbors(coord):
		# Packed arrays are values: modify copies and store them back.
		var entry: Array = tiles.get_or_add(t, [PackedVector2Array(), PackedFloat32Array()])
		var pairs: PackedVector2Array = entry[0]
		var halves: PackedFloat32Array = entry[1]
		pairs.append(a)
		pairs.append(b)
		halves.append(half)
		entry[0] = pairs
		entry[1] = halves


# --- plan: pieces, chains, curves ---


## {lines, half_widths, discs} of `kind`, cached per grid instance and links_version.
static func _plan(grid: HexGrid, kind: Kind) -> Dictionary:
	var key := "%d_%d_%d" % [grid.get_instance_id(), grid.links_version(), kind]
	if _plan_cache.has(key):
		return _plan_cache[key]
	if _plan_cache.size() > 8:
		_plan_cache.clear()
	var result := _build_plan(grid, kind)
	_plan_cache[key] = result
	return result


static func _build_plan(grid: HexGrid, kind: Kind) -> Dictionary:
	var result_lines: Array[PackedVector2Array] = []
	var result_widths: Array[PackedFloat32Array] = []
	var result_discs := PackedVector3Array()
	var pieces := _pieces(grid, kind)
	# Port (tile, dir) -> index of the piece that owns it.
	var owner := {}
	for i in pieces.size():
		var piece: Dictionary = pieces[i]
		for dir: int in piece["dirs"]:
			owner[Vector3i(piece["tile"].x, piece["tile"].y, dir)] = i
	var chains := _chains(pieces, owner)
	# Pass 1: the curves of all pieces (spoke ends aim at the tile centre for now).
	var curves: Array = []
	for chain: Array in chains:
		curves.append(_chain_curves(chain, pieces))
	# Pass 2: spokes end on the midpoint of their tile's first through piece.
	var midpoints := {}  # tile -> midpoint of its first through piece
	for ci in chains.size():
		var chain: Array = chains[ci]
		for k in chain.size():
			var step: Dictionary = chain[k]
			var piece: Dictionary = pieces[step["piece"]]
			if piece["kind"] == &"through" and piece["primary"]:
				midpoints[piece["tile"]] = _bezier(curves[ci][k], 0.5)
	# Junctions: tile -> spoke end (the midpoint) of every tile with a spoke, built once.
	var junctions := {}
	for piece: Dictionary in pieces:
		if piece["kind"] == &"spoke" and midpoints.has(piece["tile"]):
			junctions[piece["tile"]] = midpoints[piece["tile"]]
	for ci in chains.size():
		var chain: Array = chains[ci]
		for k in chain.size():
			var piece: Dictionary = pieces[chain[k]["piece"]]
			if piece["kind"] != &"spoke" or not midpoints.has(piece["tile"]):
				continue
			var m: Vector2 = midpoints[piece["tile"]]
			var bez: Array = curves[ci][k]
			# The spoke's end that is not its port: index 3 when walked port first, else 0.
			if chain[k]["reversed"]:
				bez[0] = m
				bez[1] = m + (bez[3] - m) * HANDLE
			else:
				bez[3] = m
				bez[2] = m + (bez[0] - m) * HANDLE
	for ci in chains.size():
		var line := PackedVector2Array()
		var tiles := PackedVector2Array()  # tile per sample (x, y = coord)
		var chain: Array = chains[ci]
		for k in chain.size():
			var bez: Array = curves[ci][k]
			var tile: Vector2i = pieces[chain[k]["piece"]]["tile"]
			var length := (
				(bez[0] as Vector2).distance_to(bez[1])
				+ (bez[1] as Vector2).distance_to(bez[2])
				+ (bez[2] as Vector2).distance_to(bez[3])
			)
			var n := maxi(2, ceili(length / SAMPLE_STEP))
			for s in range(0 if k == 0 else 1, n + 1):
				line.append(_bezier(bez, float(s) / n))
				tiles.append(Vector2(tile))
		var widths := _widths(line, chain, pieces, kind)
		if kind == Kind.RIVER:
			line = _meander(line, tiles, junctions)
		result_lines.append(line)
		result_widths.append(widths)
	if kind == Kind.ROAD:
		for piece: Dictionary in pieces:
			if piece["kind"] == &"dead":
				var c := _centre(piece["tile"])
				result_discs.append(Vector3(c.x, c.y, ROAD_WIDTH / 2.0))
		for tile: Vector2i in junctions:
			var m: Vector2 = junctions[tile]
			result_discs.append(Vector3(m.x, m.y, ROAD_WIDTH / 2.0))
	return {"lines": result_lines, "half_widths": result_widths, "discs": result_discs}


## Pieces of every linked tile (tiles sorted, so the result does not depend on insertion order):
## {tile, kind: through|spoke|dead, dirs: [a(, b)], primary: bool}.
static func _pieces(grid: HexGrid, kind: Kind) -> Array:
	var tiles := grid.coords()
	tiles.sort()
	var result: Array = []
	for c in tiles:
		var mask := links(grid, c, kind)
		if mask == 0:
			continue
		var dirs: Array[int] = []
		for dir in 6:
			if mask & (1 << dir):
				dirs.append(dir)
		if dirs.size() == 1:
			result.append({"tile": c, "kind": &"dead", "dirs": dirs, "primary": false})
			continue
		var primary := true
		while dirs.size() >= 2:
			var best := []
			var best_sep := 0
			for i in dirs.size():
				for j in range(i + 1, dirs.size()):
					var sep := _separation(dirs[i], dirs[j])
					if sep > best_sep:
						best_sep = sep
						best = [dirs[i], dirs[j]]
			# After the first through piece only exactly opposite pairs cross it at the centre.
			if not primary and best_sep < 3:
				break
			result.append({"tile": c, "kind": &"through", "dirs": best, "primary": primary})
			dirs.erase(best[0])
			dirs.erase(best[1])
			primary = false
		for dir in dirs:
			result.append({"tile": c, "kind": &"spoke", "dirs": [dir], "primary": false})
	return result


static func _separation(a: int, b: int) -> int:
	var d := absi(a - b)
	return mini(d, 6 - d)


## Chains of pieces: Array of Array of {piece, entry: dir the walk enters by (-1 at a chain start
## inside the tile), exit: dir it leaves by (-1 at an inner end), reversed: walked from its inner
## end}. Open chains start at a piece with a free end; the rest are closed loops.
static func _chains(pieces: Array, owner: Dictionary) -> Array:
	var visited := {}
	var result: Array = []
	# Open chains first: from spokes / dead ends (walked port-outwards after their inner end) and
	# from through pieces with a port that has no partner.
	for i in pieces.size():
		if visited.has(i):
			continue
		var piece: Dictionary = pieces[i]
		if piece["kind"] != &"through":
			result.append(_walk(i, -1, pieces, owner, visited))
			continue
		for dir: int in piece["dirs"]:
			if not visited.has(i) and _partner(piece["tile"], dir, owner) < 0:
				result.append(_walk(i, dir, pieces, owner, visited))
	for i in pieces.size():
		if not visited.has(i):
			var dirs: Array = pieces[i]["dirs"]
			result.append(_walk(i, dirs[0], pieces, owner, visited))
	return result


## Walks from piece `start`, entering it by `entry` (-1: from its inner end), until the chain ends
## or returns to `start`.
static func _walk(
	start: int, entry: int, pieces: Array, owner: Dictionary, visited: Dictionary
) -> Array:
	var chain: Array = []
	var index := start
	var into := entry
	while index >= 0 and not visited.has(index):
		visited[index] = true
		var piece: Dictionary = pieces[index]
		var dirs: Array = piece["dirs"]
		var out := -1
		if piece["kind"] == &"through":
			out = dirs[1] if into == dirs[0] else dirs[0]
		elif into < 0:
			out = dirs[0]
		# reversed: a spoke / dead end walked from its inner end out to its port.
		chain.append({"piece": index, "entry": into, "exit": out, "reversed": into < 0})
		if out < 0:
			break
		var next := _partner(piece["tile"], out, owner)
		if next < 0:
			break
		into = (out + 3) % 6
		index = next
		if index == start:
			chain[0]["closed"] = true  # a loop: the last piece ends where the first starts
			break
	return chain


## The piece owning the partner port across side `dir` of `tile`, or -1.
static func _partner(tile: Vector2i, dir: int, owner: Dictionary) -> int:
	var n := tile + Hex.DIRECTIONS[dir]
	return owner.get(Vector3i(n.x, n.y, (dir + 3) % 6), -1)


## Cubic Bézier control points [p0, c1, c2, p3] of every step of a chain.
static func _chain_curves(chain: Array, pieces: Array) -> Array:
	var closed: bool = chain[0].get("closed", false)
	var steps := chain
	# Chain points: the start of each step, then the end of the last one.
	var points := PackedVector2Array()
	for step: Dictionary in steps:
		points.append(_step_start(step, pieces))
	points.append(_step_end(steps[-1], pieces))
	var count := points.size()
	var tangents := PackedVector2Array()
	tangents.resize(count)
	for i in count:
		var prev := i - 1
		var next := i + 1
		if closed:
			prev = posmod(i - 1, count - 1)
			next = (i + 1) % (count - 1) if i < count - 1 else 1
		var normal := Vector2.ZERO  # crossing direction at a port, ZERO at an inner end
		if i < steps.size() and steps[i]["entry"] >= 0:
			normal = -_unit(steps[i]["entry"])
		elif i == steps.size() and steps[-1]["exit"] >= 0:
			normal = _unit(steps[-1]["exit"])
		var t := Vector2.ZERO
		if prev >= 0 and next < count:
			t = (points[next] - points[prev]).normalized()
		elif normal != Vector2.ZERO:
			t = normal
		elif next < count:
			t = (points[next] - points[i]).normalized()
		else:
			t = (points[i] - points[prev]).normalized()
		if normal != Vector2.ZERO:
			t = _limit_crossing(t, normal)
		tangents[i] = t
	if closed:
		tangents[count - 1] = tangents[0]
	var result: Array = []
	for k in steps.size():
		var tile: Vector2i = pieces[steps[k]["piece"]]["tile"]
		result.append(_piece_bezier(points[k], tangents[k], points[k + 1], tangents[k + 1], tile))
	return result


static func _step_start(step: Dictionary, pieces: Array) -> Vector2:
	var tile: Vector2i = pieces[step["piece"]]["tile"]
	return _port(tile, step["entry"]) if step["entry"] >= 0 else _centre(tile)


static func _step_end(step: Dictionary, pieces: Array) -> Vector2:
	var tile: Vector2i = pieces[step["piece"]]["tile"]
	return _port(tile, step["exit"]) if step["exit"] >= 0 else _centre(tile)


## `t` turned towards `normal` until it is at most MAX_CROSSING_ANGLE off it.
static func _limit_crossing(t: Vector2, normal: Vector2) -> Vector2:
	var angle := normal.angle_to(t)
	if absf(angle) <= MAX_CROSSING_ANGLE:
		return t
	return normal.rotated(signf(angle) * MAX_CROSSING_ANGLE)


## Bézier from `a` (tangent `ta`) to `b` (tangent `tb`) in `tile`, inner control points pulled in
## until they lie inside the hex (then the whole curve does).
static func _piece_bezier(
	a: Vector2, ta: Vector2, b: Vector2, tb: Vector2, tile: Vector2i
) -> Array:
	var h := a.distance_to(b) * HANDLE
	var c1 := a + ta * h
	var c2 := b - tb * h
	for _i in 8:
		if _hex_margin(c1, tile) >= 0.0:
			break
		c1 = a + (c1 - a) * 0.5
	for _i in 8:
		if _hex_margin(c2, tile) >= 0.0:
			break
		c2 = b + (c2 - b) * 0.5
	if _hex_margin(c1, tile) < 0.0:
		c1 = a
	if _hex_margin(c2, tile) < 0.0:
		c2 = b
	return [a, c1, c2, b]


static func _bezier(bez: Array, t: float) -> Vector2:
	var u := 1.0 - t
	var p0: Vector2 = bez[0]
	var p1: Vector2 = bez[1]
	var p2: Vector2 = bez[2]
	var p3: Vector2 = bez[3]
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)


## Half widths along a chain's samples: roads constant; rivers vary with world-position noise
## and narrow towards a dead-end source.
static func _widths(
	line: PackedVector2Array, chain: Array, pieces: Array, kind: Kind
) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(line.size())
	var half := width(kind) / 2.0
	if kind == Kind.ROAD:
		result.fill(half)
		return result
	var start_source: bool = pieces[chain[0]["piece"]]["kind"] == &"dead"
	var end_source: bool = chain.size() > 1 and pieces[chain[-1]["piece"]]["kind"] == &"dead"
	var along := PackedFloat32Array()
	along.resize(line.size())
	for i in range(1, line.size()):
		along[i] = along[i - 1] + line[i].distance_to(line[i - 1])
	var total := along[line.size() - 1] if line.size() > 0 else 0.0
	for i in line.size():
		var p := line[i]
		var noise := TerrainNoise.value_noise(
			p.x / WIDTH_WAVELENGTH, p.y / WIDTH_WAVELENGTH, WIDTH_SEED
		)
		var w := half * (1.0 + RIVER_WIDTH_VARIATION * (2.0 * noise - 1.0))
		var taper := 1.0
		if start_source:
			taper = minf(taper, _taper(along[i]))
		if end_source:
			taper = minf(taper, _taper(total - along[i]))
		result[i] = w * taper
	return result


static func _taper(distance_from_source: float) -> float:
	return lerpf(
		RIVER_SOURCE_WIDTH, 1.0, TerrainNoise.smooth(0.0, SOURCE_TAPER, distance_from_source)
	)


## The river's sideways meander: every sample moves along its normal by low-frequency noise of
## its world position, limited so it keeps WALL_MARGIN from the walls of its hex that the piece
## does not cross (the crossing sides may slide a little along the side).
static func _meander(
	line: PackedVector2Array, tiles: PackedVector2Array, junctions: Dictionary
) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(line.size())
	var count := line.size()
	var closed := count > 2 and line[0].is_equal_approx(line[count - 1])
	for i in count:
		var p := line[i]
		var dir := _direction(line, i, closed)
		var normal := Vector2(-dir.y, dir.x)
		var noise := TerrainNoise.value_noise(
			p.x / MEANDER_WAVELENGTH, p.y / MEANDER_WAVELENGTH, MEANDER_SEED
		)
		var offset := RIVER_MEANDER * (2.0 * noise - 1.0)
		var tile := Vector2i(tiles[i])
		# Calm at confluences, so a tributary still ends on the main river's centreline (a
		# junction within JUNCTION_CALM lies in the sample's tile or a neighbour).
		if not junctions.is_empty():
			for t: Vector2i in [tile] + Hex.neighbors(tile):
				if junctions.has(t):
					var d := p.distance_to(junctions[t])
					if d < JUNCTION_CALM:
						offset *= TerrainNoise.smooth(0.05, JUNCTION_CALM, d)
		# Pull the offset back while the moved point comes closer to a wall than WALL_MARGIN
		# (or than the unmoved point already is).
		var keep := minf(_hex_margin_loose(p, tile), WALL_MARGIN)
		for _k in 6:
			if _hex_margin_loose(p + normal * offset, tile) >= keep - 1e-6:
				break
			offset *= 0.5
		if _hex_margin_loose(p + normal * offset, tile) < keep - 1e-6:
			offset = 0.0
		result[i] = p + normal * offset
	if closed:
		result[count - 1] = result[0]
	return result


## Unit direction of a polyline at vertex `i` (from its neighbours).
static func _direction(line: PackedVector2Array, i: int, closed: bool) -> Vector2:
	var count := line.size()
	var prev := i - 1
	var next := i + 1
	if closed:
		prev = i - 1 if i > 0 else count - 2
		next = i + 1 if i < count - 1 else 1
	prev = maxi(prev, 0)
	next = mini(next, count - 1)
	var d := line[next] - line[prev]
	return d.normalized() if d != Vector2.ZERO else Vector2.RIGHT


## Signed distance of `p` from the walls of hex `tile` (positive inside).
static func _hex_margin(p: Vector2, tile: Vector2i) -> float:
	var local := p - _centre(tile)
	var reach := -INF
	for dir in 6:
		reach = maxf(reach, local.dot(_unit(dir)))
	return HALF_SEGMENT - reach


## Like _hex_margin, but measured to the hex corners' circle where the point is near a side
## midpoint: a sample on (or next to) a side it crosses is not held at that side. In practice:
## the distance to the nearest wall among those whose midpoint is farther than 0.45 from `p`.
static func _hex_margin_loose(p: Vector2, tile: Vector2i) -> float:
	var local := p - _centre(tile)
	var reach := -INF
	for dir in 6:
		var u := _unit(dir)
		if local.distance_to(u * HALF_SEGMENT) < 0.45:
			continue  # the side this sample crosses (or is about to)
		reach = maxf(reach, local.dot(u))
	return HALF_SEGMENT - reach if reach > -INF else HALF_SEGMENT


static func _centre(c: Vector2i) -> Vector2:
	var w := Hex.to_world(c, TerrainField.HEX_SIZE)
	return Vector2(w.x, w.z)


static func _port(c: Vector2i, dir: int) -> Vector2:
	return _centre(c) + _unit(dir) * HALF_SEGMENT


## Unit world-XZ direction towards neighbour `dir`.
static func _unit(dir: int) -> Vector2:
	var w := Hex.to_world(Hex.DIRECTIONS[dir], TerrainField.HEX_SIZE)
	return Vector2(w.x, w.z).normalized()


# --- triangles ---


## A strip of quads along `line` with per-vertex half widths; the side offset at each vertex is
## perpendicular to the direction through its neighbours, and neighbouring quads share their
## corner points.
static func _append_strip(
	points: PackedVector2Array,
	indices: PackedInt32Array,
	line: PackedVector2Array,
	halves: PackedFloat32Array
) -> void:
	var count := line.size()
	if count < 2:
		return
	var closed := count > 2 and line[0].is_equal_approx(line[count - 1])
	var base := points.size()
	for i in count:
		var dir := _direction(line, i, closed)
		var side := Vector2(-dir.y, dir.x) * halves[i]
		points.append(line[i] + side)  # left: base + 2 i
		points.append(line[i] - side)  # right: base + 2 i + 1
	for i in count - 1:
		var l0 := base + 2 * i
		_append_triangle(points, indices, l0, l0 + 1, l0 + 2)
		_append_triangle(points, indices, l0 + 1, l0 + 3, l0 + 2)


## Triangle (a, b, c) of `points`, wound clockwise seen from +Y whatever its order.
static func _append_triangle(
	points: PackedVector2Array, indices: PackedInt32Array, a: int, b: int, c: int
) -> void:
	# XZ with +Z south: clockwise from above = positive cross in (x, z).
	if (points[b] - points[a]).cross(points[c] - points[a]) < 0.0:
		indices.append_array(PackedInt32Array([a, c, b]))
	else:
		indices.append_array(PackedInt32Array([a, b, c]))


static func _append_disc(
	points: PackedVector2Array, indices: PackedInt32Array, centre: Vector2, radius: float
) -> void:
	var c := points.size()
	points.append(centre)
	for k in DISC_SIDES:
		var a := TAU * k / DISC_SIDES
		points.append(centre + Vector2(cos(a), sin(a)) * radius)
	for k in DISC_SIDES:
		_append_triangle(points, indices, c, c + 1 + k, c + 1 + (k + 1) % DISC_SIDES)


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0) if ab != Vector2.ZERO else 0.0
	return p.distance_to(a + ab * t)
