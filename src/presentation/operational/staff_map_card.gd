class_name StaffMapCard
extends FramedPanel
## Hover card of the staff map (TASK-093a), HUD v3 style like the terrain card: hex coordinate in
## the tab, terrain name, elevation and road / river flags. Ignores the mouse.

const WIDTH := 220
const ROW_SIZE := 12

var _name_label: Label
var _values: Array[Label] = []


## Untranslated facts about hex `c` (pure, tested): name, hex ("col·row", 1-based), elevation
## ("143 m"), road and river flags.
static func info(grid: HexGrid, c: Vector2i) -> Dictionary:
	var offset := MapGenerator.axial_to_offset(c)
	var metres := grid.elevation_m(c) if grid.has_elevation_m(c) else grid.elevation(c) * 1000.0
	return {
		"name": Terrain.definition(grid.get_terrain(c)).display_name,
		"hex": "%02d·%02d" % [offset.x + 1, offset.y + 1],
		"elevation": "%d m" % roundi(metres),
		"road": grid.road_links(c) != 0,
		"river": grid.river_links(c) != 0,
	}


func _init() -> void:
	super()
	name = "StaffMapCard"
	custom_minimum_size = Vector2(WIDTH, 0)
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	chamfers = Vector4(0, 12, 0, 12)
	padding = Vector2(12, 10)
	tab_text = " "
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 5)
	add_child(column)
	_name_label = _label(HudTheme.display(700, 1), 20, UiPalette.HUD_TEXT)
	column.add_child(_name_label)
	for caption in ["ELEVATION", "Road", "River"]:
		column.add_child(_row(caption))
	hide()
	reset_size()


## Fills the card from `info()` and shows it.
func show_info(data: Dictionary) -> void:
	tab_text = tr("TERRAIN").to_upper()
	tab_right_text = tr("HEX %s") % data["hex"]
	_name_label.text = tr(data["name"] as String).to_upper()
	_values[0].text = data["elevation"]
	_values[1].text = _yes_no(data["road"])
	_values[2].text = _yes_no(data["river"])
	show()
	reset_size()


func name_text() -> String:
	return _name_label.text


func value_text(row: int) -> String:
	return _values[row].text


func _yes_no(value: bool) -> String:
	return tr("Yes").to_upper() if value else tr("No").to_upper()


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
