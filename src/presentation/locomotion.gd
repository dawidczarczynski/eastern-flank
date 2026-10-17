class_name Locomotion
extends RefCounted
## Pure math for unit locomotion (TASK-025): marching bob/sway of infantry, wheel spin and
## hull rocking / slope tilt of tanks. Everything is a function of the move's animation time or
## travelled distance – nothing advances from frame delta. Feel constants, not balance.

const ENVELOPE_RAMP := 0.08
const STEPS_PER_UNIT := 1.5
const STEP_BOB := 0.012
const STEP_SWAY := 0.06
const LEAN := -0.08
const WHEEL_RADIANS_PER_UNIT := 5.0
const HULL_PITCH := 0.012
const HULL_PITCH_FREQ := 0.9
const HULL_ROLL := 0.008
const HULL_ROLL_FREQ := 0.55
const HULL_ROLL_OFFSET := 1.3
const TILT_LIMIT := 0.35
const HALF_LENGTH := 0.45
const HALF_WIDTH := 0.26


## XZ length travelled along the polyline at `elapsed`, clamped to the total length.
static func travelled(
	points: PackedVector3Array, elapsed: float, seconds_per_tile := MoveAnimation.SECONDS_PER_TILE
) -> float:
	if points.size() < 2:
		return 0.0
	var total := 0.0
	var remaining := maxf(0.0, elapsed)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := Vector2(b.x - a.x, b.z - a.z).length()
		if remaining >= seconds_per_tile:
			total += length
			remaining -= seconds_per_tile
		else:
			total += length * remaining / seconds_per_tile
			break
	return total


## Fade in / out factor 0..1: motion ramps up over the first and down over the last `ramp`.
static func envelope(elapsed: float, duration: float, ramp := ENVELOPE_RAMP) -> float:
	if duration <= 0.0:
		return 0.0
	return clampf(minf(elapsed, duration - elapsed) / ramp, 0.0, 1.0)


static func step_phase(i: int) -> float:
	return TerrainNoise.hash(i, 11.0, 4.0)


static func _steps(distance: float, phase: float) -> float:
	return distance * STEPS_PER_UNIT + phase


## Vertical bob of a soldier (soldier-local units), without envelope.
static func step_bob(distance: float, phase: float) -> float:
	return STEP_BOB * absf(sin(PI * _steps(distance, phase)))


## Side sway (radians, rotation.x) of a soldier, without envelope.
static func step_sway(distance: float, phase: float) -> float:
	return STEP_SWAY * sin(PI * _steps(distance, phase))


static func wheel_angle(distance: float) -> float:
	return -distance * WHEEL_RADIANS_PER_UNIT


## Hull rocking: x = pitch (rotation.z), y = roll (rotation.x), without envelope.
static func hull_bob(distance: float) -> Vector2:
	return Vector2(
		HULL_PITCH * sin(TAU * HULL_PITCH_FREQ * distance),
		HULL_ROLL * sin(TAU * HULL_ROLL_FREQ * distance + HULL_ROLL_OFFSET)
	)


## Terrain tilt under a hull at `center` facing `yaw`: x = pitch (nose up > 0), y = roll
## (right side down > 0). `ground_height` is a Callable (x, z) -> float.
static func slope_tilt(
	ground_height: Callable,
	center: Vector3,
	yaw: float,
	half_length := HALF_LENGTH,
	half_width := HALF_WIDTH
) -> Vector2:
	if not ground_height.is_valid():
		return Vector2.ZERO
	var forward := Vector3(cos(yaw), 0.0, -sin(yaw))
	var right := Vector3(sin(yaw), 0.0, cos(yaw))
	var front := center + forward * half_length
	var back := center - forward * half_length
	var r := center + right * half_width
	var l := center - right * half_width
	var h_front: float = ground_height.call(front.x, front.z)
	var h_back: float = ground_height.call(back.x, back.z)
	var h_right: float = ground_height.call(r.x, r.z)
	var h_left: float = ground_height.call(l.x, l.z)
	return Vector2(
		clampf(atan2(h_front - h_back, 2.0 * half_length), -TILT_LIMIT, TILT_LIMIT),
		clampf(atan2(h_left - h_right, 2.0 * half_width), -TILT_LIMIT, TILT_LIMIT)
	)
