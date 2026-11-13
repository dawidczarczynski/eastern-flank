class_name TerrainRows
extends RefCounted
## The per-vertex work of MapView's terrain mesh, one row of the height lattice per task on the
## WorkerThreadPool: heights and vertices (TerrainSurface, 22 noise octaves per query on a
## generated map), then normals, tangents, UVs, TerrainSplat weights and tints. The rows only
## read shared state (grid, surface, the finished vertices) and each writes its own slot, so the
## result is the same on any number of threads (`threads` off: the caller's thread).
## Usage: var rows := TerrainRows.new(grid, surface, origin, step, cells, hex_size)
##   rows.build_heights()     -> rows.heights, rows.vertices (the caller may adjust the vertices)
##   rows.build_attributes()  -> rows.normals, tangents, uvs, weights, tints

var threads := true
## Row-major over (cells.x + 1) x (cells.y + 1) lattice points.
var heights := PackedFloat32Array()
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
## 4 floats per vertex (x, y, z, w).
var tangents := PackedFloat32Array()
var uvs := PackedVector2Array()
## TerrainSplat.LAYER_COUNT floats per vertex (not smoothed).
var weights := PackedFloat32Array()
var tints := PackedVector2Array()

var _grid: HexGrid
var _surface: TerrainSurface
var _origin: Vector2
var _step: Vector2
var _cells: Vector2i
var _hex_size: float
var _row_slots: Array = []


func _init(
	grid: HexGrid,
	surface: TerrainSurface,
	origin: Vector2,
	step: Vector2,
	cells: Vector2i,
	hex_size: float
) -> void:
	_grid = grid
	_surface = surface
	_origin = origin
	_step = step
	_cells = cells
	_hex_size = hex_size


func build_heights() -> void:
	# The rows only read the surface: fill its lazy cache before the threads start.
	_surface.prime()
	_run_rows(_height_row, _cells.y + 1)
	heights = PackedFloat32Array()
	vertices = PackedVector3Array()
	for slot: Array in _row_slots:
		heights.append_array(slot[0])
		vertices.append_array(slot[1])
	_row_slots = []


func build_attributes() -> void:
	_run_rows(_attribute_row, _cells.y + 1)
	normals = PackedVector3Array()
	tangents = PackedFloat32Array()
	uvs = PackedVector2Array()
	weights = PackedFloat32Array()
	tints = PackedVector2Array()
	for slot: Array in _row_slots:
		normals.append_array(slot[0])
		tangents.append_array(slot[1])
		uvs.append_array(slot[2])
		weights.append_array(slot[3])
		tints.append_array(slot[4])
	_row_slots = []


## Runs `task(row)` for every row of the terrain mesh, on the worker threads (or one by one with
## `threads` off). A task reads shared state only and writes its own slot of _row_slots.
func _run_rows(task: Callable, rows: int) -> void:
	_row_slots = []
	_row_slots.resize(rows)
	if threads:
		var id := WorkerThreadPool.add_group_task(task, rows, -1, true, "Terrain mesh rows")
		WorkerThreadPool.wait_for_group_task_completion(id)
	else:
		for j in rows:
			task.call(j)


## Row `j` of the terrain mesh: [heights: PackedFloat32Array, vertices: PackedVector3Array].
func _height_row(j: int) -> void:
	var row := _cells.x + 1
	var heights := PackedFloat32Array()
	heights.resize(row)
	var vertices := PackedVector3Array()
	vertices.resize(row)
	var z := _origin.y + j * _step.y
	for i in row:
		var x := _origin.x + i * _step.x
		var h := _surface.height_at(x, z)
		vertices[i] = Vector3(x, h, z)
		heights[i] = h
	_row_slots[j] = [heights, vertices]


## Row `j` of the vertex attributes, from the finished `vertices`: [normals,
## tangents (4 floats per vertex), uvs, splat weights (LAYER_COUNT per vertex), tints].
func _attribute_row(j: int) -> void:
	var nx := _cells.x
	var nz := _cells.y
	var row := nx + 1
	var step := _step
	var normals := PackedVector3Array()
	normals.resize(row)
	# Godot packs tangents as (x, y, z, w) with binormal = cross(normal, tangent) * w.
	var tangents := PackedFloat32Array()
	tangents.resize(row * 4)
	var uvs := PackedVector2Array()
	uvs.resize(row)
	var weights := PackedFloat32Array()
	weights.resize(row * TerrainSplat.LAYER_COUNT)
	var tints := PackedVector2Array()
	tints.resize(row)
	# Normals by central differences on the height grid (one-sided at the border).
	var j0 := maxi(j - 1, 0)
	var j1 := mini(j + 1, nz)
	for i in row:
		var i0 := maxi(i - 1, 0)
		var i1 := mini(i + 1, nx)
		var v := vertices[j * row + i]
		var dx := (vertices[j * row + i1].y - vertices[j * row + i0].y) / ((i1 - i0) * step.x)
		var dz := (vertices[j1 * row + i].y - vertices[j0 * row + i].y) / ((j1 - j0) * step.y)
		var n := Vector3(-dx, 1.0, -dz).normalized()
		normals[i] = n
		# U runs along +x, so the tangent is the slope direction (1, dh/dx, 0), made
		# perpendicular to the normal. With w = +1 the binormal is -z, i.e. up the
		# normal map image (towards v = 0), the OpenGL convention DetailTexture writes.
		var t := Vector3(1.0, dx, 0.0)
		t = (t - n * n.dot(t)).normalized()
		tangents[i * 4] = t.x
		tangents[i * 4 + 1] = t.y
		tangents[i * 4 + 2] = t.z
		tangents[i * 4 + 3] = 1.0
		uvs[i] = Vector2(v.x, v.z) / MapView.DETAIL_TILE
		# The jittered tile type keeps forest edges from following the hex outline.
		var jittered := GroundNoise.jitter(v.x, v.z)
		var jc := Hex.from_world(Vector3(jittered.x, 0.0, jittered.y), _hex_size)
		var jittered_type := int(_grid.get_terrain(jc)) if _grid.has_tile(jc) else -1
		var on_map := _grid.has_tile(Hex.from_world(v, _hex_size))
		var w := MapView._splat(jittered_type, n.y, v, MapView._splat_noise(v.x, v.z))
		for layer in TerrainSplat.LAYER_COUNT:
			weights[i * TerrainSplat.LAYER_COUNT + layer] = w[layer]
		tints[i] = Vector2(1.0 if on_map else MapView.OFF_MAP_VALUE, 1.0)
	_row_slots[j] = [normals, tangents, uvs, weights, tints]
