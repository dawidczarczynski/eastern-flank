extends TestCase

const TOLERANCE := 0.0001


func _queue_of(types: Array[StringName]) -> EventQueue:
	var queue := EventQueue.new()
	for type in types:
		queue.push({"type": type})
	return queue


func _repeat(type: StringName, count: int) -> Array[StringName]:
	var types: Array[StringName] = []
	for i in count:
		types.append(type)
	return types


func test_pop_returns_events_in_fifo_order_then_empty() -> void:
	var queue := _queue_of([&"unit_moved", &"unit_attacked", &"unit_died"])
	assert_eq(queue.size(), 3)
	assert_eq(queue.pop()["type"], &"unit_moved")
	assert_eq(queue.pop()["type"], &"unit_attacked")
	assert_eq(queue.pop()["type"], &"unit_died")
	assert_true(queue.is_empty())
	assert_eq(queue.pop(), {})


func test_pending_duration_sums_base_durations() -> void:
	var queue := _queue_of([&"unit_moved", &"unit_attacked", &"unit_died", &"turn_started"])
	assert_true(
		absf(queue.pending_duration() - 0.9) < TOLERANCE, "got %f" % queue.pending_duration()
	)


func test_burst_of_three_seconds_plays_at_normal_speed() -> void:
	var queue := _queue_of(_repeat(&"unit_moved", 12))
	assert_true(absf(queue.begin_burst() - 1.0) < TOLERANCE)


func test_burst_of_six_seconds_plays_at_double_speed() -> void:
	var queue := _queue_of(_repeat(&"unit_moved", 24))
	assert_true(absf(queue.begin_burst() - 2.0) < TOLERANCE)


func test_empty_queue_burst_speed_is_one() -> void:
	assert_eq(EventQueue.new().begin_burst(), 1.0)


func test_turn_events_have_no_duration() -> void:
	var queue := _queue_of([&"turn_ended", &"turn_started"])
	assert_eq(queue.pending_duration(), 0.0)
	assert_eq(queue.begin_burst(), 1.0)
