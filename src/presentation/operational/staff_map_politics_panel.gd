class_name StaffMapPoliticsPanel
extends FramedPanel
## Debug politics panel of the staff map (TASK-114, F9, only with --debug): one row per country
## with a stance dropdown. A pick is only reported (`stance_requested`); the owner runs it through
## CountryRules.set_stance, the single place stances change, and shows the refusal reason of
## illegal transitions. A test handle, not a rule.

signal stance_requested(country_id: StringName, stance: StringName, side: int)

const WIDTH := 300

var _rows := {}  # country id -> OptionButton
var _choices := {}  # country id -> Array of [stance, side] per item


func _init() -> void:
	super()
	name = "StaffMapPoliticsPanel"
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size = Vector2(WIDTH, 0)
	chamfers = Vector4(0, 12, 0, 12)
	padding = Vector2(12, 10)
	tab_text = "POLITICS (DEBUG)"
	hide()


## Rebuilds the rows from `state` (call when opened and after every stance change).
func show_state(state: OperationalState) -> void:
	for child in get_children():
		child.queue_free()
	_rows.clear()
	_choices.clear()
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	add_child(column)
	for country in state.countries:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = tr(country.definition.display_name).to_upper()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override(&"font_size", 12)
		row.add_child(label)
		var picker := OptionButton.new()
		picker.focus_mode = Control.FOCUS_NONE
		var choices: Array = [[CountryState.NEUTRAL, -1]]
		for stance in [CountryState.ALIGNED, CountryState.BELLIGERENT]:
			for side in state.player_sides.size():
				choices.append([stance, side])
		var selected := 0
		for index in choices.size():
			var stance: StringName = choices[index][0]
			var side: int = choices[index][1]
			var text := stance.capitalize()
			if side >= 0:
				text += " · " + StaffMapTurnBar.side_name(state, side)
			picker.add_item(text)
			if stance == country.stance and side == country.side:
				selected = index
		picker.select(selected)
		picker.item_selected.connect(_on_picked.bind(country.id))
		row.add_child(picker)
		column.add_child(row)
		_rows[country.id] = picker
		_choices[country.id] = choices
	show()
	reset_size()


## Picks a stance as the dropdown would (tests).
func pick(country_id: StringName, stance: StringName, side: int) -> void:
	stance_requested.emit(country_id, stance, side)


func _on_picked(index: int, country_id: StringName) -> void:
	var choice: Array = _choices[country_id][index]
	stance_requested.emit(country_id, choice[0], choice[1])
