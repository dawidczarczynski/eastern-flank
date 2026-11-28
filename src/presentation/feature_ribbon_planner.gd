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
const _KINDS: Array[Kind] = [Kind.ROAD, Kind.RIVER]
const _NO_ENTRY: Array = []
## Centre to side midpoint: half the distance between neighbouring centres (√3/2 · HEX_SIZE).
const HALF_SEGMENT := Hex.SQRT3 / 2.0 * TerrainField.HEX_SIZE
## Road look in metres (TASK-108b), converted with MapScale: a 5 m carriageway with a 2.5 m worn
## verge on each side is a 10 m ribbon.
const ROAD_CARRIAGEWAY_M := 5.0
const ROAD_VERGE_M := 2.5
## Scatter keeps this far (metres) from a road ribbon's edge.
const ROAD_CLEARANCE_M := 3.0
## River look in metres (TASK-108c), converted with MapScale: 8 m of water (one width for every
## rule river, the importer stores no class) and a 3 m muddy bank band on each side; the ribbon is
## water + 2 banks wide and `across` 0 / ±1 runs from the centreline to the bank's outer edge.
const RIVER_WATER_M := 8.0
const RIVER_BANK_M := 3.0
## The bank band grows with the water width (share of it, metres) up to BANK_MAX_M.
const BANK_PER_WATER := 0.12
const BANK_MAX_M := 20.0
## Chain ends whose drawn ground differs by less than this (metres of height) have no slope to
## flow down: the river flows from its source, else from the smaller (x, z).
const FLOW_TIE_M := 1.5
## Bridges (TASK-108c): metres.
const BRIDGE_ABUTMENT_M := 4.0
const BRIDGE_MAX_SPAN_M := 40.0
const BRIDGE_WIDTH_M := 7.0
## Two crossings closer than this are one bridge.
const BRIDGE_MERGE_M := 10.0
## River width varies by ± this share along its course (low-frequency noise).
const RIVER_WIDTH_VARIATION := 0.25
## A river narrows to this share of its width towards a dead-end source, over SOURCE_TAPER_M.
const RIVER_SOURCE_WIDTH := 0.4
const SOURCE_TAPER_M := 173.0
## Largest sideways meander of a river line in metres (a main swing of a few river widths over
## ~320 m plus a smaller, faster wobble); all noise wavelengths are metres too (MapScale).
const RIVER_MEANDER_M := 32.0
const MEANDER_MAIN_M := 24.5
const MEANDER_FINE_M := 7.5
const MEANDER_WAVELENGTH_M := 317.0
const MEANDER_FINE_WAVELENGTH_M := 108.0
const MEANDER_SEED := 61.0
const MEANDER_FINE_SEED := 83.0
## Independent per-side irregularity of the water edge (share of the water half width) and of the
## bank band (share of the bank width); two noise scales in metres.
const WATER_EDGE_VARIATION := 0.25
const BANK_VARIATION := 0.5
const EDGE_WAVELENGTH_M := 130.0
const EDGE_FINE_WAVELENGTH_M := 40.0
const EDGE_SEEDS := [101.0, 113.0, 127.0, 139.0]
## Metres over which a river's end at a confluence (the tributary side) or its source fades out
## so the water merges into the body of water instead of ending in a flat slab.
const JUNCTION_FADE_M := 9.0
const SOURCE_FADE_M := 12.0
const WIDTH_SEED := 67.0
const WIDTH_WAVELENGTH_M := 332.0
const ROAD_COLOR := Color("#8a7f6a")
## Fallback (no river shader) look of the river.
const RIVER_COLOR := Color("#3d5a66")
const RIVER_ROUGHNESS := 0.35
const RIVER_SPECULAR := 0.7
## Lift above the drawn terrain mesh (below the grid lines and overlays); a road lies a little
## higher than a river, so it reads as crossing it (no depth fighting where they overlap).
const LIFT_M := 0.25
const ROAD_LIFT_M := 0.3
## Centreline sample spacing (world units); the ribbon follows the terrain mesh between samples.
const SAMPLE_STEP := 0.03
## Bézier handle length as a share of the piece's chord (1/3 = Catmull-Rom-like).
const HANDLE := 0.36
## A centreline crosses a side at most this far from the side normal.
const MAX_CROSSING_ANGLE := 0.8727  # 50°
## Sides of a junction / dead-end disc.
const DISC_SIDES := 12
## The meander fades out within this distance of a confluence (spoke end).
const JUNCTION_CALM_M := 130.0
## Meander and width noise keep this far from the hex walls a piece does not cross.
const WALL_MARGIN := 0.06

static var _plan_cache: Dictionary = {}
static var _index_grid := 0
static var _index_version := -1
static var _index_scale := 0.0
static var _index: Dictionary = {}


static func links(grid: HexGrid, c: Vector2i, kind: Kind) -> int:
	return grid.road_links(c) if kind == Kind.ROAD else grid.river_links(c)


## Nominal width of the whole ribbon of `kind` (rivers: water plus both banks, the water varies
## around it).
static func width(kind: Kind) -> float:
	return road_width() if kind == Kind.ROAD else river_width()


## Nominal river ribbon (water plus two bank bands) in world units.
static func river_width() -> float:
	return MapScale.to_units(RIVER_WATER_M + 2.0 * RIVER_BANK_M)


## Nominal water width in world units of a river `water_m` metres wide (the default river, when
## the map stores no width).
static func water_width(water_m: float = RIVER_WATER_M) -> float:
	return MapScale.to_units(water_m)


## Width of one bank band in world units of a river `water_m` wide: a wide river has a broad
## sandy shore (shoals and a beach), capped at BANK_MAX_M.
static func bank_width(water_m: float = RIVER_WATER_M) -> float:
	return MapScale.to_units(minf(RIVER_BANK_M + BANK_PER_WATER * water_m, BANK_MAX_M))


## Whole road ribbon (carriageway plus both verges) in world units.
static func road_width() -> float:
	return MapScale.to_units(ROAD_CARRIAGEWAY_M + 2.0 * ROAD_VERGE_M)


## Share of the half width (`across`) where the carriageway ends and the verge starts.
static func carriageway_across() -> float:
	return ROAD_CARRIAGEWAY_M / (ROAD_CARRIAGEWAY_M + 2.0 * ROAD_VERGE_M)


## Space scatter keeps beyond the edge of a ribbon of `kind`, in world units.
static func clearance(_kind: Kind) -> float:
	return MapScale.to_units(ROAD_CLEARANCE_M)


static func meander_limit() -> float:
	return MapScale.to_units(RIVER_MEANDER_M)


static func lift(kind: Kind) -> float:
	return MapScale.to_units(ROAD_LIFT_M if kind == Kind.ROAD else LIFT_M)


## Largest half width a ribbon of `kind` reaches anywhere (rivers: of one `water_m` metres wide).
static func max_half_width(kind: Kind, water_m: float = RIVER_WATER_M) -> float:
	if kind == Kind.ROAD:
		return width(kind) / 2.0
	return (
		water_width(water_m) / 2.0 * (1.0 + RIVER_WIDTH_VARIATION) * (1.0 + WATER_EDGE_VARIATION)
		+ bank_width(water_m) * (1.0 + BANK_VARIATION)
	)


## Centrelines (world XZ) of `kind`, one polyline per chain; a closed loop repeats its first point
## at the end. Empty when the grid has no links of `kind`. Cached per grid and links_version.
static func lines(grid: HexGrid, kind: Kind) -> Array[PackedVector2Array]:
	return _plan(grid, kind)["lines"]


## Half width of the whole ribbon (rivers: water + bank) at every centreline vertex, parallel to
## `lines`.
static func half_widths(grid: HexGrid, kind: Kind) -> Array[PackedFloat32Array]:
	return _plan(grid, kind)["half_widths"]


## Base water width in metres of every river chain, parallel to `lines(grid, RIVER)`: the median
## of the stored widths of the chain's tiles (HexGrid.river_width_m), constant along the chain.
static func water_widths_m(grid: HexGrid) -> PackedFloat32Array:
	return _plan(grid, Kind.RIVER)["base_water_m"]


## Whole water width in world units at every vertex of every river line, parallel to
## `lines(grid, RIVER)` (RiverChannel digs the bed from it).
static func water_widths(grid: HexGrid) -> Array[PackedFloat32Array]:
	return _plan(grid, Kind.RIVER)["water"]


## Junction and dead-end discs as Vector3(x, z, radius).
static func discs(grid: HexGrid, kind: Kind) -> PackedVector3Array:
	return _plan(grid, kind)["discs"]


## Indexed flat mesh of the whole ribbon of `kind`: {points: PackedVector2Array (world XZ),
## indices: PackedInt32Array (triangles, clockwise seen from above like the terrain),
## across: PackedFloat32Array (-1 / +1 on the two outer edges, 0 on the centreline; discs 0 at the
## centre and 1 on the rim), across_dirs: PackedVector2Array (unit world direction a vertex moves
## to widen the ribbon, ZERO on the centreline)} – one strip per centreline (neighbouring quads
## share their corner points) plus the discs. Rivers add `along` (PackedFloat32Array: metres of
## arc length from the upstream end, see `flows`) and `water_edge` (the `across` value where the
## water ends and the bank starts, per vertex and side) and `fade` (opacity factor 0..1: 0 at a
## source and where a tributary ends on the through river, so the water merges instead of ending
## in a flat slab). Tributary strips come last, drawn over the through river.
static func mesh(grid: HexGrid, kind: Kind) -> Dictionary:
	var points := PackedVector2Array()
	var indices := PackedInt32Array()
	var across := PackedFloat32Array()
	var dirs := PackedVector2Array()
	var plan := _plan(grid, kind)
	var all_lines := lines(grid, kind)
	var outer: Array[PackedVector2Array] = plan["outer"]
	var edges: Array[PackedVector2Array] = plan["edges"]
	var late: Array[bool] = plan["late"]
	# Tributaries (lines ending at a confluence) come last: they draw over the through river.
	var order: Array[int] = []
	for pass_late in [false, true]:
		for i in all_lines.size():
			if kind == Kind.RIVER and late[i] == pass_late or kind == Kind.ROAD and not pass_late:
				order.append(i)
	for i in order:
		_append_strip(points, indices, all_lines[i], outer[i], across, dirs)
	for disc in discs(grid, kind):
		_append_disc(points, indices, Vector2(disc.x, disc.y), disc.z, across, dirs)
	var result := {"points": points, "indices": indices, "across": across, "across_dirs": dirs}
	if kind == Kind.RIVER:
		var along := PackedFloat32Array()
		var edge := PackedFloat32Array()
		var fade := PackedFloat32Array()
		var flow_along := flows(grid)
		var flow_fade: Array[PackedFloat32Array] = plan["fade"]
		for i in order:
			for k in all_lines[i].size():
				# Vertex order of a strip: left, right.
				edge.append_array(PackedFloat32Array([edges[i][k].x, edges[i][k].y]))
				along.append_array(PackedFloat32Array([flow_along[i][k], flow_along[i][k]]))
				fade.append_array(PackedFloat32Array([flow_fade[i][k], flow_fade[i][k]]))
		# Strips come first (two vertices per sample, none for a one-point line), discs after.
		along.resize(points.size())
		edge.resize(points.size())
		fade.resize(points.size())
		result["along"] = along
		result["water_edge"] = edge
		result["fade"] = fade
	return result


## Arc length in metres from the upstream end at every river centreline vertex, parallel to
## `lines(grid, RIVER)`. Every river line is stored downstream-first (a river chain flows from its
## end with the higher drawn ground to the lower; within FLOW_TIE_M of each other: from a
## dead-end source, else from the smaller (x, z); loops keep their point order), so this rises
## monotonically from 0.
static func flows(grid: HexGrid) -> Array[PackedFloat32Array]:
	return _plan(grid, Kind.RIVER)["along"]


## The same triangles as flat point triples (`mesh` expanded).
static func triangles(grid: HexGrid, kind: Kind) -> PackedVector2Array:
	var indexed := mesh(grid, kind)
	var points: PackedVector2Array = indexed["points"]
	var result := PackedVector2Array()
	for index: int in indexed["indices"]:
		result.append(points[index])
	return result


## Bridge sites (TASK-108c, see BridgeSites): one per place where a drawn road centreline crosses
## a drawn river centreline, overlapping decks merged; empty when either kind has no links.
static func bridges(grid: HexGrid) -> Array[Dictionary]:
	return BridgeSites.find(grid)


## Span of a bridge over `water_m` of water crossed at an angle whose sine is `sin_angle`.
static func bridge_span_m(water_m: float, sin_angle: float) -> float:
	return BridgeSites.span_m(water_m, sin_angle)


## The river centreline segments owned by tile `coord` (their midpoint lies in it, so every
## segment belongs to exactly one tile): [{a: Vector2, b: Vector2, half: float}] with the half
## width of the whole ribbon (the widest side). Empty without rivers. Pure, cached index.
static func river_segments(grid: HexGrid, coord: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not grid.has_links():
		return result
	var entry: Array = (clearance_index(grid)[Kind.RIVER] as Dictionary).get(coord, _NO_ENTRY)
	if entry.is_empty():
		return result
	var pairs: PackedVector2Array = entry[0]
	var halves: PackedFloat32Array = entry[1]
	for i in halves.size():
		var a := pairs[2 * i]
		var b := pairs[2 * i + 1]
		if a == b:
			continue
		var mid := (a + b) * 0.5
		if Hex.from_world(Vector3(mid.x, 0.0, mid.y), TerrainField.HEX_SIZE) == coord:
			result.append({"a": a, "b": b, "half": halves[i]})
	return result


## Distance from world (x, z) to the nearest centreline of `kind`; INF when none is near (only
## the pieces registered for the tile under the point are checked, see `is_clear`).
static func distance(grid: HexGrid, kind: Kind, x: float, z: float) -> float:
	return _nearest(grid, kind, x, z, false)


## Distance from world (x, z) to the nearest ribbon edge of `kind` (negative on the ribbon); INF
## when none is near.
static func edge_distance(grid: HexGrid, kind: Kind, x: float, z: float) -> float:
	return _nearest(grid, kind, x, z, true)


## Whether any road or river comes near tile `coord` (is_clear can only say no there). Pure.
static func has_ribbons(grid: HexGrid, coord: Vector2i) -> bool:
	if not grid.has_links():
		return false
	var index := clearance_index(grid)
	for kind: Kind in _KINDS:
		if (index[kind] as Dictionary).has(coord):
			return true
	return false


## Whether scatter (trees, rocks, bushes, grass) may stand at (x, z): farther than the local half
## width + CLEARANCE from every road and river ribbon. Always true on grids without links.
static func is_clear(grid: HexGrid, x: float, z: float) -> bool:
	if not grid.has_links():
		return true
	# Called per grass candidate: the edge_distance(kind) < clearance(kind) rule with one index
	# and tile lookup, the segment distance inlined, squared, and an early exit.
	var index := clearance_index(grid)
	var coord := Hex.from_world(Vector3(x, 0.0, z), TerrainField.HEX_SIZE)
	for kind: Kind in _KINDS:
		var entry: Array = (index[kind] as Dictionary).get(coord, _NO_ENTRY)
		if entry.is_empty():
			continue
		var pairs: PackedVector2Array = entry[0]
		var halves: PackedFloat32Array = entry[1]
		var limit := clearance(kind)
		for i in halves.size():
			var reach := halves[i] + limit
			if reach <= 0.0:
				continue
			var a := pairs[2 * i]
			var abx := pairs[2 * i + 1].x - a.x
			var aby := pairs[2 * i + 1].y - a.y
			var dx := x - a.x
			var dy := z - a.y
			var length_squared := abx * abx + aby * aby
			if length_squared > 0.0:
				var t := clampf((dx * abx + dy * aby) / length_squared, 0.0, 1.0)
				dx -= abx * t
				dy -= aby * t
			if dx * dx + dy * dy < reach * reach:
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
	var tiles: Dictionary = clearance_index(grid)[kind]
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
static func clearance_index(grid: HexGrid) -> Dictionary:
	if (
		grid.get_instance_id() == _index_grid
		and grid.links_version() == _index_version
		and MapScale.metres_per_unit == _index_scale
	):
		return _index
	_index = {}
	_index_scale = MapScale.metres_per_unit
	_index_grid = grid.get_instance_id()
	_index_version = grid.links_version()
	for kind: Kind in Kind.values():
		var tiles: Dictionary = {}
		var all_lines := lines(grid, kind)
		var widths := half_widths(grid, kind)
		var plan_water: Array[PackedFloat32Array] = _plan(grid, kind)["water"]
		for li in all_lines.size():
			var line := all_lines[li]
			var w := widths[li]
			var water: PackedFloat32Array = (
				plan_water[li] if kind == Kind.RIVER else PackedFloat32Array()
			)
			if water.is_empty():
				water.resize(line.size())
			for i in line.size() - 1:
				_register(
					tiles, line[i], line[i + 1], maxf(w[i], w[i + 1]), maxf(water[i], water[i + 1])
				)
		for disc in discs(grid, kind):
			var c := Vector2(disc.x, disc.y)
			_register(tiles, c, c, disc.z, 0.0)
		_index[kind] = tiles
	return _index


static func _register(tiles: Dictionary, a: Vector2, b: Vector2, half: float, water: float) -> void:
	var mid := (a + b) * 0.5
	var coord := Hex.from_world(Vector3(mid.x, 0.0, mid.y), TerrainField.HEX_SIZE)
	for t: Vector2i in [coord] + Hex.neighbors(coord):
		# Packed arrays are values: modify copies and store them back.
		var entry: Array = tiles.get_or_add(
			t, [PackedVector2Array(), PackedFloat32Array(), PackedFloat32Array()]
		)
		var pairs: PackedVector2Array = entry[0]
		var halves: PackedFloat32Array = entry[1]
		var waters: PackedFloat32Array = entry[2]
		pairs.append(a)
		pairs.append(b)
		halves.append(half)
		waters.append(water)
		entry[0] = pairs
		entry[1] = halves
		entry[2] = waters


# --- plan: pieces, chains, curves ---


## {lines, half_widths, discs} of `kind`, cached per grid instance and links_version.
static func _plan(grid: HexGrid, kind: Kind) -> Dictionary:
	var key := (
		"%d_%d_%d_%f"
		% [grid.get_instance_id(), grid.links_version(), kind, MapScale.metres_per_unit]
	)
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
	var result_along: Array[PackedFloat32Array] = []
	var result_outer: Array[PackedVector2Array] = []
	var result_edges: Array[PackedVector2Array] = []
	var result_water: Array[PackedFloat32Array] = []
	var result_fade: Array[PackedFloat32Array] = []
	var result_base_water := PackedFloat32Array()
	var result_late: Array[bool] = []
	var surface: TerrainSurface = TerrainSurface.new(grid) if kind == Kind.RIVER else null
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
		var water_m := RIVER_WATER_M
		if kind == Kind.RIVER:
			water_m = _chain_water_m(grid, chain, pieces)
			result_base_water.append(water_m)
		var sides := RiverShape.sides(line, chain, pieces, kind, water_m)
		if kind == Kind.RIVER:
			line = RiverShape.meander(line, tiles, junctions)
			var ends_source := [
				pieces[chain[0]["piece"]]["kind"] == &"dead",
				chain.size() > 1 and pieces[chain[-1]["piece"]]["kind"] == &"dead"
			]
			# Which ends fade out: a tributary's confluence end (the spoke) and a source.
			var fades := [
				RiverShape.end_fade_m(chain[0], pieces, junctions, ends_source[0]),
				(
					RiverShape.end_fade_m(chain[-1], pieces, junctions, ends_source[1])
					if chain.size() > 1
					else 0.0
				)
			]
			# A lone spoke has its confluence at the end its walk direction points to.
			if chain.size() == 1 and fades[0] == JUNCTION_FADE_M and not chain[0]["reversed"]:
				fades = [0.0, JUNCTION_FADE_M]
			if not _flows_forward(line, ends_source[0], ends_source[1], surface):
				line = _reversed(line)
				sides = RiverShape.reversed_sides(sides)
				fades.reverse()
			result_along.append(arc_length_m(line))
			result_fade.append(RiverShape.fade(line, fades[0], fades[1]))
			result_late.append(fades[0] == JUNCTION_FADE_M or fades[1] == JUNCTION_FADE_M)
		result_lines.append(line)
		result_widths.append(sides["half"])
		result_outer.append(sides["outer"])
		result_edges.append(sides["edge"])
		result_water.append(sides["water"])
	if kind == Kind.ROAD:
		for piece: Dictionary in pieces:
			if piece["kind"] == &"dead":
				var c := _centre(piece["tile"])
				result_discs.append(Vector3(c.x, c.y, road_width() / 2.0))
		for tile: Vector2i in junctions:
			var m: Vector2 = junctions[tile]
			result_discs.append(Vector3(m.x, m.y, road_width() / 2.0))
	return {
		"lines": result_lines,
		"half_widths": result_widths,
		"discs": result_discs,
		"along": result_along,
		"outer": result_outer,
		"edges": result_edges,
		"water": result_water,
		"fade": result_fade,
		"late": result_late,
		"base_water_m": result_base_water,
	}


## Base water width of a river chain in metres: the (lower) median of the stored widths of the
## tiles it passes, so one wide tile at a confluence does not widen a tributary.
static func _chain_water_m(grid: HexGrid, chain: Array, pieces: Array) -> float:
	var widths: Array[float] = []
	for step: Dictionary in chain:
		widths.append(grid.river_width_m(pieces[step["piece"]]["tile"]))
	widths.sort()
	return widths[(widths.size() - 1) >> 1] if not widths.is_empty() else RIVER_WATER_M


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


## Whether a river line's point order is already downstream (see `flows`): towards the lower
## drawn ground, on a tie from a dead-end source, else from the smaller (x, z). Loops keep it.
static func _flows_forward(
	line: PackedVector2Array, start_source: bool, end_source: bool, surface: TerrainSurface
) -> bool:
	var first := line[0]
	var last := line[line.size() - 1]
	if first.is_equal_approx(last):
		return true
	var h0 := surface.ground_height(first.x, first.y)
	var h1 := surface.ground_height(last.x, last.y)
	if absf(h0 - h1) >= MapScale.to_units(FLOW_TIE_M):
		return h0 > h1
	if start_source != end_source:
		return start_source
	return first.x < last.x or (first.x == last.x and first.y <= last.y)


static func _reversed(line: PackedVector2Array) -> PackedVector2Array:
	var result := line.duplicate()
	result.reverse()
	return result


static func reversed_floats(values: PackedFloat32Array) -> PackedFloat32Array:
	var result := values.duplicate()
	result.reverse()
	return result


## Arc length in metres from the first point of `line` to every point.
static func arc_length_m(line: PackedVector2Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(line.size())
	for i in range(1, line.size()):
		result[i] = result[i - 1] + MapScale.metres_per_unit * line[i].distance_to(line[i - 1])
	return result


## Unit direction of a polyline at vertex `i` (from its neighbours).
static func direction(line: PackedVector2Array, i: int, closed: bool) -> Vector2:
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
static func hex_margin_loose(p: Vector2, tile: Vector2i) -> float:
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
	halves: PackedVector2Array,
	across: PackedFloat32Array,
	dirs: PackedVector2Array
) -> void:
	var count := line.size()
	if count < 2:
		return
	var closed := count > 2 and line[0].is_equal_approx(line[count - 1])
	var base := points.size()
	for i in count:
		var dir := direction(line, i, closed)
		var normal := Vector2(-dir.y, dir.x)
		points.append(line[i] + normal * halves[i].x)  # left: base + 2 i
		points.append(line[i] - normal * halves[i].y)  # right: base + 2 i + 1
		across.append(1.0)
		across.append(-1.0)
		dirs.append(normal)
		dirs.append(-normal)
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
	points: PackedVector2Array,
	indices: PackedInt32Array,
	centre: Vector2,
	radius: float,
	across: PackedFloat32Array,
	dirs: PackedVector2Array
) -> void:
	var c := points.size()
	points.append(centre)
	across.append(0.0)
	dirs.append(Vector2.ZERO)
	for k in DISC_SIDES:
		var a := TAU * k / DISC_SIDES
		var radial := Vector2(cos(a), sin(a))
		points.append(centre + radial * radius)
		across.append(1.0)
		dirs.append(radial)
	for k in DISC_SIDES:
		_append_triangle(points, indices, c, c + 1 + k, c + 1 + (k + 1) % DISC_SIDES)


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0) if ab != Vector2.ZERO else 0.0
	return p.distance_to(a + ab * t)
