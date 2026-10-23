class_name GrassPlanner
extends RefCounted
## Pure placement planner for grass clumps (TASK-057). The map is split into square chunks of
## CHUNK_SIZE world units; plan_chunk() returns the clumps of one chunk. Like ScatterPlanner it
## uses its own hash-seeded RandomNumberGenerator, never GameState.rng, so the same map and seed
## always give the same grass and the simulation stays deterministic.

## Grass clump kinds (TASK-070): short lawn, tall unmown grass, dry straw stalks, nettle tufts.
enum Kind { SHORT, TALL, DRY_STALK, NETTLE }

const CHUNK_SIZE := 4.0
## Clumps per world unit² at density 1.0.
const PLAINS_DENSITY := 90.0
const HILLS_DENSITY := 50.0
const FOREST_DENSITY := 25.0
## Hills steeper than this (height change per world unit) stay bare.
const MAX_SLOPE := 0.5
## Ground at most this far above the water level is shore: no grass.
const SHORE_BAND := 0.06
const SCALE_MIN := 0.7
const SCALE_RANGE := 0.6
## Total clump budget on the default map at density 1.0 (HIGH).
const INSTANCE_BUDGET := 120000
const _SLOPE_STEP := 0.1
## Own RNG stream of the flowers (TASK-070), so the grass stream is untouched.
const FLOWER_SEED_SALT := 0xF10E
## Flower candidates per chunk at flower_density 1 and density 1 (CHUNK_SIZE²).
const FLOWER_CANDIDATES_PER_DENSITY := 16


## The world rectangle (x, z) of a chunk.
static func chunk_rect(chunk: Vector2i) -> Rect2:
	return Rect2(Vector2(chunk) * CHUNK_SIZE, Vector2(CHUNK_SIZE, CHUNK_SIZE))


## Every chunk that overlaps `rect`.
static func chunks_covering(rect: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var first := Vector2i((rect.position / CHUNK_SIZE).floor())
	var last := Vector2i((rect.end / CHUNK_SIZE).ceil()) - Vector2i.ONE
	for x in range(first.x, last.x + 1):
		for z in range(first.y, last.y + 1):
			result.append(Vector2i(x, z))
	return result


## Steepness at (x, z): the length of the ground height gradient (rise per world unit).
static func slope(surface: TerrainSurface, x: float, z: float) -> float:
	var s := _SLOPE_STEP
	var dx := surface.ground_height(x + s, z) - surface.ground_height(x - s, z)
	var dz := surface.ground_height(x, z + s) - surface.ground_height(x, z - s)
	return Vector2(dx, dz).length() / (2.0 * s)


## Clumps of one chunk: [{position: Vector3, yaw, scale, tint, kind: Kind, height}]. `density`
## (graphics quality) scales the count. Every candidate draws the same numbers, so rejected ones
## never shift the stream and changing the terrain elsewhere does not move the grass of this
## chunk. `meadow` is LookPreset.meadow() (empty = the active one); the kind and the bare-patch
## thinning use deterministic noises and position hashes, never extra stream draws.
static func plan_chunk(
	chunk: Vector2i,
	grid: HexGrid,
	surface: TerrainSurface,
	seed_value: int,
	density: float,
	meadow: Dictionary = {}
) -> Array:
	var result: Array = []
	if density <= 0.0:
		return result
	if meadow.is_empty():
		meadow = LookPreset.meadow()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, chunk.x, chunk.y])
	var origin := Vector2(chunk) * CHUNK_SIZE
	var candidates := roundi(CHUNK_SIZE * CHUNK_SIZE * PLAINS_DENSITY * density)
	for i in candidates:
		var x := origin.x + rng.randf() * CHUNK_SIZE
		var z := origin.y + rng.randf() * CHUNK_SIZE
		var yaw := rng.randf() * TAU
		var scale_k := rng.randf()
		var tint := rng.randf()
		var accept := rng.randf()
		var coord := Hex.from_world(Vector3(x, 0.0, z), TerrainField.HEX_SIZE)
		if not grid.has_tile(coord):
			continue
		var terrain := grid.get_terrain(coord)
		var share := 0.0
		match terrain:
			Terrain.Type.PLAINS:
				share = PLAINS_DENSITY
			Terrain.Type.HILLS:
				share = HILLS_DENSITY
			Terrain.Type.FOREST:
				share = FOREST_DENSITY
		var keep := share / PLAINS_DENSITY
		if terrain != Terrain.Type.FOREST and meadow["bare_thinning"] > 0.0:
			keep *= 1.0 - float(meadow["bare_thinning"]) * bare_k(x, z)
		if accept >= keep:
			continue
		var y := surface.ground_height(x, z)
		if y <= TerrainSurface.WATER_SURFACE + SHORE_BAND:
			continue
		if terrain == Terrain.Type.HILLS and slope(surface, x, z) > MAX_SLOPE:
			continue
		var kind := _kind_at(x, z, coord, terrain, grid, meadow)
		var clump := {
			"position": Vector3(x, y, z),
			"yaw": yaw,
			"scale": SCALE_MIN + scale_k * SCALE_RANGE,
			"tint": tint,
			"kind": kind,
			"height": kind_height(kind, meadow),
		}
		result.append(clump)
	return result


## Share [0, 1] of the bare dirt patches of the ground texture at (x, z).
static func bare_k(x: float, z: float) -> float:
	return TerrainNoise.smooth(
		TerrainSplat.DIRT_PATCH_FROM, TerrainSplat.DIRT_PATCH_TO, GroundNoise.moisture_k(x, z)
	)


## Deterministic hash of a 2D position in [0, 1) (the sin-hash of TreeSpecies on x, z).
static func hash01(x: float, z: float, salt: int) -> float:
	var s := sin(x * 127.1 + z * 311.7 + salt * 183.31 + salt * salt * 0.37) * 43758.5453
	return s - floor(s)


## Distance from (x, z) to the nearest centre of a forest neighbour of the hex containing the
## point; INF if the hex has none (or is itself forest or water, or off the map).
static func forest_edge_distance(x: float, z: float, grid: HexGrid) -> float:
	var coord := Hex.from_world(Vector3(x, 0.0, z), TerrainField.HEX_SIZE)
	if not grid.has_tile(coord):
		return INF
	var terrain := grid.get_terrain(coord)
	if terrain == Terrain.Type.FOREST or terrain == Terrain.Type.WATER:
		return INF
	var best := INF
	for dir in Hex.DIRECTIONS:
		var n := coord + dir
		if grid.has_tile(n) and grid.get_terrain(n) == Terrain.Type.FOREST:
			var w := Hex.to_world(n, TerrainField.HEX_SIZE)
			best = minf(best, Vector2(x - w.x, z - w.z).length())
	return best


## Tall-grass share [0, 1] of a tile position from the patch noise.
static func tall_k(terrain: Terrain.Type, patch: float, in_edge: bool, meadow: Dictionary) -> float:
	var k := TerrainNoise.smooth(meadow["tall_from"], meadow["tall_to"], patch)
	if terrain == Terrain.Type.HILLS:
		k *= meadow["hills_tall_factor"]
	if in_edge:
		k += meadow["edge_tall_bonus"]
	return clampf(k, 0.0, 1.0)


## The kind of a clump from precomputed noise values (pure). Order: forest tile or too close to
## the tile centre -> SHORT; dry stalks (h1 low end); nettle in the edge band (h1 high end);
## tall grass (h2 < tall_k); otherwise SHORT.
static func pick_kind(
	terrain: Terrain.Type,
	centre_distance: float,
	dry_k: float,
	tall_k_value: float,
	in_edge: bool,
	h1: float,
	h2: float,
	meadow: Dictionary
) -> int:
	if terrain == Terrain.Type.FOREST or centre_distance < meadow["centre_clear"]:
		return Kind.SHORT
	if h1 < dry_k * float(meadow["dry_stalk_share"]):
		return Kind.DRY_STALK
	if in_edge and h1 >= 1.0 - float(meadow["nettle_share"]):
		return Kind.NETTLE
	if h2 < tall_k_value:
		return Kind.TALL
	return Kind.SHORT


## Vertical multiplier of a clump kind.
static func kind_height(kind: int, meadow: Dictionary) -> float:
	match kind:
		Kind.TALL:
			return meadow["tall_height"]
		Kind.DRY_STALK:
			return meadow["dry_stalk_height"]
		Kind.NETTLE:
			return meadow["nettle_height"]
	return 1.0


## Instance colour (linear) of a clump: the ground colour with the per-clump tint, replaced
## towards the kind's colour by its mix.
static func kind_color(kind: int, ground: Color, tint: float, meadow: Dictionary) -> Color:
	var k := lerpf(0.85, 1.1, tint)
	var base := Color(ground.r * k, ground.g * k, ground.b * k)
	var key := ""
	match kind:
		Kind.TALL:
			key = "tall"
		Kind.DRY_STALK:
			key = "dry_stalk"
		Kind.NETTLE:
			key = "nettle"
		_:
			return base
	var target: Color = (meadow[key + "_color"] as Color).srgb_to_linear()
	return base.lerp(target, meadow[key + "_mix"])


## Flowers of one chunk: [{position, yaw, scale, height, color (sRGB), species}], in clusters of
## mostly one species on open ground. Own RNG stream with seven draws per candidate, always.
static func plan_flowers(
	chunk: Vector2i,
	grid: HexGrid,
	surface: TerrainSurface,
	seed_value: int,
	density: float,
	meadow: Dictionary = {}
) -> Array:
	var result: Array = []
	if meadow.is_empty():
		meadow = LookPreset.meadow()
	var groups: Array = meadow["flowers"]
	var flower_density: float = meadow["flower_density"]
	if density <= 0.0 or flower_density <= 0.0 or groups.is_empty():
		return result
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value ^ FLOWER_SEED_SALT, chunk.x, chunk.y])
	var origin := Vector2(chunk) * CHUNK_SIZE
	var candidates := roundi(FLOWER_CANDIDATES_PER_DENSITY * flower_density * density)
	var heights: Vector2 = meadow["flower_height"]
	var cell_size: float = meadow["flower_cell"]
	var dominance: float = meadow["flower_dominance"]
	for i in candidates:
		var x := origin.x + rng.randf() * CHUNK_SIZE
		var z := origin.y + rng.randf() * CHUNK_SIZE
		var yaw := rng.randf() * TAU
		var scale_k := rng.randf()
		var height_k := rng.randf()
		var roll := rng.randf()
		var accept := rng.randf()
		var coord := Hex.from_world(Vector3(x, 0.0, z), TerrainField.HEX_SIZE)
		if not grid.has_tile(coord):
			continue
		var terrain := grid.get_terrain(coord)
		var threshold_factor := 1.0
		if terrain == Terrain.Type.HILLS:
			threshold_factor = 0.5
		elif terrain != Terrain.Type.PLAINS:
			continue
		var centre := Hex.to_world(coord, TerrainField.HEX_SIZE)
		if Vector2(x - centre.x, z - centre.z).length() < float(meadow["centre_clear"]):
			continue
		var cluster_k := TerrainNoise.smooth(
			meadow["flower_from"], meadow["flower_to"], GroundNoise.flower_k(x, z, meadow)
		)
		if accept >= cluster_k * threshold_factor or bare_k(x, z) >= 0.5:
			continue
		var y := surface.ground_height(x, z)
		if y <= TerrainSurface.WATER_SURFACE + SHORE_BAND:
			continue
		if terrain == Terrain.Type.HILLS and slope(surface, x, z) > MAX_SLOPE:
			continue
		var cell := Vector2(floorf(x / cell_size) + 0.5, floorf(z / cell_size) + 0.5) * cell_size
		var group_index := _pick_group(groups, hash01(cell.x, cell.y, 3))
		if roll >= dominance:
			group_index = _pick_group(groups, (roll - dominance) / (1.0 - dominance))
		var group: Dictionary = groups[group_index]
		(
			result
			. append(
				{
					"position": Vector3(x, y, z),
					"yaw": yaw,
					"scale": SCALE_MIN + scale_k * SCALE_RANGE,
					"height": lerpf(heights.x, heights.y, height_k),
					"color": group["color"],
					"species": group["name"],
				}
			)
		)
	return result


## Index of the species group whose cumulative share contains `roll` in [0, 1).
static func _pick_group(groups: Array, roll: float) -> int:
	var acc := 0.0
	for i in groups.size():
		acc += (groups[i] as Dictionary)["share"]
		if roll < acc:
			return i
	return groups.size() - 1


static func _kind_at(
	x: float, z: float, coord: Vector2i, terrain: Terrain.Type, grid: HexGrid, meadow: Dictionary
) -> int:
	if terrain == Terrain.Type.FOREST:
		return Kind.SHORT
	var centre := Hex.to_world(coord, TerrainField.HEX_SIZE)
	var centre_distance := Vector2(x - centre.x, z - centre.z).length()
	if centre_distance < float(meadow["centre_clear"]):
		return Kind.SHORT
	var dry_k := TerrainNoise.smooth(
		TerrainSplat.DRY_FROM, TerrainSplat.DRY_TO, GroundNoise.macro_k(x, z)
	)
	var in_edge := forest_edge_distance(x, z, grid) <= float(meadow["edge_band"])
	var tall := tall_k(terrain, GroundNoise.patch_k(x, z, meadow), in_edge, meadow)
	var h1 := hash01(x, z, 1)
	var h2 := hash01(x, z, 2)
	return pick_kind(terrain, centre_distance, dry_k, tall, in_edge, h1, h2, meadow)
