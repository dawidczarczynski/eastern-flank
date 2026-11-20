class_name BackdropTypes
extends RefCounted
## Which map terrain the backdrop ring around the playable mesh copies (TASK-052): the type of
## the map tile nearest to a point, and the type shares along the border of the playable mesh
## that the backdrop ground and canopy blend. Both are cached: every ring vertex beyond a border
## vertex asks for the same shares (TASK-083).

## Border points (offsets in hex sizes) whose tile types the backdrop averages.
const SAMPLES: Array[Vector2] = [
	Vector2.ZERO, Vector2(1.5, 0.0), Vector2(-1.5, 0.0), Vector2(0.0, 1.5), Vector2(0.0, -1.5)
]

var _grid: HexGrid
var _hex_size := 1.0
var _mesh_origin := Vector2.ZERO
var _mesh_step := Vector2.ONE
var _nearest_cache: Dictionary = {}
var _shares_cache: Dictionary = {}


## `mesh_origin` and `mesh_step` describe the playable terrain mesh grid (MapView's TerrainLattice).
func _init(grid: HexGrid, hex_size: float, mesh_origin: Vector2, mesh_step: Vector2) -> void:
	_grid = grid
	_hex_size = hex_size
	_mesh_origin = mesh_origin
	_mesh_step = mesh_step


## Share of each terrain type among the map tiles nearest to the SAMPLES around the border
## vertex (ca, cb) of the backdrop's inner lattice (every second playable mesh vertex):
## {type: share}. Averaged along the border because a single nearest tile would extend every
## border tile outwards as a stripe.
func border_shares(ca: int, cb: int) -> Dictionary:
	var key := Vector2i(ca, cb)
	if not _shares_cache.has(key):
		var border := Vector2(
			_mesh_origin.x + 2 * ca * _mesh_step.x, _mesh_origin.y + 2 * cb * _mesh_step.y
		)
		var counts := {}
		for offset: Vector2 in SAMPLES:
			var type := nearest_tile_type(border + offset * _hex_size)
			counts[type] = counts.get(type, 0) + 1
		for type: int in counts:
			counts[type] = counts[type] / float(SAMPLES.size())
		_shares_cache[key] = counts
	return _shares_cache[key]


## Terrain type of the map tile nearest to world point `p` (cached per hex it falls in). Searches
## hex rings around the point (TASK-072b: scanning every tile per hex cost seconds on large maps)
## until no farther ring can hold a closer centre (ring k is at least 1.5 k hex sizes from the
## start hex's centre, and `p` lies within one hex size of it).
## Ties go to the lowest (q, r), so the result does not depend on the grid's insertion order.
func nearest_tile_type(p: Vector2) -> int:
	var key := Hex.from_world(Vector3(p.x, 0.0, p.y), _hex_size)
	if not _nearest_cache.has(key):
		_nearest_cache[key] = _nearest_type(key, p)
	return _nearest_cache[key]


func _nearest_type(start: Vector2i, p: Vector2) -> int:
	if _grid.coords().is_empty():
		return -1
	var best := Vector2i.ZERO
	var best_distance := INF
	var radius := 0
	while best_distance == INF or (1.5 * radius - 1.0) * _hex_size <= sqrt(best_distance):
		for c in _ring(start, radius):
			if not _grid.has_tile(c):
				continue
			var w := Hex.to_world(c, _hex_size)
			var dist := Vector2(w.x, w.z).distance_squared_to(p)
			if (
				dist < best_distance
				or (dist == best_distance and (c.x < best.x or (c.x == best.x and c.y < best.y)))
			):
				best_distance = dist
				best = c
		radius += 1
	return int(_grid.get_terrain(best))


## The hexes at hex distance `radius` from `center`.
static func _ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	if radius == 0:
		return [center]
	var result: Array[Vector2i] = []
	var c := center + Hex.DIRECTIONS[4] * radius
	for side in 6:
		for step in radius:
			result.append(c)
			c += Hex.DIRECTIONS[side]
	return result
