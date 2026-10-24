class_name TerrainPanel
extends FramedPanel
## HUD v3 terrain card (TASK-079, docs/design/hud_v3/README.md "03 Terrain card"), built in code.
## Text comes from TerrainPanelModel (untranslated English); this widget only translates and lays
## it out. Ignores the mouse.

const WIDTH := 262
const NAME_SIZE := 20
const ROW_SIZE := 12
const LEADER_DOT_PERIOD := 4.0

var _name_label: Label
var _city_label: Label
var _values: Array[Label] = []
var _tags_wrap: Control
var _tags: HFlowContainer
var _path_wrap: Control
var _path_box: PanelContainer
var _path_label: Label


## Dotted leader between a row caption and its value (CSS: 1 px dots every 4 px at the baseline).
class _Leader:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_END
		custom_minimum_size = Vector2(12, 5)

	func _draw() -> void:
		var x := 0.0
		while x < size.x:
			draw_rect(Rect2(x, size.y - 2.0, 1, 1), UiPalette.HUD_MUTED)
			x += LEADER_DOT_PERIOD


func _init() -> void:
	super()
	name = "TerrainPanel"
	custom_minimum_size = Vector2(WIDTH, 0)
	# Text is translated here; keep Labels from translating the composed strings again.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	chamfers = Vector4(0, 12, 0, 12)
	padding = Vector2(12, 10)
	tab_text = " "  # reserves the tab row; the real text is set in show_tile()
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 0)
	add_child(column)
	_name_label = _label(HudTheme.display(700, 1), NAME_SIZE, UiPalette.HUD_TEXT)
	column.add_child(_name_label)
	_city_label = _label(HudTheme.mono(500), 12, UiPalette.AMBER)
	column.add_child(_city_label)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override(&"separation", 6)
	for caption in ["MOVE COST", "DEFENSE MOD.", "ELEVATION"]:
		rows.add_child(_row(caption))
	column.add_child(_margin(rows, 0, 9, 0, 0))
	_tags = HFlowContainer.new()
	_tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tags.add_theme_constant_override(&"h_separation", 8)
	_tags.add_theme_constant_override(&"v_separation", 3)
	_tags_wrap = _margin(_tags, 0, 9, 0, 0)
	column.add_child(_tags_wrap)
	_path_label = _label(HudTheme.mono(600, 1), 11, UiPalette.HUD_TEXT)
	_path_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_path_box = PanelContainer.new()
	_path_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_path_box.add_child(_margin(_path_label, 8, 5, 8, 5))
	_path_wrap = _margin(_path_box, 0, 10, 0, 0)
	column.add_child(_path_wrap)
	hide()


## Shows the card for a TerrainPanelModel.build() result; `accent` colours the path row (the
## active faction).
func show_tile(model: Dictionary, accent := UiPalette.AMBER) -> void:
	tab_text = tr("TERRAIN").to_upper()
	tab_right_text = tr("HEX %s") % model["hex"]
	_name_label.text = tr(model["name"] as String).to_upper()
	var city: String = model.get("city", "")
	_city_label.text = "◆ %s" % tr(city)
	_city_label.visible = city != ""
	_values[0].text = model["move"]
	_values[1].text = model["defense"]
	_values[2].text = model["elevation"]
	for tag in _tags.get_children():
		_tags.remove_child(tag)
		tag.queue_free()
	var tags: PackedStringArray = model["tags"]
	for tag in tags:
		_tags.add_child(Bracketed.new(tr(tag).to_upper()))
	_tags_wrap.visible = not tags.is_empty()
	var path_cost: int = model["path_cost"]
	_path_wrap.visible = path_cost >= 0
	if path_cost >= 0:
		_path_label.text = (
			("%s · %s" % [tr("PATH"), tr("%d / %d MP") % [path_cost, model["moves_left"]]])
			. to_upper()
		)
		_path_label.add_theme_color_override(&"font_color", accent)
		_path_box.add_theme_stylebox_override(&"panel", _path_style(accent))
	show()
	reset_size()  # shrink to content after rows were hidden


func _row(caption: String) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 6)
	var cap := _label(HudTheme.display(400), ROW_SIZE, UiPalette.HUD_MUTED)
	cap.text = tr(caption).to_upper()
	var value := _label(HudTheme.mono(600), ROW_SIZE, UiPalette.HUD_TEXT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_values.append(value)
	row.add_child(cap)
	row.add_child(_Leader.new())
	row.add_child(value)
	return row


func _path_style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color, 0.08)
	box.border_color = color
	box.set_border_width_all(1)
	return box


func _label(font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", size)
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
