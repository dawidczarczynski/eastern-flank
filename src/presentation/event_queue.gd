class_name EventQueue
extends RefCounted
## Pure FIFO of simulation events waiting to be animated by the view. It knows how long each
## event type takes to play and computes the playback speed for a burst, so that a long burst
## (e.g. a whole AI turn) never takes noticeably longer than MAX_BURST_SECONDS. No nodes/tweens.

## Upper bound for the playback time of one burst at its computed speed, in seconds.
const MAX_BURST_SECONDS := 3.0
const MOVE_DURATION := 0.25
const ATTACK_DURATION := 0.25
const DEATH_DURATION := 0.4

var _events: Array[Dictionary] = []


func push(event: Dictionary) -> void:
	_events.append(event)


## Removes and returns the oldest event, or `{}` when the queue is empty.
func pop() -> Dictionary:
	if _events.is_empty():
		return {}
	return _events.pop_front()


func is_empty() -> bool:
	return _events.is_empty()


func size() -> int:
	return _events.size()


## Animation time of an event at speed 1.0; events without an animation take 0.0.
static func base_duration(event: Dictionary) -> float:
	match event.get("type", &""):
		&"unit_moved":
			return MOVE_DURATION
		&"unit_attacked":
			return ATTACK_DURATION
		&"unit_died":
			return DEATH_DURATION
		_:
			return 0.0


## Sum of base_duration() over all queued events.
func pending_duration() -> float:
	var total := 0.0
	for event in _events:
		total += base_duration(event)
	return total


## Playback speed for the burst about to play (the currently queued events). The caller keeps
## it fixed until the queue is empty again. Never below 1.0.
func begin_burst() -> float:
	return maxf(1.0, pending_duration() / MAX_BURST_SECONDS)
