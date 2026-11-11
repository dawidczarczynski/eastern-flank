class_name StaffMapOddsRow
extends PanelContainer
## The interception odds line of a planned strike (TASK-098b, docs/design/operational_map/
## air_defence_overlay.html variant A): a shield glyph and the text of StaffMapAirDefence.odds()
## with its number in mono. Full size (28 px row, confirm card) or `chip` (24 px "AT TARGET ·"
## chip, strike panel). Colours: `outcome.intercepted` blue with cover, `ui.amber` suppressed,
## `ui.muted` no cover. Ignores the mouse.

const HEIGHT := 28.0
const CHIP_HEIGHT := 24.0
const BLUE := Color("#6f95ab")  # outcome.intercepted
const GLYPH_SIZE := Vector2(14, 16)

var _chip := false
var _kind: StringName = &""
var _colour := BLUE
var _glyph: Control
var _row: HBoxContainer
var _text := ""


func _init(chip := false) -> void:
	_chip = chip
	name = "OddsChip" if chip else "OddsRow"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size = Vector2(0, CHIP_HEIGHT if chip else HEIGHT)
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override(&"separation", 8)
	add_child(_row)
	hide()


## Shows a StaffMapAirDefence.odds() model; an empty model hides the row.
func show_odds(model: Dictionary) -> void:
	if model.is_empty():
		hide()
		return
	_kind = model["kind"]
	_text = model["text"]
	_colour = _colour_of(_kind)
	var fill := Color(_colour, 0.08) if _kind != StaffMapAirDefence.ODDS_NONE else Color(0, 0, 0, 0)
	var edge := Color(_colour, 0.5) if _kind != StaffMapAirDefence.ODDS_NONE else Color("#3a3f33")
	var style := MenuStyle.box(fill, edge)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2 if _chip else 4
	style.content_margin_bottom = 2 if _chip else 4
	add_theme_stylebox_override(&"panel", style)
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	if _chip:
		_row.add_child(
			MenuStyle.label(
				tr("AT TARGET").to_upper(), HudTheme.display(600, 2), 10, UiPalette.HUD_MUTED
			)
		)
	else:
		_glyph = Control.new()
		_glyph.custom_minimum_size = GLYPH_SIZE
		_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glyph.draw.connect(_draw_glyph)
		_row.add_child(_glyph)
	_add_text(model)
	show()


func kind() -> StringName:
	return _kind if visible else &""


## The line as shown ("Interception ~35% per missile"); "" when hidden.
func text() -> String:
	return _text if visible else ""


func colour() -> Color:
	return _colour


static func _colour_of(kind: StringName) -> Color:
	match kind:
		StaffMapAirDefence.ODDS_SOME:
			return BLUE
		StaffMapAirDefence.ODDS_SUPPRESSED:
			return UiPalette.AMBER
	return UiPalette.HUD_MUTED


## The text with its number in mono (the number is found in the translated text itself).
func _add_text(model: Dictionary) -> void:
	var size_px := 12 if not _chip else 11
	var text_font := HudTheme.display(700, 1)
	var text: String = model["text"]
	var number := "%d%%" % int(model["percent"])
	var at := text.find(number) if model["kind"] == StaffMapAirDefence.ODDS_SOME else -1
	if at < 0:
		_row.add_child(MenuStyle.label(text, text_font, size_px, _colour))
		return
	var number_size := 13 if _chip else 16
	var holder := HBoxContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_constant_override(&"separation", 0)
	holder.add_child(MenuStyle.label(text.substr(0, at), text_font, size_px, _colour))
	holder.add_child(MenuStyle.label(number, HudTheme.mono(700, 0), number_size, _colour))
	holder.add_child(
		MenuStyle.label(text.substr(at + number.length()), text_font, size_px, _colour)
	)
	_row.add_child(holder)


## A shield outline: flat top, pointed bottom.
func _draw_glyph() -> void:
	var w := GLYPH_SIZE.x
	var h := GLYPH_SIZE.y
	var points := PackedVector2Array(
		[
			Vector2(0.5, 1.5),
			Vector2(w * 0.5, 0.5),
			Vector2(w - 0.5, 1.5),
			Vector2(w - 0.5, h * 0.55),
			Vector2(w * 0.5, h - 0.5),
			Vector2(0.5, h * 0.55),
			Vector2(0.5, 1.5),
		]
	)
	_glyph.draw_polyline(points, _colour, 1.4, true)
	if _kind == StaffMapAirDefence.ODDS_SUPPRESSED or _kind == StaffMapAirDefence.ODDS_NONE:
		_glyph.draw_line(Vector2(1, h - 1), Vector2(w - 1, 1), _colour, 1.4, true)
