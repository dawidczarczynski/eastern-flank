class_name WorkerJob
extends RefCounted
## One piece of pure CPU work run on the WorkerThreadPool while the main thread does something
## else (the battle loading screen overlaps its independent builds this way). `result()` waits for
## it and returns what the Callable returned; without threads (tests) the work runs at once in
## `start`. The Callable must only read data that is safe to read from a worker (the planners'
## rule: no nodes, no scene tree, no shared caches without a lock).

var _id := -1
var _result: Variant = null


static func start(work: Callable, threaded := true, description := "Load job") -> WorkerJob:
	var job := WorkerJob.new()
	if threaded:
		job._id = WorkerThreadPool.add_task(
			func() -> void: job._result = work.call(), true, description
		)
	else:
		job._result = work.call()
	return job


## Waits for the work to finish (nothing when it already has) and drops the result: for a job whose
## result is no longer wanted (a task must be joined before its owner goes away).
func wait() -> void:
	if _id >= 0:
		WorkerThreadPool.wait_for_task_completion(_id)
		_id = -1


## Waits for the work (the first call) and returns its result.
func result() -> Variant:
	wait()
	return _result


## wait() and forgets the result.
func discard() -> void:
	wait()
	_result = null
