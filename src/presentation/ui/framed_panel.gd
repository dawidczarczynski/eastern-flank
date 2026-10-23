class_name FramedPanel
extends MarginContainer
## The HUD v3 frame: a 1 px `LINE` outline around a translucent fill, both the same chamfered
## polygon (the CSS "two nested clip-path elements" trick), optional header tab and corner
## brackets. Children are laid out inside the frame like in a MarginContainer; `padding` is the
## space between frame and content (the tab row is added on top of it).
##
## Chamfers are given per corner as (top-left, top-right, bottom-right, bottom-left) pixels.

const TAB_FONT_SIZE := 11
const TAB_PADDING := Vector2(10, 4)  # left, vertical
const TAB_RIGHT_PADDING := 18.0
const TAB_SPACING := 1
const RIGHT_TEXT_SIZE := 10
const BRACKET_ARM := 9.0
const BRACKET_STROKE := 2.0

@export var chamfers := Vector4.ZERO:  # tl, tr, br, bl
	set(value):
		chamfers = value
		queue_redraw()
@export var fill := UiPalette.PANEL:
	set(value):
		fill = value
		queue_redraw()
@export var line_color := UiPalette.LINE:
	set(value):
		line_color = value
		queue_redraw()
@export var padding := Vector2(12, 9):
	set(value):
		padding = value
		_update_margins()
@export var tab_text := "":
	set(value):
		tab_text = value
		_update_margins()
@export var tab_color := UiPalette.AMBER:
	set(value):
		tab_color = value
		queue_redraw()
@export var tab_right_text := "":
	set(value):
		tab_right_text = value
		queue_redraw()
@export var tab_right_color := UiPalette.HUD_MUTED:
	set(value):
		tab_right_color = value
		queue_redraw()
@export var brackets := false:
	set(value):
		brackets = value
		queue_redraw()
@export var bracket_color := UiPalette.AMBER:
	set(value):
		bracket_color = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_margins()


## Height of the header tab row (0 without a tab).
func tab_height() -> float:
	if tab_text == "":
		return 0.0
	return ceilf(_tab_font().get_height(TAB_FONT_SIZE)) + TAB_PADDING.y * 2.0


func _update_margins() -> void:
	add_theme_constant_override(&"margin_left", int(padding.x) + 1)
	add_theme_constant_override(&"margin_right", int(padding.x) + 1)
	add_theme_constant_override(&"margin_top", int(padding.y) + 1 + int(tab_height()))
	add_theme_constant_override(&"margin_bottom", int(padding.y) + 1)
	queue_redraw()
	update_minimum_size()


func _tab_font() -> Font:
	return HudTheme.mono(600, TAB_SPACING)


func _draw() -> void:
	var c := chamfers
	draw_colored_polygon(HudShapes.chamfer(size, c.x, c.y, c.z, c.w), line_color)
	draw_colored_polygon(HudShapes.chamfer_inset(size, 1.0, c.x, c.y, c.z, c.w), fill)
	if tab_text != "":
		_draw_tab()
	if brackets:
		for corner in 4:
			var pts := HudShapes.corner_bracket(corner, size, BRACKET_ARM, 1.0)
			draw_polyline(pts, bracket_color, BRACKET_STROKE)


func _draw_tab() -> void:
	var font := _tab_font()
	var text_size := font.get_string_size(tab_text, HORIZONTAL_ALIGNMENT_LEFT, -1, TAB_FONT_SIZE)
	var tab_size := Vector2(TAB_PADDING.x + text_size.x + TAB_RIGHT_PADDING, tab_height())
	var origin := Vector2(1, 1)
	var poly := HudShapes.header_tab(tab_size)
	for i in poly.size():
		poly[i] += origin
	draw_colored_polygon(poly, tab_color)
	var baseline := origin + Vector2(TAB_PADDING.x, TAB_PADDING.y + font.get_ascent(TAB_FONT_SIZE))
	draw_string(
		font, baseline, tab_text, HORIZONTAL_ALIGNMENT_LEFT, -1, TAB_FONT_SIZE, UiPalette.INK
	)
	if tab_right_text != "":
		var right_font := HudTheme.mono(500)
		var right_width := (
			right_font
			. get_string_size(tab_right_text, HORIZONTAL_ALIGNMENT_LEFT, -1, RIGHT_TEXT_SIZE)
			. x
		)
		var right_pos := Vector2(
			size.x - 1.0 - TAB_RIGHT_PADDING - right_width,
			(
				origin.y
				+ (
					(
						tab_size.y
						+ right_font.get_ascent(RIGHT_TEXT_SIZE)
						- right_font.get_descent(RIGHT_TEXT_SIZE)
					)
					* 0.5
				)
			)
		)
		draw_string(
			right_font,
			right_pos,
			tab_right_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			RIGHT_TEXT_SIZE,
			tab_right_color
		)
