class_name OrbitMath
extends RefCounted
## Pure maths of the unit catalog's orbit camera (no nodes), tested in tests/unit/. The camera
## looks at a target point from `distance` at `yaw` (about the world Y axis, 0 = on +Z looking
## towards -Z) and `pitch` above the ground; limits come from the bounding sphere of the model so a
## squad and a Homar-K both fill the view.

const FOV_DEGREES := 35.0
const PITCH_MIN := 0.05  # never below the ground disc
const PITCH_MAX := 1.5  # nearly straight down
const DEFAULT_YAW := 0.75  # three-quarter view from the front right of a model facing +X
const DEFAULT_PITCH := 0.32
## The default distance leaves this much room around the bounding sphere.
const FIT_MARGIN := 1.5
## Closest and farthest distance as multiples of the bounding radius.
const MIN_DISTANCE_RADIUS := 0.25
const MAX_DISTANCE_FIT := 2.5  # times the fitting distance
const ROTATE_PER_PIXEL := 0.007  # radians
const ZOOM_IN_FACTOR := 0.88
const ZOOM_OUT_FACTOR := 1.12
const MIN_RADIUS := 0.05


## Bounding-sphere radius of a model's box (the sphere around its centre).
static func radius(bounds: AABB) -> float:
	return maxf(MIN_RADIUS, bounds.size.length() * 0.5)


## Yaw wrapped into [-PI, PI).
static func wrap_yaw(yaw: float) -> float:
	return wrapf(yaw, -PI, PI)


static func clamp_pitch(pitch: float) -> float:
	return clampf(pitch, PITCH_MIN, PITCH_MAX)


## Distance at which a sphere of `sphere_radius` fills the vertical field of view with FIT_MARGIN.
static func fit_distance(sphere_radius: float) -> float:
	return sphere_radius * FIT_MARGIN / sin(deg_to_rad(FOV_DEGREES) * 0.5)


static func min_distance(sphere_radius: float) -> float:
	return sphere_radius * MIN_DISTANCE_RADIUS


static func max_distance(sphere_radius: float) -> float:
	return fit_distance(sphere_radius) * MAX_DISTANCE_FIT


static func clamp_distance(distance: float, sphere_radius: float) -> float:
	return clampf(distance, min_distance(sphere_radius), max_distance(sphere_radius))


## New {yaw, pitch} after a mouse drag of `delta` pixels: dragging right swings the camera to the
## left around the unit (the unit appears to turn with the cursor), dragging down looks from higher.
static func dragged(yaw: float, pitch: float, delta: Vector2) -> Dictionary:
	return {
		"yaw": wrap_yaw(yaw - delta.x * ROTATE_PER_PIXEL),
		"pitch": clamp_pitch(pitch + delta.y * ROTATE_PER_PIXEL),
	}


## Distance after `notches` of mouse wheel (positive = wheel up = closer), clamped.
static func zoomed(distance: float, notches: float, sphere_radius: float) -> float:
	var factor := pow(ZOOM_IN_FACTOR, notches) if notches >= 0.0 else pow(ZOOM_OUT_FACTOR, -notches)
	return clamp_distance(distance * factor, sphere_radius)


## Camera position for the orbit state around `target`.
static func eye(target: Vector3, yaw: float, pitch: float, distance: float) -> Vector3:
	var horizontal := cos(pitch) * distance
	return target + Vector3(sin(yaw) * horizontal, sin(pitch) * distance, cos(yaw) * horizontal)


## The state a unit is first shown in and `Home` / double click return to.
static func default_state(sphere_radius: float) -> Dictionary:
	return {
		"yaw": DEFAULT_YAW,
		"pitch": DEFAULT_PITCH,
		"distance": fit_distance(sphere_radius),
	}


## Box of the visible meshes below `node` in the space `to_root` maps `node` to (hidden parts such
## as the kneeling soldiers' Stand pose do not count). Accumulates local transforms, so it works
## outside the tree. Zero-size when there is nothing visible.
static func visible_bounds(node: Node3D, to_root: Transform3D = Transform3D.IDENTITY) -> AABB:
	var result := AABB()
	var has := false
	for child in node.get_children():
		var spatial := child as Node3D
		if spatial == null or not spatial.visible:
			continue
		var transform_to_root := to_root * spatial.transform
		var box := AABB()
		var has_box := false
		var instance := spatial as MeshInstance3D
		if instance != null and instance.mesh != null:
			box = transform_to_root * instance.get_aabb()
			has_box = true
		var inner := visible_bounds(spatial, transform_to_root)
		if inner.size != Vector3.ZERO:
			box = box.merge(inner) if has_box else inner
			has_box = true
		if has_box:
			result = result.merge(box) if has else box
			has = true
	return result
