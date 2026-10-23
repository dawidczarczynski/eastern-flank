class_name KeyCap
extends Control
## Key hint cap: a 1 px `LINE` border around amber mono text (10 px). "↵" is drawn as a shape
## because no HUD font has the glyph (HudTheme.GLYPH_GAPS).

const FONT_SIZE := 10
const PAD_X := 5.0
const PAD_Y := 1.0
const GLYPH_SIZE := Vector2(9, 8)
const ENTER := "↵"

@export var text := "":
	set(value):
		text = value
		update_minimum_size()
		queue_redraw()


func _init(key_text: String = "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	text = key_text


func _font() -> Font:
	return HudTheme.mono(500)


func _content_size() -> Vector2:
	var font := _font()
	if text == ENTER:
		return Vector2(GLYPH_SIZE.x, ceilf(font.get_height(FONT_SIZE)))
	return Vector2(
		font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x,
		ceilf(font.get_height(FONT_SIZE))
	)


func _get_minimum_size() -> Vector2:
	return _content_size() + Vector2(PAD_X + 1.0, PAD_Y + 1.0) * 2.0


func _draw() -> void:
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), UiPalette.LINE, false, 1.0)
	var content := _content_size()
	var origin := (size - content) * 0.5
	if text == ENTER:
		var top := origin + Vector2(0, (content.y - GLYPH_SIZE.y) * 0.5)
		draw_set_transform(top)
		for line in HudShapes.enter_glyph(GLYPH_SIZE):
			draw_polyline(line, UiPalette.AMBER, 1.0)
		draw_set_transform(Vector2.ZERO)
		return
	var font := _font()
	draw_string(
		font,
		origin + Vector2(0, font.get_ascent(FONT_SIZE)),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		UiPalette.AMBER
	)
