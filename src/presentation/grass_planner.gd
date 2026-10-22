class_name GrassPlanner
extends RefCounted
## Pure placement planner for grass clumps (TASK-057). The map is split into square chunks of
## CHUNK_SIZE world units; plan_chunk() returns the clumps of one chunk. Like ScatterPlanner it
## uses its own hash-seeded RandomNumberGenerator, never GameState.rng, so the same map and seed
## always give the same grass and the simulation stays deterministic.

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


## Clumps of one chunk: [{position: Vector3, yaw, scale, tint}]. `density` (graphics quality)
## scales the count. Every candidate draws the same numbers, so rejected ones never shift the
## stream and changing the terrain elsewhere does not move the grass of this chunk.
static func plan_chunk(
	chunk: Vector2i, grid: HexGrid, surface: TerrainSurface, seed_value: int, density: float
) -> Array:
	var result: Array = []
	if density <= 0.0:
		return result
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
		var share := 0.0
		match grid.get_terrain(coord):
			Terrain.Type.PLAINS:
				share = PLAINS_DENSITY
			Terrain.Type.HILLS:
				share = HILLS_DENSITY
			Terrain.Type.FOREST:
				share = FOREST_DENSITY
		if accept >= share / PLAINS_DENSITY:
			continue
		var y := surface.ground_height(x, z)
		if y <= TerrainSurface.WATER_SURFACE + SHORE_BAND:
			continue
		if grid.get_terrain(coord) == Terrain.Type.HILLS and slope(surface, x, z) > MAX_SLOPE:
			continue
		var clump := {
			"position": Vector3(x, y, z),
			"yaw": yaw,
			"scale": SCALE_MIN + scale_k * SCALE_RANGE,
			"tint": tint,
		}
		result.append(clump)
	return result
