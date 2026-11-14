class_name ActionBarButton
extends Button
## One button of the ActionBar: a square line icon (ActionIcons) on a flat dark box with an amber
## line; a toggle that is on gets an amber tint and a bright line. The name, the key and a longer
## description show in a HUD tooltip on hover (ActionTooltip).

const SIZE := 38.0
const ICON_SIZE := 20.0
const STROKE := 1.1
const TEXT_SIZE := 12
const BADGE_SIZE := 11

## A small count in the top-right corner (the fire-support missions left); "" = none.
var badge := "":
	set(value):
		badge = value
		queue_redraw()
## Why the button is off, appended to the tooltip; "" = no reason.
var reason := ""

var _label_key := ""
var _key_key := ""
var _tip_key := ""
var _icon_id: StringName


func _init(id := &"", label_key := "", key_text := "", toggle := false, tip_key := "") -> void:
	_icon_id = id
	_label_key = label_key
	_key_key = key_text
	_tip_key = tip_key
	toggle_mode = toggle
	focus_mode = Control.FOCUS_NONE  # Enter must not double as a button press
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(SIZE, SIZE)
	var line := Color(UiPalette.AMBER, 0.0)  # frameless until hovered or lit
	var bright := Color(UiPalette.AMBER, 0.9)
	add_theme_stylebox_override(&"normal", _box(Color(0, 0, 0, 0), line))
	add_theme_stylebox_override(&"hover", _box(Color(UiPalette.AMBER, 0.12), bright))
	add_theme_stylebox_override(
		&"pressed", _box(Color(UiPalette.AMBER, 0.12), Color(UiPalette.AMBER, 0.45))
	)
	add_theme_stylebox_override(&"hover_pressed", _box(Color(UiPalette.AMBER, 0.2), bright))
	add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	add_theme_stylebox_override(&"disabled", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	refresh_texts()


func refresh_texts() -> void:
	tooltip_text = label_text()  # must be non-empty for the custom tooltip to show
	queue_redraw()


func label_text() -> String:
	return tr(_label_key).to_upper()


func key_text() -> String:
	return tr(_key_key).to_upper()


func tip_text() -> String:
	var tip := tr(_tip_key) if _tip_key != "" else ""
	if reason != "":
		tip = (tip + "\n" + tr(reason)).strip_edges()
	return tip


func icon_id() -> StringName:
	return _icon_id


func _make_custom_tooltip(_for_text: String) -> Object:
	return ActionTooltip.new(label_text(), key_text(), tip_text())


func _draw() -> void:
	var color := UiPalette.HUD_MUTED
	if not disabled:
		color = UiPalette.AMBER if toggle_mode and button_pressed else UiPalette.HUD_TEXT
		if is_hovered():
			color = UiPalette.AMBER
	var glyph := ActionIcons.text(_icon_id, button_pressed)
	if glyph != "":
		var font := HudTheme.mono(700, 1)
		var width := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x
		var at := Vector2(
			(size.x - width) * 0.5,
			(size.y + font.get_ascent(TEXT_SIZE) - font.get_descent(TEXT_SIZE)) * 0.5
		)
		draw_string(font, at, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, color)
		return
	_draw_badge(color)
	var scale_factor := ICON_SIZE / ActionIcons.GRID
	var origin := (size - Vector2.ONE * ICON_SIZE) * 0.5
	for line in ActionIcons.polylines(_icon_id):
		var points := PackedVector2Array()
		for p in line:
			points.append(origin + p * scale_factor)
		draw_polyline(points, color, STROKE, true)


func _draw_badge(color: Color) -> void:
	if badge == "":
		return
	var font := HudTheme.mono(700, 1)
	var width := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_SIZE).x
	var at := Vector2(size.x - width - 3.0, font.get_ascent(BADGE_SIZE) + 1.0)
	draw_string(font, at, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_SIZE, color)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		queue_redraw()
	elif what == NOTIFICATION_DISABLED or what == NOTIFICATION_ENABLED:
		queue_redraw()


func _toggled(_on: bool) -> void:
	queue_redraw()


static func _box(fill: Color, border: Color) -> StyleBoxFlat:
	var style := MenuStyle.box(fill, border)
	style.set_content_margin_all(0)
	return style
