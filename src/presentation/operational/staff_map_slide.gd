class_name StaffMapSlide
extends RefCounted
## The playback of the counters' slide (TASK-092e) for StaffMap: collects the formation_moved
## events of one command, starts them together when the command is over, advances them with
## frame time and writes the sliding positions over the formations' anchors. The state is final
## all along; ending the slide (time or skip) just stops overriding the anchors.

var _pending := StaffMapMoveAnimation.new()
var _playing: StaffMapMoveAnimation
var _time := 0.0


## Remembers the walk of a formation_moved event for the next begin().
func collect(event: Dictionary) -> void:
	if event.get("type") == &"formation_moved":
		_pending.add_walk(event["formation_id"], event["from"], event["path"])


## Starts everything collected; false when nothing moved.
func begin() -> bool:
	if _pending.is_empty():
		return false
	_playing = _pending
	_pending = StaffMapMoveAnimation.new()
	_time = 0.0
	return true


func is_playing() -> bool:
	return _playing != null


## Advances by `delta` seconds; true when the slide just ended.
func advance(delta: float) -> bool:
	if _playing == null:
		return false
	_time += delta
	if _playing.is_finished(_time):
		_playing = null
		return true
	return false


## Ends the slide at once; true when one was running.
func skip() -> bool:
	var was := _playing != null
	_playing = null
	return was


## Puts the sliding formations' anchors (world points on the relief) where the slide has them.
func override_anchors(anchors: Dictionary, relief: StaffMapRelief) -> void:
	if _playing == null:
		return
	for id: StringName in _playing.ids():
		anchors[id] = relief.surface_point(_playing.position_at(id, _time))
