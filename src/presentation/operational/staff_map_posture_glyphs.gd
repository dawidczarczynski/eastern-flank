class_name StaffMapPostureGlyphs
extends RefCounted
## Polygon glyphs of the three postures (TASK-158, docs/design/operational_map/
## posture_badge_switcher.html): march = double chevron, advance = spear, defend = arc over a bar.
## Pure geometry in a 12 x 12 design box centred on the origin (y down); the badge, the switcher
## strip and later the unit strip draw the same shapes through draw(). No assets.

const BOX := 12.0
const ARC_STEPS := 8

const MARCH := &"march"
const ADVANCE := &"advance"
const DEFEND := &"defend"


## Open polylines (stroked) of the glyph, in design units; empty for an unknown posture.
static func strokes(posture: StringName) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	match posture:
		MARCH:
			result.append(PackedVector2Array([Vector2(-5, -4), Vector2(-1, 0), Vector2(-5, 4)]))
			result.append(PackedVector2Array([Vector2(1, -4), Vector2(5, 0), Vector2(1, 4)]))
		ADVANCE:
			result.append(PackedVector2Array([Vector2(-6, 0), Vector2(0, 0)]))
		DEFEND:
			var arc := PackedVector2Array()
			for i in ARC_STEPS + 1:
				var a := PI + PI * i / ARC_STEPS
				arc.append(Vector2(cos(a), sin(a)) * 5.0 + Vector2(0, 2))
			result.append(arc)
			result.append(PackedVector2Array([Vector2(-6, 5), Vector2(6, 5)]))
	return result


## Filled polygons of the glyph (the spear head), in design units.
static func fills(posture: StringName) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if posture == ADVANCE:
		result.append(PackedVector2Array([Vector2(-1, -4.5), Vector2(6, 0), Vector2(-1, 4.5)]))
	return result


## Draws the glyph on `canvas` centred on `centre`, `size_px` wide (BOX units = size_px).
static func draw(
	canvas: CanvasItem,
	posture: StringName,
	centre: Vector2,
	size_px: float,
	colour: Color,
	stroke_px: float
) -> void:
	var k := size_px / BOX
	for line in strokes(posture):
		canvas.draw_polyline(_place(line, centre, k), colour, stroke_px, true)
	for poly in fills(posture):
		canvas.draw_colored_polygon(_place(poly, centre, k), colour)


static func _place(points: PackedVector2Array, centre: Vector2, k: float) -> PackedVector2Array:
	var placed := PackedVector2Array()
	for p in points:
		placed.append(centre + p * k)
	return placed
