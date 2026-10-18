class_name EventQueue
extends RefCounted
## Pure FIFO of simulation events waiting to be animated by the view. It knows how long each
## event type takes to play and computes the playback speed for a burst, so that a long burst
## (e.g. a whole AI turn) never takes noticeably longer than MAX_BURST_SECONDS. No nodes/tweens.

## Upper bound for the playback time of one burst at its computed speed, in seconds.
const MAX_BURST_SECONDS := 8.0
## Duration of a move event without a `path` (old events).
const MOVE_DURATION := 0.55
## Duration of one tile of a move along its `path` (TASK-022); MoveAnimation aliases it.
const SECONDS_PER_TILE := 0.55
const ATTACK_DURATION := 0.4
const DEATH_DURATION := 0.85
## View-only event annotation: the controller sets it (seconds at speed 1) on events whose
## animation is longer than the default, e.g. a rocket volley. See with_view_duration().
const VIEW_DURATION_KEY := &"view_duration"
## View-only event annotation naming the effect to play (e.g. FX_ROCKET_VOLLEY).
const VIEW_FX_KEY := &"view_fx"
const FX_ROCKET_VOLLEY := &"rocket_volley"

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


## Copy of `event` annotated with its animation time; the simulation's event stays untouched.
static func with_view_duration(event: Dictionary, seconds: float) -> Dictionary:
	var copy := event.duplicate()
	copy[VIEW_DURATION_KEY] = seconds
	return copy


## Animation time of an event at speed 1.0; events without an animation take 0.0. An event
## carrying VIEW_DURATION_KEY plays for exactly that long.
static func base_duration(event: Dictionary) -> float:
	if event.has(VIEW_DURATION_KEY):
		return float(event[VIEW_DURATION_KEY])
	match event.get("type", &""):
		&"unit_moved":
			if event.has("path"):
				return SECONDS_PER_TILE * (event["path"] as Array).size()
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
