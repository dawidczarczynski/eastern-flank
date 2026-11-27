class_name TerrainLattice
extends RefCounted
## The vertex lattice of MapView's chunked terrain (TASK-072b): vertex (i, j) sits at
## origin + (i, j) * STEP with the height of the TerrainSurface there, except the odd vertices on
## the outer border, which lie on the line between their even neighbours so the half-density
## backdrop ring (BackdropMesh) meets the edge without cracks. Heights are a pure function of
## (i, j), so every chunk computes the same value for a shared vertex, in any order and on any
## thread. The drawn height at a point (`mesh_height_at`) reads blocks of CELLS_PER_CHUNK x
## CELLS_PER_CHUNK cells that are computed on first use and kept (thread-safe), so a query never
## needs the whole map's mesh – only the chunks it touches (and a few stray queries not even those).

## Cells per world unit (MapView.RESOLUTION) and the cell size.
const RESOLUTION := 4
const STEP := 1.0 / RESOLUTION
const CELLS_PER_CHUNK := 32
const CHUNK_SIZE := CELLS_PER_CHUNK * STEP
## Cell counts are a multiple of this, so the coarse lattice (TerrainChunks.COARSE_STRIDE) ends on
## the border too.
const CELL_MULTIPLE := 4
## Height queries into a block before mesh_height_at computes the whole block.
const BLOCK_AFTER_MISSES := 48

var origin := Vector2.ZERO
var cells := Vector2i.ZERO

var _surface: TerrainSurface
var _mutex := Mutex.new()
## Vector2i chunk -> PackedFloat32Array of (CELLS_PER_CHUNK + 1)^2 heights (row-major; entries
## past the lattice border are unused).
var _blocks: Dictionary = {}
## Blocks a thread is computing right now -> true.
var _computing: Dictionary = {}
## Group task of warm_blocks_async, -1 when none.
var _warm_task := -1
## Vector2i chunk -> height queries answered without its block.
var _misses: Dictionary = {}


## Covers `rect` (from its corner, rounded up to whole cells).
func _init(rect: Rect2, surface: TerrainSurface) -> void:
	_surface = surface
	origin = rect.position
	cells = Vector2i(
		CELL_MULTIPLE * maxi(1, ceili(rect.size.x * RESOLUTION / CELL_MULTIPLE - 1e-6)),
		CELL_MULTIPLE * maxi(1, ceili(rect.size.y * RESOLUTION / CELL_MULTIPLE - 1e-6))
	)


func rect() -> Rect2:
	return Rect2(origin, Vector2(cells) * STEP)


## Chunks along x and z (the last ones may be partial).
func chunk_counts() -> Vector2i:
	return Vector2i(
		ceili(float(cells.x) / CELLS_PER_CHUNK), ceili(float(cells.y) / CELLS_PER_CHUNK)
	)


func x_of(i: int) -> float:
	return origin.x + i * STEP


func z_of(j: int) -> float:
	return origin.y + j * STEP


## The surface height at vertex (i, j) (clamped to the lattice), with the border rule.
func height(i: int, j: int) -> float:
	i = clampi(i, 0, cells.x)
	j = clampi(j, 0, cells.y)
	if (j == 0 or j == cells.y) and i % 2 == 1:
		return (_raw(i - 1, j) + _raw(i + 1, j)) * 0.5
	if (i == 0 or i == cells.x) and j % 2 == 1:
		return (_raw(i, j - 1) + _raw(i, j + 1)) * 0.5
	return _raw(i, j)


func _raw(i: int, j: int) -> float:
	return _surface.height_at(x_of(i), z_of(j))


## The heights of `chunk`'s vertices, (CELLS_PER_CHUNK + 1)^2 row-major, computed once: a thread
## that asks for a block another thread is computing waits for it instead of computing it again.
func block(chunk: Vector2i) -> PackedFloat32Array:
	_mutex.lock()
	while true:
		var cached: Variant = _blocks.get(chunk)
		if cached != null:
			_mutex.unlock()
			return cached
		if not _computing.has(chunk):
			_computing[chunk] = true
			break
		_mutex.unlock()
		OS.delay_usec(100)
		_mutex.lock()
	_mutex.unlock()
	var side := CELLS_PER_CHUNK + 1
	var heights := PackedFloat32Array()
	heights.resize(side * side)
	var i0 := chunk.x * CELLS_PER_CHUNK
	var j0 := chunk.y * CELLS_PER_CHUNK
	for b in side:
		var j := j0 + b
		if j > cells.y:
			break
		for a in side:
			var i := i0 + a
			if i > cells.x:
				break
			heights[b * side + a] = height(i, j)
	_mutex.lock()
	_blocks[chunk] = heights
	_computing.erase(chunk)
	_mutex.unlock()
	return heights


## Starts computing every height block on worker threads (block() is thread-safe, a block asked for
## meanwhile is waited for, not computed twice); `finish_blocks` joins them. The loading screen
## starts it as soon as the lattice exists, the forest's height image (all blocks) then finds them
## done.
func warm_blocks_async() -> void:
	if _warm_task >= 0:
		return
	var counts := chunk_counts()
	var compute := func(index: int) -> void: block(Vector2i(index % counts.x, index / counts.x))
	_warm_task = WorkerThreadPool.add_group_task(
		compute, counts.x * counts.y, -1, false, "Terrain lattice blocks"
	)


## Waits for the task of `warm_blocks_async` (nothing when not started): a group task must be joined
## before the lattice goes away.
func wait_blocks() -> void:
	if _warm_task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_warm_task)
		_warm_task = -1


## Waits for `warm_blocks_async`; afterwards every block is cached.
func finish_blocks() -> void:
	var counts := chunk_counts()
	wait_blocks()
	for index in counts.x * counts.y:
		block(Vector2i(index % counts.x, index / counts.x))


## Number of height blocks computed so far (statistics, tests).
func block_count() -> int:
	_mutex.lock()
	var count := _blocks.size()
	_mutex.unlock()
	return count


## Height of the drawn terrain at (x, z), interpolated on the triangles the mesh is drawn with
## (cell split along the b–c diagonal), clamped to the lattice and to the water surface.
func mesh_height_at(x: float, z: float) -> float:
	var fx := clampf((x - origin.x) / STEP, 0.0, cells.x)
	var fz := clampf((z - origin.y) / STEP, 0.0, cells.y)
	var i := mini(floori(fx), cells.x - 1)
	var j := mini(floori(fz), cells.y - 1)
	var u := fx - i
	var v := fz - j
	var chunk := Vector2i(i / CELLS_PER_CHUNK, j / CELLS_PER_CHUNK)
	var ha: float
	var hb: float
	var hc: float
	var hd: float
	var heights := _block_for_query(chunk)
	if heights.is_empty():
		# A few queries into a block nobody needed yet (the camera's ground clearance right after a
		# fast move): the cell's own corners, not the whole block on the main thread.
		ha = height(i, j)
		hb = height(i + 1, j)
		hc = height(i, j + 1)
		hd = height(i + 1, j + 1) if u + v > 1.0 else 0.0
	else:
		var side := CELLS_PER_CHUNK + 1
		var a := i - chunk.x * CELLS_PER_CHUNK
		var b := j - chunk.y * CELLS_PER_CHUNK
		ha = heights[b * side + a]
		hb = heights[b * side + a + 1]
		hc = heights[(b + 1) * side + a]
		hd = heights[(b + 1) * side + a + 1]
	var h: float
	if u + v <= 1.0:
		h = ha + u * (hb - ha) + v * (hc - ha)
	else:
		h = hd + (1.0 - u) * (hc - hd) + (1.0 - v) * (hb - hd)
	return maxf(h, TerrainSurface.WATER_SURFACE)


## The block of `chunk` for a height query: the cached one, else computed once BLOCK_AFTER_MISSES
## queries asked for it (bulk users: draping, planners); before that empty (the caller computes the
## few corners it needs – the same values).
func _block_for_query(chunk: Vector2i) -> PackedFloat32Array:
	_mutex.lock()
	var cached: Variant = _blocks.get(chunk)
	var misses := 0
	if cached == null:
		misses = _misses.get(chunk, 0) + 1
		_misses[chunk] = misses
	_mutex.unlock()
	if cached != null:
		return cached
	if misses >= BLOCK_AFTER_MISSES:
		return block(chunk)
	return PackedFloat32Array()
