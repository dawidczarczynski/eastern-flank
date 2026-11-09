class_name StaffMapPoliticsPanel
extends FramedPanel
## Debug politics panel of the staff map (TASK-114, F9, only with --debug): one row per country
## with a stance dropdown. A pick is only reported (`stance_requested`); the owner runs it through
## CountryRules.set_stance, the single place stances change, and shows the refusal reason of
## illegal transitions. A test handle, not a rule.

signal stance_requested(country_id: StringName, stance: StringName, side: int)
## Raise / Lower of the escalation level attributed to side `by` (TASK-115).
signal escalation_requested(by: int, raise: bool)

## Strikes block (TASK-097a): a strike as the Strike button would order it / debug stock.
signal strike_requested(player: int, means: StringName, count: int, target: StringName)
signal stock_requested(player: int, means: StringName, count: int)

const WIDTH := 300

var _by := 0
# Strikes block selections, kept over rebuilds.
var _strike_player := 0
var _strike_means: StringName = &""
var _salvo := 1
var _target: StringName = &""

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
	column.add_child(_escalation_row(state))
	column.add_child(_strikes_block(state))
	show()
	reset_size()


func _escalation_row(state: OperationalState) -> Control:
	var row := HBoxContainer.new()
	row.name = "EscalationRow"
	var label := Label.new()
	label.text = "LEVEL %d" % state.escalation_level
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override(&"font_size", 12)
	row.add_child(label)
	var side := OptionButton.new()
	side.name = "By"
	side.focus_mode = Control.FOCUS_NONE
	for player in state.player_sides.size():
		side.add_item(StaffMapTurnBar.side_name(state, player))
	side.select(_by)
	side.item_selected.connect(func(index: int) -> void: _by = index)
	row.add_child(side)
	for raise in [true, false]:
		var button := Button.new()
		button.name = "Raise" if raise else "Lower"
		button.text = "Raise" if raise else "Lower"
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: escalation_requested.emit(_by, raise))
		row.add_child(button)
	return row


func _strikes_block(state: OperationalState) -> Control:
	var block := VBoxContainer.new()
	block.name = "Strikes"
	block.add_theme_constant_override(&"separation", 4)
	var title := Label.new()
	title.text = "STRIKES"
	title.add_theme_font_size_override(&"font_size", 12)
	block.add_child(title)
	_strike_player = clampi(_strike_player, 0, state.player_sides.size() - 1)
	var means_ids: Array = state.strike_means.keys()
	means_ids.sort()
	if not means_ids.has(_strike_means) and not means_ids.is_empty():
		_strike_means = means_ids[0]
	var targets := StrikeRules.targets(state, _strike_player)
	var target_ids: Array[StringName] = []
	for target in targets:
		target_ids.append(target["id"])
	if not target_ids.has(_target) and not target_ids.is_empty():
		_target = target_ids[0]
	var row := HBoxContainer.new()
	var player := OptionButton.new()
	player.name = "StrikePlayer"
	player.focus_mode = Control.FOCUS_NONE
	for side in state.player_sides.size():
		player.add_item(StaffMapTurnBar.side_name(state, side))
	player.select(_strike_player)
	player.item_selected.connect(_on_strike_player)
	row.add_child(player)
	var means := OptionButton.new()
	means.name = "StrikeMeans"
	means.focus_mode = Control.FOCUS_NONE
	means.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id: StringName in means_ids:
		means.add_item(String(id))
		if id == _strike_means:
			means.select(means.item_count - 1)
	means.item_selected.connect(func(i: int) -> void: _strike_means = means_ids[i])
	row.add_child(means)
	var salvo := SpinBox.new()
	salvo.name = "StrikeSalvo"
	salvo.min_value = 1
	salvo.max_value = 8
	salvo.value = _salvo
	salvo.value_changed.connect(func(v: float) -> void: _salvo = int(v))
	row.add_child(salvo)
	block.add_child(row)
	var target_picker := OptionButton.new()
	target_picker.name = "StrikeTarget"
	target_picker.focus_mode = Control.FOCUS_NONE
	for target in targets:
		var text := String(target["id"])
		if target["kind"] == &"installation":
			text = (
				"%s (%s)"
				% [
					TranslationServer.translate(_installation_name(state, target["id"])),
					target["class_id"]
				]
			)
		target_picker.add_item(text)
		if target["id"] == _target:
			target_picker.select(target_picker.item_count - 1)
	target_picker.item_selected.connect(func(i: int) -> void: _target = target_ids[i])
	block.add_child(target_picker)
	var buttons := HBoxContainer.new()
	for caption in ["Strike", "+stock"]:
		var button := Button.new()
		button.name = "StrikeFire" if caption == "Strike" else "StrikeStock"
		button.text = caption
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_strike_button.bind(caption == "Strike"))
		buttons.add_child(button)
	block.add_child(buttons)
	var line := Label.new()
	line.name = "StockLine"
	line.text = stock_text(state, _strike_player)
	line.add_theme_font_size_override(&"font_size", 11)
	block.add_child(line)
	return block


## "cruise 8 · ballistic 4 · strike_drone 6 · strikes left 2" for the stock line.
static func stock_text(state: OperationalState, player: int) -> String:
	var ids: Array = state.strike_means.keys()
	ids.sort()
	var parts: Array[String] = []
	for id: StringName in ids:
		parts.append("%s %d" % [id, StrikeRules.stock(state, player, id)])
	parts.append("strikes left %d" % state.strikes_left)
	return " · ".join(parts)


static func _installation_name(state: OperationalState, id: StringName) -> String:
	var installation := state.get_installation(id)
	return installation.display_name if installation != null else String(id)


func _on_strike_player(index: int) -> void:
	_strike_player = index
	_target = &""
	strike_requested.emit(-1, &"", 0, &"")  # asks the owner for a rebuild (no strike)


func _on_strike_button(fire: bool) -> void:
	if fire:
		strike_requested.emit(_strike_player, _strike_means, _salvo, _target)
	else:
		stock_requested.emit(_strike_player, _strike_means, _salvo)


## Presses Strike / +stock as the buttons would (tests); null selections keep the panel's.
func press_strike(player: int, means: StringName, count: int, target: StringName) -> void:
	_strike_player = player
	_strike_means = means
	_salvo = count
	_target = target
	strike_requested.emit(player, means, count, target)


func press_stock(player: int, means: StringName, count: int) -> void:
	stock_requested.emit(player, means, count)


## Picks a stance as the dropdown would (tests).
func pick(country_id: StringName, stance: StringName, side: int) -> void:
	stance_requested.emit(country_id, stance, side)


## Presses Raise / Lower for side `by` as the buttons would (tests).
func press_escalation(by: int, raise: bool) -> void:
	escalation_requested.emit(by, raise)


func _on_picked(index: int, country_id: StringName) -> void:
	var choice: Array = _choices[country_id][index]
	stance_requested.emit(country_id, choice[0], choice[1])
