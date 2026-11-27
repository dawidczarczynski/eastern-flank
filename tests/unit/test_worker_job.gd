extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")
## WorkerJob (TASK-222): without threads the work runs at once and result() returns it. (A threaded
## job is not run here: worker tasks never returned inside the headless test runner, see TASK-222;
## the game and tools/screenshot.sh run them.)


func test_unthreaded_job_runs_in_start_and_can_be_asked_twice() -> void:
	var ran := [false]
	var job := WorkerJob.start(
		func() -> String:
			ran[0] = true
			return "done",
		false
	)
	assert_true(ran[0], "ran before result()")
	assert_eq(job.result(), "done")
	assert_eq(job.result(), "done")


func test_wait_and_discard_join_without_result_and_are_repeatable() -> void:
	var job := WorkerJob.start(func() -> int: return 5, false)
	job.wait()
	job.wait()
	assert_eq(job.result(), 5, "wait keeps the result")
	job.discard()
	assert_eq(job.result(), null, "discard drops it")
	job.discard()


func test_finish_blocks_computes_every_lattice_block_without_a_warm_up() -> void:
	var grid := Fixtures.plains_grid(3)
	var lattice := TerrainLattice.new(Rect2(-6.0, -6.0, 12.0, 12.0), TerrainSurface.new(grid))
	lattice.wait_blocks()  # nothing started: a no-op
	lattice.finish_blocks()
	var counts := lattice.chunk_counts()
	assert_eq(lattice.block_count(), counts.x * counts.y)
	var side := TerrainLattice.CELLS_PER_CHUNK + 1
	assert_eq(lattice.block(Vector2i.ZERO)[side + 1], lattice.height(1, 1))
