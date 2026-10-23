class_name HeavyMove
extends RefCounted
## Timeline of a tracked / wheeled vehicle driving a path: it never turns while rolling. At the
## start and at every bend it stops, pivots in place to the new heading and only then drives off;
## straight stretches (consecutive segments with the same heading) are driven as one run with a
## slow acceleration and braking. Pure math, a function of the move's animation time only; the
## move lasts longer than MoveAnimation.duration() by the time of the pivots.

## Pivot speed (radians per second) and the shortest pivot.
const PIVOT_RATE := 1.0
const PIVOT_MIN := 0.3
## A heading change below this is no turn (radians).
const TURN_EPSILON := 0.03

const PIVOT := &"pivot"
const DRIVE := &"drive"


## Phases of the move along world `points` for a hull facing `start_yaw`: {kind, t0, t1, yaw0,
## yaw1, path0 (path time at the start of the run)}, plus `duration` and `path_end` (path time of
## the last point). A pivot's `path0` is that of the run which follows it.
static func plan(points: PackedVector3Array, start_yaw: float) -> Dictionary:
	var phases: Array[Dictionary] = []
	var segments := points.size() - 1
	var t := 0.0
	var yaw := start_yaw
	var i := 0
	while i < segments:
		var heading := _heading(points, i, yaw)
		var diff := MoveAnimation.wrap_angle(heading - yaw)
		var path0 := i * MoveAnimation.SECONDS_PER_TILE
		if absf(diff) > TURN_EPSILON:
			var seconds := maxf(PIVOT_MIN, absf(diff) / PIVOT_RATE)
			phases.append(_phase(PIVOT, t, t + seconds, yaw, heading, path0))
			t += seconds
			yaw = heading
		var last := i
		while (
			last + 1 < segments
			and (
				absf(MoveAnimation.wrap_angle(_heading(points, last + 1, heading) - heading))
				<= TURN_EPSILON
			)
		):
			last += 1
		var seconds := (last - i + 1) * MoveAnimation.SECONDS_PER_TILE
		phases.append(_phase(DRIVE, t, t + seconds, yaw, yaw, path0))
		t += seconds
		i = last + 1
	return {
		"phases": phases,
		"duration": t,
		"path_end": maxf(0.0, segments) * MoveAnimation.SECONDS_PER_TILE,
		"end_yaw": yaw,
	}


## State at `elapsed`: {path_time (MoveAnimation.sample's argument), yaw, driving, run_t,
## run_duration (progress inside the current phase), turn_left (radians still to pivot)}.
static func pose(move: Dictionary, elapsed: float) -> Dictionary:
	var phases: Array = move["phases"]
	var e := clampf(elapsed, 0.0, move["duration"])
	for index in phases.size():
		var phase: Dictionary = phases[index]
		if e > phase["t1"] and index < phases.size() - 1:
			continue
		var length: float = phase["t1"] - phase["t0"]
		var local := clampf(e - phase["t0"], 0.0, length)
		if phase["kind"] == PIVOT:
			var u := smoothstep(0.0, 1.0, local / length)
			var diff := MoveAnimation.wrap_angle(phase["yaw1"] - phase["yaw0"])
			return {
				"path_time": phase["path0"],
				"yaw": phase["yaw0"] + diff * u,
				"driving": false,
				"run_t": local,
				"run_duration": length,
				"turn_left": diff * (1.0 - u),
			}
		var path: float = (
			phase["path0"] + MoveAnimation.path_time(local, length, MoveAnimation.HEAVY_ACCEL_TIME)
		)
		return {
			"path_time": path,
			"yaw": phase["yaw1"],
			"driving": true,
			"run_t": local,
			"run_duration": length,
			"turn_left": 0.0,
		}
	return {
		"path_time": move["path_end"],
		"yaw": move["end_yaw"],
		"driving": false,
		"run_t": 0.0,
		"run_duration": 0.0,
		"turn_left": 0.0,
	}


static func _phase(
	kind: StringName, t0: float, t1: float, yaw0: float, yaw1: float, path0: float
) -> Dictionary:
	return {"kind": kind, "t0": t0, "t1": t1, "yaw0": yaw0, "yaw1": yaw1, "path0": path0}


## Heading of segment `i`; `fallback` for a zero-length one.
static func _heading(points: PackedVector3Array, i: int, fallback: float) -> float:
	var a := points[i]
	var b := points[i + 1]
	if Vector2(b.x - a.x, b.z - a.z).length_squared() < 0.000001:
		return fallback
	return MoveAnimation.facing_yaw(a, b)
