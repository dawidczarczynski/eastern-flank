class_name BackdropTypes
extends RefCounted
## Which map terrain the backdrop ring around the playable mesh copies (TASK-052): the type of
## the map tile nearest to a point, and the type shares along the border of the playable mesh
## that the backdrop ground and canopy blend. Both are cached: every ring vertex beyond a border
## vertex asks for the same shares (TASK-083).
## With a land-cover raster (TASK-108g, `look`) the backdrop instead continues the real land cover
## beyond the cut wherever the raster reaches (`shares_at`, `forest_at`, `ring_type`); beyond it,
## and on maps without a raster, it copies the border tiles as before.

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
var _look: CoverLook
var _cover_rect := Rect2()


## `mesh_origin` and `mesh_step` describe the playable terrain mesh grid (MapView's TerrainLattice).
func _init(
	grid: HexGrid, hex_size: float, mesh_origin: Vector2, mesh_step: Vector2, look: CoverLook = null
) -> void:
	_grid = grid
	_look = look
	if look != null:
		_cover_rect = look.world_rect()
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


## The terrain look shares of the backdrop vertex at world (x, z) beyond border vertex (ca, cb):
## the land cover there ({type: 1.0}) inside the raster, else border_shares(ca, cb).
func shares_at(x: float, z: float, ca: int, cb: int) -> Dictionary:
	if _look != null and _cover_rect.has_point(Vector2(x, z)):
		return {_look.terrain_at(x, z): 1.0}
	return border_shares(ca, cb)


## Forest share (0..1) of the backdrop canopy at world (x, z) beyond border vertex (ca, cb): the
## soft forest of the land cover inside the raster, else the forest share of border_shares.
func forest_at(x: float, z: float, ca: int, cb: int) -> float:
	if _look != null and _cover_rect.has_point(Vector2(x, z)):
		return _look.forest_k(x, z)
	return border_shares(ca, cb).get(Terrain.Type.FOREST, 0.0)


## Terrain type of a virtual backdrop tile at `p` whose nearest playable border point is `border`:
## the land cover at `p` inside the raster, else nearest_tile_type(border).
func ring_type(p: Vector2, border: Vector2) -> int:
	if _look != null and _cover_rect.has_point(p):
		return _look.terrain_at(p.x, p.y)
	return nearest_tile_type(border)


## MapView's backdrop vertex callback (BackdropMesh.build_mesh): TerrainSplat weights followed by
## the value and saturation factors. At the seam it equals the playable margin (off-map plains,
## MapView.OFF_MAP_VALUE); over MapView.BACKDROP_FADE units it blends into the terrain of
## shares_at with the muted backdrop look, so the playable edge reads without a hard line.
func backdrop_vertex(
	x: float, z: float, h: float, normal_y: float, distance: float, ca: int, cb: int
) -> PackedFloat32Array:
	var v := Vector3(x, h, z)
	var t := TerrainNoise.smooth(0.0, MapView.BACKDROP_FADE, distance)
	var shares := shares_at(x, z, ca, cb)
	# The noises and the splats a vertex does not show are skipped (TASK-072b: tens of thousands
	# of ring vertices on a large map); the weights are the same.
	var noisy := t < 1.0
	for type: int in shares:
		noisy = noisy or TerrainSplat.uses_noise(type)
	var noise := MapView._splat_noise(x, z) if noisy else Vector2.ZERO
	var seam := MapView._splat(-1, normal_y, v, noise) if t < 1.0 else PackedFloat32Array()
	var land := PackedFloat32Array()
	land.resize(TerrainSplat.LAYER_COUNT)
	if t > 0.0:
		for type: int in shares:
			var share: float = shares[type]
			var w := MapView._splat(type, normal_y, v, noise)
			for layer in TerrainSplat.LAYER_COUNT:
				land[layer] += w[layer] * share
	if t >= 1.0:
		seam = land
	elif t <= 0.0:
		land = seam
	var result := PackedFloat32Array()
	for layer in TerrainSplat.LAYER_COUNT:
		result.append(lerpf(seam[layer], land[layer], t))
	result.append(lerpf(MapView.OFF_MAP_VALUE, MapView.BACKDROP_VALUE, t))
	result.append(lerpf(1.0, MapView.BACKDROP_SATURATION, t))
	return result


## BackdropMesh vertex callback of the canopy: forest cover in the first value (the rest is
## unused padding of the shared vertex layout).
func canopy_vertex(
	x: float, z: float, _h: float, _normal_y: float, distance: float, ca: int, cb: int
) -> PackedFloat32Array:
	var cover := forest_at(x, z, ca, cb)
	cover *= TerrainNoise.smooth(BackdropCanopy.FADE_FROM, BackdropCanopy.FADE_TO, distance)
	var result := PackedFloat32Array()
	result.resize(TerrainSplat.LAYER_COUNT + 2)
	result[0] = cover
	return result


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
