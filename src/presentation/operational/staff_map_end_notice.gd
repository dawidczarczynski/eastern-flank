class_name StaffMapEndNotice
extends Control
## Full-screen notice when the operation ends (TASK-115): "Operation over", the side that crossed
## the strategic threshold (it loses), the outcome per side and a Back to menu button. A dim layer
## blocks the map; HUD v3 frame like the battle result notice.

signal menu_pressed

const WIDTH := 460.0

var _title: Label
var _lines: Array[Label] = []
var _menu: Button


func _init() -> void:
	name = "EndNotice"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var frame := FramedPanel.new()
	frame.custom_minimum_size = Vector2(WIDTH, 0)
	frame.chamfers = Vector4(0, 16, 0, 16)
	frame.padding = Vector2(20, 18)
	frame.brackets = true
	frame.bracket_color = Color("#e07c5e")
	frame.tab_color = Color("#e07c5e")
	frame.fill = UiPalette.PANEL_STRONG
	centre.add_child(frame)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 10)
	frame.add_child(column)
	_title = MenuStyle.label("", HudTheme.display(700, 2), 28, UiPalette.HUD_TEXT)
	_title.name = "Title"
	column.add_child(_title)
	for index in 3:
		var line := MenuStyle.label("", HudTheme.mono(500, 0), 12, UiPalette.HUD_DESC)
		line.name = "Line%d" % index
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(line)
		_lines.append(line)
	_menu = MenuStyle.button("")
	_menu.name = "BackToMenu"
	_menu.focus_mode = Control.FOCUS_NONE
	_menu.pressed.connect(func() -> void: menu_pressed.emit())
	column.add_child(_menu)
	hide()


## `lines` = StaffMapEscalation.end_lines; the loser line is red, the winner's in its colour.
func present(lines: Array[String], palette: StaffMapPalette, winner: int) -> void:
	var frame := _title.get_parent().get_parent() as FramedPanel
	frame.tab_text = tr("ESC_END_TAB").to_upper()
	_title.text = tr("ESC_END_TITLE").to_upper()
	for index in _lines.size():
		_lines[index].text = lines[index].to_upper()
	_lines[0].add_theme_color_override(&"font_color", UiPalette.HUD_TEXT)
	_lines[1].add_theme_color_override(&"font_color", palette.ui_alert)
	_lines[2].add_theme_color_override(
		&"font_color", StaffMapFormations.side_colour(palette, winner)
	)
	_menu.text = tr("ESC_END_MENU").to_upper()
	show()


func title_text() -> String:
	return _title.text


func line_text(index: int) -> String:
	return _lines[index].text


func press_menu() -> void:
	_menu.pressed.emit()
