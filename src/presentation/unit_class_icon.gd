class_name UnitClassIcon
extends Control
## The class icon of a unit marker (TASK-111): a 15 x 11 px plate in the faction colour with the
## APP-6-like class symbol (HudShapes.class_glyph) in dark ink, like a friendly-force frame.

const SIZE := Vector2(15, 11)
const INK := Color(14 / 255.0, 16 / 255.0, 13 / 255.0, 0.95)  # UnitLabel.BACKGROUND, opaque
const LINE_WIDTH := 1.2
const DOT_RADIUS := 1.3
## The classes HudShapes.class_glyph draws (docs/design/units/classes.json).
const CLASSES: Array[StringName] = [
	&"infantry",
	&"mech_infantry",
	&"tank",
	&"ifv",
	&"apc",
	&"recon",
	&"sp_artillery",
	&"mlrs",
	&"air_defense",
	&"atgm",
	&"engineer",
]

var unit_class: StringName
var color := Color.WHITE


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


static func has_glyph(id: StringName) -> bool:
	return CLASSES.has(id)


func setup(id: StringName, faction_color: Color) -> void:
	unit_class = id
	color = faction_color
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), color)
	for line in HudShapes.class_glyph(unit_class, SIZE):
		draw_polyline(line, INK, LINE_WIDTH, true)
	for dot in HudShapes.class_glyph_dots(unit_class, SIZE):
		draw_circle(dot, DOT_RADIUS, INK)
