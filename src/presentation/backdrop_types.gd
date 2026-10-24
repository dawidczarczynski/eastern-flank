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


## `mesh_origin` and `mesh_step` describe the playable terrain mesh grid (MapView).
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


## Terrain type of the map tile nearest to world point `p` (cached per hex it falls in).
func nearest_tile_type(p: Vector2) -> int:
	var key := Hex.from_world(Vector3(p.x, 0.0, p.y), _hex_size)
	if not _nearest_cache.has(key):
		var best := -1
		var best_distance := INF
		for c in _grid.coords():
			var w := Hex.to_world(c, _hex_size)
			var dist := Vector2(w.x, w.z).distance_squared_to(p)
			if dist < best_distance:
				best_distance = dist
				best = int(_grid.get_terrain(c))
		_nearest_cache[key] = best
	return _nearest_cache[key]
