class_name StaffMapCameraMath
extends RefCounted
## Pure maths of the fixed top-down staff map camera (TASK-093a): zoom limits, the clamp to the
## map and cursor-centred zoom. World units are pixels at zoom 1; the camera shows
## `viewport / zoom` world pixels around its position.

const ZOOM_STEP := 1.2
## Largest zoom: the shorter side of the window shows this many hex rows (row pitch 1.5).
const MAX_ZOOM_HEXES := 10.0
const KEY_PAN_SPEED := 900.0  # screen pixels per second
const EDGE_MARGIN := 6.0  # screen edge pan zone, pixels


## Smallest zoom: the whole `map` fits into the viewport.
static func min_zoom(map: Rect2, viewport: Vector2) -> float:
	return minf(viewport.x / maxf(map.size.x, 1.0), viewport.y / maxf(map.size.y, 1.0))


## Largest zoom: about MAX_ZOOM_HEXES hexes along the shorter side; never below `min_zoom`.
static func max_zoom(viewport: Vector2, hex_unit: float, smallest: float) -> float:
	var rows_px := MAX_ZOOM_HEXES * 1.5 * hex_unit
	return maxf(minf(viewport.x, viewport.y) / rows_px, smallest)


## `position` moved so that the visible rectangle stays inside `map` (centred on an axis where the
## map is smaller than the view).
static func clamp_position(
	position: Vector2, zoom: float, map: Rect2, viewport: Vector2
) -> Vector2:
	var half := viewport / zoom * 0.5
	var result := position
	for axis in 2:
		var low := map.position[axis] + half[axis]
		var high := map.end[axis] - half[axis]
		result[axis] = (
			(map.position[axis] + map.end[axis]) * 0.5
			if low > high
			else clampf(position[axis], low, high)
		)
	return result


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
