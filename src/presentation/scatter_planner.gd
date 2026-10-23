class_name ScatterPlanner
extends RefCounted
## Pure placement planner for cosmetic scatter: trees on forest/plains tiles, rocks on hills
## (TASK-018). Uses its own RandomNumberGenerator – never GameState.rng – so the same map and
## seed always give the same scatter and the simulation stays deterministic.

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
const SHRUB := &"shrub"
const UNDERGROWTH := &"undergrowth"


## Returns {"trees", "rocks", "bushes", "edge_shrubs", "young_trees", "ground_cover",
## "meadow_scrub"} (Array[Dictionary] each). Young trees, edge shrubs, ground cover and meadow
## scrub are tree dictionaries (as trees, plus "species": TreeMeshes shrub / undergrowth for the
## last three) drawn by the TreeField. Meadow scrub follows LookPreset.meadow().
## Tree: {position, scale, height_scale, yaw, conifer, k}. Rock: {position, scale, rotation}.
## Bush: {position, scale, height_scale, yaw, k}.
static func plan(grid: HexGrid, surface: TerrainSurface, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var trees: Array[Dictionary] = []
	var rocks: Array[Dictionary] = []
	var bushes: Array[Dictionary] = []
	var bush_rng := RandomNumberGenerator.new()
	bush_rng.seed = seed_value ^ BUSH_SEED_SALT
	var edge_rng := RandomNumberGenerator.new()
	edge_rng.seed = seed_value ^ EDGE_SEED_SALT
	var edge_shrubs: Array[Dictionary] = []
	var young_trees: Array[Dictionary] = []
	var ground_cover: Array[Dictionary] = []
	var meadow_scrub: Array[Dictionary] = []
	var meadow_rng := RandomNumberGenerator.new()
	meadow_rng.seed = seed_value ^ MEADOW_SEED_SALT
	var meadow := LookPreset.meadow()
	for c in grid.coords():
		var center := Hex.to_world(c, TerrainField.HEX_SIZE)
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
	return {
		"trees": trees,
		"rocks": rocks,
		"bushes": bushes,
		"edge_shrubs": edge_shrubs,
		"young_trees": young_trees,
		"ground_cover": ground_cover,
		"meadow_scrub": meadow_scrub,
	}


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
	if terrain == Terrain.Type.PLAINS:
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
