class_name ScatterPlanner
extends RefCounted
## Pure placement planner for cosmetic scatter: trees on forest/plains tiles, rocks on hills
## (TASK-018). Uses its own RandomNumberGenerators – never GameState.rng – so the same map and
## seed always give the same scatter and the simulation stays deterministic. Every tile seeds its
## own streams from (seed, tile, stream salt) (TASK-072b), so a tile's scatter does not depend on
## which other tiles are planned: the chunked world plans the tiles of each chunk (`plan_rect`), in
## any order, and together they give exactly the eager plan.

const FOREST_TREES := 30
const PLAINS_TREES := 4
const PLAINS_TREE_CHANCE := 0.5
const TREE_RADIUS := 0.95
## Clearing around the tile centre where the unit stands.
const CLEARING_RADIUS := 0.3
## Candidates on or below the shore are dropped.
const MIN_TREE_GROUND := 0.05
const TREE_SINK := 0.02
const HIGH_GROUND := 0.6
const CONIFER_CHANCE_HIGH := 0.8
const CONIFER_CHANCE_LOW := 0.35
const ROCKS_HILLS := 3
const ROCKS_MOUNTAIN := 8
const MOUNTAIN_ELEVATION := 1.45
const ROCK_RADIUS := 0.9
## Bushes (TASK-028): drawn from their own RNG stream so the tree/rock sequence is unchanged.
const BUSHES_FOREST := 8
const BUSHES_PLAINS := 2
const BUSH_RADIUS := 0.92
const BUSH_SCALE_MIN := 0.28
const BUSH_SCALE_RANGE := 0.25
const BUSH_SINK := 0.06
const BUSH_HEIGHT := 0.6
const BUSH_SEED_SALT := 0x5B05
## Forest edges and undergrowth (TASK-061): own RNG stream again, so the arrays above are
## unchanged. Sizes are at the `current` VisualScale preset.
const EDGE_SEED_SALT := 0xED6E
const EDGE_FOREST_SHRUBS := 8
const EDGE_FOREST_TREES := 2
const EDGE_OPEN_SHRUBS := 4
const EDGE_FOREST_SECTOR := PI / 6.0
const EDGE_OPEN_SECTOR := deg_to_rad(25.0)
const EDGE_FOREST_RADIUS_MIN := 0.55
const EDGE_FOREST_RADIUS_RANGE := 0.4
const EDGE_TREE_RADIUS_MIN := 0.5
const EDGE_TREE_RADIUS_RANGE := 0.3
const EDGE_OPEN_RADIUS_MIN := 0.65
const EDGE_OPEN_RADIUS_RANGE := 0.3
## Shrub / undergrowth scales are in tree units (TreeMeshes: a shrub is ~0.1 and undergrowth
## ~0.045 tall at scale 1, a tree 0.2-0.3), so they follow VisualScale.tree_scale().
const EDGE_FOREST_SHRUB_SCALE := Vector2(0.9, 1.5)
const EDGE_OPEN_SHRUB_SCALE := Vector2(0.7, 1.2)
const EDGE_TREE_SCALE := Vector2(0.4, 0.6)
const GROUND_COVER_FOREST := 10
const GROUND_COVER_OPEN := 3
const GROUND_COVER_SCALE := Vector2(0.7, 1.3)
## Scrub clumps on open ground (TASK-070): own RNG stream again.
const MEADOW_SEED_SALT := 0x3EAD
## Hedgerow copses on the balks of farmland (TASK-108f): this share of the strips carries one on
## its long balk, a clump every HEDGE_STEP_M with a gap chance, a tree (else a shrub) by chance.
const HEDGE_CHANCE := 0.5
const HEDGE_STEP_M := 40.0
const HEDGE_GAP_CHANCE := 0.25
const HEDGE_TREE_CHANCE := 0.3
const PLAN_KEYS: Array[String] = [
	"trees", "rocks", "bushes", "edge_shrubs", "young_trees", "ground_cover", "meadow_scrub"
]
const SHRUB := &"shrub"
const UNDERGROWTH := &"undergrowth"
const TREE_SEED_SALT := 0x7EE5
## No planned item lies farther than this from its tile centre (trees 0.95, bushes 0.92, edges
## 0.95, meadow scrub 0.92 + 0.14 companion offset): a chunk's items stand at most this far
## outside it.
const TILE_REACH := 1.2
## Land-cover raster path (TASK-108g, plan's `look`): tree candidates per hex (a quarter falls
## outside the hex and is dropped, so ~FOREST_TREES stand on a forest hex), edge candidates per
## hex, the offset (world units) at which an edge candidate looks for the other side of the forest
## outline, the share of forest-side edge candidates that are young trees, and the slope (rise per
## unit) from which rocks lie on the ground.
const COVER_TREE_DRAWS := 40
const COVER_EDGE_DRAWS := 32
const COVER_EDGE_REACH := 0.12
const COVER_EDGE_TREE_SHARE := 0.25
const COVER_ROCK_SLOPE := 0.45


## `parcels` (TASK-108f) removes everything that stands on a farmland parcel.
## Returns {"trees", "rocks", "bushes", "edge_shrubs", "young_trees", "ground_cover",
## "meadow_scrub"} (Array[Dictionary] each). Young trees, edge shrubs, ground cover and meadow
## scrub are tree dictionaries (as trees, plus "species": TreeMeshes shrub / undergrowth for the
## last three) drawn by the TreeField. Meadow scrub follows LookPreset.meadow().
## Tree: {position, scale, height_scale, yaw, conifer, k}. Rock: {position, scale, rotation}.
## Bush: {position, scale, height_scale, yaw, k}.
## `coords` limits the plan to those tiles (default: every tile of the grid, in grid order).
## `look` (TASK-108g): the land-cover raster decides what stands where (`_plan_cover`) instead of
## the hex types.
static func plan(
	grid: HexGrid,
	surface: TerrainSurface,
	seed_value: int,
	parcels: ParcelMap = null,
	coords: Array[Vector2i] = [],
	look: CoverLook = null
) -> Dictionary:
	if look != null:
		return _filtered(_plan_cover(grid, surface, seed_value, coords, look), grid, parcels)
	var rng := RandomNumberGenerator.new()
	var trees: Array[Dictionary] = []
	var rocks: Array[Dictionary] = []
	var bushes: Array[Dictionary] = []
	var bush_rng := RandomNumberGenerator.new()
	var edge_rng := RandomNumberGenerator.new()
	var edge_shrubs: Array[Dictionary] = []
	var young_trees: Array[Dictionary] = []
	var ground_cover: Array[Dictionary] = []
	var meadow_scrub: Array[Dictionary] = []
	var meadow_rng := RandomNumberGenerator.new()
	var meadow := LookPreset.meadow()
	for c in coords if not coords.is_empty() else grid.coords():
		var center := Hex.to_world(c, TerrainField.HEX_SIZE)
		rng.seed = tile_seed(seed_value, c, TREE_SEED_SALT)
		bush_rng.seed = tile_seed(seed_value, c, BUSH_SEED_SALT)
		edge_rng.seed = tile_seed(seed_value, c, EDGE_SEED_SALT)
		meadow_rng.seed = tile_seed(seed_value, c, MEADOW_SEED_SALT)
		plan_tile_meadow(grid, surface, meadow_rng, c, meadow_scrub, meadow)
		match grid.get_terrain(c):
			Terrain.Type.FOREST:
				_plan_trees(trees, surface, rng, center, FOREST_TREES)
				_plan_bushes(bushes, surface, bush_rng, center, BUSHES_FOREST)
				plan_tile_edges(grid, surface, edge_rng, c, edge_shrubs, young_trees, ground_cover)
			Terrain.Type.PLAINS:
				_plan_bushes(bushes, surface, bush_rng, center, BUSHES_PLAINS)
				plan_tile_edges(grid, surface, edge_rng, c, edge_shrubs, young_trees, ground_cover)
				var n := PLAINS_TREES if rng.randf() < PLAINS_TREE_CHANCE else 0
				_plan_trees(trees, surface, rng, center, n)
			Terrain.Type.HILLS:
				var n := ROCKS_MOUNTAIN if grid.elevation(c) > MOUNTAIN_ELEVATION else ROCKS_HILLS
				_plan_rocks(rocks, surface, rng, center, n)
				plan_tile_edges(grid, surface, edge_rng, c, edge_shrubs, young_trees, ground_cover)
			# Real-terrain types (TASK-108, basic look): fields and marsh as open plains, a village
			# without trees or rocks (houses come with TASK-108b).
			Terrain.Type.FIELDS, Terrain.Type.MARSH:
				_plan_bushes(bushes, surface, bush_rng, center, BUSHES_PLAINS)
				plan_tile_edges(grid, surface, edge_rng, c, edge_shrubs, young_trees, ground_cover)
				var n := PLAINS_TREES if rng.randf() < PLAINS_TREE_CHANCE else 0
				_plan_trees(trees, surface, rng, center, n)
			Terrain.Type.URBAN:
				_plan_bushes(bushes, surface, bush_rng, center, BUSHES_PLAINS)
				plan_tile_edges(grid, surface, edge_rng, c, edge_shrubs, young_trees, ground_cover)
	var plan := {
		"trees": trees,
		"rocks": rocks,
		"bushes": bushes,
		"edge_shrubs": edge_shrubs,
		"young_trees": young_trees,
		"ground_cover": ground_cover,
		"meadow_scrub": meadow_scrub,
	}
	return _filtered(plan, grid, parcels)


## `plan` without the items on farmland parcels, roads and rivers.
static func _filtered(plan: Dictionary, grid: HexGrid, parcels: ParcelMap) -> Dictionary:
	# Nothing stands on crop, ploughed and meadow parcels (TASK-108f; filtered afterwards, so the
	# streams above are unchanged). Under `true` ParcelMap.blocks_standing reads the crop keep-off
	# mask (TASK-217c): no kind lookup per item.
	if parcels != null:
		for key: String in plan:
			var kept: Array[Dictionary] = []
			for item: Dictionary in plan[key]:
				var p: Vector3 = item["position"]
				if not parcels.blocks_standing(p.x, p.z):
					kept.append(item)
			plan[key] = kept
	# Nothing grows on roads and rivers (filtered afterwards, so the streams above are unchanged).
	if grid.has_links():
		for key: String in plan:
			var kept: Array[Dictionary] = []
			kept.assign(FeatureRibbonPlanner.without_ribbons(grid, plan[key]))
			plan[key] = kept
	return plan


## The plan() of the tiles whose centre lies in `rect` (XZ, end exclusive; their items may stand
## up to TILE_REACH outside it): every tile belongs to exactly one rectangle of a chunk grid, and
## a tile's items do not depend on what else is planned, so the chunks together give exactly the
## eager plan, in any order.
static func plan_rect(
	grid: HexGrid,
	surface: TerrainSurface,
	seed_value: int,
	rect: Rect2,
	parcels: ParcelMap = null,
	look: CoverLook = null
) -> Dictionary:
	var coords := coords_near(grid, rect)
	if coords.is_empty():
		var result := {}
		for key: String in PLAN_KEYS:
			result[key] = [] as Array[Dictionary]
		return result
	return plan(grid, surface, seed_value, parcels, coords, look)


## Whether world point `p` lies in `rect` (XZ), the end edges excluded (so every point belongs to
## exactly one chunk).
static func in_rect(p: Vector3, rect: Rect2) -> bool:
	return (
		p.x >= rect.position.x and p.x < rect.end.x and p.z >= rect.position.y and p.z < rect.end.y
	)


## The grid's tiles whose centre lies in `rect` (XZ, end exclusive), in (r, q) order.
static func coords_near(grid: HexGrid, rect: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var size := TerrainField.HEX_SIZE
	var r0 := floori(rect.position.y / (1.5 * size))
	var r1 := ceili(rect.end.y / (1.5 * size))
	for r in range(r0, r1 + 1):
		var q0 := floori(rect.position.x / (Hex.SQRT3 * size) - r / 2.0)
		var q1 := ceili(rect.end.x / (Hex.SQRT3 * size) - r / 2.0)
		for q in range(q0, q1 + 1):
			var c := Vector2i(q, r)
			if not grid.has_tile(c):
				continue
			var w := Hex.to_world(c, size)
			if rect.has_point(Vector2(w.x, w.z)):
				result.append(c)
	return result


## Seed of one tile's stream: a hash of the plan seed, the tile and the stream's salt.
static func tile_seed(seed_value: int, c: Vector2i, salt: int) -> int:
	var h := _mix((seed_value ^ salt) & 0xFFFFFFFF)
	h = _mix(h ^ (c.x & 0xFFFFFFFF))
	return _mix(h ^ (c.y & 0xFFFFFFFF))


## 32-bit integer finaliser (the operands stay below 2^59, no overflow).
static func _mix(h: int) -> int:
	h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	return h ^ (h >> 16)


## A thorny thicket (one shrub plus bramble/nettle undergrowth) on the open ground of one land
## tile, appended to `out`. Draws a fixed count of numbers for every land tile (the chance roll
## and one clump's worth, used or not), water tiles draw nothing. Forest tiles never get a clump.
static func plan_tile_meadow(
	grid: HexGrid,
	surface: TerrainSurface,
	rng: RandomNumberGenerator,
	c: Vector2i,
	out: Array[Dictionary],
	meadow: Dictionary
) -> void:
	var terrain := grid.get_terrain(c)
	if terrain == Terrain.Type.WATER:
		return
	var chance := rng.randf()
	var angle := rng.randf() * TAU
	var u := rng.randf()
	var shrub_scale: Vector2 = meadow["scrub_shrub_scale"]
	var scale_k := rng.randf()
	var k := rng.randf()
	var companions: Array = []
	var offsets: Vector2 = meadow["scrub_companion_offset"]
	var scales: Vector2 = meadow["scrub_companion_scale"]
	for i in int(meadow["scrub_companions"]):
		var a := rng.randf() * TAU
		var o := offsets.x + rng.randf() * (offsets.y - offsets.x)
		var s := scales.x + rng.randf() * (scales.y - scales.x)
		companions.append([a, o, s, rng.randf()])
	var threshold := 0.0
	if terrain in [Terrain.Type.PLAINS, Terrain.Type.FIELDS, Terrain.Type.MARSH]:
		threshold = meadow["scrub_chance_plains"]
	elif terrain == Terrain.Type.HILLS:
		threshold = meadow["scrub_chance_hills"]
	if chance >= threshold:
		return
	var center := Hex.to_world(c, TerrainField.HEX_SIZE)
	var radius: Vector2 = meadow["scrub_radius"]
	var r := radius.x + sqrt(u) * (radius.y - radius.x)
	var s0 := shrub_scale.x + scale_k * (shrub_scale.y - shrub_scale.x)
	_append_scrub(out, surface, center, angle, r, s0, k, SHRUB)
	var shrub_at := Vector3(center.x + cos(angle) * r, 0.0, center.z + sin(angle) * r)
	for companion: Array in companions:
		_append_scrub(
			out,
			surface,
			shrub_at,
			companion[0],
			companion[1],
			companion[2],
			companion[3],
			UNDERGROWTH
		)


## Edge plants and undergrowth of one land tile, appended to the output arrays: a forest tile gets
## ground cover plus shrubs and young trees on each open side, any other tile gets a little ground
## cover and shrubs on each forest side. Water tiles get nothing.
static func plan_tile_edges(
	grid: HexGrid,
	surface: TerrainSurface,
	rng: RandomNumberGenerator,
	c: Vector2i,
	edge_shrubs: Array[Dictionary],
	young_trees: Array[Dictionary],
	ground_cover: Array[Dictionary]
) -> void:
	var terrain := grid.get_terrain(c)
	if terrain == Terrain.Type.WATER:
		return
	var center := Hex.to_world(c, TerrainField.HEX_SIZE)
	var is_forest := terrain == Terrain.Type.FOREST
	_plan_ground_cover(
		ground_cover, surface, rng, center, GROUND_COVER_FOREST if is_forest else GROUND_COVER_OPEN
	)
	for d in _edge_directions(grid, c, is_forest):
		_plan_edge_shrubs(edge_shrubs, surface, rng, center, d, is_forest)
		if is_forest:
			_plan_young_trees(young_trees, surface, rng, center, d)


## World angle (radians, atan2(z, x)) of each neighbour direction of `c` that borders a forest
## edge: from a forest tile, neighbours on the map that are neither forest nor water ("open
## sides"); from any other land tile, forest neighbours ("forest sides").
static func _edge_directions(grid: HexGrid, c: Vector2i, is_forest: bool) -> Array[float]:
	var result: Array[float] = []
	var center := Hex.to_world(c, TerrainField.HEX_SIZE)
	for dir in Hex.DIRECTIONS:
		var n := c + dir
		if not grid.has_tile(n):
			continue
		var t := grid.get_terrain(n)
		if t == Terrain.Type.WATER:
			continue
		if (t != Terrain.Type.FOREST) == is_forest:
			var w := Hex.to_world(n, TerrainField.HEX_SIZE) - center
			result.append(atan2(w.z, w.x))
	return result


## Shrubs in a sector around `angle`. Four numbers per candidate, always.
static func _plan_edge_shrubs(
	out: Array[Dictionary],
	surface: TerrainSurface,
	rng: RandomNumberGenerator,
	center: Vector3,
	angle: float,
	forest_side: bool
) -> void:
	var count := EDGE_FOREST_SHRUBS if forest_side else EDGE_OPEN_SHRUBS
	var sector := EDGE_FOREST_SECTOR if forest_side else EDGE_OPEN_SECTOR
	var r_min := EDGE_FOREST_RADIUS_MIN if forest_side else EDGE_OPEN_RADIUS_MIN
	var r_range := EDGE_FOREST_RADIUS_RANGE if forest_side else EDGE_OPEN_RADIUS_RANGE
	var scales := EDGE_FOREST_SHRUB_SCALE if forest_side else EDGE_OPEN_SHRUB_SCALE
	for i in count:
		var a := angle + (rng.randf() * 2.0 - 1.0) * sector
		var r := r_min + rng.randf() * r_range
		var s := scales.x + rng.randf() * (scales.y - scales.x)
		var k := rng.randf()
		_append_scrub(out, surface, center, a, r, s, k, SHRUB)


## Young trees in the forest-side sector of an open side. Five numbers per candidate.
static func _plan_young_trees(
	out: Array[Dictionary],
	surface: TerrainSurface,
	rng: RandomNumberGenerator,
	center: Vector3,
	angle: float
) -> void:
	for i in EDGE_FOREST_TREES:
		var a := angle + (rng.randf() * 2.0 - 1.0) * EDGE_FOREST_SECTOR
		var r := EDGE_TREE_RADIUS_MIN + rng.randf() * EDGE_TREE_RADIUS_RANGE
		var s := EDGE_TREE_SCALE.x + rng.randf() * (EDGE_TREE_SCALE.y - EDGE_TREE_SCALE.x)
		var k := rng.randf()
		var conifer_roll := rng.randf()
		var x := center.x + cos(a) * r
		var z := center.z + sin(a) * r
		var y := surface.ground_height(x, z)
		if y < MIN_TREE_GROUND:
			continue
		var chance := CONIFER_CHANCE_HIGH if y > HIGH_GROUND else CONIFER_CHANCE_LOW
		(
			out
			. append(
				{
					"position": Vector3(x, y - TREE_SINK, z),
					"scale": s,
					"height_scale": s * (0.9 + k * 0.3),
					"yaw": k * 6.0,
					"conifer": conifer_roll < chance,
					"k": k,
				}
			)
		)


## Low undergrowth anywhere in a tile. Four numbers per candidate.
static func _plan_ground_cover(
	out: Array[Dictionary],
	surface: TerrainSurface,
	rng: RandomNumberGenerator,
	center: Vector3,
	count: int
) -> void:
	for i in count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * BUSH_RADIUS
		var s := GROUND_COVER_SCALE.x + rng.randf() * (GROUND_COVER_SCALE.y - GROUND_COVER_SCALE.x)
		var k := rng.randf()
		_append_scrub(out, surface, center, a, r, s, k, UNDERGROWTH)


static func _append_scrub(
	out: Array[Dictionary],
	surface: TerrainSurface,
	center: Vector3,
	angle: float,
	r: float,
	s: float,
	k: float,
	species: StringName
) -> void:
	var x := center.x + cos(angle) * r
	var z := center.z + sin(angle) * r
	var y := surface.ground_height(x, z)
	if y < MIN_TREE_GROUND:
		return
	(
		out
		. append(
			{
				"position": Vector3(x, y - TREE_SINK, z),
				"scale": s,
				"height_scale": s * (0.85 + k * 0.35),
				"yaw": k * 6.0,
				"conifer": false,
				"species": species,
				"k": k,
			}
		)
	)


static func _in_circle(rng: RandomNumberGenerator, center: Vector3, radius: float) -> Vector2:
	while true:
		var x := (rng.randf() * 2.0 - 1.0) * radius
		var z := (rng.randf() * 2.0 - 1.0) * radius
		if Vector2(x, z).length() < radius:
			return Vector2(center.x + x, center.z + z)
	return Vector2.ZERO  # unreachable; satisfies the return-path check


static func _plan_trees(
	out: Array[Dictionary],
	surface: TerrainSurface,
	rng: RandomNumberGenerator,
	center: Vector3,
	count: int
) -> void:
	for i in count:
		var p := _in_circle(rng, center, TREE_RADIUS)
		var y := surface.ground_height(p.x, p.y)
		if y < MIN_TREE_GROUND or p.distance_to(Vector2(center.x, center.z)) < CLEARING_RADIUS:
			continue
		var s := 0.7 + rng.randf() * 0.6
		var chance := CONIFER_CHANCE_HIGH if y > HIGH_GROUND else CONIFER_CHANCE_LOW
		var conifer := rng.randf() < chance
		var k := rng.randf()
		(
			out
			. append(
				{
					"position": Vector3(p.x, y - TREE_SINK, p.y),
					"scale": s,
					"height_scale": s * (0.9 + k * 0.3),
					"yaw": k * 6.0,
					"conifer": conifer,
					"k": k,
				}
			)
		)


## Every candidate draws the same four numbers, so skipped ones never shift the stream.
static func _plan_bushes(
	out: Array[Dictionary],
	surface: TerrainSurface,
	rng: RandomNumberGenerator,
	center: Vector3,
	count: int
) -> void:
	for i in count:
		var angle := rng.randf() * TAU
		var r := sqrt(rng.randf()) * BUSH_RADIUS
		var s := BUSH_SCALE_MIN + rng.randf() * BUSH_SCALE_RANGE
		var k := rng.randf()
		var x := center.x + cos(angle) * r
		var z := center.z + sin(angle) * r
		var y := surface.ground_height(x, z)
		if y < MIN_TREE_GROUND:
			continue
		(
			out
			. append(
				{
					"position": Vector3(x, y - BUSH_SINK * s, z),
					"scale": s,
					"height_scale": BUSH_HEIGHT * s,
					"yaw": k * 6.0,
					"k": k,
				}
			)
		)


static func _plan_rocks(
	out: Array[Dictionary],
	surface: TerrainSurface,
	rng: RandomNumberGenerator,
	center: Vector3,
	count: int
) -> void:
	for i in count:
		var p := _in_circle(rng, center, ROCK_RADIUS)
		var s := 0.5 + rng.randf() * 1.2
		(
			out
			. append(
				{
					"position": Vector3(p.x, surface.ground_height(p.x, p.y), p.y),
					"scale": s,
					"rotation": Vector3(s, 3.0 * s, 0.0),
				}
			)
		)


## plan() on a land-cover raster (TASK-108g): every tile plans the same candidates, spread over
## the whole hex (so neighbouring tiles tile the ground without seams), and the cover at each
## candidate decides what stands there – trees on forest (noisy soft edge), a few on open land,
## edge plants along the forest outline, rocks where the ground is steep. The hex type is never
## read, so a forest covering a hex only partly gets trees only on that part.
static func _plan_cover(
	grid: HexGrid,
	surface: TerrainSurface,
	seed_value: int,
	coords: Array[Vector2i],
	look: CoverLook
) -> Dictionary:
	var plan := {}
	for key: String in PLAN_KEYS:
		plan[key] = [] as Array[Dictionary]
	var rng := RandomNumberGenerator.new()
	var meadow := LookPreset.meadow()
	for c in coords if not coords.is_empty() else grid.coords():
		var center := Hex.to_world(c, TerrainField.HEX_SIZE)
		rng.seed = tile_seed(seed_value, c, TREE_SEED_SALT)
		_plan_trees_cover(plan["trees"], surface, rng, center, look)
		rng.seed = tile_seed(seed_value, c, BUSH_SEED_SALT)
		_plan_bushes_cover(plan["bushes"], plan["rocks"], surface, rng, center, look)
		rng.seed = tile_seed(seed_value, c, EDGE_SEED_SALT)
		_plan_edges_cover(plan, surface, rng, center, look)
		rng.seed = tile_seed(seed_value, c, MEADOW_SEED_SALT)
		_plan_meadow_cover(plan["meadow_scrub"], surface, rng, center, meadow, look)
	return plan


## A uniform point of the pointy-top hex of size 1 around `center` (two draws, always), or
## Vector2.INF when the draw falls in the corners of the bounding box (about a quarter).
static func _hex_point_cover(rng: RandomNumberGenerator, center: Vector3) -> Vector2:
	var dx := (rng.randf() * 2.0 - 1.0) * Hex.SQRT3 * 0.5
	var dz := rng.randf() * 2.0 - 1.0
	if absf(dz) > 1.0 - absf(dx) / Hex.SQRT3:
		return Vector2.INF
	return Vector2(center.x + dx, center.z + dz)


## Trees of one tile: COVER_TREE_DRAWS candidates over the hex, kept on forest (and a few on
## open land). Six draws per candidate, always.
static func _plan_trees_cover(
	out: Array[Dictionary],
	surface: TerrainSurface,
	rng: RandomNumberGenerator,
	center: Vector3,
	look: CoverLook
) -> void:
	var open_keep := float(PLAINS_TREES) / FOREST_TREES * PLAINS_TREE_CHANCE
	for i in COVER_TREE_DRAWS:
		var p := _hex_point_cover(rng, center)
		var s := 0.7 + rng.randf() * 0.6
		var conifer_roll := rng.randf()
		var k := rng.randf()
		var keep := rng.randf()
		if p == Vector2.INF or p.distance_to(Vector2(center.x, center.z)) < CLEARING_RADIUS:
			continue
		var terrain := look.terrain_at(p.x, p.y)
		if terrain == Terrain.Type.WATER or terrain == Terrain.Type.URBAN:
			continue
		if terrain != Terrain.Type.FOREST and keep >= open_keep:
			continue
		var y := surface.ground_height(p.x, p.y)
		if y < MIN_TREE_GROUND:
			continue
		var chance := CONIFER_CHANCE_HIGH if y > HIGH_GROUND else CONIFER_CHANCE_LOW
		(
			out
			. append(
				{
					"position": Vector3(p.x, y - TREE_SINK, p.y),
					"scale": s,
					"height_scale": s * (0.9 + k * 0.3),
					"yaw": k * 6.0,
					"conifer": conifer_roll < chance,
					"k": k,
				}
			)
		)


## Bushes of one tile (all on forest, a share on open land) and rocks where the ground is steep.
## Five draws per bush candidate and four per rock candidate, always.
static func _plan_bushes_cover(
	bushes: Array[Dictionary],
	rocks: Array[Dictionary],
	surface: TerrainSurface,
	rng: RandomNumberGenerator,
	center: Vector3,
	look: CoverLook
) -> void:
	var open_keep := float(BUSHES_PLAINS) / BUSHES_FOREST
	for i in BUSHES_FOREST + 2:
		var p := _hex_point_cover(rng, center)
		var s := BUSH_SCALE_MIN + rng.randf() * BUSH_SCALE_RANGE
		var k := rng.randf()
		var keep := rng.randf()
		if p == Vector2.INF:
			continue
		var terrain := look.terrain_at(p.x, p.y)
		if terrain == Terrain.Type.WATER or (terrain != Terrain.Type.FOREST and keep >= open_keep):
			continue
		var y := surface.ground_height(p.x, p.y)
		if y < MIN_TREE_GROUND:
			continue
		(
			bushes
			. append(
				{
					"position": Vector3(p.x, y - BUSH_SINK * s, p.y),
					"scale": s,
					"height_scale": BUSH_HEIGHT * s,
					"yaw": k * 6.0,
					"k": k,
				}
			)
		)
	for i in ROCKS_MOUNTAIN:
		var p := _hex_point_cover(rng, center)
		var s := 0.5 + rng.randf() * 1.2
		if p == Vector2.INF or GrassPlanner.slope(surface, p.x, p.y) < COVER_ROCK_SLOPE:
			continue
		if look.terrain_at(p.x, p.y) == Terrain.Type.WATER:
			continue
		(
			rocks
			. append(
				{
					"position": Vector3(p.x, surface.ground_height(p.x, p.y), p.y),
					"scale": s,
					"rotation": Vector3(s, 3.0 * s, 0.0),
				}
			)
		)


## Ground cover over the tile (dense on forest, sparse on open land) and the forest edge: shrubs
## on both sides of the forest outline (a candidate is on the edge when the forest test differs
## COVER_EDGE_REACH away), young trees on its forest side. Fixed draws per candidate.
static func _plan_edges_cover(
	plan: Dictionary,
	surface: TerrainSurface,
	rng: RandomNumberGenerator,
	center: Vector3,
	look: CoverLook
) -> void:
	var cover_keep := float(GROUND_COVER_OPEN) / GROUND_COVER_FOREST
	for i in GROUND_COVER_FOREST + 3:
		var p := _hex_point_cover(rng, center)
		var s := GROUND_COVER_SCALE.x + rng.randf() * (GROUND_COVER_SCALE.y - GROUND_COVER_SCALE.x)
		var k := rng.randf()
		if p == Vector2.INF:
			continue
		var terrain := look.terrain_at(p.x, p.y)
		if terrain == Terrain.Type.WATER or (terrain != Terrain.Type.FOREST and k >= cover_keep):
			continue
		_append_scrub(plan["ground_cover"], surface, _at(p), 0.0, 0.0, s, k, UNDERGROWTH)
	for i in COVER_EDGE_DRAWS:
		var p := _hex_point_cover(rng, center)
		var s_roll := rng.randf()
		var k := rng.randf()
		var tree_roll := rng.randf()
		if p == Vector2.INF:
			continue
		var forest := look.is_forest(p.x, p.y)
		var r := COVER_EDGE_REACH
		if (
			look.is_forest(p.x + r, p.y) == forest
			and look.is_forest(p.x - r, p.y) == forest
			and look.is_forest(p.x, p.y + r) == forest
			and look.is_forest(p.x, p.y - r) == forest
		):
			continue
		if not forest and look.terrain_at(p.x, p.y) == Terrain.Type.WATER:
			continue
		if forest and tree_roll < COVER_EDGE_TREE_SHARE:
			var s := EDGE_TREE_SCALE.x + s_roll * (EDGE_TREE_SCALE.y - EDGE_TREE_SCALE.x)
			var y := surface.ground_height(p.x, p.y)
			if y < MIN_TREE_GROUND:
				continue
			var chance := CONIFER_CHANCE_HIGH if y > HIGH_GROUND else CONIFER_CHANCE_LOW
			(
				plan["young_trees"]
				. append(
					{
						"position": Vector3(p.x, y - TREE_SINK, p.y),
						"scale": s,
						"height_scale": s * (0.9 + k * 0.3),
						"yaw": k * 6.0,
						"conifer": tree_roll < COVER_EDGE_TREE_SHARE * chance,
						"k": k,
					}
				)
			)
			continue
		var scales := EDGE_FOREST_SHRUB_SCALE if forest else EDGE_OPEN_SHRUB_SCALE
		var s := scales.x + s_roll * (scales.y - scales.x)
		_append_scrub(plan["edge_shrubs"], surface, _at(p), 0.0, 0.0, s, k, SHRUB)


## A thorny thicket on the open ground of the tile (plan_tile_meadow's numbers and look), placed
## by the cover at the shrub: none on forest, water or villages.
static func _plan_meadow_cover(
	out: Array[Dictionary],
	surface: TerrainSurface,
	rng: RandomNumberGenerator,
	center: Vector3,
	meadow: Dictionary,
	look: CoverLook
) -> void:
	var chance := rng.randf()
	var angle := rng.randf() * TAU
	var u := rng.randf()
	var shrub_scale: Vector2 = meadow["scrub_shrub_scale"]
	var scale_k := rng.randf()
	var k := rng.randf()
	var companions: Array = []
	var offsets: Vector2 = meadow["scrub_companion_offset"]
	var scales: Vector2 = meadow["scrub_companion_scale"]
	for i in int(meadow["scrub_companions"]):
		var a := rng.randf() * TAU
		var o := offsets.x + rng.randf() * (offsets.y - offsets.x)
		var s := scales.x + rng.randf() * (scales.y - scales.x)
		companions.append([a, o, s, rng.randf()])
	if chance >= float(meadow["scrub_chance_plains"]):
		return
	var radius: Vector2 = meadow["scrub_radius"]
	var r := radius.x + sqrt(u) * (radius.y - radius.x)
	var shrub_at := Vector3(center.x + cos(angle) * r, 0.0, center.z + sin(angle) * r)
	var terrain := look.terrain_at(shrub_at.x, shrub_at.z)
	if terrain not in [Terrain.Type.PLAINS, Terrain.Type.FIELDS, Terrain.Type.MARSH]:
		return
	var s0 := shrub_scale.x + scale_k * (shrub_scale.y - shrub_scale.x)
	_append_scrub(out, surface, center, angle, r, s0, k, SHRUB)
	for companion: Array in companions:
		_append_scrub(
			out,
			surface,
			shrub_at,
			companion[0],
			companion[1],
			companion[2],
			companion[3],
			UNDERGROWTH
		)


static func _at(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


## Tree lines along the real parcels' hedges (TASK-215b, ParcelMap.hedge_lines): an item every
## RealParcelLook.hedge_step_m on the hedge balk (none where the land cover masks it), by hash of
## the line and step; appended to `trees` / `shrubs` in plan_hedges' format.
static func _plan_parcel_hedges(
	surface: TerrainSurface,
	parcels: ParcelMap,
	area: Rect2,
	within: Rect2,
	trees: Array[Dictionary],
	shrubs: Array[Dictionary]
) -> void:
	var lines := parcels.hedge_lines()
	if lines.is_empty():
		return
	var settings := RealParcelLook.load_default()
	var scale_m := MapScale.metres_per_unit
	var limited := within.has_area()
	var reach := area.grow(FieldParcels.BALK_M)
	for j in lines.size():
		var line := lines[j]
		for k in line.size() - 1:
			var a := line[k]
			var b := line[k + 1]
			if not reach.intersects(Rect2(a, Vector2.ZERO).expand(b)):
				continue
			var length := a.distance_to(b)
			var dir := (b - a) / maxf(length, 1e-6)
			var side := Vector2(-dir.y, dir.x)
			var steps := floori(length / settings.hedge_step_m)
			for i in steps:
				var h1 := FieldParcels.unit_hash(j, k, i, 21)
				var h2 := FieldParcels.unit_hash(j, k, i, 22)
				var h3 := FieldParcels.unit_hash(j, k, i, 23)
				if h3 < settings.hedge_gap_chance:
					continue
				var p := (
					a
					+ dir * (i + 0.3 + 0.4 * h1) * settings.hedge_step_m
					+ side * (h2 - 0.5) * 0.4 * FieldParcels.BALK_M
				)
				if not area.has_point(p):
					continue
				if parcels.kind_at_metres(p.x, p.y) != FieldParcels.Kind.BALK:
					continue
				var x := p.x / scale_m
				var z := p.y / scale_m
				if limited and not in_rect(Vector3(x, 0.0, z), within):
					continue
				var y := surface.ground_height(x, z)
				if y < MIN_TREE_GROUND:
					continue
				var h4 := FieldParcels.unit_hash(j, k, i, 24)
				var is_tree := h4 < settings.hedge_tree_chance
				var s := (0.55 + 0.4 * h1) if is_tree else (0.8 + 0.5 * h2)
				var item := {
					"position": Vector3(x, y - TREE_SINK, z),
					"scale": s,
					"height_scale": s * (0.9 + h2 * 0.3),
					"yaw": h1 * 6.0,
					"conifer": false,
					"k": h4,
				}
				if is_tree:
					trees.append(item)
				else:
					item["species"] = SHRUB
					shrubs.append(item)


## Hedgerow trees and shrubs on the balks of some farmland strips (TASK-108f), by position hash
## (no RNG stream): {"trees": [...], "edge_shrubs": [...]} in the formats of plan(), for the
## playable map only (the planned ring around it has no parcels of its own).
## `within` (world units, optional) keeps only the items in that rectangle (in_rect) and visits only
## the parcels that touch it: the chunked world's share of the eager result.
static func plan_hedges(
	grid: HexGrid, surface: TerrainSurface, parcels: ParcelMap, within := Rect2()
) -> Dictionary:
	var trees: Array[Dictionary] = []
	var shrubs: Array[Dictionary] = []
	if parcels == null:
		return {"trees": trees, "edge_shrubs": shrubs}
	var scale_m := MapScale.metres_per_unit
	var size_m := Vector2(parcels.size_px()) * parcels.metres_per_pixel
	var area := Rect2(parcels.origin_m, size_m)
	var limited := within.has_area()
	if limited:
		var within_m := Rect2(within.position * scale_m, within.size * scale_m)
		if not area.intersects(within_m):
			return {"trees": trees, "edge_shrubs": shrubs}
		area = area.intersection(within_m)
	var first := Vector2i((area.position / FieldParcels.BLOCK_M).floor())
	var last := Vector2i((area.end / FieldParcels.BLOCK_M).floor())
	for bx in range(first.x, last.x + 1):
		for bz in range(first.y, last.y + 1):
			for parcel: Dictionary in FieldParcels.parcels_of_block(bx, bz):
				var key: int = parcel["key"]
				var rect: Rect2 = parcel["rect"]
				if (
					not rect.intersects(area)
					or FieldParcels.unit_hash(key, 11, 0, 0) >= HEDGE_CHANCE
				):
					continue
				var along_x: bool = parcel["along_x"]
				var v0 := rect.position.x if along_x else rect.position.y
				var v1 := rect.end.x if along_x else rect.end.y
				var line := (
					(rect.position.y if along_x else rect.position.x) + 0.5 * FieldParcels.BALK_M
				)
				var steps := floori((v1 - v0) / HEDGE_STEP_M)
				for i in steps:
					var h1 := FieldParcels.unit_hash(key, 12, i, 1)
					var h2 := FieldParcels.unit_hash(key, 12, i, 2)
					var h3 := FieldParcels.unit_hash(key, 12, i, 3)
					var h4 := FieldParcels.unit_hash(key, 12, i, 4)
					if h3 < HEDGE_GAP_CHANCE:
						continue
					var along := v0 + (i + 0.3 + 0.4 * h1) * HEDGE_STEP_M
					var across := line + (h2 - 0.5) * 0.6 * FieldParcels.BALK_M
					var x_m := along if along_x else across
					var z_m := across if along_x else along
					if (
						parcels.kind_at_metres(x_m, z_m) != FieldParcels.Kind.BALK
						or parcels.is_real_at_metres(x_m, z_m)
					):
						# Only a strip's balk (a real parcel's hedge balk is TASK-199's).
						continue
					var x := x_m / scale_m
					var z := z_m / scale_m
					if limited and not in_rect(Vector3(x, 0.0, z), within):
						continue
					var y := surface.ground_height(x, z)
					if y < MIN_TREE_GROUND:
						continue
					var is_tree := h4 < HEDGE_TREE_CHANCE
					var s := (0.5 + 0.4 * h1) if is_tree else (0.8 + 0.5 * h2)
					var tree := {
						"position": Vector3(x, y - TREE_SINK, z),
						"scale": s,
						"height_scale": s * (0.9 + h2 * 0.3),
						"yaw": h1 * 6.0,
						"conifer": false,
						"k": h4,
					}
					if is_tree:
						trees.append(tree)
					else:
						tree["species"] = SHRUB
						shrubs.append(tree)
	_plan_parcel_hedges(surface, parcels, area, within, trees, shrubs)
	if grid.has_links():
		var kept_trees: Array[Dictionary] = []
		kept_trees.assign(FeatureRibbonPlanner.without_ribbons(grid, trees))
		var kept_shrubs: Array[Dictionary] = []
		kept_shrubs.assign(FeatureRibbonPlanner.without_ribbons(grid, shrubs))
		return {"trees": kept_trees, "edge_shrubs": kept_shrubs}
	return {"trees": trees, "edge_shrubs": shrubs}
