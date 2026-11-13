class_name TurnBarFrame
extends MarginContainer
## The trapezoid frame of the top turn bar (hangs from the top edge, 26 px slants): a 1 px
## `LINE` outline (none on top) around a translucent fill, the CSS "two nested clip-paths" trick.

const SLANT := 26.0
const PADDING := Vector2(44, 12)
## Compact bars (accepted 2026-11-13, docs/design/operational_map "Turn bar"): 6 px above and below.
const COMPACT_PADDING := Vector2(44, 6)


func _init(padding := PADDING) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"margin_left", int(padding.x) + 1)
	add_theme_constant_override(&"margin_right", int(padding.x) + 1)
	add_theme_constant_override(&"margin_top", int(padding.y))
	add_theme_constant_override(&"margin_bottom", int(padding.y) + 1)


func _draw() -> void:
	draw_colored_polygon(HudShapes.trapezoid(size, SLANT), UiPalette.LINE)
	var inner := HudShapes.trapezoid(size - Vector2(2, 1), SLANT)
	for i in inner.size():
		inner[i] += Vector2(1, 0)
	draw_colored_polygon(inner, UiPalette.PANEL)
