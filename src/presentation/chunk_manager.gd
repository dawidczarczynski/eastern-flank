class_name ChunkManager
extends RefCounted
## The chunked lazy world (TASK-072b, ADR 0024): every registered ChunkLayer keeps only the
## chunks near the camera target. A layer's chunks within its build ring (ChunkRings, metres) are
## queued nearest first, planned on the WorkerThreadPool (ChunkLayer.plan_chunk, pure) and turned
## into nodes on the main thread (build_chunk) within `budget_usec` per frame; the rest of the
## queue carries over to the next frame. Built chunks beyond the free ring (build ring x 1.2) are
## freed (free_chunk); the gap between the two rings is the hysteresis that keeps a camera
## wobbling at a border from rebuilding. Frees are spread over frames too (half the budget). The
## result never depends on the build order: a chunk's plan is a function of the chunk alone.
## Usage: register(layer)…; each frame update(target) and process(); behind a loading screen or in
## tests finish_all() builds everything the rings ask for at once.

## Main-thread time per frame spent on build_chunk / free_chunk calls.
const DEFAULT_BUDGET_USEC := 4000
## Jobs per worker batch: big enough to keep the threads busy, small enough to follow the camera.
const BATCH_SIZE := 24
## Cores left to the main and render threads while planning in play (not on the loading screen).
const PLAY_THREADS_SPARED := 2
## The rings are only rescanned after the target moved this far (world units) or a layer changed:
## the build ring is 1.5 x the draw reach, so a few units of lag never show, and a fast pan does not
## rescan every frame.
const RESCAN_DISTANCE := 2.0

## Plans on the WorkerThreadPool (off: on the main thread, inside the budget).
var threads := true
var budget_usec := DEFAULT_BUDGET_USEC

var _rings: ChunkRings
var _low_quality := false
var _layers: Array[ChunkLayer] = []
## One Dictionary per layer: Vector2i chunk -> true for the built chunks.
var _live: Array[Dictionary] = []
## Jobs waiting for a plan, Vector3i(layer index, chunk x, chunk z), farthest first (pop_back).
var _pending: Array[Vector3i] = []
## Every job in _pending, the running batch or _ready -> true.
var _queued: Dictionary = {}
## Jobs whose plan went stale (invalidate) while queued: dropped and queued again when finished.
var _stale: Dictionary = {}
## Built chunks beyond their free ring, Vector3i(layer index, chunk x, chunk z) -> true: freed
## within the frame budget (a camera jump leaves hundreds at once: ~0.4 ms each).
var _to_free: Dictionary = {}
var _batch: Array[Vector3i] = []
var _batch_plans: Array = []
var _batch_task := -1
## Planned jobs waiting for build_chunk: [Vector3i job, Variant plan], nearest last.
var _ready: Array = []
## Average build_chunk time per layer (usec), for the budget estimate.
var _build_cost: Array[float] = []
## Totals per layer (usec): plan time (worker or main thread) and build time (main thread).
var _plan_usec: Array[int] = []
var _build_usec: Array[int] = []
var _batch_usec: Array[int] = []
var _target := Vector2.ZERO
var _has_target := false
var _scanned_target := Vector2.ZERO
var _scan_needed := false
var _built_total := 0
var _freed_total := 0


func _init(rings: ChunkRings = null, low_quality := false) -> void:
	_rings = rings if rings != null else ChunkRings.load_default()
	_low_quality = low_quality


## Adds a layer; its chunks are built from the next update() on.
func register(layer: ChunkLayer) -> void:
	_layers.append(layer)
	_live.append({})
	_build_cost.append(0.0)
	_plan_usec.append(0)
	_build_usec.append(0)
	_scan_needed = true


func layer(id: StringName) -> ChunkLayer:
	for l in _layers:
		if l.id == id:
			return l
	return null


func layers() -> Array[ChunkLayer]:
	return _layers


func build_radius(id: StringName) -> float:
	return _rings.build_radius(id, _low_quality)


func free_radius(id: StringName) -> float:
	return _rings.free_radius(id, _low_quality)


## The built chunks of layer `id`.
func live_chunks(id: StringName) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in _layers.size():
		if _layers[i].id == id:
			result.assign(_live[i].keys())
	return result


func is_live(id: StringName, chunk: Vector2i) -> bool:
	for i in _layers.size():
		if _layers[i].id == id:
			return _live[i].has(chunk)
	return false


## Chunks built and freed so far (all layers).
func built_total() -> int:
	return _built_total


func freed_total() -> int:
	return _freed_total


## Per layer id: {"live": built chunks, "plan_ms": total plan time (summed over the threads),
## "build_ms": total main-thread build time, "build_avg_ms": the running build cost estimate}.
func stats() -> Dictionary:
	var result := {}
	for i in _layers.size():
		result[_layers[i].id] = {
			"live": _live[i].size(),
			"plan_ms": _plan_usec[i] / 1000.0,
			"build_ms": _build_usec[i] / 1000.0,
			"build_avg_ms": _build_cost[i] / 1000.0,
		}
	return result


func has_target() -> bool:
	return _has_target


func target() -> Vector2:
	return _target


## True when every chunk the rings ask for around the current target is built.
func is_settled() -> bool:
	return (
		_has_target
		and not _scan_needed
		and _to_free.is_empty()
		and _pending.is_empty()
		and _batch.is_empty()
		and _ready.is_empty()
	)


## The camera target moved: frees what fell out of the free rings and queues what came into the
## build rings (only after RESCAN_DISTANCE of movement, or when something asked for a rescan).
func update(target: Vector2) -> void:
	_target = target
	if not _has_target or target.distance_to(_scanned_target) > RESCAN_DISTANCE:
		_scan_needed = true
	_has_target = true
	if _scan_needed:
		_scan()


## One frame of work: collects a finished worker batch, starts the next one and builds planned
## chunks for up to budget_usec (the first one of a frame always runs).
func process() -> void:
	if not _has_target:
		return
	if _scan_needed:
		_scan()
	var started := Time.get_ticks_usec()
	if not _to_free.is_empty():
		_free_queued(started + budget_usec / 2)
	if threads:
		_collect_batch(false)
		_start_batch(false)
	elif _ready.is_empty() and not _pending.is_empty():
		_plan_now(1)
	var first := true
	while not _ready.is_empty():
		var job: Vector3i = (_ready.back() as Array)[0]
		var spent := Time.get_ticks_usec() - started
		if not first and spent + _build_cost[job.x] > budget_usec:
			break
		_finish_one()
		first = false
		if not threads and _ready.is_empty() and not _pending.is_empty():
			if Time.get_ticks_usec() - started >= budget_usec:
				break
			_plan_now(1)


## Builds everything the rings ask for around the current target, ignoring the budget (loading
## screen, tests, screenshots).
func finish_all() -> void:
	if not _has_target:
		return
	while not is_settled():
		if _scan_needed:
			_scan()
		_free_queued(0)
		if threads:
			_collect_batch(true)
			_start_batch(true)
			_collect_batch(true)
		else:
			_plan_now(_pending.size())
		while not _ready.is_empty():
			_finish_one()


## Frees the chunks of layer `id` that touch `rect` and queues them again (their content changed,
## e.g. a clearing in the grass); queued plans that touch it are dropped and planned again.
func invalidate(id: StringName, rect: Rect2) -> void:
	for i in _layers.size():
		var l := _layers[i]
		if l.id != id:
			continue
		for chunk: Vector2i in _live[i].keys():
			if l.chunk_rect(chunk).intersects(rect):
				l.free_chunk.call(chunk)
				_live[i].erase(chunk)
				_to_free.erase(Vector3i(i, chunk.x, chunk.y))
				_freed_total += 1
		# Jobs still waiting are planned later anyway; planned or planning ones are stale.
		for job: Vector3i in _queued:
			if job.x == i and job not in _pending:
				if l.chunk_rect(Vector2i(job.y, job.z)).intersects(rect):
					_stale[job] = true
	_scan_needed = true


## Waits for a running worker batch (its plans stay queued). The owner calls it before it goes
## away: the batch's tasks call into the layers.
func wait() -> void:
	_collect_batch(true)


## Frees every built chunk and forgets the queue (a new map is built, or the view goes away).
## Waits for a running worker batch first.
func clear() -> void:
	if _batch_task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_batch_task)
		_batch_task = -1
	_batch = []
	_batch_plans = []
	_pending = []
	_ready = []
	_queued.clear()
	_stale.clear()
	_to_free.clear()
	for i in _layers.size():
		for chunk: Vector2i in _live[i].keys():
			_layers[i].free_chunk.call(chunk)
			_freed_total += 1
		_live[i].clear()
	_scan_needed = true


## Like clear(), and forgets the layers too.
func reset() -> void:
	clear()
	_layers = []
	_live = []
	_build_cost = []
	_plan_usec = []
	_build_usec = []
	_has_target = false


func _scan() -> void:
	_scan_needed = false
	_scanned_target = _target
	var frees: Array[float] = []
	for i in _layers.size():
		var l := _layers[i]
		var free := free_radius(l.id)
		frees.append(free)
		# Beyond the free ring: freed within the frame budget (process); back inside: kept.
		for chunk: Vector2i in _live[i].keys():
			var job := Vector3i(i, chunk.x, chunk.y)
			if l.distance_to(chunk, _target) > free:
				_to_free[job] = true
			else:
				_to_free.erase(job)
		var build := build_radius(l.id)
		if build <= 0.0:
			continue
		# One more on the low side: a chunk whose far edge lies exactly on the ring counts.
		var first := l.chunk_at(_target.x - build, _target.y - build) - Vector2i.ONE
		var last := l.chunk_at(_target.x + build, _target.y + build)
		for x in range(first.x, last.x + 1):
			for z in range(first.y, last.y + 1):
				var chunk := Vector2i(x, z)
				var job := Vector3i(i, x, z)
				if _live[i].has(chunk) or _queued.has(job):
					continue
				if (
					l.distance_to(chunk, _target) > build
					or not l.chunk_rect(chunk).intersects(l.area)
				):
					continue
				_pending.append(job)
				_queued[job] = true
	# Queued jobs that left the free ring are dropped; the rest is ordered farthest first. The
	# order key is one int per job (distance in 1/1000 units, then the job's index), sorted
	# natively: a GDScript comparator over hundreds of jobs cost tens of ms on a fast pan.
	var keys := PackedInt64Array()
	var kept: Array[Vector3i] = []
	for job in _pending:
		var distance := _job_distance(job)
		if distance > frees[job.x]:
			_queued.erase(job)
			_stale.erase(job)
			continue
		keys.append((roundi(distance * 1000.0) << 20) | kept.size())
		kept.append(job)
	keys.sort()
	var ordered: Array[Vector3i] = []
	ordered.resize(kept.size())
	for k in keys.size():
		ordered[keys.size() - 1 - k] = kept[keys[k] & 0xFFFFF]
	_pending = ordered


## Frees queued chunks (beyond the free ring) until `deadline` (usec ticks; 0 = all of them).
func _free_queued(deadline: int) -> void:
	for job: Vector3i in _to_free.keys():
		if deadline > 0 and Time.get_ticks_usec() >= deadline:
			return
		_to_free.erase(job)
		var chunk := Vector2i(job.y, job.z)
		if _live[job.x].has(chunk):
			_layers[job.x].free_chunk.call(chunk)
			_live[job.x].erase(chunk)
			_freed_total += 1


func _job_distance(job: Vector3i) -> float:
	return _layers[job.x].distance_to(Vector2i(job.y, job.z), _target)


## Plans up to `count` pending jobs on this thread (nearest first) into _ready.
func _plan_now(count: int) -> void:
	var prepared := {}
	for n in count:
		if _pending.is_empty():
			return
		var job: Vector3i = _pending.pop_back()
		var l := _layers[job.x]
		if not prepared.has(job.x) and l.prepare.is_valid():
			l.prepare.call()
			prepared[job.x] = true
		var started := Time.get_ticks_usec()
		var plan: Variant = l.plan(Vector2i(job.y, job.z))
		_plan_usec[job.x] += Time.get_ticks_usec() - started
		_ready.push_front([job, plan])


## Starts planning the nearest pending jobs on the worker threads. In play (`all_threads` off) a
## batch uses at most PLAY_THREADS_SPARED fewer threads than there are cores, at normal priority:
## four busy workers starved the main and render threads into 80–140 ms frames while panning.
func _start_batch(all_threads: bool) -> void:
	if _batch_task >= 0 or not _batch.is_empty() or _pending.is_empty():
		return
	while not _pending.is_empty() and _batch.size() < BATCH_SIZE:
		_batch.append(_pending.pop_back())
	var prepared := {}
	for job in _batch:
		var l := _layers[job.x]
		if not prepared.has(job.x) and l.prepare.is_valid():
			l.prepare.call()
			prepared[job.x] = true
	_batch_plans = []
	_batch_plans.resize(_batch.size())
	_batch_usec = []
	_batch_usec.resize(_batch.size())
	var workers := -1 if all_threads else maxi(1, OS.get_processor_count() - PLAY_THREADS_SPARED)
	_batch_task = WorkerThreadPool.add_group_task(
		_plan_batch_job, _batch.size(), workers, all_threads, "Chunk plans"
	)


## Runs on a worker thread: writes only its own slot of _batch_plans.
func _plan_batch_job(index: int) -> void:
	var job := _batch[index]
	var started := Time.get_ticks_usec()
	_batch_plans[index] = _layers[job.x].plan(Vector2i(job.y, job.z))
	_batch_usec[index] = Time.get_ticks_usec() - started


## Moves a finished batch into _ready (nearest last); `wait` blocks until it is finished.
func _collect_batch(wait: bool) -> void:
	if _batch_task < 0:
		return
	if not wait and not WorkerThreadPool.is_group_task_completed(_batch_task):
		return
	WorkerThreadPool.wait_for_group_task_completion(_batch_task)
	_batch_task = -1
	# _batch is nearest first and _ready is consumed from the back: the batch goes in front of
	# what is still waiting, its nearest job closest to the back.
	for k in _batch.size():
		_ready.push_front([_batch[k], _batch_plans[k]])
		_plan_usec[_batch[k].x] += _batch_usec[k]
	_batch = []
	_batch_plans = []


## Builds the nearest planned job (or drops it when it went stale or out of the free ring).
func _finish_one() -> void:
	var entry: Array = _ready.pop_back()
	var job: Vector3i = entry[0]
	_queued.erase(job)
	var chunk := Vector2i(job.y, job.z)
	var l := _layers[job.x]
	if _stale.has(job):
		_stale.erase(job)
		_scan_needed = true
		return
	if _live[job.x].has(chunk) or l.distance_to(chunk, _target) > free_radius(l.id):
		return
	var started := Time.get_ticks_usec()
	l.build_chunk.call(chunk, entry[1])
	var cost := float(Time.get_ticks_usec() - started)
	_build_usec[job.x] += int(cost)
	_build_cost[job.x] = cost if _build_cost[job.x] == 0.0 else lerpf(_build_cost[job.x], cost, 0.2)
	_live[job.x][chunk] = true
	_built_total += 1
