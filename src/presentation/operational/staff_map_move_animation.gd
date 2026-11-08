class_name StaffMapMoveAnimation
extends RefCounted
## The cosmetic slide of counters at the end of a move (TASK-092e), pure timing and path maths:
## every moving formation walks its `path` hex by hex, SECONDS_PER_HEX each, capped at
## MAX_SECONDS per formation; all formations run at once. The state is already final when this
## starts – the animation only decides where a counter is drawn at time t (world xz, hex units;
## StaffMap puts that on the relief). Past the end every formation stands on its last hex.

const SECONDS_PER_HEX := 0.4
const MAX_SECONDS := 2.5

var _tracks := {}  # formation id -> Array[Vector2] (world xz of from, then every hex entered)


## Adds the walk of one formation: `from` and the hexes entered (a formation_moved event).
func add_walk(formation_id: StringName, from: Vector2i, path: Array) -> void:
	var points: Array[Vector2] = [_world(from)]
	for c: Vector2i in path:
		points.append(_world(c))
	_tracks[formation_id] = points


func is_empty() -> bool:
	return _tracks.is_empty()


func ids() -> Array:
	return _tracks.keys()


## Seconds the formation's slide takes.
func duration_of(formation_id: StringName) -> float:
	var points: Array = _tracks.get(formation_id, [])
	return minf(SECONDS_PER_HEX * maxi(points.size() - 1, 0), MAX_SECONDS)


## Seconds until every formation stood still.
func total() -> float:
	var longest := 0.0
	for id: StringName in _tracks:
		longest = maxf(longest, duration_of(id))
	return longest


func is_finished(t: float) -> bool:
	return t >= total()


## World xz position of the formation at time `t` (Vector2.ZERO for an unknown id).
func position_at(formation_id: StringName, t: float) -> Vector2:
	var points: Array = _tracks.get(formation_id, [])
	if points.is_empty():
		return Vector2.ZERO
	var duration := duration_of(formation_id)
	if duration <= 0.0 or t >= duration:
		return points[points.size() - 1]
	var along := maxf(t, 0.0) / duration * (points.size() - 1)
	var index := mini(int(along), points.size() - 2)
	return (points[index] as Vector2).lerp(points[index + 1], along - index)


static func _world(c: Vector2i) -> Vector2:
	var w := Hex.to_world(c, 1.0)
	return Vector2(w.x, w.z)
