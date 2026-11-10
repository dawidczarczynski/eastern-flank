class_name ActionTooltip
extends FramedPanel
## HUD tooltip of an action bar button (TASK-139): a title in Chakra with the key on a KeyCap
## beside it, and a longer description below. Built by ActionBarButton._make_custom_tooltip.

const WIDTH := 240


func _init(title: String, key: String, description: String) -> void:
	name = "ActionTooltip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	chamfers = Vector4(8, 0, 8, 0)
	fill = UiPalette.PANEL_STRONG
	padding = Vector2(12, 9)
	custom_minimum_size.x = WIDTH
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 5)
	add_child(column)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override(&"separation", 10)
	column.add_child(head)
	var name_label := _label(HudTheme.display(700, 2), 13, UiPalette.HUD_TEXT)
	name_label.text = title
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	if key != "":
		var cap := KeyCap.new(key)
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(cap)
	if description != "":
		var body := _label(HudTheme.display(400), 12, UiPalette.HUD_DESC)
		body.text = description
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = WIDTH - 24
		column.add_child(body)


func _label(font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label
