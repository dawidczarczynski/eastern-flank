class_name EndTurnButton
extends Button
## HUD v3 end-turn button: faction-coloured fill with a 14 px chamfer bottom-right, a dark hatch
## strip on the left, the caption in Chakra Petch 700 and the Enter key hint drawn as a shape.
## The Button draws nothing itself (empty styleboxes, no text); everything is in _draw().

const MIN_HEIGHT := 52.0
const FONT_SIZE := 15
const LETTER_SPACING := 2
const CHAMFER := 14.0
const PAD_LEFT := 18.0
const PAD_RIGHT := 22.0
const GAP := 12.0
const HATCH_SIZE := Vector2(10, 26)
const GLYPH_SIZE := Vector2(9, 8)
const HOVER_BRIGHTNESS := 1.12
const PRESSED_BRIGHTNESS := 0.9

@export var fill := UiPalette.NEUTRAL_FACTION:
	set(value):
		fill = value
		queue_redraw()
@export var caption := "":
	set(value):
		caption = value
		custom_minimum_size = _compute_minimum()
		queue_redraw()


func _init() -> void:
	focus_mode = Control.FOCUS_NONE  # Enter must not double as a button press
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for state: StringName in [
		&"normal", &"hover", &"pressed", &"disabled", &"focus", &"hover_pressed"
	]:
		add_theme_stylebox_override(state, empty)


## Fill colour used for the current interaction state (hover brighter, pressed darker).
func state_fill() -> Color:
	var f := 1.0
	if not disabled:
		if is_pressed() or get_draw_mode() == DRAW_PRESSED:
			f = PRESSED_BRIGHTNESS
		elif is_hovered():
			f = HOVER_BRIGHTNESS
	return Color(minf(fill.r * f, 1.0), minf(fill.g * f, 1.0), minf(fill.b * f, 1.0), fill.a)


func _font() -> Font:
	return HudTheme.display(700, LETTER_SPACING)


# Button's native get_minimum_size() shadows the script virtual, so the size is set explicitly.
func _compute_minimum() -> Vector2:
	var text_width := _font().get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var width := PAD_LEFT + HATCH_SIZE.x + GAP + text_width + GAP + GLYPH_SIZE.x + PAD_RIGHT
	return Vector2(ceilf(width), MIN_HEIGHT)


func _draw() -> void:
	draw_colored_polygon(HudShapes.chamfer(size, 0, 0, CHAMFER, 0), state_fill())
	var mid := size.y * 0.5
	var hatch_origin := Vector2(PAD_LEFT, mid - HATCH_SIZE.y * 0.5)
	for stripe in HudShapes.hatch_thin(HATCH_SIZE):
		draw_colored_polygon(_offset(stripe, hatch_origin), UiPalette.INK_HATCH)
	var font := _font()
	var text_x := PAD_LEFT + HATCH_SIZE.x + GAP
	var baseline := mid + (font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) * 0.5
	draw_string(
		font,
		Vector2(text_x, baseline),
		caption,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		UiPalette.INK
	)
	var text_width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var glyph_origin := Vector2(text_x + text_width + GAP, mid - GLYPH_SIZE.y * 0.5)
	var ink := UiPalette.INK
	ink.a = 0.7
	for line in HudShapes.enter_glyph(GLYPH_SIZE):
		draw_polyline(_offset(line, glyph_origin), ink, 1.5)


static func _offset(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(p + by)
	return out
