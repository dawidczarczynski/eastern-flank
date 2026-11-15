class_name StaffMapOrderExtrasPaint
extends RefCounted
## Draws the order extras of StaffMapOrderExtras (TASK-153 stage 2) onto a CanvasItem
## (StaffMapRouteMarks): the destination ghost, the goal-conflict mark and the far-zoom stub.
## Look: docs/design/operational_map/order_lines.html D2 / D5 / D6; colours are passed in from the
## palette, none are defined here.

## The ghost counter outline (the notched counter of the mockup, centred on the hex).
const GHOST_OUTLINE := [
	Vector2(-20, -13), Vector2(14, -13), Vector2(20, -7), Vector2(20, 13), Vector2(-20, 13)
]
const GHOST_WIDTH := 1.3
const GHOST_DASH := 4.0
const GHOST_GAP := 3.0
const GHOST_ALPHA := 0.85
const TEXT_SIZE := 11
const TRIANGLE := Vector2(28, 24)
const PLATE_SIZE := 12
const PLATE_PAD := Vector2(7, 4)


## The dashed destination ghost at `at` with `text` ("T+n") under it.
static func ghost(
	canvas: CanvasItem, at: Vector2, text: String, colour: Color, ink: Color, font: Font
) -> void:
	var outline := PackedVector2Array()
	for corner: Vector2 in GHOST_OUTLINE:
		outline.append(at + corner)
	canvas.draw_colored_polygon(outline, Color(colour, 0.1))
	for i in outline.size():
		_dashed(canvas, outline[i], outline[(i + 1) % outline.size()], Color(colour, GHOST_ALPHA))
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE)
	var origin := at + Vector2(-size.x / 2.0, 13.0 + 6.0 + size.y * 0.6)
	canvas.draw_string_outline(
		font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, 4, Color(ink, 0.9)
	)
	canvas.draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, colour)


## The conflict mark: an amber triangle with "!" on the hex and one plate line above it.
static func conflict(
	canvas: CanvasItem,
	at: Vector2,
	text: String,
	amber: Color,
	ink: Color,
	panel: Color,
	text_colour: Color,
	font: Font,
	viewport: Vector2
) -> void:
	var half := TRIANGLE / 2.0
	var triangle := PackedVector2Array(
		[at + Vector2(0, -half.y), at + Vector2(half.x, half.y), at + Vector2(-half.x, half.y)]
	)
	canvas.draw_colored_polygon(triangle, amber)
	var bang := font.get_string_size("!", HORIZONTAL_ALIGNMENT_LEFT, -1, PLATE_SIZE)
	canvas.draw_string(
		font, at + Vector2(-bang.x / 2.0, 8.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, PLATE_SIZE, ink
	)
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, PLATE_SIZE)
	var box := size + PLATE_PAD * 2.0
	var top_left := at + Vector2(-box.x / 2.0, -half.y - 6.0 - box.y)
	top_left.x = clampf(top_left.x, 4.0, maxf(4.0, viewport.x - box.x - 4.0))
	if top_left.y < 4.0:
		top_left.y = at.y + half.y + 6.0
	var rect := Rect2(top_left, box)
	canvas.draw_rect(rect, panel)
	canvas.draw_rect(rect, Color(amber, 0.7), false, 1.0)
	canvas.draw_string(
		font,
		top_left + Vector2(PLATE_PAD.x, PLATE_PAD.y + font.get_ascent(PLATE_SIZE)),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		PLATE_SIZE,
		text_colour
	)


## The far-zoom stub `stub` ({from, to}, StaffMapOrderExtras.stub) with a chevron head at its end:
## a dark casing under the line colour, like the ribbon.
static func stub(canvas: CanvasItem, stub_line: Dictionary, colour: Color, ink: Color) -> void:
	var from: Vector2 = stub_line["from"]
	var to: Vector2 = stub_line["to"]
	var along := (to - from).normalized()
	var side := Vector2(-along.y, along.x)
	var head := PackedVector2Array(
		[to + along * 7.0, to - along * 3.0 + side * 7.0, to - along * 3.0 - side * 7.0]
	)
	canvas.draw_line(from, to, Color(ink, 0.85), 5.6, true)
	canvas.draw_line(from, to, colour, 3.0, true)
	canvas.draw_colored_polygon(head, colour)
	var closed := head.duplicate()
	closed.append(head[0])
	canvas.draw_polyline(closed, Color(ink, 0.9), 1.0, true)


static func _dashed(canvas: CanvasItem, a: Vector2, b: Vector2, colour: Color) -> void:
	var length := a.distance_to(b)
	var along := (b - a) / maxf(length, 0.001)
	var at := 0.0
	while at < length:
		var to := minf(at + GHOST_DASH, length)
		canvas.draw_line(a + along * at, a + along * to, colour, GHOST_WIDTH, true)
		at += GHOST_DASH + GHOST_GAP
