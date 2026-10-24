class_name Toast
extends FramedPanel
## Transient message (HUD v3 "06 Notices"): chamfer 8 top-left / bottom-right, `>>` in the active
## faction colour and a mono 11.5 px text. Hides itself after SECONDS; a new message restarts
## the countdown. Anchored by its owner (BattleHud: bottom 130, centred). Ignores the mouse.

const SECONDS := 2.8
const TEXT_SIZE := 11.5

var _remaining := 0.0
var _marker: Label
var _text: Label


func _init() -> void:
	name = "Toast"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	chamfers = Vector4(8, 0, 8, 0)
	padding = Vector2(14, 8)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 8)
	add_child(row)
	_marker = _label(HudTheme.mono(700, 0), UiPalette.AMBER)
	_marker.text = ">>"
	row.add_child(_marker)
	_text = _label(HudTheme.mono(500, 0), UiPalette.HUD_TEXT)
	_text.name = "Message"
	row.add_child(_text)
	set_process(false)
	hide()


## Shows `message` (already translated) and restarts the countdown; `color` tints the `>>`.
func show_message(message: String, color: Color = UiPalette.AMBER) -> void:
	_text.text = message
	_marker.add_theme_color_override(&"font_color", color)
	_remaining = SECONDS
	show()
	set_process(true)


func message() -> String:
	return _text.text


func remaining() -> float:
	return _remaining


func advance(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_remaining = 0.0
		hide()
		set_process(false)


func _process(delta: float) -> void:
	advance(delta)


func _label(font: Font, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", int(ceilf(TEXT_SIZE)))
	label.add_theme_color_override(&"font_color", color)
	return label
