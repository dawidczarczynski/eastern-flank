class_name StaffMapJoinNotice
extends FramedPanel
## Notice "<Country> joins <side> – N formations" of the staff map (TASK-118, HUD v3 "06 Notices"
## look like Toast: chamfered frame, amber `>>`, mono text) with a *Show* button that asks the
## map to centre on the new formations. Hides itself after SECONDS; a new present() restarts it.

signal show_pressed(formation_ids: Array)

const SECONDS := 9.0

var _remaining := 0.0
var _ids: Array = []
var _marker: Label
var _text: Label
var _button: Button


func _init() -> void:
	name = "JoinNotice"
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	chamfers = Vector4(8, 0, 8, 0)
	padding = Vector2(14, 6)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	add_child(row)
	_marker = _label(HudTheme.mono(700, 0), UiPalette.AMBER)
	_marker.text = ">>"
	row.add_child(_marker)
	_text = _label(HudTheme.mono(500, 0), UiPalette.HUD_TEXT)
	_text.name = "Message"
	row.add_child(_text)
	_button = MenuStyle.button(tr("JOIN_SHOW"))
	_button.name = "Show"
	_button.pressed.connect(func() -> void: show_pressed.emit(_ids))
	row.add_child(_button)
	set_process(false)
	hide()


## Shows the (translated) `message` for the formations `ids`; `colour` tints the `>>`.
func present(message: String, ids: Array, colour: Color) -> void:
	_text.text = message
	_marker.add_theme_color_override(&"font_color", colour)
	_button.text = tr("JOIN_SHOW").to_upper()
	_ids = ids.duplicate()
	_remaining = SECONDS
	show()
	reset_size()
	set_process(true)


func message() -> String:
	return _text.text


func formation_ids() -> Array:
	return _ids


func press_show() -> void:
	_button.pressed.emit()


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
	label.add_theme_font_size_override(&"font_size", 12)
	label.add_theme_color_override(&"font_color", color)
	return label
