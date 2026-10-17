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


## Returns {"trees": Array[Dictionary], "rocks": Array[Dictionary]}.
## Tree: {position, scale, height_scale, yaw, conifer, k}. Rock: {position, scale, rotation}.
static func plan(grid: HexGrid, surface: TerrainSurface, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var trees: Array[Dictionary] = []
	var rocks: Array[Dictionary] = []
	for c in grid.coords():
		var center := Hex.to_world(c, TerrainField.HEX_SIZE)
		match grid.get_terrain(c):
			Terrain.Type.FOREST:
				_plan_trees(trees, surface, rng, center, FOREST_TREES)
			Terrain.Type.PLAINS:
				var n := PLAINS_TREES if rng.randf() < PLAINS_TREE_CHANCE else 0
				_plan_trees(trees, surface, rng, center, n)
			Terrain.Type.HILLS:
				var n := ROCKS_MOUNTAIN if grid.elevation(c) > MOUNTAIN_ELEVATION else ROCKS_HILLS
				_plan_rocks(rocks, surface, rng, center, n)
	return {"trees": trees, "rocks": rocks}


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
