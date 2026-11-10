class_name TerrainPanel
extends HBoxContainer
## Terrain strip in the left zone of the bottom bar (TASK-079, TASK-139, docs/design/hud_v3/
## README.md "07 Bottom command bar"): a tab with the hex, the terrain name, the city, three
## key / value columns, tags and the path chip. Text comes from TerrainPanelModel (untranslated
## English); this widget only translates and lays it out. Ignores the mouse. Without a hovered
## hex it shows `HOVER A HEX`; the strip keeps its width so the bar does not jump.

## Fixed slot widths: the strip never changes width with the hovered hex.
const TITLE_WIDTH := 100
const COLUMN_WIDTH := 58
const SIDE_WIDTH := 112  # path chip over the tags
const SEPARATION := 12
const MIN_WIDTH := TITLE_WIDTH + 3 * COLUMN_WIDTH + SIDE_WIDTH + 4 * SEPARATION
const NAME_SIZE := 17
const COLUMN_SIZE := 10

var _empty: Label
var _content: HBoxContainer
var _tab: Label
var _name_label: Label
var _city_label: Label
var _values: Array[Label] = []
var _tags: HBoxContainer
var _path_label: Label
var _path_box: PanelContainer


func _init() -> void:
	name = "TerrainPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(MIN_WIDTH, 0)
	# Text is translated here; keep Labels from translating the composed strings again.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_empty = _label(HudTheme.mono(500, 1), COLUMN_SIZE, UiPalette.HUD_MUTED)
	_empty.text = tr("HOVER A HEX").to_upper()
	add_child(_empty)
	_content = HBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override(&"separation", SEPARATION)
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_content)
	var title := VBoxContainer.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_constant_override(&"separation", 0)
	title.custom_minimum_size.x = TITLE_WIDTH
	_tab = _label(HudTheme.mono(600, 1), COLUMN_SIZE, UiPalette.INK)
	var tab_box := PanelContainer.new()
	tab_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tab_style := StyleBoxFlat.new()
	tab_style.bg_color = UiPalette.AMBER
	tab_style.content_margin_left = 8
	tab_style.content_margin_right = 14
	tab_style.content_margin_top = 2
	tab_style.content_margin_bottom = 2
	tab_box.add_theme_stylebox_override(&"panel", tab_style)
	tab_box.add_child(_tab)
	tab_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	title.add_child(tab_box)
	_name_label = _label(HudTheme.display(700, 1), NAME_SIZE, UiPalette.HUD_TEXT)
	_name_label.clip_text = true
	title.add_child(_name_label)
	_city_label = _label(HudTheme.mono(500), 11, UiPalette.AMBER)
	title.add_child(_city_label)
	_content.add_child(title)
	for caption in ["MOVE COST", "DEF. MOD", "ELEVATION"]:
		_content.add_child(_column(caption))
	var side := VBoxContainer.new()
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_theme_constant_override(&"separation", 4)
	side.custom_minimum_size.x = SIDE_WIDTH
	_content.add_child(side)
	_path_label = _label(HudTheme.mono(600, 1), COLUMN_SIZE, UiPalette.HUD_TEXT)
	_path_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_path_box = PanelContainer.new()
	_path_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for edge in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + edge, 5)
	for edge in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 2)
	margin.add_child(_path_label)
	_path_box.add_child(margin)
	side.add_child(_path_box)
	_tags = HBoxContainer.new()
	_tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tags.add_theme_constant_override(&"separation", 6)
	_tags.clip_contents = true
	side.add_child(_tags)
	clear()


## No hovered hex: the placeholder instead of the strip.
func clear() -> void:
	_content.hide()
	_empty.show()


## Shows the strip for a TerrainPanelModel.build() result; `accent` colours the path chip (the
## active faction).
func show_tile(model: Dictionary, accent := UiPalette.AMBER) -> void:
	_tab.text = (tr("HEX %s") % model["hex"]).to_upper()
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
	var path_cost: int = model["path_cost"]
	_path_box.visible = path_cost >= 0
	if path_cost >= 0:
		_path_label.text = ((tr("%d / %d MP") % [path_cost, model["moves_left"]]).to_upper())
		_path_label.add_theme_color_override(&"font_color", accent)
		_path_box.add_theme_stylebox_override(&"panel", _path_style(accent))
	_empty.hide()
	_content.show()


func is_showing_tile() -> bool:
	return _content.visible


func name_text() -> String:
	return _name_label.text


func _column(caption: String) -> Control:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 2)
	column.custom_minimum_size.x = COLUMN_WIDTH
	var cap := _label(HudTheme.mono(500, 1), COLUMN_SIZE, UiPalette.HUD_MUTED)
	cap.text = tr(caption).to_upper()
	var value := _label(HudTheme.mono(600), 12, UiPalette.HUD_TEXT)
	_values.append(value)
	column.add_child(cap)
	column.add_child(value)
	return column


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
