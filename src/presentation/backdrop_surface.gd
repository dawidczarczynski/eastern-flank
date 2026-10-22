class_name BackdropSurface
extends TerrainSurface
## TerrainSurface whose heights come from a callable (the drawn backdrop ground), so that
## ScatterPlanner can place scenery on the non-playable ring (TASK-052).

var _height_fn: Callable


func _init(grid: HexGrid, height_fn: Callable) -> void:
	super(grid)
	_height_fn = height_fn


func height_at(x: float, z: float) -> float:
	return _height_fn.call(x, z)


func ground_height(x: float, z: float) -> float:
	return maxf(_height_fn.call(x, z), TerrainSurface.WATER_SURFACE)
