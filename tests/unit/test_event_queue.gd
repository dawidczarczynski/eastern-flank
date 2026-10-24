extends TestCase

const TOLERANCE := 0.0001


func _queue_of(types: Array[StringName]) -> EventQueue:
	var queue := EventQueue.new()
	for type in types:
		queue.push({"type": type})
	return queue


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
	var expected := (
		EventQueue.MOVE_DURATION + EventQueue.ATTACK_DURATION + EventQueue.DEATH_DURATION
	)
	assert_true(
		absf(queue.pending_duration() - expected) < TOLERANCE, "got %f" % queue.pending_duration()
	)


func _queue_lasting(seconds: float, count: int) -> EventQueue:
	var queue := EventQueue.new()
	for i in count:
		queue.push(EventQueue.with_view_duration({"type": &"unit_moved"}, seconds / count))
	return queue


func test_burst_up_to_the_cap_plays_at_normal_speed() -> void:
	var queue := _queue_lasting(EventQueue.MAX_BURST_SECONDS, 8)
	assert_true(absf(queue.begin_burst() - 1.0) < TOLERANCE)


func test_burst_of_twice_the_cap_plays_at_double_speed() -> void:
	var queue := _queue_lasting(EventQueue.MAX_BURST_SECONDS * 2.0, 8)
	assert_true(absf(queue.begin_burst() - 2.0) < TOLERANCE)


func test_empty_queue_burst_speed_is_one() -> void:
	assert_eq(EventQueue.new().begin_burst(), 1.0)


func test_turn_events_have_no_duration() -> void:
	var queue := _queue_of([&"turn_ended", &"turn_started"])
	assert_eq(queue.pending_duration(), 0.0)
	assert_eq(queue.begin_burst(), 1.0)


func test_move_with_path_lasts_per_tile() -> void:
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var event := {"type": &"unit_moved", "path": path}
	assert_true(absf(EventQueue.base_duration(event) - EventQueue.SECONDS_PER_TILE * 3) < TOLERANCE)


func test_move_without_path_keeps_default_duration() -> void:
	var duration := EventQueue.base_duration({"type": &"unit_moved"})
	assert_true(absf(duration - EventQueue.MOVE_DURATION) < TOLERANCE)


func test_view_duration_annotation_overrides_base_duration() -> void:
	var event := {"type": &"unit_attacked", "attacker_id": 1}
	var annotated := EventQueue.with_view_duration(event, 1.5)
	assert_false(event.has(EventQueue.VIEW_DURATION_KEY), "original event must stay untouched")
	assert_true(absf(EventQueue.base_duration(annotated) - 1.5) < TOLERANCE)
	var queue := EventQueue.new()
	queue.push(annotated)
	queue.push({"type": &"unit_attacked"})
	assert_true(absf(queue.pending_duration() - 1.5 - EventQueue.ATTACK_DURATION) < TOLERANCE)


func test_long_volley_speeds_up_burst() -> void:
	var queue := EventQueue.new()
	for i in 4:
		var seconds := EventQueue.MAX_BURST_SECONDS / 2.0
		queue.push(EventQueue.with_view_duration({"type": &"unit_attacked"}, seconds))
	assert_true(absf(queue.begin_burst() - 2.0) < TOLERANCE)


func _volley(seconds: float) -> Dictionary:
	var event := EventQueue.with_view_duration({"type": &"unit_attacked"}, seconds)
	event[EventQueue.VIEW_FX_KEY] = EventQueue.FX_ROCKET_VOLLEY
	return event


func _one_tile_move() -> Dictionary:
	var path: Array[Vector2i] = [Vector2i(1, 0)]
	return {"type": &"unit_moved", "path": path}


func test_volleys_do_not_speed_up_the_burst() -> void:
	var queue := EventQueue.new()
	queue.push(_volley(10.0))
	queue.push(_volley(10.0))
	for i in 12:
		queue.push(_one_tile_move())
	assert_true(absf(queue.burst_duration() - 9.6) < TOLERANCE, "%f" % queue.burst_duration())
	assert_true(absf(queue.begin_burst() - 1.2) < TOLERANCE, "%f" % queue.begin_burst())
	assert_true(absf(queue.pending_duration() - 29.6) < TOLERANCE, "volleys still pending")


func test_only_volleys_play_at_normal_speed() -> void:
	var queue := EventQueue.new()
	queue.push(_volley(10.0))
	queue.push(_volley(10.0))
	assert_true(absf(queue.begin_burst() - 1.0) < TOLERANCE)
	assert_true(absf(queue.pending_duration() - 20.0) < TOLERANCE)


func test_volley_playback_speed_is_capped() -> void:
	var volley := _volley(10.0)
	assert_true(absf(EventQueue.playback_speed(volley, 3.0) - 1.5) < TOLERANCE)
	assert_true(absf(EventQueue.playback_speed(volley, 1.0) - 1.0) < TOLERANCE)
	assert_true(absf(EventQueue.playback_speed(_one_tile_move(), 3.0) - 3.0) < TOLERANCE)
