class_name StaffMapCard
extends HBoxContainer
## Hex strip of the staff map (TASK-093a, TASK-139): the hovered hex in the left zone of the
## bottom bar (docs/design/hud_v3/README.md "07 Bottom command bar"): tab with the hex
## coordinate, terrain name, then elevation, road, river, country and stance columns.
## Ignores the mouse.

const COLUMN_SIZE := 10
## Fixed column widths (title, then elevation, road, river, country, stance): the strip never
## changes width with the hovered hex. They add up to the slot in the bottom bar (470 px).
const TITLE_WIDTH := 114
const COLUMN_WIDTHS: Array[int] = [52, 40, 40, 76, 78]
## A place-based name wraps to at most two lines of this font size, so the strip keeps its height.
const NAMED_TAB_SIZE := 9
const SEPARATION := 14
## Relation of the hex's country to the viewer (CountryRules.relation).
const RELATION_TEXT := {
	&"own": "Ally",
	&"enemy": "Enemy",
	&"hostile": "Hostile",
	&"neutral": "Neutral",
}

## (Vector2i) -> String: a place-based name of a hex, set by the owner; "" = use the hex number.
var place_namer: Callable
var _tab: Label
var _name_label: Label
var _values: Array[Label] = []


## Untranslated facts about hex `c` (pure, tested): name, hex ("col·row", 1-based), elevation
## ("143 m"), road and river flags, `country` (ISO code or "", from ImportedMap.country_at).
static func info(grid: HexGrid, c: Vector2i, country := "") -> Dictionary:
	var offset := MapGenerator.axial_to_offset(c)
	var metres := grid.elevation_m(c) if grid.has_elevation_m(c) else grid.elevation(c) * 1000.0
	return {
		"name": Terrain.definition(grid.get_terrain(c)).display_name,
		"hex": "%02d·%02d" % [offset.x + 1, offset.y + 1],
		"coord": c,
		"elevation": "%d m" % roundi(metres),
		"road": grid.road_links(c) != 0,
		"river": grid.river_links(c) != 0,
		"country": country,
	}


func _init() -> void:
	name = "StaffMapCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_theme_constant_override(&"separation", SEPARATION)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	var title := VBoxContainer.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_constant_override(&"separation", 1)
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
	_name_label = _label(HudTheme.display(700, 1), 17, UiPalette.HUD_TEXT)
	_name_label.clip_text = true
	title.add_child(_name_label)
	add_child(title)
	var captions: Array[String] = ["ELEVATION", "Road", "River", "Country", "Stance"]
	for i in captions.size():
		add_child(_column(captions[i], COLUMN_WIDTHS[i]))
	hide()


## Fills the strip from `info()` and shows it.
func show_info(data: Dictionary) -> void:
	var named := StaffMapPlaceName.named(place_namer, data["coord"]) if data.has("coord") else ""
	_tab.text = (named if named != "" else tr("HEX %s") % data["hex"]).to_upper()
	_tab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if named != "" else TextServer.AUTOWRAP_OFF
	_tab.max_lines_visible = 2 if named != "" else -1
	_tab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_tab.add_theme_font_size_override(&"font_size", NAMED_TAB_SIZE if named != "" else COLUMN_SIZE)
	_tab.custom_minimum_size.x = TITLE_WIDTH - 22.0 if named != "" else 0.0
	_name_label.text = tr(data["name"] as String).to_upper()
	_values[0].text = data["elevation"]
	_values[1].text = _yes_no(data["road"])
	_values[2].text = _yes_no(data["river"])
	var country: String = data.get("country", "")
	_values[3].text = (
		tr(StaffMapCountries.NAMES.get(country, country)).to_upper() if country != "" else "–"
	)
	_values[4].text = (
		tr(RELATION_TEXT.get(data.get("relation", &"none"), "")).to_upper()
		if country != ""
		else "–"
	)
	show()


func name_text() -> String:
	return _name_label.text


func value_text(row: int) -> String:
	return _values[row].text


func _yes_no(value: bool) -> String:
	return tr("Yes").to_upper() if value else tr("No").to_upper()


func _column(caption: String, width: int) -> Control:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 2)
	column.custom_minimum_size.x = width
	var cap := _label(HudTheme.mono(500, 1), COLUMN_SIZE, UiPalette.HUD_MUTED)
	cap.text = tr(caption).to_upper()
	var value := _label(HudTheme.mono(600), 12, UiPalette.HUD_TEXT)
	value.clip_text = true
	_values.append(value)
	column.add_child(cap)
	column.add_child(value)
	return column


func _label(font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label
