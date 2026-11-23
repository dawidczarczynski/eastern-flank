extends TestCase
## ChunkManager (TASK-072b): rings, hysteresis, the layer interface, threaded planning, budget.

const SIZE := 8.0
const AREA := Rect2(-200.0, -200.0, 400.0, 400.0)


## A stub layer that records what the manager asks of it; its plan is a pure function of the chunk.
class Stub:
	extends RefCounted
	var live := {}
	var built := 0
	var freed := 0
	var plans := {}
	var delay_usec := 0

	func plan(chunk: Vector2i) -> Variant:
		var values := PackedInt32Array()
		for i in 64:
			values.append((chunk.x * 73856093) ^ (chunk.y * 19349663) ^ i)
		return values

	func build(chunk: Vector2i, plan_value: Variant) -> void:
		if delay_usec > 0:
			OS.delay_usec(delay_usec)
		live[chunk] = true
		plans[chunk] = plan_value
		built += 1

	func free_chunk(chunk: Vector2i) -> void:
		live.erase(chunk)
		freed += 1


func _rings(reach_units: float) -> ChunkRings:
	var rings := ChunkRings.new()
	rings.reach_m = {&"stub": reach_units * MapScale.metres_per_unit}
	return rings


func _manager(stub: Stub, reach_units := 20.0, threads := false, low := false) -> ChunkManager:
	var manager := ChunkManager.new(_rings(reach_units), low)
	manager.threads = threads
	manager.register(ChunkLayer.new(&"stub", SIZE, AREA, stub.build, stub.free_chunk, stub.plan))
	return manager


func _expected(layer: ChunkLayer, target: Vector2, radius: float) -> Dictionary:
	var result := {}
	var first := layer.chunk_at(target.x - radius - SIZE, target.y - radius - SIZE)
	var last := layer.chunk_at(target.x + radius + SIZE, target.y + radius + SIZE)
	for x in range(first.x, last.x + 1):
		for z in range(first.y, last.y + 1):
			var chunk := Vector2i(x, z)
			if (
				layer.distance_to(chunk, target) <= radius
				and layer.chunk_rect(chunk).intersects(AREA)
			):
				result[chunk] = true
	return result


func test_moving_the_camera_builds_the_build_ring_and_frees_beyond_the_free_ring() -> void:
	var stub := Stub.new()
	var manager := _manager(stub)
	var layer := manager.layer(&"stub")
	var rings := _rings(20.0)
	var build := rings.build_radius(&"stub")
	var free := rings.free_radius(&"stub")
	manager.update(Vector2.ZERO)
	manager.finish_all()
	assert_eq(stub.live.keys().size(), _expected(layer, Vector2.ZERO, build).size())
	for chunk: Vector2i in _expected(layer, Vector2.ZERO, build):
		assert_true(stub.live.has(chunk), "built %s" % chunk)
	var target := Vector2(70.0, -10.0)
	manager.update(target)
	manager.finish_all()
	for chunk: Vector2i in stub.live:
		assert_true(
			layer.distance_to(chunk, target) <= free, "kept within the free ring %s" % chunk
		)
	for chunk: Vector2i in _expected(layer, target, build):
		assert_true(stub.live.has(chunk), "built around the new target %s" % chunk)
	assert_true(stub.freed > 0, "chunks behind the camera were freed")
	assert_eq(manager.live_chunks(&"stub").size(), stub.live.size())


func test_chunks_outside_the_layer_area_are_never_built() -> void:
	var stub := Stub.new()
	var manager := _manager(stub)
	manager.update(Vector2(AREA.end.x + 10.0, 0.0))
	manager.finish_all()
	for chunk: Vector2i in stub.live:
		assert_true(manager.layer(&"stub").chunk_rect(chunk).intersects(AREA), "%s" % chunk)


func test_oscillating_around_the_ring_border_builds_and_frees_nothing_after_the_first_pass(
) -> void:
	var stub := Stub.new()
	var manager := _manager(stub)
	var radius := _rings(20.0).build_radius(&"stub")
	var low := Vector2(-0.1 * radius, 0.0)
	var high := Vector2(0.1 * radius, 0.0)
	for target in [low, high]:
		manager.update(target)
		manager.finish_all()
	var built := stub.built
	var freed := stub.freed
	for i in 10:
		for target in [low, high]:
			manager.update(target)
			manager.finish_all()
	assert_eq(stub.built - built, 0, "no rebuilds")
	assert_eq(stub.freed - freed, 0, "no frees")


func test_a_stub_layer_gets_its_plan_in_build_and_is_freed_through_the_interface() -> void:
	var stub := Stub.new()
	var manager := _manager(stub)
	manager.update(Vector2.ZERO)
	manager.finish_all()
	for chunk: Vector2i in stub.plans:
		assert_eq(stub.plans[chunk], stub.plan(chunk))
	var count := stub.live.size()
	manager.clear()
	assert_eq(stub.freed, count, "clear frees every live chunk")
	assert_eq(stub.live.size(), 0)


func test_a_second_layer_is_added_without_touching_the_first() -> void:
	var stub := Stub.new()
	var other := Stub.new()
	var rings := _rings(20.0)
	rings.reach_m[&"other"] = 5.0 * MapScale.metres_per_unit
	var manager := ChunkManager.new(rings)
	manager.threads = false
	manager.register(ChunkLayer.new(&"stub", SIZE, AREA, stub.build, stub.free_chunk, stub.plan))
	manager.register(ChunkLayer.new(&"other", 4.0, AREA, other.build, other.free_chunk))
	manager.update(Vector2.ZERO)
	manager.finish_all()
	assert_true(other.live.size() > 0)
	assert_true(other.live.size() < 20, "its own, smaller ring: %d" % other.live.size())
	for chunk: Vector2i in other.plans:
		assert_eq(other.plans[chunk], null, "no planner: null plan")
	assert_eq(stub.live.size(), _expected(manager.layer(&"stub"), Vector2.ZERO, 30.0).size())


func test_threaded_plans_equal_single_thread_plans() -> void:
	var single := Stub.new()
	var threaded := Stub.new()
	var a := _manager(single, 20.0, false)
	var b := _manager(threaded, 20.0, true)
	for manager: ChunkManager in [a, b]:
		manager.update(Vector2(3.0, 5.0))
		manager.finish_all()
	assert_eq(threaded.live.size(), single.live.size())
	for chunk: Vector2i in single.plans:
		assert_eq(threaded.plans.get(chunk), single.plans[chunk], "%s" % chunk)


func test_threaded_process_carries_the_queue_over_until_settled() -> void:
	var stub := Stub.new()
	var manager := _manager(stub, 20.0, true)
	manager.update(Vector2.ZERO)
	assert_false(manager.is_settled())
	var frames := 0
	while not manager.is_settled() and frames < 10000:
		manager.process()
		frames += 1
	assert_true(manager.is_settled())
	assert_eq(stub.live.size(), _expected(manager.layer(&"stub"), Vector2.ZERO, 30.0).size())


func test_finishing_stays_within_the_frame_budget() -> void:
	var stub := Stub.new()
	stub.delay_usec = 1500
	var manager := _manager(stub)
	manager.budget_usec = 4000
	manager.update(Vector2.ZERO)
	var total := _expected(manager.layer(&"stub"), Vector2.ZERO, 30.0).size()
	var frames := 0
	while not manager.is_settled() and frames < 1000:
		var before := stub.built
		manager.process()
		frames += 1
		# The first chunk of a frame always runs; then only while the measured cost of a build
		# still fits the budget (wall-clock asserts would flake on a loaded machine).
		assert_true(stub.built - before >= 1, "progress every frame")
		assert_true(stub.built - before <= 2, "at most 2 builds of 1.5 ms in 4 ms")
	assert_eq(stub.built, total, "the queue carried over until everything was built")
	assert_true(frames >= total / 2, "spread over frames: %d" % frames)


func test_low_quality_has_smaller_rings_and_the_same_behaviour() -> void:
	var high := Stub.new()
	var low := Stub.new()
	var a := _manager(high)
	var b := _manager(low, 20.0, false, true)
	for manager: ChunkManager in [a, b]:
		manager.update(Vector2.ZERO)
		manager.finish_all()
	assert_true(low.live.size() < high.live.size(), "%d < %d" % [low.live.size(), high.live.size()])
	var rings := _rings(20.0)
	var expected := _expected(b.layer(&"stub"), Vector2.ZERO, rings.build_radius(&"stub", true))
	assert_eq(low.live.size(), expected.size())
	var radius := rings.build_radius(&"stub", true)
	for target in [Vector2(-0.1 * radius, 0.0), Vector2(0.1 * radius, 0.0)]:
		b.update(target)
		b.finish_all()
	var built := low.built
	for target in [Vector2(-0.1 * radius, 0.0), Vector2(0.1 * radius, 0.0)]:
		b.update(target)
		b.finish_all()
	assert_eq(low.built, built, "hysteresis on LOW too")


func test_invalidate_rebuilds_the_chunks_it_touches() -> void:
	var stub := Stub.new()
	var manager := _manager(stub)
	manager.update(Vector2.ZERO)
	manager.finish_all()
	var built := stub.built
	manager.invalidate(&"stub", Rect2(-1.0, -1.0, 2.0, 2.0))
	manager.finish_all()
	assert_eq(stub.built - built, 4, "the four chunks around the origin")
	assert_eq(stub.live.size(), _expected(manager.layer(&"stub"), Vector2.ZERO, 30.0).size())


func test_ring_radii_come_from_the_data_in_metres() -> void:
	var rings := ChunkRings.load_default()
	assert_true(rings != null)
	for layer: StringName in [&"terrain", &"scatter", &"trees", &"grass", &"marks", &"grid"]:
		assert_true(rings.reach(layer) > 0.0, "%s has a reach" % layer)
		assert_eq(rings.free_radius(layer), rings.build_radius(layer) * 1.2)
		assert_eq(rings.build_radius(layer), rings.reach(layer) * 1.5)
		assert_true(rings.build_radius(layer, true) < rings.build_radius(layer))
	var reach := rings.reach(&"terrain")
	MapScale.metres_per_unit = MapScale.DEFAULT_METRES_PER_UNIT * 2.0
	assert_true(is_equal_approx(rings.reach(&"terrain"), reach * 0.5), "metres, not units")
	MapScale.reset()


func test_a_camera_jump_frees_the_old_ring_over_several_frames() -> void:
	var stub := Stub.new()
	var manager := _manager(stub)
	manager.update(Vector2.ZERO)
	manager.finish_all()
	var count := stub.live.size()
	manager.budget_usec = 0
	manager.update(Vector2(150.0, 150.0))
	manager.process()
	assert_true(
		stub.freed < count, "not all %d freed in one zero-budget frame: %d" % [count, stub.freed]
	)
	manager.finish_all()
	assert_eq(stub.freed, count, "all freed once settled")


## TASK-134: the near terrain layer only exists while the camera is close.
func test_a_disabled_layer_frees_its_chunks_and_builds_nothing_until_enabled() -> void:
	var stub := Stub.new()
	var manager := _manager(stub)
	manager.update(Vector2.ZERO)
	manager.finish_all()
	var count := stub.live.size()
	assert_true(count > 0)
	manager.set_enabled(&"stub", false)
	assert_eq(manager.build_radius(&"stub"), 0.0)
	manager.update(Vector2.ZERO)
	manager.finish_all()
	assert_eq(stub.live.size(), 0, "every chunk freed, the one under the target too")
	manager.update(Vector2(30.0, 0.0))
	manager.finish_all()
	assert_eq(stub.live.size(), 0, "nothing built while disabled")
	manager.set_enabled(&"stub", true)
	manager.update(Vector2(30.0, 0.0))
	manager.finish_all()
	assert_eq(
		stub.live.size(),
		(
			_expected(
				manager.layer(&"stub"), Vector2(30.0, 0.0), _rings(20.0).build_radius(&"stub")
			)
			. size()
		)
	)


## A small ring is rescanned after a quarter of its build radius, not after RESCAN_DISTANCE.
func test_a_small_ring_is_rescanned_after_a_quarter_of_its_build_radius() -> void:
	var stub := Stub.new()
	var manager := ChunkManager.new(_rings(2.0))
	manager.threads = false
	manager.register(ChunkLayer.new(&"stub", 1.0, AREA, stub.build, stub.free_chunk, stub.plan))
	var build := manager.build_radius(&"stub")
	assert_true(build * 0.25 < ChunkManager.RESCAN_DISTANCE)
	manager.update(Vector2.ZERO)
	manager.finish_all()
	var target := Vector2(build * 0.3, 0.0)
	manager.update(target)
	manager.finish_all()
	var layer := manager.layer(&"stub")
	for chunk: Vector2i in _expected(layer, target, build):
		assert_true(stub.live.has(chunk), "built around the moved target %s" % chunk)


## TASK-189: an instant layer (one cheap node per chunk, no worker plan) is built by the scan
## itself: after a camera jump its whole build ring exists before the first process().
func test_an_instant_layer_builds_its_ring_in_the_update_that_finds_it() -> void:
	var stub := Stub.new()
	var manager := ChunkManager.new(_rings(20.0))
	manager.threads = true
	manager.budget_usec = 0
	var layer := ChunkLayer.new(&"stub", SIZE, AREA, stub.build, stub.free_chunk)
	layer.instant = true
	manager.register(layer)
	manager.update(Vector2.ZERO)
	var expected := _expected(layer, Vector2.ZERO, manager.build_radius(&"stub"))
	assert_eq(stub.live.size(), expected.size(), "the whole ring, no frame later")
	assert_true(stub.plans.values().all(func(p: Variant) -> bool: return p == null), "no plan")
	var target := Vector2(150.0, 150.0)
	manager.update(target)
	expected = _expected(layer, target, manager.build_radius(&"stub"))
	for chunk: Vector2i in expected:
		assert_true(stub.live.has(chunk), "%s built at once after the jump" % chunk)
	manager.finish_all()
	assert_eq(stub.live.size(), expected.size(), "the old ring freed as usual")
	assert_true(manager.is_settled())


## TASK-189: a layer of a higher priority is planned before any job of a lower one.
func test_a_higher_priority_layer_is_planned_first() -> void:
	var near := Stub.new()
	var first := Stub.new()
	var rings := ChunkRings.new()
	rings.reach_m = {
		&"near": 20.0 * MapScale.metres_per_unit, &"first": 20.0 * MapScale.metres_per_unit
	}
	var manager := ChunkManager.new(rings)
	manager.threads = false
	manager.budget_usec = 0
	manager.register(ChunkLayer.new(&"near", SIZE, AREA, near.build, near.free_chunk, near.plan))
	var layer := ChunkLayer.new(&"first", SIZE, AREA, first.build, first.free_chunk, first.plan)
	layer.priority = 1
	manager.register(layer)
	manager.update(Vector2.ZERO)
	var total := _expected(layer, Vector2.ZERO, manager.build_radius(&"first")).size()
	while first.live.size() < total:
		manager.process()
		assert_eq(near.live.size(), 0, "nothing of the lower priority before the higher is done")
	manager.finish_all()
	assert_true(near.live.size() > 0)


## TASK-189: instant builds stay within their budget per scan / process(), nearest first.
func test_instant_builds_are_budgeted_nearest_first() -> void:
	var stub := Stub.new()
	stub.delay_usec = 1500
	var manager := ChunkManager.new(_rings(40.0))
	manager.instant_budget_usec = 3000
	var layer := ChunkLayer.new(&"stub", SIZE, AREA, stub.build, stub.free_chunk)
	layer.instant = true
	manager.register(layer)
	manager.update(Vector2.ZERO)
	var total := _expected(layer, Vector2.ZERO, manager.build_radius(&"stub")).size()
	assert_true(
		stub.live.size() >= 1 and stub.live.size() <= 3, "%d in the scan" % stub.live.size()
	)
	assert_true(stub.live.has(Vector2i(0, 0)) or stub.live.has(Vector2i(-1, -1)), "nearest first")
	assert_false(manager.is_settled())
	var frames := 0
	while stub.live.size() < total and frames < 1000:
		var before := stub.live.size()
		manager.process()
		assert_true(stub.live.size() - before <= 3, "within the budget")
		frames += 1
	assert_eq(stub.live.size(), total)
	assert_true(manager.is_settled())


func test_loading_mode_plans_the_whole_queue_in_one_batch_and_builds_the_same_chunks() -> void:
	var stub := Stub.new()
	var manager := _manager(stub)
	manager.loading = true
	manager.update(Vector2.ZERO)
	var wanted := _expected(
		manager.layer(&"stub"), Vector2.ZERO, _rings(20.0).build_radius(&"stub")
	)
	assert_true(wanted.size() > ChunkManager.BATCH_SIZE, "more jobs than a play batch holds")
	var frames := 0
	while not manager.is_settled() and frames < 2000:
		manager.process()
		frames += 1
	assert_true(manager.is_settled(), "settled through process()")
	assert_eq(stub.live.keys().size(), wanted.size())
