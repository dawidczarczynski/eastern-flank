class_name TargetingBar
extends FramedPanel
## Targeting mode bar (HUD v3 "06 Notices"): 16 px amber hatch | amber block with the mode title |
## unit · instruction · keycaps (`LMB`, `RMB`/`ESC`), inside a 1 px rgba(232,176,74,.6) border.
## Anchored by its owner (BattleHud: top 118, centred). Ignores the mouse. The targeting mode
## itself arrives with TASK-081/082; this is only the display.

const HATCH_WIDTH := 16
const TITLE_SIZE := 13
const TEXT_SIZE := 11

var _title: Label
var _unit: Label
var _instruction: Label


func _init() -> void:
	name = "TargetingBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	line_color = UiPalette.AMBER_BORDER
	padding = Vector2.ZERO
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 0)
	add_child(row)
	var hatch := HatchBar.new(UiPalette.AMBER, Vector2(HATCH_WIDTH, 1))
	hatch.name = "Hatch"
	row.add_child(hatch)
	var block := PanelContainer.new()
	block.name = "TitleBlock"
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.AMBER
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	block.add_theme_stylebox_override(&"panel", style)
	row.add_child(block)
	_title = _label(HudTheme.display(700, 2), TITLE_SIZE, UiPalette.INK)
	_title.name = "Title"
	block.add_child(_title)
	var info := HBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override(&"separation", 10)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 14)
	margin.add_theme_constant_override(&"margin_right", 14)
	margin.add_child(info)
	row.add_child(margin)
	_unit = _label(HudTheme.mono(600, 1), TEXT_SIZE, UiPalette.HUD_TEXT)
	_unit.name = "Unit"
	info.add_child(_unit)
	info.add_child(_dot())
	_instruction = _label(HudTheme.mono(500, 0), TEXT_SIZE, UiPalette.HUD_DESC)
	_instruction.name = "Instruction"
	info.add_child(_instruction)
	info.add_child(_dot())
	info.add_child(_key_group("LMB", "CONFIRM"))
	info.add_child(_key_group("RMB/ESC", "CANCEL"))
	hide()


## Shows the bar. All three texts are translation keys (or already plain text).
func show_targeting(title: String, unit_text: String, instruction: String) -> void:
	_title.text = tr(title).to_upper()
	_unit.text = tr(unit_text).to_upper()
	_instruction.text = tr(instruction)
	show()


func hide_targeting() -> void:
	hide()


func title_text() -> String:
	return _title.text


func unit_text() -> String:
	return _unit.text


func instruction_text() -> String:
	return _instruction.text


func _key_group(key: String, label_key: String) -> Control:
	var pair := HBoxContainer.new()
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pair.add_theme_constant_override(&"separation", 5)
	pair.add_child(KeyCap.new(key))
	var label := _label(HudTheme.mono(500, 0), 10, UiPalette.HUD_MUTED)
	label.text = tr(label_key).to_upper()
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pair.add_child(label)
	return pair


func _dot() -> Label:
	var dot := _label(HudTheme.mono(500, 0), TEXT_SIZE, UiPalette.HUD_MUTED)
	dot.text = "·"
	return dot


func _label(font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label
