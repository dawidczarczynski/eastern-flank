class_name GroundMarks
extends RefCounted
## Pure planner for the ground decals of TASK-058: track and tyre marks behind moving vehicles,
## shell craters and scorch marks. It decides what is drawn where; GroundMarksView makes the
## Decal nodes. Randomness comes from a hash-seeded RandomNumberGenerator keyed by the view's
## own event index, never GameState.rng, so replays look the same.
## A mark is a Dictionary {kind, center: Vector3, yaw, pitch, length, width}; track marks also
## have `segment` (index in the path) and `pitch` is their slope. Round marks have
## length == width == the diameter.

const KIND_TRACK := &"track"
const KIND_TYRE := &"tyre"
const KIND_CRATER := &"crater"
const KIND_SCORCH := &"scorch"
## The wide black burnt ground a destroyed vehicle stands on.
const KIND_BURNT := &"burnt"

## Mark widths in world units at the `current` unit scale preset (VisualScale 1.3).
const TANK_WIDTH := 0.42
const MLRS_WIDTH := 0.34
const REFERENCE_UNIT_SCALE := 1.3
## Track marks overlap their neighbour a little so a turning path leaves no gap.
const TRACK_OVERLAP := 0.06
## How far behind the vehicle's position the visible end of a track mark sits (world units):
## under the rear of the hull, so the mark seems to be laid by the tracks.
const TRACK_REAR_OFFSET := 0.2
const CRATER_MIN := 2
const CRATER_MAX := 3
## Craters lie within this distance of the target tile centre; radius range.
const CRATER_SPREAD := 0.35
const CRATER_RADIUS_MIN := 0.10
const CRATER_RADIUS_MAX := 0.16
const IMPACT_SCORCH_RADIUS := 0.25
const DEATH_SCORCH_RADIUS := 0.35
const WRECK_BURNT_RADIUS := 0.95
## Minimum attack range and target distance (tiles) of fire that craters the ground.
const INDIRECT_RANGE := 2
const INDIRECT_DISTANCE := 2
const _EVENT_SALT := 58027


## Marks for walking `path_world` (tile centres including the start), one per segment.
## `unit_scale` is VisualScale.unit_model_scale(); the widths follow it relative to the
## `current` preset. Infantry and unknown classes leave nothing.
static func track_segments(
	path_world: PackedVector3Array, unit_class: StringName, unit_scale := REFERENCE_UNIT_SCALE
) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	var kind: StringName
	var width: float
	match unit_class:
		&"tank":
			kind = KIND_TRACK
			width = TANK_WIDTH
		&"mlrs":
			kind = KIND_TYRE
			width = MLRS_WIDTH
		_:
			return marks
	width *= unit_scale / REFERENCE_UNIT_SCALE
	for i in range(path_world.size() - 1):
		var from := path_world[i]
		var to := path_world[i + 1]
		if Vector2(to.x - from.x, to.z - from.z).length_squared() < 0.000001:
			continue
		var flat := Vector2(to.x - from.x, to.z - from.z).length()
		var mark := {
			"kind": kind,
			"segment": i,
			"center": (from + to) * 0.5,
			"yaw": MoveAnimation.facing_yaw(from, to),
			"pitch": atan2(to.y - from.y, flat),
			"length": flat,
			"width": width,
		}
		marks.append(mark)
	return marks


## Whether fire from an attacker with `attacker_range` at a target `distance` tiles away is
## indirect (rocket) fire that leaves marks; counter-attacks and direct fire do not.
static func is_indirect(attacker_range: int, distance: int, counter: bool) -> bool:
	return not counter and attacker_range >= INDIRECT_RANGE and distance >= INDIRECT_DISTANCE


## 2-3 craters around the target tile centre; empty for direct fire and counter-attacks.
static func craters(
	event_index: int, target_center: Vector3, attacker_range: int, distance: int, counter: bool
) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	if not is_indirect(attacker_range, distance, counter):
		return marks
	var rng := _rng(event_index, 1)
	var count := rng.randi_range(CRATER_MIN, CRATER_MAX)
	for i in count:
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf()) * CRATER_SPREAD
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
		marks.append(
			_round_mark(
				KIND_CRATER, target_center + offset, rng, CRATER_RADIUS_MIN, CRATER_RADIUS_MAX
			)
		)
	return marks


## The scorch blob that goes with the craters of the same event (empty without craters).
static func impact_scorch(
	event_index: int, target_center: Vector3, attacker_range: int, distance: int, counter: bool
) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	if is_indirect(attacker_range, distance, counter):
		var rng := _rng(event_index, 2)
		marks.append(
			_round_mark(KIND_SCORCH, target_center, rng, IMPACT_SCORCH_RADIUS, IMPACT_SCORCH_RADIUS)
		)
	return marks


## The scorched patch a destroyed unit leaves on its tile.
static func death_scorch(event_index: int, center: Vector3) -> Dictionary:
	return _round_mark(
		KIND_SCORCH, center, _rng(event_index, 3), DEATH_SCORCH_RADIUS, DEATH_SCORCH_RADIUS
	)


## The burnt ground around a destroyed vehicle: wider than its hull, solid black near it.
static func wreck_burnt(event_index: int, center: Vector3) -> Dictionary:
	return _round_mark(
		KIND_BURNT, center, _rng(event_index, 4), WRECK_BURNT_RADIUS, WRECK_BURNT_RADIUS
	)


## Revealed share (0..1) of every path segment's track mark when the unit has walked
## `path_time` (MoveAnimation path time: SECONDS_PER_TILE per segment, `sample()`'s argument):
## the marks are drawn from the start up to the unit's position minus `rear_offset`, measured
## along the path in the ground plane. Index = path segment; zero-length segments count as
## revealed. At or after the end of the path everything is revealed.
static func reveal_fractions(
	points: PackedVector3Array, path_time: float, rear_offset := TRACK_REAR_OFFSET
) -> PackedFloat32Array:
	var segments := maxi(0, points.size() - 1)
	var fractions := PackedFloat32Array()
	fractions.resize(segments)
	var lengths := PackedFloat32Array()
	lengths.resize(segments)
	var starts := PackedFloat32Array()
	starts.resize(segments)
	var total := 0.0
	for i in segments:
		starts[i] = total
		lengths[i] = Vector2(points[i + 1].x - points[i].x, points[i + 1].z - points[i].z).length()
		total += lengths[i]
	var done := path_time >= segments * MoveAnimation.SECONDS_PER_TILE
	var head := total
	if not done:
		var i := MoveAnimation.segment_index(points, maxf(path_time, 0.0))
		var t := clampf(path_time / MoveAnimation.SECONDS_PER_TILE - i, 0.0, 1.0)
		head = starts[i] + t * lengths[i] - rear_offset
	for i in segments:
		fractions[i] = (
			1.0 if lengths[i] <= 0.0001 else clampf((head - starts[i]) / lengths[i], 0.0, 1.0)
		)
	return fractions


static func _round_mark(
	kind: StringName,
	center: Vector3,
	rng: RandomNumberGenerator,
	radius_min: float,
	radius_max: float
) -> Dictionary:
	var diameter := 2.0 * rng.randf_range(radius_min, radius_max)
	return {
		"kind": kind,
		"center": center,
		"yaw": rng.randf() * TAU,
		"pitch": 0.0,
		"length": diameter,
		"width": diameter,
	}


static func _rng(event_index: int, stream: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_EVENT_SALT, event_index, stream])
	return rng


## Bounded set of decal handles with the eviction order of the task: when full, the oldest
## track or tyre mark goes first, then the oldest crater, scorch marks last.
class Pool:
	extends RefCounted

	var max_count: int
	## Entries {kind, handle} oldest first.
	var _entries: Array[Dictionary] = []

	func _init(max_marks: int) -> void:
		max_count = maxi(0, max_marks)

	func size() -> int:
		return _entries.size()

	## Adds a mark and returns the handles that had to go (the new one itself when max is 0).
	func add(kind: StringName, handle: Variant) -> Array:
		var evicted: Array = []
		if max_count == 0:
			evicted.append(handle)
			return evicted
		_entries.append({"kind": kind, "handle": handle})
		while _entries.size() > max_count:
			evicted.append(_evict_one())
		return evicted

	func _evict_one() -> Variant:
		# Tracks and tyre marks share the first class; the others follow in order.
		for rank in 3:
			for i in _entries.size() - 1:  # never the mark that was just added
				if _rank(_entries[i]["kind"]) == rank:
					return _entries.pop_at(i)["handle"]
		return _entries.pop_front()["handle"]

	static func _rank(kind: StringName) -> int:
		match kind:
			GroundMarks.KIND_TRACK, GroundMarks.KIND_TYRE:
				return 0
			GroundMarks.KIND_CRATER:
				return 1
			_:
				return 2
