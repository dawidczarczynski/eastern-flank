class_name StaffMapInstallationCard
extends FramedPanel
## Hover card of an installation (TASK-097a), the look of StaffMapCard: class in the tab, the
## name large, then country, integrity and what the installation gives. Ignores the mouse.

const WIDTH := 220
const ROW_SIZE := 12

var _name_label: Label
var _gives_label: Label
var _note_label: Label
var _values: Array[Label] = []


func _init() -> void:
	super()
	name = "StaffMapInstallationCard"
	custom_minimum_size = Vector2(WIDTH, 0)
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	chamfers = Vector4(0, 12, 0, 12)
	padding = Vector2(12, 10)
	tab_text = " "
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 5)
	add_child(column)
	_name_label = _label(HudTheme.display(700, 1), 20, UiPalette.HUD_TEXT)
	column.add_child(_name_label)
	for caption in ["Country", "Integrity"]:
		column.add_child(_row(caption))
	_gives_label = _label(HudTheme.display(400), ROW_SIZE, UiPalette.HUD_MUTED)
	_gives_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gives_label.custom_minimum_size = Vector2(WIDTH - 24, 0)
	column.add_child(_gives_label)
	_note_label = _label(HudTheme.mono(600, 0), ROW_SIZE, Color("#e07c5e"))
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label.custom_minimum_size = Vector2(WIDTH - 24, 0)
	_note_label.hide()
	column.add_child(_note_label)
	hide()
	reset_size()


## Fills the card from StaffMapInstallations.info() and shows it.
func show_info(data: Dictionary) -> void:
	tab_text = tr(data["class"] as String).to_upper()
	_name_label.text = tr(data["name"] as String).to_upper()
	_values[0].text = tr(data["country"] as String).to_upper() if data["country"] != "" else "–"
	_values[1].text = "DESTROYED" if data["destroyed"] else "%d %%" % data["integrity"]
	_gives_label.text = tr(data["gives"] as String)
	set_note("")
	show()
	reset_size()


## A line in the alert colour under the facts (the strike mode's reason, TASK-097b); "" hides it.
func set_note(text: String) -> void:
	_note_label.text = text
	_note_label.visible = text != ""
	reset_size()


func note_text() -> String:
	return _note_label.text if _note_label.visible else ""


func name_text() -> String:
	return _name_label.text


func value_text(row: int) -> String:
	return _values[row].text


func gives_text() -> String:
	return _gives_label.text


func _row(caption: String) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := _label(HudTheme.display(400), ROW_SIZE, UiPalette.HUD_MUTED)
	cap.text = tr(caption).to_upper()
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := _label(HudTheme.mono(600), ROW_SIZE, UiPalette.HUD_TEXT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_values.append(value)
	row.add_child(cap)
	row.add_child(value)
	return row


func _label(font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label
