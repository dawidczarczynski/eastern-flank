class_name StaffMapCameraMath
extends RefCounted
## Pure maths of the staff map camera (TASK-093a, tilted in TASK-125): zoom limits, the clamp to
## the map, cursor-centred zoom, pitch and the ray / projection of the tilted orthographic camera.
##
## 2D state as in v0: `position` (world pixels = hex units * unit, the ground point at the screen
## centre) and `zoom` (screen pixels per world pixel). The camera is **orthographic** and pitched
## about the east axis only (no yaw, north stays up): pitch 0 looks straight down and reproduces
## v0 exactly; at pitch p the ground plane is foreshortened by cos(p) vertically, the same on the
## whole screen (an orthographic camera does not shrink the far edge – TASK-125 anti-compression).
## The ground-plane functions therefore take the "ground viewport" (viewport.y / cos p).
## 3D world: hex units, x east, y up, z south (Hex.to_world with size 1).

const ZOOM_STEP := 1.2
## Largest zoom: the shorter side of the window shows this many hex rows (row pitch 1.5).
const MAX_ZOOM_HEXES := 10.0
const KEY_PAN_SPEED := 900.0  # screen pixels per second
const EDGE_MARGIN := 6.0  # screen edge pan zone, pixels
## Pitch in degrees from straight down.
const PITCH_MIN := 0.0
const PITCH_MAX := 50.0
const PITCH_DEFAULT := 35.0
const PITCH_WHEEL_STEP := 5.0  # degrees per Ctrl + wheel notch
const PITCH_KEY_SPEED := 60.0  # degrees per second while Q / E is held
## Distance of the camera from its target along the view axis, hex units (orthographic: only
## needs to clear the relief).
const CAMERA_DISTANCE := 400.0
## Screen px the HUD covers: Vector4(top, bottom, left, right). Top = turn bar + escalation chip.
const TOP_INSET := 92.0
const EASE_MARGIN := 40.0  # px between an eased-in counter and the clear zone edge
const EASE_SECONDS := 0.28


## Smallest zoom: the whole `map` fits into the viewport (pass ground_viewport when tilted).
static func min_zoom(map: Rect2, viewport: Vector2) -> float:
	return minf(viewport.x / maxf(map.size.x, 1.0), viewport.y / maxf(map.size.y, 1.0))


## Largest zoom: about MAX_ZOOM_HEXES hexes along the shorter side; never below `min_zoom`.
static func max_zoom(viewport: Vector2, hex_unit: float, smallest: float) -> float:
	var rows_px := MAX_ZOOM_HEXES * 1.5 * hex_unit
	return maxf(minf(viewport.x, viewport.y) / rows_px, smallest)


## The part of the viewport no bar or docked window covers. `insets` = (top, bottom, left, right).
static func clear_rect(viewport: Vector2, insets: Vector4) -> Rect2:
	var origin := Vector2(insets.z, insets.x)
	return Rect2(origin, viewport - origin - Vector2(insets.w, insets.y))


## Insets for the ground plane: top and bottom stretch like ground_viewport (1 / cos pitch).
static func ground_insets(insets: Vector4, pitch: float) -> Vector4:
	var k := 1.0 / cos(deg_to_rad(pitch))
	return Vector4(insets.x * k, insets.y * k, insets.z, insets.w)


## `position` moved so that the clear zone (the viewport minus `insets`, same space as `viewport`)
## stays inside `map`: the theatre edge can reach the clear-zone edge, so no unit stays under a
## bar. Where the map is smaller than the clear zone it is centred in it (horizontally: centred on the
## screen when it fits the screen width, windows then overlay it).
static func clamp_position(
	position: Vector2, zoom: float, map: Rect2, viewport: Vector2, insets := Vector4()
) -> Vector2:
	var clear := clear_rect(viewport, insets)
	var from := clear.position - viewport * 0.5  # clear-zone corners relative to the centre
	var to := clear.end - viewport * 0.5
	var result := position
	for axis in 2:
		if axis == 0 and map.size.x * zoom <= viewport.x:
			# The theatre is no wider than the screen: keep it centred on the screen, so a window
			# docking left / right does not shove the whole map sideways (it just covers it).
			result.x = map.get_center().x
			continue
		var low := map.position[axis] - from[axis] / zoom
		var high := map.end[axis] - to[axis] / zoom
		result[axis] = (
			(map.position[axis] + map.end[axis] - (from[axis] + to[axis]) / zoom) * 0.5
			if low > high
			else clampf(position[axis], low, high)
		)
	return result


## True when the formation panel docks on the left: the counter is on the right half and the
## left dock is free; otherwise it stays on the right dock.
static func panel_on_left(counter_x: float, viewport_width: float, left_free: bool) -> bool:
	return left_free and counter_x > viewport_width * 0.5


## Screen shift that brings `point` into `clear` (shrunk by `margin`) by the shortest way; zero
## when it is already inside.
static func ease_shift(point: Vector2, clear: Rect2, margin: float) -> Vector2:
	var inner := clear.grow(-margin)
	if not inner.has_area():
		return Vector2.ZERO
	return point.clamp(inner.position, inner.end) - point


## New camera position that keeps the world point under `cursor` (viewport pixels) fixed when the
## zoom changes from `old_zoom` to `new_zoom`.
static func zoom_about(
	position: Vector2, old_zoom: float, new_zoom: float, cursor: Vector2, viewport: Vector2
) -> Vector2:
	var offset := cursor - viewport * 0.5
	return position + offset / old_zoom - offset / new_zoom


## Zoom after `notches` wheel notches (positive = in), kept in [smallest, largest].
static func zoom_by(zoom: float, notches: float, smallest: float, largest: float) -> float:
	return clampf(zoom * pow(ZOOM_STEP, notches), smallest, largest)


static func clamp_pitch(degrees: float) -> float:
	return clampf(degrees, PITCH_MIN, PITCH_MAX)


## V: flat when tilted, back to `tilt` (the last tilt, default PITCH_DEFAULT) when flat.
static func toggle_pitch(current: float, tilt: float) -> float:
	if current > 0.5:
		return PITCH_MIN
	return clamp_pitch(tilt if tilt > 0.5 else PITCH_DEFAULT)


## The viewport as seen on the ground plane: the screen height covers 1 / cos(pitch) as much
## ground. Feed it to min_zoom / clamp_position / zoom_about.
static func ground_viewport(viewport: Vector2, pitch: float) -> Vector2:
	return Vector2(viewport.x, viewport.y / cos(deg_to_rad(pitch)))


## A cursor position mapped into ground_viewport coordinates (the same ground point).
static func ground_cursor(cursor: Vector2, viewport: Vector2, pitch: float) -> Vector2:
	var ground := ground_viewport(viewport, pitch)
	return Vector2(cursor.x, ground.y * 0.5 + (cursor.y - viewport.y * 0.5) * ground.y / viewport.y)


## Ground-plane drag: world-pixel displacement of the camera when the cursor moved by `relative`
## screen pixels.
static func drag_delta(relative: Vector2, zoom: float, pitch: float) -> Vector2:
	return -Vector2(relative.x, relative.y / cos(deg_to_rad(pitch))) / zoom


## Camera orientation: rotated about the east axis, looking north-down; pitch 0 = straight down.
static func camera_basis(pitch: float) -> Basis:
	return Basis(Vector3.RIGHT, -deg_to_rad(90.0 - pitch))


## Camera transform for a ground `target` (hex units, y = 0).
static func camera_transform(target: Vector3, pitch: float) -> Transform3D:
	var basis := camera_basis(pitch)
	return Transform3D(basis, target + basis.z * CAMERA_DISTANCE)


## World ray through screen point `cursor`: {"origin": Vector3, "direction": Vector3}. `scale` =
## screen pixels per hex unit (zoom * unit), `target` the ground point at the screen centre.
static func screen_ray(
	cursor: Vector2, viewport: Vector2, target: Vector3, scale: float, pitch: float
) -> Dictionary:
	var basis := camera_basis(pitch)
	var offset := (cursor - viewport * 0.5) / scale
	var origin := target + basis.z * CAMERA_DISTANCE + basis.x * offset.x - basis.y * offset.y
	return {"origin": origin, "direction": -basis.z}


## Where the ray through `cursor` meets the ground plane y = 0 (hex units, x / z).
static func plane_point(
	cursor: Vector2, viewport: Vector2, target: Vector3, scale: float, pitch: float
) -> Vector2:
	var ray := screen_ray(cursor, viewport, target, scale, pitch)
	var origin: Vector3 = ray["origin"]
	var direction: Vector3 = ray["direction"]
	var t := -origin.y / direction.y
	var hit := origin + direction * t
	return Vector2(hit.x, hit.z)


## Screen position of a world point (inverse of screen_ray).
static func project(
	point: Vector3, viewport: Vector2, target: Vector3, scale: float, pitch: float
) -> Vector2:
	var basis := camera_basis(pitch)
	var d := point - target
	return viewport * 0.5 + Vector2(d.dot(basis.x), -d.dot(basis.y)) * scale


## Zoom level 0 / 1 / 2 for `px_per_km` with `thresholds` (Z1, Z2 starts) and ±`hysteresis`
## (fraction): the level only changes once the value is past the threshold by that margin.
static func zoom_level(
	px_per_km: float, current: int, thresholds: Vector2, hysteresis: float
) -> int:
	var level := clampi(current, 0, 2)
	while level < 2 and px_per_km > thresholds[level] * (1.0 + hysteresis):
		level += 1
	while level > 0 and px_per_km < thresholds[level - 1] * (1.0 - hysteresis):
		level -= 1
	return level
