class_name StaffMapObjectivesWindow
extends StaffMapWindow
## The objectives window of the staff map (OBJECTIVES button, key O; TASK-175a, variant A of
## docs/design/operational_map/objectives_window.html): the MAIN objective card (the Gap road: chain
## bar, closed-rounds bar, rule) and the SIDE objectives rows (holder shape, name, chip, points).
## Every row is a button; Up / Down move the selection, Enter or a click emits `centre_requested`
## with the hexes to show. Holds no rules: `show_objectives` rebuilds the rows from
## StaffMapObjectivesModel; it can be reopened at any time during the operation.

## A row was chosen (click or Enter): the hexes to bring into view (one hex, or the Gap's chain).
signal centre_requested(hexes: Array[Vector2i])
## The selected row changed to one with `hexes` (or to none: empty).
signal selection_changed(hexes: Array[Vector2i])

const CHIP_FILL := 0.12
const ROW_TEXT_WIDTH := 164.0  # fixed so wrapped names get their height before layout
const CHIP_WIDTH := 120.0
const CARD_TEXT_WIDTH := 220.0
const SELECTED_FILL := 0.12
const BAR_WIDTH := 3.0
const SEPARATOR := Color(1, 1, 1, 0.06)
const SEGMENT_OFF := Color("#1b201a")
const SEGMENT_LINE := Color("#3a3f33")
const NEUTRAL_LINE := Color("#555c50")

var _palette: StaffMapPalette
var _column: VBoxContainer
var _rows_box: VBoxContainer
var _round: Label
var _buttons: Array[ObjectiveRow] = []
var _models: Array[Dictionary] = []
var _selected := -1
var _state: OperationalState
var _viewer := 0


func _init(palette: StaffMapPalette = null) -> void:
	super(tr("OBJECTIVES").to_upper(), WIDTH_REPORT)
	_palette = palette if palette != null else StaffMapPalette.new()
	name = "ObjectivesWindow"
	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override(&"separation", 4)
	add_child(_column)
	_column.minimum_size_changed.connect(_fit.call_deferred)
	_rows_box = VBoxContainer.new()
	_rows_box.name = "Rows"
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_box.add_theme_constant_override(&"separation", 0)
	_column.add_child(_rows_box)
	_round = MenuStyle.label("", HudTheme.mono(700, 1), 12, UiPalette.AMBER)
	_round.name = "Round"
	_column.add_child(_round)
	_column.add_child(StaffMapWindow.hint_line(tr("↑ ↓ select · Enter centre · Esc closes")))


## Rebuilds the rows for `viewer` from `state`; the selected row is kept.
func show_objectives(state: OperationalState, viewer: int) -> void:
	_state = state
	_viewer = viewer
	_rebuild()


## Whether the window took the key (Up / Down move the selection and wrap, Enter centres).
func handle_key(keycode: Key) -> bool:
	if not is_open() or _buttons.is_empty():
		return false
	match keycode:
		KEY_UP:
			select_row(
				posmod(_selected - 1, _buttons.size()) if _selected >= 0 else _buttons.size() - 1
			)
		KEY_DOWN:
			select_row(posmod(_selected + 1, _buttons.size()))
		KEY_ENTER, KEY_KP_ENTER:
			if _selected < 0:
				select_row(0)
			activate_row(_selected)
		_:
			return false
	return true


## Selects row `index` (no centring). -1 clears the selection.
func select_row(index: int) -> void:
	if index == _selected:
		return
	_selected = index if index >= 0 and index < _buttons.size() else -1
	for i in _buttons.size():
		_buttons[i].set_selected(i == _selected)
	selection_changed.emit(_hexes_of(_selected))


## Selects row `index` and asks for it to be centred (a click or Enter).
func activate_row(index: int) -> void:
	if index < 0 or index >= _buttons.size():
		return
	select_row(index)
	centre_requested.emit(_hexes_of(index))


func selected_row() -> int:
	return _selected


## Closing clears the selection (the map outline goes with it).
func close() -> bool:
	var was_open := super()
	if was_open or _selected >= 0:
		_selected = -1
		for button in _buttons:
			button.set_selected(false)
		selection_changed.emit([] as Array[Vector2i])
	return was_open


## The row nodes' count (tests).
func row_count() -> int:
	return _buttons.size()


## The model of row `index` (tests).
func row_model(index: int) -> Dictionary:
	return _models[index]


func row_button(index: int) -> Control:
	return _buttons[index]


func _hexes_of(index: int) -> Array[Vector2i]:
	var hexes: Array[Vector2i] = []
	if index < 0 or index >= _models.size():
		return hexes
	var chain: Array[Vector2i] = _models[index]["chain"]
	if not chain.is_empty():
		return chain.duplicate()
	hexes.append(_models[index]["hex"])
	return hexes


func _rebuild() -> void:
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_models = StaffMapObjectivesModel.rows(_state, _viewer, _selected)
	if _selected >= _models.size():
		_selected = -1
	var seen_side := false
	for i in _models.size():
		var model := _models[i]
		if i == 0 and model["tier"] == StaffMapObjectivesModel.MAIN:
			_rows_box.add_child(_section(StaffMapObjectivesModel.main_header(), 0))
		elif not seen_side:
			seen_side = true
			_rows_box.add_child(_section(StaffMapObjectivesModel.side_header(_state), 10))
		var button := (
			_gap_card(model) if model["tier"] == StaffMapObjectivesModel.MAIN else _row(model)
		)
		button.set_selected(i == _selected)
		button.pressed.connect(activate_row.bind(i))
		_buttons.append(button)
		_rows_box.add_child(button)
	_round.text = StaffMapObjectivesModel.round_line(_state)
	reset_size()
	_fit.call_deferred()


## Shrinks the panel to its content once wrapped labels have their final height.
func _fit() -> void:
	if is_inside_tree():
		reset_size()


func _section(text: String, gap: int) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if gap > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, gap)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(spacer)
	var label := MenuStyle.label(text.to_upper(), HudTheme.display(700, 1), 11, UiPalette.AMBER)
	label.custom_minimum_size = Vector2(0, 26)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	var line := ColorRect.new()
	line.color = Color(UiPalette.AMBER, 0.3)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	return box


## The colour of a holder as `_viewer` sees it: own side blue, the enemy red, nobody muted.
func _status_colour(status: StringName) -> Color:
	match status:
		StaffMapObjectivesModel.MINE:
			return _palette.side_own
		StaffMapObjectivesModel.THEIRS:
			return _palette.side_enemy
	return UiPalette.HUD_MUTED


func _row(model: Dictionary) -> ObjectiveRow:
	var row := ObjectiveRow.new(false)
	var line := _line(row)
	var colour := _status_colour(model["status"])
	var shape := ObjectiveShape.new(model["status"], colour)
	shape.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(shape)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override(&"separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(ROW_TEXT_WIDTH, 0)
	var yours: bool = model["yours"]
	var title_colour := UiPalette.HUD_TEXT if yours else UiPalette.HUD_MUTED
	var title := _label(model["label"], HudTheme.display(700, 1), 14, title_colour)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(title)
	if model["sub"] != "":
		var sub := _label(
			String(model["sub"]).to_upper(), HudTheme.display(400), 11, UiPalette.HUD_MUTED
		)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(sub)
	line.add_child(text)
	var chip := _chip(model["chip"], model["status"], colour)
	chip.custom_minimum_size = Vector2(CHIP_WIDTH, 0)
	line.add_child(chip)
	line.add_child(_points(model))
	line.add_child(_label("›", HudTheme.mono(700), 12, UiPalette.HUD_MUTED))
	return row


func _gap_card(model: Dictionary) -> ObjectiveRow:
	var card := ObjectiveRow.new(true)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 6)
	card.add_child(column)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override(&"separation", 10)
	var colour := _status_colour(model["status"])
	var shape := ObjectiveShape.new(StaffMapObjectivesModel.NONE, UiPalette.HUD_MUTED)
	shape.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(shape)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override(&"separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(CARD_TEXT_WIDTH, 0)
	var card_title := _label(model["label"], HudTheme.display(700, 1), 14, UiPalette.HUD_TEXT)
	card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(card_title)
	var held := _label(
		String(model["chain_text"]).to_upper(), HudTheme.display(400), 11, UiPalette.HUD_MUTED
	)
	held.name = "ChainText"
	held.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(held)
	top.add_child(text)
	top.add_child(_chip(model["chip"], model["status"], colour))
	top.add_child(_label("›", HudTheme.mono(700), 12, UiPalette.HUD_MUTED))
	column.add_child(top)
	var attacker := _status_colour(model["attacker_status"])
	var chain := SegmentBar.new(_flags(model["chain_held"]), attacker, 5.0, 2.0, false)
	chain.name = "ChainBar"
	column.add_child(chain)
	var progress := HBoxContainer.new()
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.add_theme_constant_override(&"separation", 10)
	progress.add_child(
		_label(tr("CLOSED IN A ROW"), HudTheme.display(700, 1), 11, UiPalette.HUD_MUTED)
	)
	var filled: Array[bool] = []
	for i in int(model["need"]):
		filled.append(i < int(model["closed_rounds"]))
	var segments := SegmentBar.new(filled, attacker, 7.0, 3.0, true)
	segments.name = "ProgressBar"
	segments.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.add_child(segments)
	var count := _label(model["progress"], HudTheme.mono(700), 13, UiPalette.HUD_TEXT)
	count.name = "Progress"
	progress.add_child(count)
	column.add_child(progress)
	var rule := _label(model["rule"], HudTheme.display(400), 12.5, UiPalette.HUD_TEXT)
	rule.name = "Rule"
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.custom_minimum_size = Vector2(WIDTH_REPORT - 80.0, 0)
	var rule_box := PanelContainer.new()
	rule_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiPalette.AMBER, 0.07)
	style.border_color = UiPalette.AMBER
	style.border_width_left = 3
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	rule_box.add_theme_stylebox_override(&"panel", style)
	rule_box.add_child(rule)
	column.add_child(rule_box)
	return card


static func _flags(values: Array) -> Array[bool]:
	var flags: Array[bool] = []
	for value in values:
		flags.append(bool(value))
	return flags


func _line(row: Control) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override(&"separation", 6)
	row.add_child(line)
	return line


func _chip(text: String, status: StringName, colour: Color) -> Control:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	var line := NEUTRAL_LINE if status == StaffMapObjectivesModel.NONE else colour
	style.bg_color = (
		Color(colour, CHIP_FILL) if status != StaffMapObjectivesModel.NONE else Color(0, 0, 0, 0)
	)
	style.border_color = line
	style.set_border_width_all(1)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	chip.add_theme_stylebox_override(&"panel", style)
	var chip_label := _label(text, HudTheme.display(700, 1), 10.5, colour)
	chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(chip_label)
	return chip


func _points(model: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(44, 0)
	box.add_theme_constant_override(&"separation", 0)
	var yours: bool = model["yours"]
	var colour := UiPalette.HUD_TEXT if yours else UiPalette.HUD_MUTED
	var value := _label("+%d" % int(model["points"]), HudTheme.mono(700), 15, colour)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(value)
	var tag := _label(
		tr("PTS") if yours else tr("ENEMY"), HudTheme.mono(600, 1), 10, UiPalette.HUD_MUTED
	)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(tag)
	return box


func _label(text: String, font: Font, size: float, colour: Color) -> Label:
	var label := MenuStyle.label(text, font, int(size), colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## A whole row: a MarginContainer (so its height follows the wrapped text) that draws hover 7 %
## white, selected amber 12 % with a 3 px bar on the left, a 1 px separator under it, and emits
## `pressed` on a left click.
class ObjectiveRow:
	extends MarginContainer

	signal pressed

	var _selected := false
	var _hover := false

	func _init(card: bool) -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(0, 46)
		for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
			add_theme_constant_override(side, 8)
		name = "MainCard" if card else "Row"
		mouse_entered.connect(_set_hover.bind(true))
		mouse_exited.connect(_set_hover.bind(false))

	func set_selected(value: bool) -> void:
		_selected = value
		queue_redraw()

	func is_selected() -> bool:
		return _selected

	func _set_hover(value: bool) -> void:
		_hover = value
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.button_index == MOUSE_BUTTON_LEFT and not click.pressed:
			pressed.emit()
			accept_event()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		if _selected:
			draw_rect(rect, Color(UiPalette.AMBER, SELECTED_FILL))
			draw_rect(Rect2(0, 0, BAR_WIDTH, size.y), UiPalette.AMBER)
		elif _hover:
			draw_rect(rect, Color(1, 1, 1, 0.07))
		draw_rect(Rect2(0, size.y - 1.0, size.x, 1.0), SEPARATOR)


## The 14 px holder shape: own rectangle, enemy diamond, neutral circle.
class ObjectiveShape:
	extends Control

	var _status: StringName
	var _colour: Color

	func _init(status: StringName, colour: Color) -> void:
		_status = status
		_colour = colour
		custom_minimum_size = Vector2(14, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var centre := size * 0.5
		match _status:
			StaffMapObjectivesModel.MINE:
				draw_rect(Rect2(Vector2.ZERO, size), _colour)
			StaffMapObjectivesModel.THEIRS:
				var r := 7.0 * 1.0
				draw_colored_polygon(
					PackedVector2Array(
						[
							centre + Vector2(0, -r),
							centre + Vector2(r, 0),
							centre + Vector2(0, r),
							centre + Vector2(-r, 0)
						]
					),
					_colour
				)
			_:
				draw_circle(centre, 6.0, _colour)


## A row of skewed cells, `flags[i]` filled with `colour` (the chain bar and the 5-segment bar).
class SegmentBar:
	extends Control

	var _flags: Array[bool]
	var _colour: Color
	var _gap: float
	var _skew: bool

	func _init(flags: Array[bool], colour: Color, height: float, gap: float, skew: bool) -> void:
		_flags = flags
		_colour = colour
		_gap = gap
		_skew = skew
		custom_minimum_size = Vector2(0, height)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var count := _flags.size()
		if count == 0:
			return
		var width := (size.x - _gap * (count - 1)) / count
		var lean := size.y * 0.36 if _skew else 0.0
		for i in count:
			var x := i * (width + _gap)
			var points := PackedVector2Array(
				[
					Vector2(x + lean, 0),
					Vector2(x + width, 0),
					Vector2(x + width - lean, size.y),
					Vector2(x, size.y)
				]
			)
			draw_colored_polygon(points, _colour if _flags[i] else SEGMENT_OFF)
			if _skew:
				var line := _colour if _flags[i] else SEGMENT_LINE
				points.append(points[0])
				draw_polyline(points, line, 1.0)
