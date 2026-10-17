class_name TerrainSurface
extends RefCounted
## Pure "height at any world point" query over a HexGrid (hex size TerrainField.HEX_SIZE).
## On generated maps it follows the continuous TerrainField, corrected near the centre of
## tiles whose elevation differs from the field (forced tiles), so the surface stays
## continuous across hex edges. Hand-made grids without a field are flat per tile.

## Height of the water plane; what units, overlays and picking sit on over water.
const WATER_SURFACE := 0.0
## Full correction within this distance of a tile centre...
const _CORRECTION_FULL := 0.35
## ...fading to none at this distance (below the hex inradius 0.866).
const _CORRECTION_NONE := 0.8

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
	var center := Hex.to_world(c, TerrainField.HEX_SIZE)
	var distance := Vector2(x - center.x, z - center.z).length()
	var w := TerrainNoise.smooth(_CORRECTION_NONE, _CORRECTION_FULL, distance)
	if w == 0.0:
		return raw
	return raw + w * (_grid.elevation(c) - _center_height(c, center))


## Height that units, overlays and picking sit on: never below the water surface.
func ground_height(x: float, z: float) -> float:
	return maxf(height_at(x, z), WATER_SURFACE)


func _center_height(c: Vector2i, center: Vector3) -> float:
	if not _center_heights.has(c):
		_center_heights[c] = _grid.field.height(center.x, center.z)
	return _center_heights[c]
