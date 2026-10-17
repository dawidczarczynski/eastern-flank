class_name CameraMath
extends RefCounted
## Pure camera formulas (no nodes), shared by CameraRig and tested in tests/unit/.

const MIN_DISTANCE := 7.0
const MAX_DISTANCE := 46.0
const ZOOM_OUT_FACTOR := 1.12
const ZOOM_IN_FACTOR := 0.88
const PAN_PER_PIXEL := 0.0016  # world units per pixel per unit of distance
const DRAG_THRESHOLD := 4.0  # pixels


## Camera pitch above the horizon (radians): flatter when close, more top-down when far.
static func pitch_for_distance(d: float) -> float:
	return 0.82 + (d - 8.0) / 37.0 * 0.3


## Offset from the look-at point to the camera. Yaw 0 = camera on the +Z side.
static func camera_offset(yaw: float, d: float) -> Vector3:
	var p := pitch_for_distance(d)
	return Vector3(sin(yaw) * cos(p) * d, sin(p) * d, cos(yaw) * cos(p) * d)


## Positive notches zoom out, negative zoom in; the result is clamped.
static func zoom(d: float, notches: float) -> float:
	var factor := pow(ZOOM_OUT_FACTOR, notches) if notches > 0.0 else pow(ZOOM_IN_FACTOR, -notches)
	return clampf(d * factor, MIN_DISTANCE, MAX_DISTANCE)


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
