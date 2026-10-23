class_name Bracketed
extends HBoxContainer
## Tag in amber brackets, "[ TEXT ]": mono 10.5 (rendered at 11) as used for unit and terrain tags.

const FONT_SIZE := 11

var text: String:
	set(value):
		text = value
		if _label != null:
			_label.text = value

var _label: Label


func _init(tag_text: String = "", text_color: Color = UiPalette.HUD_MUTED) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_theme_constant_override(&"separation", 3)
	add_child(_make(UiPalette.AMBER, "["))
	_label = _make(text_color, tag_text)
	add_child(_label)
	add_child(_make(UiPalette.AMBER, "]"))
	text = tag_text


static func _make(color: Color, content: String) -> Label:
	var label := Label.new()
	label.text = content
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_override(&"font", HudTheme.mono(500))
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.add_theme_color_override(&"font_color", color)
	return label
