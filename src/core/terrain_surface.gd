class_name TerrainSurface
extends RefCounted
## Pure "height at any world point" query over a HexGrid (hex size TerrainField.HEX_SIZE).
## On generated maps it follows the continuous TerrainField, corrected near the centre of
## tiles whose elevation differs from the field (forced tiles), so the surface stays
## continuous across hex edges. Hand-made grids without a field are flat per tile.
## Water tiles dig their correction wider, past their edges (the lower surface wins), so
## adjacent forced water tiles join into one channel instead of separate pits.

## Height of the water plane; what units, overlays and picking sit on over water.
const WATER_SURFACE := 0.0
## Full correction within this distance of a tile centre...
const _CORRECTION_FULL := 0.35
## ...fading to none at this distance (below the hex inradius 0.866).
const _CORRECTION_NONE := 0.8
## Water tiles: full correction within this distance, none beyond this one (past the
## hex edge at 0.866, so the neighbouring tiles' sides of a shared edge dip as well).
const _WATER_CORRECTION_FULL := 0.5
const _WATER_CORRECTION_NONE := 1.4
## Raycast: marching starts where the ray is at this height (nothing on the map is higher)...
const _RAY_START_HEIGHT := 3.0
## ...in steps of this length, for at most this distance, then refines the hit by bisection.
const _RAY_STEP := 0.25
const _RAY_MAX_DISTANCE := 120.0
const _RAY_BISECTION_STEPS := 8

var _grid: HexGrid
## Vector2i -> float (field height at the tile centre). Not invalidated: assumes
## grid.field is not replaced after this surface is created.
var _center_heights: Dictionary = {}


func _init(grid: HexGrid) -> void:
	_grid = grid


func height_at(x: float, z: float) -> float:
	var c := Hex.from_world(Vector3(x, 0.0, z), TerrainField.HEX_SIZE)
	var on_map := _grid.has_tile(c)
	if _grid.field == null:
		return _grid.elevation(c) if on_map else 0.0
	var raw := _grid.field.height(x, z)
	if not on_map:
		return raw
	var h := raw
	if _grid.get_terrain(c) != Terrain.Type.WATER:
		h += _correction(c, x, z, _CORRECTION_NONE, _CORRECTION_FULL)
	for t: Vector2i in [c] + Hex.neighbors(c):
		if _grid.has_tile(t) and _grid.get_terrain(t) == Terrain.Type.WATER:
			var water := _correction(t, x, z, _WATER_CORRECTION_NONE, _WATER_CORRECTION_FULL)
			if water < 0.0:  # water only digs, it never undoes another tile's raise
				h = minf(h, raw + water)
	return h


## Height that units, overlays and picking sit on: never below the water surface.
func ground_height(x: float, z: float) -> float:
	return maxf(height_at(x, z), WATER_SURFACE)


## First point where the ray from `origin` along `direction` (need not be normalised)
## meets `ground_height`, or null if it points up/sideways or misses within the range.
## Port of the design's pickGround (docs/design/game_screen.scene.js).
func raycast(origin: Vector3, direction: Vector3) -> Variant:
	if direction.y >= 0.0:
		return null
	var d := direction.normalized()
	var t0 := maxf(0.0, (origin.y - _RAY_START_HEIGHT) / -d.y)
	var prev := t0
	var t := t0
	while t < t0 + _RAY_MAX_DISTANCE:
		if _is_below_ground(origin + d * t):
			var a := prev
			var b := t
			for i in _RAY_BISECTION_STEPS:
				var m := (a + b) * 0.5
				if _is_below_ground(origin + d * m):
					b = m
				else:
					a = m
			return origin + d * b
		prev = t
		t += _RAY_STEP
	return null


func _is_below_ground(p: Vector3) -> bool:
	return p.y <= ground_height(p.x, p.z)


## Tile c's correction at (x, z): the gap between its elevation and the field at its centre,
## fading from full within `full` of the centre to none at `none`.
func _correction(c: Vector2i, x: float, z: float, none: float, full: float) -> float:
	var center := Hex.to_world(c, TerrainField.HEX_SIZE)
	var w := TerrainNoise.smooth(none, full, Vector2(x - center.x, z - center.z).length())
	if w == 0.0:
		return 0.0
	return w * (_grid.elevation(c) - _center_height(c, center))


func _center_height(c: Vector2i, center: Vector3) -> float:
	if not _center_heights.has(c):
		_center_heights[c] = _grid.field.height(center.x, center.z)
	return _center_heights[c]
