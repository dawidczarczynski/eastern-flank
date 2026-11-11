class_name LineOfSight
extends RefCounted
## Line of sight of direct fire (TASK-131a, GDD "Combat"). Pure and static.
## The line is Hex.line between the two hexes, always traced from the endpoint with the lower
## (y, x) so that visible(a, b) == visible(b, a); the endpoints themselves never block. The
## sight height at a middle hex is the linear interpolation between ground(from) + EYE_HEIGHT_M
## and ground(to) + EYE_HEIGHT_M; the hex blocks when ground + obstacle is above it. Ground =
## the real height in metres (imported maps, HexGrid.elevation_m) or elevation x
## ELEVATION_METRES; obstacle = the terrain's los_obstacle_m (forest, urban). Units never block
## [ASSUMPTION]. Hexes off the map don't block.

## Eye (and sight) height above the ground in metres [ASSUMPTION].
const EYE_HEIGHT_M := 2.0
## Metres per unit of HexGrid.elevation on maps without real heights.
const ELEVATION_METRES := 1000.0


## True when nothing between `from` and `to` blocks the sight line. Adjacent hexes always see
## each other.
static func visible(grid: HexGrid, from: Vector2i, to: Vector2i) -> bool:
	if Hex.distance(from, to) <= 1:
		return true
	var a := from
	var b := to
	if b.y < a.y or (b.y == a.y and b.x < a.x):
		a = to
		b = from
	var line := Hex.line(a, b)
	var start := ground_m(grid, a) + EYE_HEIGHT_M
	var end := ground_m(grid, b) + EYE_HEIGHT_M
	var steps := line.size() - 1
	for i in range(1, steps):
		var c := line[i]
		if not grid.has_tile(c):
			continue
		var sight := lerpf(start, end, float(i) / steps)
		if ground_m(grid, c) + obstacle_m(grid, c) > sight:
			return false
	return true


## The tile's ground height in metres (see the class comment).
static func ground_m(grid: HexGrid, c: Vector2i) -> float:
	if grid.has_elevation_m(c):
		return grid.elevation_m(c)
	return grid.elevation(c) * ELEVATION_METRES


## Height of the tile's trees or buildings in metres (TerrainDefinition.los_obstacle_m).
static func obstacle_m(grid: HexGrid, c: Vector2i) -> float:
	return Terrain.definition(grid.get_terrain(c)).los_obstacle_m
