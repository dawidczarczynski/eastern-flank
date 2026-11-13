class_name StaffMapUnitStrip
extends HBoxContainer
## Unit variant of the bottom-bar strip (TASK-151): the formation under the cursor, or else the
## selected own one, in the left slot where StaffMapCard shows the hovered hex and in its look:
## a tab "FORMATION · OWN / HOSTILE" in the side colour, the name (at most two lines), then fixed
## columns STRENGTH (gauge and "30 / 40"), POSTURE and ORDER. The content comes from
## StaffMapUnitCardModel (a hostile formation shows only "EST." and "?"). Ignores the mouse.

const COLUMN_SIZE := 10
const VALUE_SIZE := 12
## The name wraps to at most two lines of this size (StaffMapUnitCardModel.NAME_MAX_CHARS fits).
const NAME_SIZE := 12
## Fixed widths (title, then strength, posture, order): they add up to the 470 px slot.
const TITLE_WIDTH := 124
const COLUMN_WIDTHS: Array[int] = [108, 66, 130]
const SEPARATION := 14
## Height both bottom-bar strips (this one and the terrain strip) are fixed to, so the bar never
## changes height when the cursor goes from a hex to a unit (docs/design/hud_v3 "07").
const SLOT_HEIGHT := 56
## Width of the whole strip (title, three columns and the gaps between them).
const SLOT_WIDTH := (
	TITLE_WIDTH + COLUMN_WIDTHS[0] + COLUMN_WIDTHS[1] + COLUMN_WIDTHS[2] + 3 * SEPARATION
)
const DEFAULT_CAPTIONS: Array[String] = ["STRENGTH", "POSTURE", "ORDER"]
const TAB_SIZE := 9

var formation_id: StringName = &""
var _palette: StaffMapPalette
var _tab: Label
var _tab_style: StyleBoxFlat
var _name_label: Label
var _gauge: StaffMapFormationPanel.Gauge
var _values: Array[Label] = []
var _captions: Array[Label] = []
var _shown: Array = []


func _init() -> void:
	name = "StaffMapUnitStrip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_theme_constant_override(&"separation", SEPARATION)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	custom_minimum_size.y = SLOT_HEIGHT
	var title := VBoxContainer.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_constant_override(&"separation", 1)
	title.custom_minimum_size.x = TITLE_WIDTH
	_tab = _label(HudTheme.mono(600, 1), TAB_SIZE, UiPalette.INK)
	var tab_box := PanelContainer.new()
	tab_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_style = StyleBoxFlat.new()
	_tab_style.bg_color = UiPalette.AMBER
	_tab_style.content_margin_left = 6
	_tab_style.content_margin_right = 8
	_tab_style.content_margin_top = 2
	_tab_style.content_margin_bottom = 2
	tab_box.add_theme_stylebox_override(&"panel", _tab_style)
	tab_box.add_child(_tab)
	tab_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	title.add_child(tab_box)
	_name_label = _label(HudTheme.display(700, 1), NAME_SIZE, UiPalette.HUD_TEXT)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.max_lines_visible = 2
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Two lines high whatever the name: the strip keeps its height (and wraps need a size).
	_name_label.custom_minimum_size = Vector2(
		TITLE_WIDTH, ceilf(_name_label.get_line_height()) * 2.0
	)
	title.add_child(_name_label)
	add_child(title)
	_gauge = StaffMapFormationPanel.Gauge.new()
	add_child(_column("STRENGTH", COLUMN_WIDTHS[0], true))
	add_child(_column("POSTURE", COLUMN_WIDTHS[1], false))
	add_child(_column("ORDER", COLUMN_WIDTHS[2], false))
	hide()


## Shows `model` (StaffMapUnitCardModel.build). `armed_posture` (translated, "" = none) replaces
## the posture of the selected formation while key 1-3 armed a posture for the next click.
##
## The battle scene (no StaffMapPalette) passes `palette` null and a model with "side_color",
## "gauge_color", "unlit_color", "kind" (tab word, default FORMATION) and "captions" (the three
## column captions, translation keys) – see UnitStripModel.
func show_unit(model: Dictionary, palette: StaffMapPalette = null, armed_posture := "") -> void:
	var key := [model, palette, armed_posture]
	if visible and key == _shown:
		return
	_shown = key
	_palette = palette
	formation_id = model["id"]
	var side: Color = (
		model["side_color"]
		if model.has("side_color")
		else StaffMapFormations.side_colour(palette, model["owner_id"])
	)
	_tab_style.bg_color = side
	_tab.text = (
		("%s · %s" % [tr(model.get("kind", "FORMATION") as String), model["side_text"]]).to_upper()
	)
	var captions: Array = model.get("captions", DEFAULT_CAPTIONS)
	for i in _captions.size():
		_captions[i].text = tr(captions[i] as String).to_upper()
	_name_label.text = model["name"]
	_gauge.visible = model["known"]
	if model["known"]:
		if model.has("gauge_color"):
			_gauge.set_value(model["lit"], model["gauge_color"], model["unlit_color"])
		else:
			_gauge.set_value(
				model["lit"],
				StaffMapFormations.strength_colour(
					model["strength"], model["max_strength"], palette
				),
				Color(palette.ui_muted, 0.3)
			)
	_values[0].text = model["strength_text"]
	_values[1].text = armed_posture if armed_posture != "" else model["posture_text"]
	_values[1].add_theme_color_override(
		&"font_color", UiPalette.AMBER if armed_posture != "" else UiPalette.HUD_TEXT
	)
	_values[2].text = model["order_text"]
	show()


func name_text() -> String:
	return _name_label.text


func tab_text() -> String:
	return _tab.text


func has_gauge() -> bool:
	return _gauge.visible


## Text of a column value: 0 strength, 1 posture, 2 order.
func value_text(column: int) -> String:
	return _values[column].text


func _column(caption: String, width: int, with_gauge: bool) -> Control:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 2)
	column.custom_minimum_size.x = width
	var cap := _label(HudTheme.mono(500, 1), COLUMN_SIZE, UiPalette.HUD_MUTED)
	cap.text = tr(caption).to_upper()
	var value := _label(HudTheme.mono(600), VALUE_SIZE, UiPalette.HUD_TEXT)
	value.clip_text = true
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_values.append(value)
	_captions.append(cap)
	column.add_child(cap)
	if with_gauge:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override(&"separation", 6)
		row.add_child(_gauge)
		row.add_child(value)
		column.add_child(row)
	else:
		column.add_child(value)
	return column


func _label(font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label
