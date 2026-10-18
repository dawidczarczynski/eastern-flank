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
