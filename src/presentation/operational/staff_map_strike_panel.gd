class_name StaffMapStrikePanel
extends StaffMapWindow
## The strike mode panel of the staff map (TASK-097b): the means with stock and range (a toggle
## each, greyed at stock 0), the salvo stepper, "Strikes: n/N", a hint and the line about the
## hovered target. Look: the contact notice frame (HUD v3 "Panels"; no strike mockup exists).
## Pure view: StaffMapStrikeHud feeds it and listens to its signals.

signal means_picked(id: StringName)
signal salvo_stepped(delta: int)

const WIDTH := 330.0

var _rows := {}  # means id -> Button
var _column: VBoxContainer
var _salvo_label: Label
var _minus: Button
var _plus: Button
var _strikes_label: Label
var _hint: Label
var _hover: Label


func _init() -> void:
	super()
	name = "StrikePanel"
	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override(&"separation", 8)
	add_child(_column)
	hide()


## Fills the panel: `means` from StaffMapStrike.means_list, the picked id (&"" for none), the salvo
## and its limit, the strikes line and the hint under the list.
func show_state(
	means: Array[Dictionary],
	picked: StringName,
	salvo: int,
	salvo_max: int,
	strikes_text: String,
	hint: String
) -> void:
	tab_text = tr("STRIKE").to_upper()
	if _rows.is_empty():
		_build(means)
	for entry in means:
		var id: StringName = entry["id"]
		var button: Button = _rows[id]
		button.text = (
			(
				"%s   %s %d   %s %d"
				% [
					entry["name"],
					tr("STOCK"),
					entry["stock"],
					tr("RANGE"),
					entry["range_hexes"],
				]
			)
			. to_upper()
		)
		button.disabled = int(entry["stock"]) <= 0
		button.set_pressed_no_signal(id == picked)
	_salvo_label.text = "%s  %d" % [tr("SALVO").to_upper(), salvo] if picked != &"" else "–"
	_minus.disabled = picked == &"" or salvo <= 1
	_plus.disabled = picked == &"" or salvo >= salvo_max
	_strikes_label.text = strikes_text.to_upper()
	_hint.text = hint
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


func salvo_buttons() -> Array[Button]:
	return [_minus, _plus]


func _build(means: Array[Dictionary]) -> void:
	_column.add_child(MenuStyle.caption(tr("MEANS")))
	for entry in means:
		var id: StringName = entry["id"]
		var button := MenuStyle.button("", true)
		button.name = String(id).capitalize().replace(" ", "")
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_override(&"font", HudTheme.mono(600, 0))
		button.add_theme_font_size_override(&"font_size", 11)
		button.pressed.connect(func() -> void: means_picked.emit(id))
		_column.add_child(button)
		_rows[id] = button
	var salvo := HBoxContainer.new()
	salvo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	salvo.add_theme_constant_override(&"separation", 8)
	_column.add_child(salvo)
	_minus = _stepper("−", -1)
	salvo.add_child(_minus)
	_salvo_label = MenuStyle.label("", HudTheme.mono(700, 0), 13, UiPalette.HUD_TEXT)
	_salvo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_salvo_label.custom_minimum_size = Vector2(90, 0)
	salvo.add_child(_salvo_label)
	_plus = _stepper("+", 1)
	salvo.add_child(_plus)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	salvo.add_child(spacer)
	_strikes_label = MenuStyle.label("", HudTheme.mono(700, 0), 12, UiPalette.AMBER)
	_strikes_label.name = "StrikesLeft"
	salvo.add_child(_strikes_label)
	_hint = MenuStyle.label("", HudTheme.mono(500, 0), 10, UiPalette.HUD_MUTED)
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(WIDTH - 30, 0)
	_column.add_child(_hint)
	_hover = MenuStyle.label("", HudTheme.mono(600, 0), 11, UiPalette.HUD_TEXT)
	_hover.name = "HoverLine"
	_hover.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hover.custom_minimum_size = Vector2(WIDTH - 30, 0)
	_column.add_child(_hover)


func _stepper(text: String, delta: int) -> Button:
	var button := MenuStyle.button(text)
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(34, 28)
	button.pressed.connect(func() -> void: salvo_stepped.emit(delta))
	return button
