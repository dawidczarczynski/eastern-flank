class_name TerrainPanel
extends PanelContainer
## Bottom-left terrain info panel (TASK-024), built in code. Text comes from TerrainPanelModel
## (untranslated English); this widget only translates and lays it out. Ignores the mouse.

const WIDTH := 250
const MONO := "IBMPlexMono-Medium"
const SANS_SEMIBOLD := "IBMPlexSansCondensed-SemiBold"
const CHIP_BG := Color(235 / 255.0, 232 / 255.0, 223 / 255.0, 0.08)
const PATH_BG := Color(235 / 255.0, 232 / 255.0, 223 / 255.0, 0.06)

var _hex_label: Label
var _name_label: Label
var _values: Array[Label] = []
var _tags_margin: MarginContainer
var _tags_flow: HFlowContainer
var _path_row: PanelContainer
var _path_value: Label


func _init() -> void:
	name = "TerrainPanel"
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Text is translated here; keep Labels from translating the composed strings again.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_theme_stylebox_override(&"panel", _box(UiPalette.PANEL_BG, 1, UiPalette.PANEL_BORDER))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 0)
	add_child(column)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _label(MONO, 10, UiPalette.TEXT_SECONDARY, 2)
	title.text = tr("TERRAIN")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hex_label = _label(MONO, 10, UiPalette.TEXT_SECONDARY, 2)
	_hex_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(title)
	header.add_child(_hex_label)
	column.add_child(_margin(header, 12, 9, 12, 0))

	_name_label = _label(SANS_SEMIBOLD, 20, UiPalette.TEXT, 0)
	column.add_child(_margin(_name_label, 12, 4, 12, 10))

	var stats := HBoxContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_theme_constant_override(&"separation", 0)
	var captions: Array[String] = ["MOVE", "DEFENSE", "ELEV."]
	for i in captions.size():
		stats.add_child(_stat_cell(captions[i], i > 0))
	var stats_box := _plain_panel(_box(Color(0, 0, 0, 0), 1, UiPalette.DIVIDER, SIDE_TOP))
	stats_box.add_child(stats)
	column.add_child(stats_box)

	_tags_flow = HFlowContainer.new()
	_tags_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tags_flow.add_theme_constant_override(&"h_separation", 4)
	_tags_flow.add_theme_constant_override(&"v_separation", 4)
	_tags_margin = _margin(_tags_flow, 12, 0, 12, 10)
	column.add_child(_tags_margin)

	_path_row = _plain_panel(_box(PATH_BG, 0, UiPalette.DIVIDER))
	var path_box := HBoxContainer.new()
	path_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path_caption := _label(MONO, 11, UiPalette.TEXT_SECONDARY, 0)
	path_caption.text = tr("PATH COST")
	path_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_value = _label(MONO, 11, UiPalette.TEXT, 0)
	_path_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	path_box.add_child(path_caption)
	path_box.add_child(_path_value)
	_path_row.add_child(_margin(path_box, 12, 8, 12, 8))
	column.add_child(_path_row)
	hide()


## Shows the panel for a TerrainPanelModel.build() result.
func show_tile(model: Dictionary) -> void:
	_hex_label.text = tr("HEX %s") % model["hex"]
	_name_label.text = tr(model["name"] as String)
	_values[0].text = model["move"]
	_values[1].text = model["defense"]
	_values[2].text = model["elevation"]
	for chip in _tags_flow.get_children():
		_tags_flow.remove_child(chip)
		chip.queue_free()
	var tags: PackedStringArray = model["tags"]
	for tag in tags:
		_tags_flow.add_child(_chip(tr(tag)))
	_tags_margin.visible = not tags.is_empty()
	var path_cost: int = model["path_cost"]
	_path_row.visible = path_cost >= 0
	if path_cost >= 0:
		_path_value.text = tr("%d / %d MP") % [path_cost, model["moves_left"]]
	show()
	reset_size()  # shrink to content after rows were hidden


func _stat_cell(caption: String, divider: bool) -> Control:
	var cell := _plain_panel(
		_box(
			Color(0, 0, 0, 0), 1 if divider else 0, UiPalette.DIVIDER, SIDE_LEFT if divider else -1
		)
	)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.custom_minimum_size = Vector2(WIDTH / 3.0 - 1.0, 0)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 2)
	var cap := _label(MONO, 9.5, UiPalette.TEXT_SECONDARY, 1)
	cap.text = tr(caption)
	var value := _label(MONO, 13, UiPalette.TEXT, 0)
	_values.append(value)
	box.add_child(cap)
	box.add_child(value)
	cell.add_child(_margin(box, 12, 8, 12, 8))
	return cell


func _chip(text: String) -> Control:
	var chip := _plain_panel(_box(CHIP_BG, 0, UiPalette.DIVIDER))
	var label := _label(MONO, 10, UiPalette.TEXT_MUTED, 0)
	label.text = text
	chip.add_child(_margin(label, 6, 2, 6, 2))
	return chip


func _label(file: String, size: float, color: Color, spacing: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", HudTheme.font(file, spacing))
	label.add_theme_font_size_override(&"font_size", roundi(size))
	label.add_theme_color_override(&"font_color", color)
	return label


func _margin(child: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", left)
	margin.add_theme_constant_override(&"margin_top", top)
	margin.add_theme_constant_override(&"margin_right", right)
	margin.add_theme_constant_override(&"margin_bottom", bottom)
	margin.add_child(child)
	return margin


func _plain_panel(box: StyleBoxFlat) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(&"panel", box)
	return panel


## `side` -1 = all sides (when width > 0), otherwise only that Side gets the border.
func _box(bg: Color, width: int, border: Color, side: int = -1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	if side < 0:
		box.set_border_width_all(width)
	else:
		box.set_border_width(side as Side, width)
	return box
