class_name StaffMapCountryCard
extends FramedPanel
## Country card of the staff map (TASK-114, docs/design/operational_map "Panels" – closed-country
## card): the country's stance seen from the viewer, its leaning, whether it is a sanctuary and
## what it allows the viewer – may enter, may strike – with the reason when not. Opened by a click
## on a country name (or C on the hovered hex), closed by Esc / the next click elsewhere.
## `info` is pure and tested; the card only shows it. Stances are read, never changed.

const WIDTH := 250
const ROW_SIZE := 12

var _name_label: Label
var _values: Array[Label] = []
var _reasons: Array[Label] = []
var _country := &""


## Untranslated facts about `country_id` for `player`: name (translation key), relation
## (CountryRules.relation), stance (display key), leaning (key), sanctuary, may_enter / may_strike
## and their reasons ("" when allowed, otherwise a translation key). Empty for an unknown id.
static func info(state: OperationalState, player: int, country_id: StringName) -> Dictionary:
	var country := state.get_country(country_id)
	if country == null:
		return {}
	var relation := CountryRules.relation(state, player, country_id)
	var coord := _any_hex(state, country_id)
	var may_enter := CountryRules.may_enter(state, player, coord)
	var may_strike := CountryRules.may_strike(state, player, coord)
	var enter_reason := "" if may_enter else _closed_reason(relation)
	return {
		"id": country_id,
		"name": country.definition.display_name,
		"iso": country.definition.iso_code,
		"relation": relation,
		"stance": _stance_text(country, relation),
		"leaning": _leaning_text(country, player),
		"sanctuary": country.definition.sanctuary,
		"may_enter": may_enter,
		"enter_reason": enter_reason,
		"may_strike": may_strike,
		"strike_reason":
		"" if may_strike else ("Your own soil" if relation == &"own" else enter_reason),
	}


static func _any_hex(state: OperationalState, country_id: StringName) -> Vector2i:
	for coord: Vector2i in state.country_map:
		if state.country_map[coord] == country_id:
			return coord
	return Vector2i(-100000, -100000)


static func _stance_text(country: CountryState, relation: StringName) -> String:
	match relation:
		&"own":
			var at_war := country.stance == CountryState.BELLIGERENT
			return "At war on your side" if at_war else "Aligned with you"
		&"enemy":
			return "At war against you"
		&"hostile":
			return "Aligned with the enemy"
	return "Neutral"


static func _leaning_text(country: CountryState, player: int) -> String:
	if country.leaning < 0:
		return "No leaning"
	return "Leans to you" if country.leaning == player else "Leans to the enemy"


static func _closed_reason(relation: StringName) -> String:
	match relation:
		&"neutral":
			return "Closed: neutral country"
		&"hostile":
			return "Closed: hostile to you"
		&"enemy":
			return "Closed: sanctuary until open war"
	return ""


func _init() -> void:
	super()
	name = "StaffMapCountryCard"
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
	for caption in ["Stance", "Leaning", "Sanctuary", "May enter", "May strike"]:
		column.add_child(_row(caption))
	hide()
	reset_size()


## Shows the card for `data` (from `info`), tinted by the relation's colour.
func show_info(data: Dictionary, palette: StaffMapPalette) -> void:
	if data.is_empty():
		hide()
		return
	_country = data["id"]
	var ink := StanceTint.ink(palette, data["relation"])
	tab_text = tr("Country").to_upper()
	tab_right_text = data["iso"]
	tab_color = ink
	_name_label.text = tr(data["name"] as String).to_upper()
	_name_label.add_theme_color_override(&"font_color", ink)
	_values[0].text = tr(data["stance"] as String).to_upper()
	_values[1].text = tr(data["leaning"] as String).to_upper()
	_values[2].text = _yes_no(data["sanctuary"])
	_values[3].text = _yes_no(data["may_enter"])
	_values[4].text = _yes_no(data["may_strike"])
	_reasons[3].text = tr(data["enter_reason"] as String) if data["enter_reason"] != "" else ""
	_reasons[4].text = tr(data["strike_reason"] as String) if data["strike_reason"] != "" else ""
	for reason in _reasons:
		if reason != null:
			reason.visible = reason.text != ""
	show()
	reset_size()


func country_id() -> StringName:
	return _country


func value_text(row: int) -> String:
	return _values[row].text


func reason_text(row: int) -> String:
	return _reasons[row].text if _reasons[row] != null else ""


func _yes_no(value: bool) -> String:
	return tr("Yes").to_upper() if value else tr("No").to_upper()


func _row(caption: String) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 1)
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
	box.add_child(row)
	if caption.begins_with("May"):
		var reason := _label(HudTheme.mono(400), 10, UiPalette.HUD_MUTED)
		reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		reason.visible = false
		_reasons.append(reason)
		box.add_child(reason)
	else:
		_reasons.append(null)
	return box


func _label(font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label
