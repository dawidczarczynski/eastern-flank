class_name StaffMapFormationPanel
extends StaffMapWindow
## Formation panel of the staff map (TASK-092b, look: docs/design/operational_map "Panels"),
## HUD v3 style, on the right edge: name, parent, type, side, strength (5-segment gauge),
## location and the companies (ref, unit type, strength). Hostile formations are fully shown
## (fog is TASK-100) but marked HOSTILE in the tab and the side row. Own formations also
## show posture, points and order (TASK-092d). Stops the mouse, so a click on it never reaches a
## counter under it.

const WIDTH := 300
const ROW_SIZE := 12
const REF_SIZE := 10


## A 5-segment strength gauge (StaffMapCounter.draw_segments) as a control.
class Gauge:
	extends Control
	const SCALE := 1.3
	var lit := 0
	var colour := Color.WHITE
	var unlit := Color(1, 1, 1, 0.2)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(
			StaffMapCounter.segments_width(SCALE), StaffMapCounter.SEGMENT_SIZE.y * SCALE
		)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_value(p_lit: int, p_colour: Color, p_unlit: Color) -> void:
		lit = p_lit
		colour = p_colour
		unlit = p_unlit
		queue_redraw()

	func _draw() -> void:
		StaffMapCounter.draw_segments(self, Vector2.ZERO, lit, colour, unlit, SCALE)


## (Vector2i) -> String: a place-based name of a hex, set by the owner; "" = use the hex number.
var place_namer: Callable
var formation_id: StringName = &""
var hostile := false

var _palette: StaffMapPalette
var _name_label: Label
var _parent_label: Label
var _values := {}  # caption -> Label
var _gauge: Gauge
var _companies: VBoxContainer
var _order_box: VBoxContainer
var _companies_caption: Label
var _country_row: Control  # country of origin of a joined ally (TASK-118)


func _init() -> void:
	super(" ", WIDTH)
	name = "FormationPanel"
	dock_side = StaffMapWindow.Dock.RIGHT
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 5)
	add_child(column)
	_name_label = _label(HudTheme.display(700, 1), 18, UiPalette.HUD_TEXT)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A fixed width, so the wrapped height is known before the first layout.
	_name_label.custom_minimum_size = Vector2(WIDTH - 2 * padding.x - 2, 0)
	column.add_child(_name_label)
	_parent_label = _label(HudTheme.display(500), ROW_SIZE, UiPalette.HUD_MUTED)
	column.add_child(_parent_label)
	column.add_child(_divider())
	for caption in ["Type", "Side", "STRENGTH", "Location"]:
		column.add_child(_row(caption))
	_country_row = _row("Country")
	_country_row.hide()
	column.add_child(_country_row)
	_order_box = VBoxContainer.new()
	_order_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_order_box.add_theme_constant_override(&"separation", 5)
	for caption in ["POSTURE", "POINTS", "ORDER"]:
		_order_box.add_child(_row(caption))
	_order_box.hide()
	column.add_child(_order_box)
	column.add_child(_divider())
	_companies_caption = _label(HudTheme.mono(600, 1), REF_SIZE, UiPalette.HUD_MUTED)
	column.add_child(_companies_caption)
	_companies = VBoxContainer.new()
	_companies.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_companies.add_theme_constant_override(&"separation", 6)
	column.add_child(_companies)
	hide()


## Fills the panel from a formation of `state` and shows it.
func show_formation(
	state: OperationalState, formation: Formation, viewer_player: int, palette: StaffMapPalette
) -> void:
	_palette = palette
	formation_id = formation.id
	hostile = (
		StaffMapFormations.viewer_relation(formation.owner_id, viewer_player)
		== StaffMapFormations.ENEMY
	)
	var side_colour := StaffMapFormations.side_colour(palette, formation.owner_id)
	tab_text = tr("FORMATION").to_upper()
	tab_right_text = tr("HOSTILE") if hostile else tr("OWN")
	tab_right_color = side_colour
	tab_color = side_colour
	line_color = Color(side_colour, 0.45) if hostile else UiPalette.LINE
	_name_label.text = tr(formation.display_name).to_upper()
	_parent_label.text = tr(formation.parent)
	_values["Type"].text = tr(formation.definition.display_name).to_upper()
	var side := SideDefinition.find(state.player_sides[formation.owner_id])
	var side_name := tr(side.display_name) if side != null else ""
	var side_label: Label = _values["Side"]
	side_label.text = (
		(("%s · %s" % [side_name, tr("HOSTILE")]) if hostile else side_name).to_upper()
	)
	side_label.add_theme_color_override(&"font_color", side_colour)
	var current := formation.strength()
	var maximum := formation.max_strength()
	_values["STRENGTH"].text = "%d / %d" % [current, maximum]
	_gauge.set_value(
		StaffMapFormations.lit_segments(current, maximum),
		StaffMapFormations.strength_colour(current, maximum, palette),
		Color(palette.ui_muted, 0.3)
	)
	_values["Location"].text = _place_text(formation.coord, true)
	_companies_caption.text = tr("COMPANIES").to_upper()
	_fill_companies(formation)
	show()
	reset_size()


## Shows the country of origin of a joined ally (translation key of its name); "" hides the row.
func show_origin(country_name: String) -> void:
	_country_row.visible = country_name != ""
	_values["Country"].text = tr(country_name).to_upper()
	reset_size()


## Posture and order of an own formation (TASK-092d): "[2] ATTACK", the move points it spends per
## turn against the formation's own, and the destination of its order. Keys 1 / 2 / 3 change the
## posture, Delete cancels the order.
func show_order(formation: Formation) -> void:
	var posture := OperationalPosture.find(formation.posture)
	var move_points := formation.definition.move_points
	(_values["POSTURE"] as Label).text = (
		StaffMapOrderRingModel.caption(formation.posture).to_upper()
	)
	var budget := OperationalOrders.budget(formation, posture) if posture != null else move_points
	(_values["POINTS"] as Label).text = "%d / %d" % [budget, move_points]
	(_values["ORDER"] as Label).text = (
		tr("ORDER_NONE")
		if formation.order == null
		else _place_text(formation.order.destination, false)
	)
	_order_box.show()
	reset_size()


func hide_order() -> void:
	_order_box.hide()
	reset_size()


func order_visible() -> bool:
	return _order_box.visible


func name_text() -> String:
	return _name_label.text


func parent_text() -> String:
	return _parent_label.text


func value_text(caption: String) -> String:
	return (_values[caption] as Label).text


func company_count() -> int:
	return _companies.get_child_count()


## Text of a company entry: "<unit>  <strength>/<max>  <ref>".
func company_text(index: int) -> String:
	var parts: Array[String] = []
	for row in _companies.get_child(index).get_children():
		for child in row.get_children():
			if child is Label:
				parts.append((child as Label).text)
	return "  ".join(parts)


## The place name of a hex, else its number ("HEX 06·01" when `prefixed`).
func _place_text(c: Vector2i, prefixed: bool) -> String:
	var named := StaffMapPlaceName.named(place_namer, c)
	if named != "":
		return named
	return tr("HEX %s") % _hex_text(c) if prefixed else _hex_text(c)


## The axial coordinate as the hex card shows it ("col·row", 1-based offset).
static func _hex_text(c: Vector2i) -> String:
	var offset := MapGenerator.axial_to_offset(c)
	return "%02d·%02d" % [offset.x + 1, offset.y + 1]


func _fill_companies(formation: Formation) -> void:
	for child in _companies.get_children():
		_companies.remove_child(child)
		child.queue_free()
	for i in formation.companies.size():
		var company := formation.companies[i]
		var unit: UnitDefinition = (
			formation.definition.companies[i] if i < formation.definition.companies.size() else null
		)
		# Two lines: unit type and strength, then ref and gauge.
		var entry := VBoxContainer.new()
		entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_theme_constant_override(&"separation", 1)
		var top := _hbox()
		var unit_label := _label(HudTheme.display(600), ROW_SIZE, UiPalette.HUD_TEXT)
		unit_label.text = tr(unit.display_name) if unit != null else String(company.unit_type)
		unit_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unit_label.clip_text = true
		var value := _label(HudTheme.mono(600), REF_SIZE, UiPalette.HUD_TEXT)
		value.text = "%d/%d" % [company.strength, company.max_strength]
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		top.add_child(unit_label)
		top.add_child(value)
		var bottom := _hbox()
		var ref := _label(HudTheme.mono(500), REF_SIZE, UiPalette.HUD_MUTED)
		ref.text = company.ref
		ref.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var gauge := Gauge.new()
		gauge.set_value(
			StaffMapFormations.lit_segments(company.strength, company.max_strength),
			StaffMapFormations.strength_colour(company.strength, company.max_strength, _palette),
			Color(_palette.ui_muted, 0.3)
		)
		bottom.add_child(ref)
		bottom.add_child(gauge)
		entry.add_child(top)
		entry.add_child(bottom)
		_companies.add_child(entry)


func _hbox() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 8)
	return row


func _row(caption: String) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 8)
	var cap := _label(HudTheme.display(400), ROW_SIZE, UiPalette.HUD_MUTED)
	cap.text = tr(caption).to_upper()
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cap)
	if caption == "STRENGTH":
		_gauge = Gauge.new()
		row.add_child(_gauge)
	var value := _label(HudTheme.mono(600), ROW_SIZE, UiPalette.HUD_TEXT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if caption in ["Location", "ORDER"]:  # place names can be long: wrap them
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.custom_minimum_size.x = 150.0
	_values[caption] = value
	row.add_child(value)
	return row


func _divider() -> Control:
	var line := ColorRect.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.color = UiPalette.DIVIDER
	line.custom_minimum_size = Vector2(0, 1)
	return line


func _label(font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label
