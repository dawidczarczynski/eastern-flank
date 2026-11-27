extends TestCase
## The shared chunk plan of FoliageChunks (TASK-222): the scatter and the trees job of one chunk
## run at the same time on the worker threads; the plan is computed once and the other job waits
## for it (before, nearly every chunk was planned twice).

const Fixtures := preload("res://tests/fixtures.gd")


## FoliageChunks whose plan is a slow stand-in that counts its calls.
class CountingChunks:
	extends FoliageChunks
	var plans := 0
	var _count_mutex := Mutex.new()

	func _plan_source(chunk: Vector2i) -> Dictionary:
		_count_mutex.lock()
		plans += 1
		_count_mutex.unlock()
		OS.delay_msec(30)
		return {"map": {"chunk": chunk}, "backdrop": {}}


func _chunks() -> CountingChunks:
	var grid := Fixtures.plains_grid(3)
	return CountingChunks.new(
		grid,
		TerrainSurface.new(grid),
		null,
		7,
		Rect2(-8, -8, 16, 16),
		Rect2(-6, -6, 12, 12),
		TreeField.new()
	)


func test_two_layers_asking_at_once_plan_a_chunk_once() -> void:
	var chunks := _chunks()
	var results: Array = [{}, {}]
	var tasks: Array[int] = []
	for i in 2:
		var layer: StringName = [&"scatter", &"trees"][i]
		tasks.append(
			WorkerThreadPool.add_task(
				func() -> void: results[i] = chunks.source(Vector2i.ZERO, layer)
			)
		)
	for task in tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	assert_eq(chunks.plans, 1, "planned once for both layers")
	assert_true(results[0] is Dictionary and not (results[0] as Dictionary).is_empty())
	assert_true(results[0] == results[1], "both layers read the same plan")
	assert_true(chunks._cache.is_empty(), "the cache entry is dropped after both layers took it")
	assert_true(chunks._planning.is_empty())
