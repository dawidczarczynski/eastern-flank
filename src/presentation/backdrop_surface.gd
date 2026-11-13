class_name BackdropSurface
extends TerrainSurface
## TerrainSurface whose heights come from a callable (the drawn ground), so that ScatterPlanner
## can place scenery on the non-playable ring (TASK-052) and the grass stands on the terrain
## mesh (MapView.mesh_height_at) without evaluating the surface per clump.

var _height_fn: Callable


func _init(grid: HexGrid, height_fn: Callable) -> void:
	super(grid)
	_height_fn = height_fn


func height_at(x: float, z: float) -> float:
	return _height_fn.call(x, z)


func ground_height(x: float, z: float) -> float:
	return maxf(_height_fn.call(x, z), TerrainSurface.WATER_SURFACE)
