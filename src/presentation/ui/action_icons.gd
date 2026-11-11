class_name ActionIcons
extends RefCounted
## Pure geometry of the action bar icons (TASK-139): line drawings on a 24 x 24 grid, each a list
## of polylines. ActionBarButton scales and strokes them; nothing here touches nodes.

const GRID := 24.0

const IDS: Array[StringName] = [
	&"grid",
	&"reset_view",
	&"deselect",
	&"save",
	&"names",
	&"borders",
	&"politics",
	&"flat",
	&"next",
	&"cancel",
	&"report",
	&"decisions",
	&"strike",
	&"map_options",
]

## Icons drawn as text instead of lines: id -> [text when off, text when on] (the view toggle
## reads "3D" while tilted and "2D" once flat).
const TEXT := {&"flat": ["3D", "2D"]}


static func text(id: StringName, active: bool) -> String:
	var pair: Array = TEXT.get(id, [])
	return "" if pair.is_empty() else pair[1 if active else 0]


## Polylines of icon `id` on the 24 x 24 grid; empty for an unknown id.
static func polylines(id: StringName) -> Array[PackedVector2Array]:
	var lines: Array[PackedVector2Array] = []
	match id:
		&"grid":  # one hex
			lines.append(_hex(Vector2(12, 12), 8.5))
		&"reset_view":  # circular arrow
			lines.append(_arc(Vector2(12, 12), 7.5, -60.0, 250.0))
			lines.append(_poly([Vector2(17.5, 3.5), Vector2(18.5, 8.5), Vector2(13.5, 8.5)]))
		&"deselect":  # ring with a cross
			lines.append(_arc(Vector2(12, 12), 8.5, 0.0, 360.0))
			lines.append(_poly([Vector2(8.5, 8.5), Vector2(15.5, 15.5)]))
			lines.append(_poly([Vector2(15.5, 8.5), Vector2(8.5, 15.5)]))
		&"save":  # floppy disk
			lines.append(
				_poly(
					[
						Vector2(4, 4),
						Vector2(17, 4),
						Vector2(20, 7),
						Vector2(20, 20),
						Vector2(4, 20),
						Vector2(4, 4)
					]
				)
			)
			lines.append(_poly([Vector2(8, 4), Vector2(8, 9), Vector2(15, 9), Vector2(15, 4)]))
			lines.append(_poly([Vector2(8, 20), Vector2(8, 14), Vector2(16, 14), Vector2(16, 20)]))
		&"names":  # map pin
			lines.append(_arc(Vector2(12, 10), 6.0, 150.0, 390.0))
			lines.append(_poly([Vector2(6.8, 13), Vector2(12, 21), Vector2(17.2, 13)]))
			lines.append(_arc(Vector2(12, 10), 2.0, 0.0, 360.0))
		&"borders":  # a dash-dot border line
			lines.append(_poly([Vector2(3, 18), Vector2(8, 14.5)]))
			lines.append(_poly([Vector2(10.5, 12.8), Vector2(11.5, 12.1)]))
			lines.append(_poly([Vector2(14, 10.5), Vector2(15, 9.8)]))
			lines.append(_poly([Vector2(17, 8.5), Vector2(21, 5.5)]))
		&"politics":  # flag on a pole
			lines.append(_poly([Vector2(6, 21), Vector2(6, 3)]))
			lines.append(
				_poly(
					[
						Vector2(6, 4),
						Vector2(19, 4),
						Vector2(16, 8.5),
						Vector2(19, 13),
						Vector2(6, 13)
					]
				)
			)
		&"next":  # skip arrow
			lines.append(_poly([Vector2(5, 5), Vector2(15, 12), Vector2(5, 19), Vector2(5, 5)]))
			lines.append(_poly([Vector2(19, 5), Vector2(19, 19)]))
		&"cancel":  # backspace
			lines.append(
				_poly(
					[
						Vector2(9, 5),
						Vector2(21, 5),
						Vector2(21, 19),
						Vector2(9, 19),
						Vector2(3, 12),
						Vector2(9, 5)
					]
				)
			)
			lines.append(_poly([Vector2(11, 9), Vector2(17, 15)]))
			lines.append(_poly([Vector2(17, 9), Vector2(11, 15)]))
		&"decisions":  # balance scales (a political decision weighs a price)
			lines.append(_poly([Vector2(12, 4), Vector2(12, 20)]))
			lines.append(_poly([Vector2(7, 20), Vector2(17, 20)]))
			lines.append(_poly([Vector2(4, 7), Vector2(20, 7)]))
			lines.append(_poly([Vector2(4, 7), Vector2(2, 13), Vector2(6, 13), Vector2(4, 7)]))
			lines.append(_poly([Vector2(20, 7), Vector2(18, 13), Vector2(22, 13), Vector2(20, 7)]))
		&"strike":  # crosshair
			lines.append(_arc(Vector2(12, 12), 7.0, 0.0, 360.0))
			lines.append(_poly([Vector2(12, 2), Vector2(12, 8)]))
			lines.append(_poly([Vector2(12, 16), Vector2(12, 22)]))
			lines.append(_poly([Vector2(2, 12), Vector2(8, 12)]))
			lines.append(_poly([Vector2(16, 12), Vector2(22, 12)]))
		&"map_options":  # stacked layers
			lines.append(
				_poly(
					[Vector2(12, 3), Vector2(21, 8), Vector2(12, 13), Vector2(3, 8), Vector2(12, 3)]
				)
			)
			lines.append(_poly([Vector2(3, 12), Vector2(12, 17), Vector2(21, 12)]))
			lines.append(_poly([Vector2(3, 16), Vector2(12, 21), Vector2(21, 16)]))
		&"report":  # sheet with text lines
			lines.append(
				_poly(
					[
						Vector2(5, 3),
						Vector2(14, 3),
						Vector2(19, 8),
						Vector2(19, 21),
						Vector2(5, 21),
						Vector2(5, 3)
					]
				)
			)
			lines.append(_poly([Vector2(14, 3), Vector2(14, 8), Vector2(19, 8)]))
			lines.append(_poly([Vector2(8, 12), Vector2(16, 12)]))
			lines.append(_poly([Vector2(8, 15.5), Vector2(16, 15.5)]))
			lines.append(_poly([Vector2(8, 19), Vector2(12, 19)]))
	return lines


static func _poly(points: Array[Vector2]) -> PackedVector2Array:
	return PackedVector2Array(points)


static func _hex(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 7:
		var angle := deg_to_rad(60.0 * i - 30.0)  # pointy top
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


## Arc from `from_deg` to `to_deg` (degrees, clockwise from +x on screen) as a polyline.
static func _arc(
	center: Vector2, radius: float, from_deg: float, to_deg: float
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := maxi(int(absf(to_deg - from_deg) / 20.0), 2)
	for i in steps + 1:
		var angle := deg_to_rad(lerpf(from_deg, to_deg, float(i) / steps))
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points
