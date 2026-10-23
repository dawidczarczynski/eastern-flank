class_name UnitPopup
extends PanelContainer
## Unit hover card (TASK-021), built in code. Content comes from UnitPopupModel (untranslated
## English); this widget translates and lays it out. Ignores the mouse.

const WIDTH := 320
const MONO := "IBMPlexMono-Medium"
const MONO_SEMIBOLD := "IBMPlexMono-SemiBold"
const SANS := "IBMPlexSansCondensed-Regular"
const SANS_SEMIBOLD := "IBMPlexSansCondensed-SemiBold"
const BORDER := Color(235 / 255.0, 232 / 255.0, 223 / 255.0, 0.14)
const SEGMENT_HEIGHT := 7
const BAR_HEIGHT := 2
const PORTRAIT_HEIGHT := 170
const PORTRAIT_BG := Color("#2a2e27")

var _strip: ColorRect
var _portrait: TextureRect
var _type_label: Label
var _faction_label: Label
var _name_label: Label
var _hp_label: Label
var _segments: HBoxContainer
var _stat_values: Array[Label] = []
var _stat_captions: Array[Label] = []
var _stat_bars: Array[_Bar] = []
var _dot: Panel
var _dot_style: StyleBoxFlat
var _status_label: Label


## A 2 px track with a filled part of `fill` (0..1) of its width.
class _Bar:
	extends Control
	var fill := 0.0
	var fill_color := UiPalette.TEXT_MUTED

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, BAR_HEIGHT)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiPalette.DIVIDER)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * fill, size.y)), fill_color)


func _init() -> void:
	name = "UnitPopup"
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Text is translated here; keep Labels from translating the composed strings again.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_theme_stylebox_override(&"panel", _box(UiPalette.PANEL_BG_STRONG, 1, BORDER))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 0)
	add_child(column)

	_strip = ColorRect.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.custom_minimum_size = Vector2(0, 3)
	column.add_child(_strip)

	column.add_child(_build_portrait())
	column.add_child(_build_header())
	column.add_child(_build_strength())
	column.add_child(_build_stats())
	column.add_child(_build_footer())
	hide()


## Fills the card from a UnitPopupModel.build() result.
func show_model(model: Dictionary) -> void:
	var color: Color = model["color"]
	_strip.color = color
	_type_label.text = tr(model["type"] as String).to_upper()
	_faction_label.text = tr(model["faction"] as String)
	_faction_label.add_theme_color_override(&"font_color", color)
	_name_label.text = tr(model["name"] as String)
	_hp_label.text = "%d / %d" % [model["hp"], model["max_hp"]]
	var colors: Array[Color] = model["segments"]
	for child in _segments.get_children():
		_segments.remove_child(child)
		child.queue_free()
	for segment_color in colors:
		var segment := ColorRect.new()
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segment.color = segment_color
		segment.custom_minimum_size = Vector2(0, SEGMENT_HEIGHT)
		segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_segments.add_child(segment)
	var stats: Array = model["stats"]
	for i in stats.size():
		var stat: Dictionary = stats[i]
		_stat_captions[i].text = tr(stat["label"] as String)
		_stat_values[i].text = stat["value"]
		_stat_bars[i].fill = stat["fill"]
		_stat_bars[i].queue_redraw()
	var status_color: Color = model["status_color"]
	_status_label.text = tr(model["status"] as String)
	_status_label.add_theme_color_override(&"font_color", status_color)
	_dot_style.bg_color = status_color
	_dot.queue_redraw()
	show()
	reset_size()


## The unit's rendered portrait; null while it is not ready (plain background).
func set_portrait(portrait: Texture2D) -> void:
	_portrait.texture = portrait


## Real card size for UnitPopupModel.placement() (layout is deferred, so ask the minimum).
func card_size() -> Vector2:
	var minimum := get_combined_minimum_size()
	return Vector2(maxf(minimum.x, WIDTH), minimum.y)


func _build_portrait() -> Control:
	var panel := ColorRect.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.color = PORTRAIT_BG
	panel.custom_minimum_size = Vector2(0, PORTRAIT_HEIGHT)
	_portrait = TextureRect.new()
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(_portrait)
	return panel


func _build_header() -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 2)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_type_label = _label(MONO, 10, UiPalette.TEXT_SECONDARY, 1)
	_type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_faction_label = _label(MONO, 10, UiPalette.TEXT, 1)
	_faction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_type_label)
	row.add_child(_faction_label)
	box.add_child(row)
	_name_label = _label(SANS_SEMIBOLD, 21, UiPalette.TEXT, 0)
	box.add_child(_name_label)
	return _margin(box, 14, 10, 14, 10)


func _build_strength() -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 5)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caption := _label(MONO, 10, UiPalette.TEXT_SECONDARY, 1)
	caption.text = tr("STRENGTH")
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_label = _label(MONO, 12, UiPalette.TEXT, 0)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(caption)
	row.add_child(_hp_label)
	box.add_child(row)
	_segments = HBoxContainer.new()
	_segments.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_segments.add_theme_constant_override(&"separation", 2)
	box.add_child(_segments)
	var panel := _plain_panel(_box(Color(0, 0, 0, 0), 0, UiPalette.DIVIDER))
	panel.add_child(_margin(box, 14, 0, 14, 10))
	return panel


func _build_stats() -> Control:
	var grid := GridContainer.new()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 16)
	grid.add_theme_constant_override(&"v_separation", 9)
	for i in 5:
		var cell := VBoxContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override(&"separation", 4)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var caption := _label(SANS, 12, UiPalette.TEXT_DIM, 0)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value := _label(MONO_SEMIBOLD, 12, UiPalette.TEXT, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(caption)
		line.add_child(value)
		var bar := _Bar.new()
		cell.add_child(line)
		cell.add_child(bar)
		grid.add_child(cell)
		_stat_captions.append(caption)
		_stat_values.append(value)
		_stat_bars.append(bar)
	var panel := _plain_panel(_box(Color(0, 0, 0, 0), 1, UiPalette.DIVIDER, SIDE_TOP))
	panel.add_child(_margin(grid, 14, 10, 14, 12))
	return panel


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 7)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_dot = Panel.new()
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.custom_minimum_size = Vector2(7, 7)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dot_style = StyleBoxFlat.new()
	_dot_style.set_corner_radius_all(4)
	_dot.add_theme_stylebox_override(&"panel", _dot_style)
	_status_label = _label(MONO, 11, UiPalette.TEXT, 0)
	row.add_child(_dot)
	row.add_child(_status_label)
	var panel := _plain_panel(_box(Color(0, 0, 0, 0), 1, UiPalette.DIVIDER, SIDE_TOP))
	panel.add_child(_margin(row, 14, 9, 14, 9))
	return panel


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
