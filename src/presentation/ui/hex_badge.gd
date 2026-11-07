class_name HexBadge
extends Control
## HUD v3 faction badge: a 40 x 36 pointy hexagon in the faction colour with its short name in
## the faction ink (Chakra Petch 700).

const FONT_SIZE := 14
## Texts longer than two characters ("NATO") use this size, as in the design.
const LONG_FONT_SIZE := 10

@export var fill := UiPalette.NEUTRAL_FACTION:
	set(value):
		fill = value
		queue_redraw()
@export var ink := UiPalette.NEUTRAL_INK:
	set(value):
		ink = value
		queue_redraw()
@export var text := "":
	set(value):
		text = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = HudShapes.BADGE_SIZE


func _draw() -> void:
	draw_colored_polygon(HudShapes.hex_badge(size), fill)
	if text == "":
		return
	var font := HudTheme.display(700)
	var font_size := FONT_SIZE if text.length() <= 2 else LONG_FONT_SIZE
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(
		font,
		Vector2((size.x - width) * 0.5, baseline),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		ink
	)
