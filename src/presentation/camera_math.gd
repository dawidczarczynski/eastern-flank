class_name CameraMath
extends RefCounted
## Pure camera formulas (no nodes), shared by CameraRig and tested in tests/unit/.

## Zoom range (TASK-111): MIN_DISTANCE 0.18 units is ~26 m at the 250 m hex scale, close enough
## to look at a real-size vehicle (TASK-110 zoom study); MAX_DISTANCE shows the whole map.
const MIN_DISTANCE := 0.18
const MAX_DISTANCE := 46.0
## Closer than this the camera is in its close range: it looks at the ground under the target
## (look_height), its ground clearance shrinks with the square of the distance (clearance) and the
## pitch stays at PITCH_CLOSE. It was the closest zoom before TASK-111.
const CLOSE_RANGE_DISTANCE := 7.0
## Group-drawing hook (TASK-136): closer than this a unit may be drawn as a 3-4 model group, its
## marker stays; farther only the marker and the single model. Compared with
## UnitView.distance_to_camera.
const GROUP_DRAW_DISTANCE := 3.0
## Every wheel notch multiplies (out) or divides (in) the distance by this factor, so the zoom feels
## the same at every distance: 46 -> 0.18 in 25 notches.
const ZOOM_STEP_FACTOR := 1.25
## The camera never goes lower than this many metres above the drawn ground (MapScale converts).
const MIN_HEIGHT_METRES := 2.0
## Near clip plane: NEAR_PLANE_PER_DISTANCE x the distance, within [NEAR_PLANE_MIN, NEAR_PLANE_MAX]
## (0.1 = the scene's value at the default zoom, 0.009 at MIN_DISTANCE).
const NEAR_PLANE_PER_DISTANCE := 0.05
const NEAR_PLANE_MIN := 0.005
const NEAR_PLANE_MAX := 0.1
const PAN_PER_PIXEL := 0.0016  # world units per pixel per unit of distance
const DRAG_THRESHOLD := 4.0  # pixels

## Pitch curve control points (distance, pitch in radians), TASK-052: close up the horizon is in
## frame (pitch < half the vertical FOV), the default shows far land at the top, zoomed out is
## nearly top-down. Piecewise linear between them, flat PITCH_CLOSE in the close range (down to
## MIN_DISTANCE: towards the horizon, TASK-111) and clamped beyond MAX_DISTANCE.
const PITCH_CLOSE := 0.30  # at CLOSE_RANGE_DISTANCE and closer, ~17 degrees
const PITCH_DEFAULT := 0.56  # at PITCH_DEFAULT_DISTANCE, ~32 degrees
const PITCH_DEFAULT_DISTANCE := 24.0
const PITCH_FAR := 1.05  # at MAX_DISTANCE, ~60 degrees
## The camera never goes lower than this above the ground under it (at CLOSE_RANGE_DISTANCE and
## farther; closer see clearance()).
const GROUND_CLEARANCE := 1.5
const CLEAR_PITCH_ITERATIONS := 8

## Player tilt (TASK-052 revision): an offset in radians added to the distance curve. Positive =
## more top-down, negative = towards the horizon. The result never leaves [PITCH_MIN, PITCH_MAX].
const PITCH_OFFSET_LIMIT := 0.35  # ~20 degrees either way
const PITCH_MIN := 0.14  # ~8 degrees
const PITCH_MAX := PI / 2.0
const TILT_STEP := 0.05  # radians per Ctrl+wheel notch
const TILT_KEY_SPEED := 0.6  # rad/s while R/F is held
const TILT_MOUSE_SPEED := 0.004  # rad/px of vertical middle-mouse drag
const TILT_RESET_SECONDS := 0.3  # a full-range offset returns to 0 in this time


## Camera pitch above the horizon (radians): flatter when close, more top-down when far.
static func pitch_for_distance(d: float) -> float:
	if d <= PITCH_DEFAULT_DISTANCE:
		var t := clampf(
			(d - CLOSE_RANGE_DISTANCE) / (PITCH_DEFAULT_DISTANCE - CLOSE_RANGE_DISTANCE), 0.0, 1.0
		)
		return lerpf(PITCH_CLOSE, PITCH_DEFAULT, t)
	var t := clampf(
		(d - PITCH_DEFAULT_DISTANCE) / (MAX_DISTANCE - PITCH_DEFAULT_DISTANCE), 0.0, 1.0
	)
	return lerpf(PITCH_DEFAULT, PITCH_FAR, t)


## The offset limited to +-PITCH_OFFSET_LIMIT.
static func clamp_pitch_offset(offset: float) -> float:
	return clampf(offset, -PITCH_OFFSET_LIMIT, PITCH_OFFSET_LIMIT)


## The distance curve shifted by the player's (clamped) tilt offset, within [PITCH_MIN, PITCH_MAX].
static func pitch_with_offset(d: float, offset: float) -> float:
	return clampf(pitch_for_distance(d) + clamp_pitch_offset(offset), PITCH_MIN, PITCH_MAX)


## New offset after tilting `amount` radians towards the horizon (negative = towards top-down).
static func tilt_toward_horizon(offset: float, amount: float) -> float:
	return clamp_pitch_offset(offset - amount)


## Ctrl+wheel: positive notches (wheel up) tilt towards the horizon by TILT_STEP each.
static func tilt_step(offset: float, notches: float) -> float:
	return tilt_toward_horizon(offset, notches * TILT_STEP)


## One reset animation frame: moves the offset towards 0 at a constant speed, never overshooting.
static func reset_offset(offset: float, delta: float) -> float:
	var step := PITCH_OFFSET_LIMIT / TILT_RESET_SECONDS * delta
	return move_toward(offset, 0.0, step)


## Smallest pitch (radians) that puts the camera at least GROUND_CLEARANCE above `ground_height`,
## for a look-at point at `target_height` and distance `d`. Between 0 and straight down.
static func min_pitch_for_ground(
	ground_height: float, target_height: float, d: float, clearance := GROUND_CLEARANCE
) -> float:
	var needed := (ground_height + clearance - target_height) / d
	return asin(clampf(needed, 0.0, 1.0))


## Offset from the look-at point to the camera. Yaw 0 = camera on the +Z side. `min_pitch` raises
## the pitch above the (offset) curve (ground clearance, see min_pitch_for_ground).
static func camera_offset(yaw: float, d: float, min_pitch := 0.0, pitch_offset := 0.0) -> Vector3:
	return camera_offset_at_pitch(yaw, d, maxf(pitch_with_offset(d, pitch_offset), min_pitch))


## Offset from the look-at point for exactly this pitch (no curve, no floor).
static func camera_offset_at_pitch(yaw: float, d: float, p: float) -> Vector3:
	return Vector3(sin(yaw) * cos(p) * d, sin(p) * d, cos(yaw) * cos(p) * d)


## Positive notches zoom out, negative zoom in (geometric: x ZOOM_STEP_FACTOR per notch); the
## result is clamped.
static func zoom(d: float, notches: float) -> float:
	var factor := pow(ZOOM_STEP_FACTOR, notches)
	return clampf(d * factor, DevTunables.camera_min_distance(), DevTunables.camera_max_distance())


## Ground clearance (world units) at distance `d`: GROUND_CLEARANCE from CLOSE_RANGE_DISTANCE out,
## shrinking with (d / CLOSE_RANGE_DISTANCE)^2 closer (a 216 m clearance would force a top-down
## close-up), never below MIN_HEIGHT_METRES.
static func clearance(d: float) -> float:
	var near := minf(d / CLOSE_RANGE_DISTANCE, 1.0)
	return maxf(GROUND_CLEARANCE * near * near, MapScale.to_units(MIN_HEIGHT_METRES))


## Height of the look-at point at distance `d` over ground `ground` (the terrain under the
## target): `base` (CameraRig.TARGET_HEIGHT above y = 0) from 2 x CLOSE_RANGE_DISTANCE out; in
## the close range the ground plus a share of `base` that shrinks with the distance (a real-size
## tank is ~0.02 units tall); blended linearly in between, so zooming never jumps.
static func look_height(d: float, ground: float, base: float) -> float:
	var close := ground + base * minf(d / CLOSE_RANGE_DISTANCE, 1.0)
	var t := clampf((d - CLOSE_RANGE_DISTANCE) / CLOSE_RANGE_DISTANCE, 0.0, 1.0)
	return lerpf(close, base, t)


## Near clip plane (world units) at camera distance `d`: small enough close up for a 26 m view,
## the scene's 0.1 from the default zoom out (depth precision far away).
static func near_plane(d: float) -> float:
	return clampf(d * NEAR_PLANE_PER_DISTANCE, NEAR_PLANE_MIN, NEAR_PLANE_MAX)


## True when a unit `distance_to_camera` away is drawn as a group (TASK-136 hook).
static func draws_group(distance_to_camera: float) -> bool:
	return distance_to_camera < GROUP_DRAW_DISTANCE


## XZ change of the target for a screen drag (grab semantics: the ground follows the cursor).
static func pan_delta(drag: Vector2, yaw: float, d: float) -> Vector2:
	return -(_right(yaw) * drag.x + _toward_camera(yaw) * drag.y) * d * PAN_PER_PIXEL


## Unit XZ direction for key panning; input x = camera right, y = away from the camera.
static func key_pan(input: Vector2, yaw: float) -> Vector2:
	return (_right(yaw) * input.x - _toward_camera(yaw) * input.y).normalized()


static func _right(yaw: float) -> Vector2:
	return Vector2(cos(yaw), -sin(yaw))


static func _toward_camera(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


## True once the cursor is more than DRAG_THRESHOLD pixels away from the press position.
static func is_drag(press: Vector2, current: Vector2) -> bool:
	return press.distance_to(current) > DRAG_THRESHOLD


## XZ rectangle covering all tile centres, grown by a hex's half-width in X and size in Z.
static func map_bounds(centers: Array[Vector3], hex_size: float) -> Rect2:
	if centers.is_empty():
		return Rect2()
	var min_p := Vector2(centers[0].x, centers[0].z)
	var max_p := min_p
	for c in centers:
		min_p = Vector2(minf(min_p.x, c.x), minf(min_p.y, c.z))
		max_p = Vector2(maxf(max_p.x, c.x), maxf(max_p.y, c.z))
	var grow := Vector2(hex_size * sqrt(3.0) / 2.0, hex_size)
	return Rect2(min_p - grow, max_p - min_p + grow * 2.0)


## Keeps the target inside the bounds shrunk by margin; on an axis where nothing is left,
## the target is fixed to the centre.
static func clamp_target(target: Vector2, bounds: Rect2, margin: float) -> Vector2:
	var lo := bounds.position + Vector2.ONE * margin
	var hi := bounds.end - Vector2.ONE * margin
	var center := bounds.get_center()
	return Vector2(
		center.x if lo.x > hi.x else clampf(target.x, lo.x, hi.x),
		center.y if lo.y > hi.y else clampf(target.y, lo.y, hi.y),
	)


## Smallest pitch >= the offset curve at which the camera is at least GROUND_CLEARANCE above
## `ground_fn(x, z) -> float`. Raising the pitch moves the camera towards the target, so the ground
## is re-sampled until it settles; if it does not settle (steep terrain) the camera goes straight
## above the target, which always clears. `clearance` overrides GROUND_CLEARANCE (CameraRig passes
## clearance(d)).
static func clear_pitch(
	ground_fn: Callable,
	target: Vector2,
	yaw: float,
	d: float,
	target_height: float,
	pitch_offset := 0.0,
	clearance := GROUND_CLEARANCE,
) -> float:
	var pitch := pitch_with_offset(d, pitch_offset)
	for i in CLEAR_PITCH_ITERATIONS:
		var offset := camera_offset_at_pitch(yaw, d, pitch)
		var ground: float = ground_fn.call(target.x + offset.x, target.y + offset.z)
		if target_height + offset.y >= ground + clearance - 0.0005:
			return pitch
		pitch = maxf(pitch, min_pitch_for_ground(ground, target_height, d, clearance))
	return PI / 2.0
