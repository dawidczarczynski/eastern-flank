class_name StaffMapStrikePanel
extends StaffMapWindow
## The strike mode panel of the staff map (TASK-097b, TASK-141b): docs/design/operational_map/
## strike_panel.html variant A. A 420 px docked window "STRIKE · <SIDE>" with one 46 px row per
## weapon of the viewer's side (StaffMapStrikeRow; stock 0 greyed, never hidden), the detail card
## of the hovered / picked weapon (StaffMapWeaponCard: model or class glyph and four chips), the
## salvo stepper with "STRIKES n / N", a hint and the line about the hovered target.
## Pure view: StaffMapStrikeHud feeds it and listens to its signals.

signal means_picked(id: StringName)
## The salvo slider was moved to `count` (an integer 1 .. max salvo).
signal salvo_set(count: int)

const WIDTH := StaffMapWindow.WIDTH_REPORT

var _rows := {}  # means id -> StaffMapStrikeRow
var _entries := {}  # means id -> StaffMapStrike.means_list entry
var _picked: StringName = &""
var _previewed: StringName = &""
var _hover_id: StringName = &""
var _class_colour := Color("#6f95ab")
var _column: VBoxContainer
var _list: VBoxContainer
var _card: StaffMapWeaponCard
var _salvo_label: Label
var _salvo_caption: Label
var _slider: HSlider
var _strikes_label: Label
var _hint: Label
var _hover: Label


func _init() -> void:
	super(" ", WIDTH)
	name = "StrikePanel"
	padding = Vector2(16, 12)
	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override(&"separation", 8)
	add_child(_column)
	_list = VBoxContainer.new()
	_list.name = "Weapons"
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override(&"separation", 0)
	_column.add_child(_list)
	_card = StaffMapWeaponCard.new()
	_column.add_child(_card)
	_build_salvo_row()
	hide()


## The tab "STRIKE · NATO" in the side colour; `class_colour` colours the class word of a row.
func set_side(side_name: String, side_colour: Color, class_colour: Color) -> void:
	tab_text = (
		("%s · %s" % [tr("STRIKE"), side_name]).to_upper() if side_name != "" else tr("STRIKE")
	)
	tab_color = side_colour
	_class_colour = class_colour


## Fills the panel: `means` from StaffMapStrike.means_list, the picked id (&"" for none), the salvo
## and its limit, the strikes line and the hint under the stepper.
func show_state(
	means: Array[Dictionary],
	picked: StringName,
	salvo: int,
	salvo_max: int,
	strikes_text: String,
	hint: String
) -> void:
	if tab_text.strip_edges() == "":
		tab_text = tr("STRIKE").to_upper()
	_picked = picked
	_sync_rows(means)
	for id: StringName in _rows:
		var row: StaffMapStrikeRow = _rows[id]
		row.picked = id == picked
		row.set_pressed_no_signal(id == picked)
	_salvo_label.text = str(salvo) if picked != &"" else "–"
	_slider.max_value = maxi(salvo_max, 1)
	_slider.set_value_no_signal(clampi(salvo, 1, maxi(salvo_max, 1)))
	_slider.editable = picked != &"" and salvo_max > 1
	_strikes_label.text = strikes_text.to_upper()
	_hint.text = hint
	_refresh_card()
	show()
	reset_size()


func set_hover_text(text: String, colour: Color = UiPalette.HUD_TEXT) -> void:
	_hover.text = text
	_hover.add_theme_color_override(&"font_color", colour)


func hover_text() -> String:
	return _hover.text


func hint_text() -> String:
	return _hint.text


func strikes_line() -> String:
	return _strikes_label.text


func salvo_text() -> String:
	return _salvo_label.text


func means_button(id: StringName) -> Button:
	return _rows.get(id) as Button


## The row of a weapon.
func row(id: StringName) -> StaffMapStrikeRow:
	return _rows.get(id) as StaffMapStrikeRow


## The ids of the rows from top to bottom.
func row_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for child in _list.get_children():
		ids.append((child as StaffMapStrikeRow).means_id)
	return ids


## The row's text as shown ("NAME | DESIGNATION · CLASS · RANGE | STOCK CAPTION").
func row_text(id: StringName) -> String:
	var found := row(id)
	return found.summary() if found != null else ""


func card() -> StaffMapWeaponCard:
	return _card


func salvo_slider() -> HSlider:
	return _slider


## The weapon whose detail card is up: the hovered row, else the picked one, else the first.
static func previewed_id(
	order: Array[StringName], picked: StringName, hovered: StringName
) -> StringName:
	if hovered != &"" and order.has(hovered):
		return hovered
	if picked != &"" and order.has(picked):
		return picked
	return order[0] if not order.is_empty() else &""


## Hover on a row (or leaving it) as the mouse does it, for tests.
func hover_row(id: StringName) -> void:
	_set_hover(id)


func _sync_rows(means: Array[Dictionary]) -> void:
	var order: Array[StringName] = []
	for entry in means:
		order.append(entry["id"])
	var same := order == row_ids()
	_entries.clear()
	for entry in means:
		_entries[entry["id"]] = entry
	if not same:
		for child in _list.get_children():
			_list.remove_child(child)
			child.queue_free()
		_rows.clear()
		for entry in means:
			var id: StringName = entry["id"]
			var new_row := StaffMapStrikeRow.new()
			new_row.pressed.connect(func() -> void: _on_row_pressed(id))
			new_row.hovered.connect(_set_hover)
			new_row.unhovered.connect(func(_id: StringName) -> void: _set_hover(&""))
			_list.add_child(new_row)
			_rows[id] = new_row
	for entry in means:
		(_rows[entry["id"]] as StaffMapStrikeRow).setup(entry, _class_colour)


func _on_row_pressed(id: StringName) -> void:
	var entry: Dictionary = _entries[id]
	if not entry["enabled"]:
		(_rows[id] as StaffMapStrikeRow).set_pressed_no_signal(false)
		set_hover_text(tr("Arrives only from allies"), UiPalette.AMBER)
		return
	means_picked.emit(id)


func _set_hover(id: StringName) -> void:
	_hover_id = id
	_refresh_card()
	reset_size()


func _refresh_card() -> void:
	var order := row_ids()
	var id := previewed_id(order, _picked, _hover_id)
	if id != &"" and _entries.has(id):
		_card.show_entry(_entries[id])


func _build_salvo_row() -> void:
	var salvo := HBoxContainer.new()
	salvo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	salvo.add_theme_constant_override(&"separation", 8)
	_column.add_child(salvo)
	_salvo_caption = MenuStyle.label(
		tr("SALVO").to_upper(), HudTheme.display(600, 1), 12, UiPalette.HUD_MUTED
	)
	salvo.add_child(_salvo_caption)
	_slider = _make_slider()
	salvo.add_child(_slider)
	_salvo_label = MenuStyle.label("", HudTheme.mono(700, 0), 20, UiPalette.AMBER)
	_salvo_label.name = "SalvoCount"
	_salvo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_salvo_label.custom_minimum_size = Vector2(36, 0)
	salvo.add_child(_salvo_label)
	_strikes_label = MenuStyle.label("", HudTheme.mono(700, 0), 12, UiPalette.AMBER)
	_strikes_label.name = "StrikesLeft"
	salvo.add_child(_strikes_label)
	_hint = MenuStyle.label("", HudTheme.display(400, 0), 12, UiPalette.HUD_MUTED)
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(WIDTH - 36, 0)
	_column.add_child(_hint)
	_hover = MenuStyle.label("", HudTheme.mono(600, 0), 11, UiPalette.HUD_TEXT)
	_hover.name = "HoverLine"
	_hover.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hover.custom_minimum_size = Vector2(WIDTH - 36, 0)
	_column.add_child(_hover)


## An integer slider 1 .. max salvo in the HUD tokens: a thin card-edge track, an amber filled part
## and a small amber grabber.
func _make_slider() -> HSlider:
	var slider := HSlider.new()
	slider.name = "SalvoSlider"
	slider.min_value = 1
	slider.max_value = 1
	slider.step = 1
	slider.value = 1
	slider.rounded = true
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(150, 24)
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var track := StyleBoxFlat.new()
	track.bg_color = UiPalette.CARD_EDGE
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var filled := StyleBoxFlat.new()
	filled.bg_color = UiPalette.AMBER
	filled.content_margin_top = 2
	filled.content_margin_bottom = 2
	slider.add_theme_stylebox_override(&"slider", track)
	slider.add_theme_stylebox_override(&"grabber_area", filled)
	slider.add_theme_stylebox_override(&"grabber_area_highlight", filled)
	var grabber := _grabber(UiPalette.AMBER)
	slider.add_theme_icon_override(&"grabber", grabber)
	slider.add_theme_icon_override(&"grabber_highlight", _grabber(UiPalette.HUD_TEXT))
	slider.add_theme_icon_override(&"grabber_disabled", _grabber(UiPalette.HUD_MUTED))
	slider.value_changed.connect(
		func(value: float) -> void:
			_salvo_label.text = str(int(value))
			salvo_set.emit(int(value))
	)
	return slider


static func _grabber(colour: Color) -> ImageTexture:
	var image := Image.create(8, 18, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	return ImageTexture.create_from_image(image)
