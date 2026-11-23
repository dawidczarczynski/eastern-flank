class_name TreeFeatures
extends RefCounted
## Real tree features in the open country (TASK-199b), only under the `true` VisualScale preset:
## the OSM single trees, tree rows, orchards and farmyard orchards (TreeFeatureSet, TASK-199a) and,
## where OSM knows nothing, rule fill – roadside tree lines, solitary field trees near parcel
## edges, copses on hills and marsh. Everything is a pure function of the map and the seed (integer
## hashes, no RNG object, no GameState.rng) and of one chunk's rectangle: the items of a rectangle
## are exactly the eager items that stand in it, in any order. Items are ScatterPlanner trees
## ({position, scale, height_scale, yaw, conifer, k}) that go through the TreeField's trees layer;
## no new draw calls. Nothing stands in forest, on water, in villages or on a road or river
## ribbon. A building mask does not exist yet (TASK-195): no building test.

const SALT := 0x7F3A
const SALT_ROW := 0x7F3B
const SALT_ORCHARD := 0x7F3C
const SALT_FARMYARD := 0x7F3D
const SALT_ROAD := 0x7F3E
const SALT_SOLITARY := 0x7F3F
const SALT_COPSE := 0x7F40

## Spacing (metres) of the trees of an OSM tree row and the largest offset from its polyline.
const ROW_SPACING_M := Vector2(5.0, 10.0)
const ROW_JITTER_M := 0.6
## Orchard row and tree spacing (metres), one value per orchard and axis.
const ORCHARD_SPACING_M := Vector2(5.0, 8.0)
## Share of the farmyards that get a small orchard of FARMYARD_COLUMNS x FARMYARD_ROWS trees.
const FARMYARD_ORCHARD_CHANCE := 0.3
const FARMYARD_COLUMNS := Vector2i(3, 6)
const FARMYARD_ROWS := Vector2i(3, 5)
const FARMYARD_TRIES := 12
## Roadside lines: a road is cut into ROAD_SEGMENT_M pieces, in every ROAD_GROUP consecutive ones
## exactly one (by hash) carries a tree line on one side: 25 % of the length.
const ROAD_SEGMENT_M := 80.0
const ROAD_GROUP := 4
const ROAD_SPACING_M := Vector2(6.0, 12.0)
const ROAD_OFFSET_M := Vector2(3.3, 5.7)
const ROAD_JITTER_M := 0.3
## Solitary trees per open hex: cumulative shares of 0, 1, 2 trees (the rest 3), their reach from
## the hex centre (world units) and the distance to a parcel edge or hex edge (metres) they keep
## within.
const SOLITARY_CUMULATIVE: Array[float] = [0.7, 0.9, 0.97]
const SOLITARY_TRIES := 8
const SOLITARY_REACH := 0.85
const BOUNDARY_M := 15.0
## Copses: share of the hill and marsh hexes with one, their tree count and the reach of their
## centre from the hex centre (world units).
const COPSE_CHANCE := 0.06
const COPSE_TREES := Vector2i(5, 30)
const COPSE_REACH := 0.4
## Distance (metres) the trees keep from a road's carriageway and a river's bank.
const ROAD_MARGIN_M := 0.4
const GOLDEN_ANGLE := 2.399963

const _OPEN_TERRAIN: Array[int] = [Terrain.Type.PLAINS, Terrain.Type.FIELDS, Terrain.Type.HILLS]
const _WET_TERRAIN: Array[int] = [Terrain.Type.HILLS, Terrain.Type.MARSH]


## The trees of the rectangle `rect` (world units, end exclusive) on the `true` preset (an empty
## list on every other one): `features` (OSM, may be null) and the rule fill. `parcels` / `look`
## may be null.
static func plan(
	grid: HexGrid,
	surface: TerrainSurface,
	seed_value: int,
	rect: Rect2,
	parcels: ParcelMap,
	look: CoverLook,
	features: TreeFeatureSet
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not VisualScale.is_true_size():
		return out
	var ctx := _Context.new(grid, surface, seed_value, rect, parcels, look)
	if features != null:
		_plan_osm(ctx, features, out)
	_plan_roadside(ctx, out)
	_plan_solitary(ctx, out)
	_plan_copses(ctx, out)
	return out


## Tree positions (metres) along `line` (a road centreline, metres): the roadside tree lines. Each
## ROAD_SEGMENT_M piece is numbered from the line's start; one piece in ROAD_GROUP carries a line
## on one side, 3.3..5.7 m from the centre line, a tree every 6..12 m. `area` (optional) keeps only
## the positions inside it.
static func roadside_positions(
	line: PackedVector2Array, key: int, area := Rect2()
) -> PackedVector2Array:
	var result := PackedVector2Array()
	var cumulative := _cumulative(line)
	if cumulative.is_empty():
		return result
	var total: float = cumulative[cumulative.size() - 1]
	var limited := area.has_area()
	for s in ceili(total / ROAD_SEGMENT_M):
		var group := s / ROAD_GROUP
		var chosen := mini(int(_unit(key, group, 0, SALT_ROAD) * ROAD_GROUP), ROAD_GROUP - 1)
		if chosen != s % ROAD_GROUP:
			continue
		var t0 := s * ROAD_SEGMENT_M
		var t1 := minf(total, t0 + ROAD_SEGMENT_M)
		var side := 1.0 if _unit(key, s, 1, SALT_ROAD) < 0.5 else -1.0
		var offset := lerpf(ROAD_OFFSET_M.x, ROAD_OFFSET_M.y, _unit(key, s, 2, SALT_ROAD))
		var t := t0 + _unit(key, s, 3, SALT_ROAD) * ROAD_SPACING_M.x
		var i := 0
		while t < t1:
			var at := _point_at(line, cumulative, t)
			var dir: Vector2 = at[1]
			var jitter := (_unit(key, s, 100 + i, SALT_ROAD) - 0.5) * 2.0 * ROAD_JITTER_M
			var p: Vector2 = at[0] + Vector2(-dir.y, dir.x) * side * (offset + jitter)
			if not limited or area.has_point(p):
				result.append(p)
			t += lerpf(ROAD_SPACING_M.x, ROAD_SPACING_M.y, _unit(key, s, 1000 + i, SALT_ROAD))
			i += 1
	return result


## Tree positions (metres) of an OSM tree row: every 5..10 m along `polyline`, at most
## ROW_JITTER_M off it.
static func row_positions(
	polyline: PackedVector2Array, key: int, area := Rect2()
) -> PackedVector2Array:
	var result := PackedVector2Array()
	var cumulative := _cumulative(polyline)
	if cumulative.is_empty():
		return result
	var total: float = cumulative[cumulative.size() - 1]
	var limited := area.has_area()
	var t := _unit(key, 0, 0, SALT_ROW) * ROW_SPACING_M.x
	var i := 0
	while t <= total:
		var at := _point_at(polyline, cumulative, t)
		var dir: Vector2 = at[1]
		var jitter := (_unit(key, i, 1, SALT_ROW) - 0.5) * 2.0 * ROW_JITTER_M
		var p: Vector2 = at[0] + Vector2(-dir.y, dir.x) * jitter
		if not limited or area.has_point(p):
			result.append(p)
		t += lerpf(ROW_SPACING_M.x, ROW_SPACING_M.y, _unit(key, i, 2, SALT_ROW))
		i += 1
	return result


## Orchard tree positions (metres): a lattice along the long axis of the polygon's outer ring
## with one row and one tree spacing of 5..8 m, every point inside the polygon (outer ring, not in
## a hole). `area` (optional) keeps only the positions inside it.
static func orchard_positions(
	rings: Array[PackedVector2Array], key: int, area := Rect2()
) -> PackedVector2Array:
	var result := PackedVector2Array()
	if rings.is_empty() or rings[0].size() < 3:
		return result
	var axis := RealParcels.long_axis(rings[0])
	var perp := Vector2(-axis.y, axis.x)
	var along := lerpf(ORCHARD_SPACING_M.x, ORCHARD_SPACING_M.y, _unit(key, 0, 0, SALT_ORCHARD))
	var across := lerpf(ORCHARD_SPACING_M.x, ORCHARD_SPACING_M.y, _unit(key, 1, 0, SALT_ORCHARD))
	var u0 := INF
	var u1 := -INF
	var v0 := INF
	var v1 := -INF
	for p in rings[0]:
		u0 = minf(u0, p.dot(axis))
		u1 = maxf(u1, p.dot(axis))
		v0 = minf(v0, p.dot(perp))
		v1 = maxf(v1, p.dot(perp))
	u0 += _unit(key, 2, 0, SALT_ORCHARD) * along
	v0 += _unit(key, 3, 0, SALT_ORCHARD) * across
	var limited := area.has_area()
	var u := u0
	while u <= u1:
		var v := v0
		while v <= v1:
			var p := axis * u + perp * v
			if (not limited or area.has_point(p)) and inside(rings, p):
				result.append(p)
			v += across
		u += along
	return result


## The small orchard of a farmyard polygon (metres): with probability FARMYARD_ORCHARD_CHANCE (by
## hash of `key`) a block of 3..6 x 3..5 trees (9..30) on a lattice of 5..8 m along the polygon's
## long axis, wholly inside the polygon; empty when none fits.
static func farmyard_positions(
	rings: Array[PackedVector2Array], key: int, area := Rect2()
) -> PackedVector2Array:
	var result := PackedVector2Array()
	if rings.is_empty() or rings[0].size() < 3:
		return result
	if _unit(key, 0, 0, SALT_FARMYARD) >= FARMYARD_ORCHARD_CHANCE:
		return result
	var axis := RealParcels.long_axis(rings[0])
	var perp := Vector2(-axis.y, axis.x)
	var along := lerpf(ORCHARD_SPACING_M.x, ORCHARD_SPACING_M.y, _unit(key, 1, 0, SALT_FARMYARD))
	var across := lerpf(ORCHARD_SPACING_M.x, ORCHARD_SPACING_M.y, _unit(key, 2, 0, SALT_FARMYARD))
	var columns := (
		FARMYARD_COLUMNS.x
		+ mini(
			int(_unit(key, 3, 0, SALT_FARMYARD) * (FARMYARD_COLUMNS.y - FARMYARD_COLUMNS.x + 1)),
			FARMYARD_COLUMNS.y - FARMYARD_COLUMNS.x
		)
	)
	var rows := (
		FARMYARD_ROWS.x
		+ mini(
			int(_unit(key, 4, 0, SALT_FARMYARD) * (FARMYARD_ROWS.y - FARMYARD_ROWS.x + 1)),
			FARMYARD_ROWS.y - FARMYARD_ROWS.x
		)
	)
	var u0 := INF
	var u1 := -INF
	var v0 := INF
	var v1 := -INF
	for p in rings[0]:
		u0 = minf(u0, p.dot(axis))
		u1 = maxf(u1, p.dot(axis))
		v0 = minf(v0, p.dot(perp))
		v1 = maxf(v1, p.dot(perp))
	var block := Vector2((columns - 1) * along, (rows - 1) * across)
	for attempt in FARMYARD_TRIES:
		var u := lerpf(u0, u1 - block.x, _unit(key, 5, attempt, SALT_FARMYARD))
		var v := lerpf(v0, v1 - block.y, _unit(key, 6, attempt, SALT_FARMYARD))
		var block_points := PackedVector2Array()
		var fits := true
		for i in columns:
			for j in rows:
				var p := axis * (u + i * along) + perp * (v + j * across)
				if not inside(rings, p):
					fits = false
					break
				block_points.append(p)
			if not fits:
				break
		if fits:
			for p in block_points:
				if not area.has_area() or area.has_point(p):
					result.append(p)
			return result
	return result


## Whether `p` lies inside the polygon `rings` (the outer ring, not in one of the holes).
static func inside(rings: Array[PackedVector2Array], p: Vector2) -> bool:
	if rings.is_empty() or not Geometry2D.is_point_in_polygon(p, rings[0]):
		return false
	for h in range(1, rings.size()):
		if Geometry2D.is_point_in_polygon(p, rings[h]):
			return false
	return true


## What lies at (x_m, z_m): the parcel kind and its labels on a parcel, else the hex: two points
## with different labels are on different sides of a boundary.
static func boundary_label(parcels: ParcelMap, x_m: float, z_m: float) -> Vector3i:
	if parcels != null and parcels.kind_at_metres(x_m, z_m) != 0:
		var pixel := parcels.label_at_metres(x_m, z_m)
		return Vector3i(
			roundi(pixel.r * 255.0) + 1, roundi(pixel.g * 255.0), roundi(pixel.b * 255.0)
		)
	var c := Hex.from_world(
		Vector3(x_m / MapScale.metres_per_unit, 0.0, z_m / MapScale.metres_per_unit),
		TerrainField.HEX_SIZE
	)
	return Vector3i(0, c.x, c.y)


## Whether a parcel edge or hex edge lies within BOUNDARY_M of (x_m, z_m): one of eight points
## BOUNDARY_M away has another boundary_label.
static func near_boundary(parcels: ParcelMap, x_m: float, z_m: float) -> bool:
	var here := boundary_label(parcels, x_m, z_m)
	for i in 8:
		var a := i * TAU / 8.0
		var q := Vector2(x_m, z_m) + Vector2(cos(a), sin(a)) * BOUNDARY_M
		if boundary_label(parcels, q.x, q.y) != here:
			return true
	return false


static func _plan_osm(ctx: _Context, features: TreeFeatureSet, out: Array[Dictionary]) -> void:
	var area := ctx.area_m
	for i in features.points.size():
		var p := features.points[i]
		if area.has_point(p):
			_add(ctx, out, p, false, Vector2(0.75, 1.1), 0.2)
	for i in features.rows.size():
		if features.row_bounds[i].grow(ROW_JITTER_M).intersects(area):
			for p in row_positions(features.rows[i], i, area):
				_add(ctx, out, p, false, Vector2(0.7, 1.05), 0.15)
	for i in features.orchards.size():
		if features.orchard_bounds[i].intersects(area):
			var rings: Array[PackedVector2Array] = []
			rings.assign(features.orchards[i])
			for p in orchard_positions(rings, i, area):
				_add(ctx, out, p, false, Vector2(0.26, 0.34), 0.0)
	for i in features.farmyards.size():
		if features.farmyard_bounds[i].intersects(area):
			var rings: Array[PackedVector2Array] = []
			rings.assign(features.farmyards[i])
			for p in farmyard_positions(rings, i, area):
				_add(ctx, out, p, false, Vector2(0.26, 0.34), 0.0)


static func _plan_roadside(ctx: _Context, out: Array[Dictionary]) -> void:
	if not ctx.grid.has_links():
		return
	var lines := FeatureRibbonPlanner.lines(ctx.grid, FeatureRibbonPlanner.Kind.ROAD)
	var reach := ctx.area_m.grow(ROAD_OFFSET_M.y + 1.0)
	for j in lines.size():
		var line := Transform2D.IDENTITY.scaled(Vector2(ctx.metres, ctx.metres)) * lines[j]
		if not TreeFeatureSet.bounds_of(line).grow(1.0).intersects(reach):
			continue
		for p in roadside_positions(line, j, ctx.area_m):
			_add(ctx, out, p, false, Vector2(0.7, 1.0), 0.1)


static func _plan_solitary(ctx: _Context, out: Array[Dictionary]) -> void:
	var seed_value := ctx.seed_value
	for c in ScatterPlanner.coords_near(ctx.grid, ctx.rect.grow(TerrainField.HEX_SIZE)):
		if ctx.grid.get_terrain(c) not in _OPEN_TERRAIN:
			continue
		var roll := _unit(seed_value, c.x, c.y, SALT_SOLITARY)
		var count := 0
		while count < SOLITARY_CUMULATIVE.size() and roll >= SOLITARY_CUMULATIVE[count]:
			count += 1
		var centre := Hex.to_world(c, TerrainField.HEX_SIZE)
		for n in count:
			for attempt in SOLITARY_TRIES:
				var h := (n * SOLITARY_TRIES + attempt) * 4 + 1
				var angle := _unit(seed_value, c.x, c.y * 64 + h, SALT_SOLITARY) * TAU
				var r := sqrt(_unit(seed_value, c.x, c.y * 64 + h + 1, SALT_SOLITARY))
				var p := (
					Vector2(centre.x, centre.z)
					+ Vector2(cos(angle), sin(angle)) * (r * SOLITARY_REACH * TerrainField.HEX_SIZE)
				)
				var p_m := p * ctx.metres
				if not near_boundary(ctx.parcels, p_m.x, p_m.y):
					continue
				var tree := _make(ctx, p_m, true, Vector2(0.7, 1.0), 0.1)
				if tree.is_empty():
					continue
				# Whether this tile gets its tree never depends on the chunk: only the append does.
				if ScatterPlanner.in_rect(tree["position"], ctx.rect):
					out.append(tree)
				break


static func _plan_copses(ctx: _Context, out: Array[Dictionary]) -> void:
	var seed_value := ctx.seed_value
	for c in ScatterPlanner.coords_near(ctx.grid, ctx.rect.grow(TerrainField.HEX_SIZE)):
		if ctx.grid.get_terrain(c) not in _WET_TERRAIN:
			continue
		if _unit(seed_value, c.x, c.y, SALT_COPSE) >= COPSE_CHANCE:
			continue
		var centre := Hex.to_world(c, TerrainField.HEX_SIZE)
		var angle := _unit(seed_value, c.x, c.y, SALT_COPSE + 1) * TAU
		var reach := sqrt(_unit(seed_value, c.x, c.y, SALT_COPSE + 2)) * COPSE_REACH
		var middle := (
			(Vector2(centre.x, centre.z) + Vector2(cos(angle), sin(angle)) * reach) * ctx.metres
		)
		var count := (
			COPSE_TREES.x
			+ mini(
				int(
					(
						_unit(seed_value, c.x, c.y, SALT_COPSE + 3)
						* (COPSE_TREES.y - COPSE_TREES.x + 1)
					)
				),
				COPSE_TREES.y - COPSE_TREES.x
			)
		)
		var radius := 3.0 + 3.5 * sqrt(count)
		var phase := _unit(seed_value, c.x, c.y, SALT_COPSE + 4) * TAU
		for i in count:
			var a := phase + i * GOLDEN_ANGLE
			var d := radius * sqrt((i + 0.5) / count)
			var wobble := (_unit(seed_value, c.x, c.y * 64 + i, SALT_COPSE + 5) - 0.5) * 2.0
			var p := middle + Vector2(cos(a), sin(a)) * (d + wobble)
			_add(ctx, out, p, true, Vector2(0.55, 0.95), 0.2)


## Appends the tree of `_make` when it stands in the rectangle; true when it was added.
static func _add(
	ctx: _Context,
	out: Array[Dictionary],
	p_m: Vector2,
	clear: bool,
	size: Vector2,
	conifer_chance: float
) -> bool:
	if not ScatterPlanner.in_rect(Vector3(p_m.x / ctx.metres, 0.0, p_m.y / ctx.metres), ctx.rect):
		return false
	var tree := _make(ctx, p_m, clear, size, conifer_chance)
	if tree.is_empty():
		return false
	out.append(tree)
	return true


## The tree at `p_m` (metres) on open ground off the ribbons (`clear`: with the full clearance of
## scatter, else just off the road and river) and above the shore, or an empty dictionary. Size and
## species hash from the position. Does not look at the rectangle: whether a candidate is accepted
## never depends on the chunk.
static func _make(
	ctx: _Context, p_m: Vector2, clear: bool, size: Vector2, conifer_chance: float
) -> Dictionary:
	var x := p_m.x / ctx.metres
	var z := p_m.y / ctx.metres
	var c := Hex.from_world(Vector3(x, 0.0, z), TerrainField.HEX_SIZE)
	if not ctx.grid.has_tile(c):
		return {}
	var terrain := ctx.look.terrain_at(x, z) if ctx.look != null else ctx.grid.get_terrain(c)
	if terrain in [Terrain.Type.FOREST, Terrain.Type.WATER, Terrain.Type.URBAN]:
		return {}
	if clear:
		if not FeatureRibbonPlanner.is_clear(ctx.grid, x, z):
			return {}
	elif not _off_ribbons(ctx.grid, x, z):
		return {}
	var y := ctx.surface.ground_height(x, z)
	if y < ScatterPlanner.MIN_TREE_GROUND:
		return {}
	var key := int(roundf(p_m.x * 10.0)) * 7919 + ctx.seed_value
	var key_z := int(roundf(p_m.y * 10.0))
	var h1 := _unit(key, key_z, 0, SALT)
	var h2 := _unit(key, key_z, 1, SALT)
	var h3 := _unit(key, key_z, 2, SALT)
	var s := lerpf(size.x, size.y, h1)
	return {
		"position": Vector3(x, y - ScatterPlanner.TREE_SINK, z),
		"scale": s,
		"height_scale": s * (0.92 + 0.16 * h2),
		"yaw": h2 * TAU,
		"conifer": h3 < conifer_chance,
		"k": h3,
	}


## Whether (x, z) lies off the carriageway of a road and off a river (a margin of 0.4 m): roadside
## trees may stand on the worn verge of the 10 m road ribbon, 3 m and more from its centre line.
static func _off_ribbons(grid: HexGrid, x: float, z: float) -> bool:
	if not grid.has_links():
		return true
	var margin := ROAD_MARGIN_M / MapScale.metres_per_unit
	var verge := FeatureRibbonPlanner.ROAD_VERGE_M / MapScale.metres_per_unit
	if (
		FeatureRibbonPlanner.edge_distance(grid, FeatureRibbonPlanner.Kind.ROAD, x, z)
		< margin - verge
	):
		return false
	return FeatureRibbonPlanner.edge_distance(grid, FeatureRibbonPlanner.Kind.RIVER, x, z) >= margin


static func _unit(a: int, b: int, c: int, salt: int) -> float:
	return FieldParcels.unit_hash(a, b, c, salt)


## Arc length at every vertex of `line` (empty for fewer than two vertices).
static func _cumulative(line: PackedVector2Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if line.size() < 2:
		return result
	var sum := 0.0
	result.append(0.0)
	for i in range(1, line.size()):
		sum += line[i].distance_to(line[i - 1])
		result.append(sum)
	return result


## [position, unit direction] at arc length `t` of `line` (`cumulative` from _cumulative).
static func _point_at(line: PackedVector2Array, cumulative: PackedFloat32Array, t: float) -> Array:
	var lo := 0
	var hi := cumulative.size() - 2
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if cumulative[mid] <= t:
			lo = mid
		else:
			hi = mid - 1
	var a := line[lo]
	var b := line[lo + 1]
	var length := cumulative[lo + 1] - cumulative[lo]
	var dir := (b - a) / maxf(length, 1e-6)
	var f := clampf(t - cumulative[lo], 0.0, length)
	return [a + dir * f, dir]


## What one plan() call shares between its parts.
class _Context:
	extends RefCounted
	var grid: HexGrid
	var surface: TerrainSurface
	var seed_value: int
	var rect: Rect2
	var area_m: Rect2
	var parcels: ParcelMap
	var look: CoverLook
	var metres: float

	func _init(
		p_grid: HexGrid,
		p_surface: TerrainSurface,
		p_seed: int,
		p_rect: Rect2,
		p_parcels: ParcelMap,
		p_look: CoverLook
	) -> void:
		grid = p_grid
		surface = p_surface
		seed_value = p_seed
		rect = p_rect
		parcels = p_parcels
		look = p_look
		metres = MapScale.metres_per_unit
		area_m = Rect2(rect.position * metres, rect.size * metres)
