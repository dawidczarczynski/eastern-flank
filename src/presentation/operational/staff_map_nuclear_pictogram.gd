class_name StaffMapNuclearPictogram
extends Control
## Flat pictogram of a mushroom cloud (TASK-140) above the operation-over notice, after the standard
## nuclear-hazard sign: a cap of big lobes with scallops under it, a neck, a ring round the stem,
## a flared stem on a bed of billows and a flat ground ellipse. One colour (`colour`); the gaps
## around the ring are cut in `cut` (the black the map has faded to). Drawn in a 120 x 120 box.

const BOX := 120.0
const SHOWN_SIZE := 190.0

var colour := Color("#e07c5e")
var cut := Color.BLACK


func _init() -> void:
	name = "Pictogram"
	custom_minimum_size = Vector2(SHOWN_SIZE, SHOWN_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var scale_factor := minf(size.x, size.y) / BOX
	draw_set_transform(
		Vector2((size.x - BOX * scale_factor) / 2.0, 0.0), 0.0, Vector2(scale_factor, scale_factor)
	)
	# Cap: the big dome, two side lobes, two small top lobes and the scallops under it.
	for lobe: Vector3 in [
		Vector3(60.4, 35.4, 19.0),
		Vector3(60.4, 20.4, 13.0),
		Vector3(43.5, 20.4, 6.5),
		Vector3(75.6, 20.4, 6.5),
		Vector3(35.4, 38.0, 15.0),
		Vector3(84.3, 38.0, 15.0),
		Vector3(45.0, 50.0, 7.0),
		Vector3(75.0, 50.0, 7.0),
	]:
		draw_circle(Vector2(lobe.x, lobe.y), lobe.z, colour)
	# Neck and stem, the ring round it in between.
	draw_colored_polygon(
		PackedVector2Array(
			[Vector2(52.0, 52.0), Vector2(68.0, 52.0), Vector2(69.0, 72.0), Vector2(51.0, 72.0)]
		),
		colour
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(51.2, 77.5),
				Vector2(68.8, 77.5),
				Vector2(73.0, 94.0),
				Vector2(47.0, 94.0),
			]
		),
		colour
	)
	var ring := _ellipse_points(Vector2(60.0, 70.5), Vector2(24.0, 4.8))
	draw_polyline(ring, cut, 5.2, true)
	draw_polyline(ring, colour, 2.6, true)
	# A bed of billows on the ground and the ground itself.
	for lump: Vector3 in [
		Vector3(34.0, 98.0, 6.0),
		Vector3(45.0, 95.0, 7.0),
		Vector3(61.0, 92.5, 5.5),
		Vector3(75.0, 94.0, 6.5),
		Vector3(85.5, 98.0, 5.5),
	]:
		draw_circle(Vector2(lump.x, lump.y), lump.z, colour)
	draw_colored_polygon(_ellipse_points(Vector2(60.0, 104.2), Vector2(37.0, 5.4)), colour)
	draw_set_transform(Vector2.ZERO)


func _ellipse_points(centre: Vector2, radii: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in 33:
		var angle := TAU * index / 32.0
		points.append(centre + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points
