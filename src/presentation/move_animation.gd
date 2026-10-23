class_name MoveAnimation
extends RefCounted
## Pure math for animating a unit along a path of world points (TASK-022): position along the
## polyline, facing of a segment and smooth turning. No nodes – tested headless.

## Seconds per path segment (one tile); matches EventQueue.SECONDS_PER_TILE.
const SECONDS_PER_TILE := EventQueue.SECONDS_PER_TILE
## Default turn rate: fraction of the remaining angle closed per second (`min(1, dt * rate)`).
const TURN_RATE := 6.0
## Time to accelerate from standstill to cruise speed (and to brake at the end of a move).
const ACCEL_TIME := 0.32
## Tracked vehicles pull away sluggishly and brake slowly (see HeavyMove).
const HEAVY_ACCEL_TIME := 1.2
## Wheeled vehicles: a softer start than infantry and a wide, smooth turn (no stopping to turn).
const WHEELED_ACCEL_TIME := 0.6
## Wheeled vehicles steer along the path: the heading looks this far (path seconds) ahead and
## behind, and a wrong initial heading is steered out over WHEELED_STEER_IN seconds.
const WHEELED_LOOK := 0.35
const WHEELED_STEER_IN := 0.9


## Yaw that makes a model facing +X at yaw 0 look from `from` towards `to` (XZ only).
static func facing_yaw(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.z - from.z), to.x - from.x)


## One frame of turning from `current` towards `target` along the shortest arc.
static func turn_towards(current: float, target: float, dt: float, rate := TURN_RATE) -> float:
	return current + wrap_angle(target - current) * minf(1.0, dt * rate)


## Wraps an angle to (-PI, PI].
static func wrap_angle(angle: float) -> float:
	var wrapped := fposmod(angle + PI, TAU) - PI
	return PI if wrapped == -PI else wrapped


## Total animation time of the polyline: one `seconds_per_tile` per segment.
static func duration(points: PackedVector3Array, seconds_per_tile := SECONDS_PER_TILE) -> float:
	return maxf(0.0, points.size() - 1) * seconds_per_tile


## Maps real animation time to path time (the time `sample()` expects) with a trapezoidal
## speed profile: accelerate over `accel_time`, cruise, brake over the last `accel_time`. Path
## time starts at 0 and reaches `duration` at `elapsed == duration`; the cruise speed rises so
## the total stays the same. A move shorter than two ramps never reaches cruise speed.
static func path_time(elapsed: float, duration: float, accel_time := ACCEL_TIME) -> float:
	if duration <= 0.0:
		return 0.0
	var t := clampf(elapsed, 0.0, duration)
	var ramp := minf(accel_time, duration / 2.0)
	if ramp <= 0.0:
		return t
	var cruise := duration / (duration - ramp)
	if t < ramp:
		return cruise * t * t / (2.0 * ramp)
	if t > duration - ramp:
		var left := duration - t
		return duration - cruise * left * left / (2.0 * ramp)
	return cruise * (t - ramp / 2.0)


## Index of the segment (`points[i] -> points[i + 1]`) being walked at `elapsed`, clamped to
## the last segment; 0 for fewer than two points.
static func segment_index(
	points: PackedVector3Array, elapsed: float, seconds_per_tile := SECONDS_PER_TILE
) -> int:
	var segments := points.size() - 1
	if segments < 1:
		return 0
	return clampi(floori(elapsed / seconds_per_tile), 0, segments - 1)


## End point of the segment being walked at `elapsed` (the point the unit should face).
## A single point returns that point; an empty array returns Vector3.ZERO.
static func segment_target(
	points: PackedVector3Array, elapsed: float, seconds_per_tile := SECONDS_PER_TILE
) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	if points.size() == 1:
		return points[0]
	return points[segment_index(points, elapsed, seconds_per_tile) + 1]


## Position at `elapsed` seconds: linear interpolation between consecutive points, clamped to
## the first/last point. `y` is interpolated too; the view replaces it with the ground height.
static func sample(
	points: PackedVector3Array, elapsed: float, seconds_per_tile := SECONDS_PER_TILE
) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	if points.size() == 1:
		return points[0]
	var i := segment_index(points, elapsed, seconds_per_tile)
	var t := clampf(elapsed / seconds_per_tile - i, 0.0, 1.0)
	return points[i].lerp(points[i + 1], t)


## Heading of a steered (wheeled) vehicle at `path_time`: along the chord from a little behind to
## a little ahead on the path, so it follows bends without lagging. The last stretch keeps the
## final segment's heading.
static func steered_yaw(
	points: PackedVector3Array,
	path_time_value: float,
	look := WHEELED_LOOK,
	seconds_per_tile := SECONDS_PER_TILE
) -> float:
	var from := sample(points, path_time_value - look, seconds_per_tile)
	var to := sample(points, path_time_value + look, seconds_per_tile)
	if Vector2(to.x - from.x, to.z - from.z).length_squared() < 0.0001:
		var i := segment_index(points, path_time_value, seconds_per_tile)
		return facing_yaw(points[i], points[i + 1])
	return facing_yaw(from, to)
