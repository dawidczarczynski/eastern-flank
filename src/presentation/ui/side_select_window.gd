class_name SideSelectWindow
extends StaffMapWindow
## Side selection before an operation starts (TASK-149, docs/design/operational_map/
## side_selection.html, variant A "Briefing sheet"): a centred window with one card per side of the
## OperationDefinition (flag, name, briefing, lead faction, alliance decision, nuclear option,
## formations) and BACK / START OPERATION. Nothing is pre-picked: START stays disabled until a card
## is picked. The picked card is drawn as the player's (rectangle, `side_own`, "YOU COMMAND"), the
## other as the opponent (diamond, `side_enemy`, "OPPONENT · AI").
## Holds no rules: emits `start_requested(side_id)` and `cancelled` (BACK, X, Esc); the owner acts.

signal start_requested(side_id: StringName)
signal cancelled

const SIZE := Vector2(1000, 620)
const CARD_SIZE := Vector2(456, 400)
const CARD_EDGE := Color("#3a3f33")
const SHAPE_SIZE := 14.0

var _definition: OperationDefinition
var _palette: StaffMapPalette
var _cards: Array[Button] = []
var _picked := -1
var _row: HBoxContainer
var _seed_label: Label
var _back: Button
var _start: Button


func _init() -> void:
	super(" ", SIZE.x)
	name = "SideSelect"
	custom_minimum_size = SIZE
	padding = Vector2(28, 14)
	_palette = load(StaffMapPalette.PATH) as StaffMapPalette
	close_requested.connect(func() -> void: cancelled.emit())
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 18)
	add_child(column)
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override(&"separation", 32)
	column.add_child(_row)
	_seed_label = MenuStyle.label("", HudTheme.mono(500, 0), 12, UiPalette.HUD_MUTED)
	_seed_label.name = "Seed"
	column.add_child(_seed_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(buttons)
	_back = MenuStyle.button("‹ " + tr("Back"))
	_back.name = "Back"
	_back.custom_minimum_size = Vector2(180, MenuStyle.BUTTON_HEIGHT)
	_back.pressed.connect(func() -> void: cancelled.emit())
	buttons.add_child(_back)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.add_child(fill)
	_start = MenuStyle.button(tr("START OPERATION"))
	_start.name = "Start"
	_start.custom_minimum_size = Vector2(240, MenuStyle.BUTTON_HEIGHT)
	_start.add_theme_stylebox_override(&"normal", MenuStyle.box(UiPalette.AMBER, UiPalette.AMBER))
	_start.add_theme_stylebox_override(
		&"hover", MenuStyle.box(UiPalette.AMBER.lightened(0.15), UiPalette.AMBER)
	)
	_start.add_theme_stylebox_override(
		&"disabled", MenuStyle.box(Color(UiPalette.AMBER, 0.4), Color(UiPalette.AMBER, 0.4))
	)
	for colour_name in [&"font_color", &"font_hover_color", &"font_disabled_color"]:
		_start.add_theme_color_override(colour_name, Color("#0a0c09"))
	_start.pressed.connect(_on_start)
	buttons.add_child(_start)
	_start.disabled = true


## Builds the cards for `definition` (two sides) and shows the window centred in `viewport`;
## nothing is picked.
func present(definition: OperationDefinition, seed_value: int, viewport: Vector2) -> void:
	_definition = definition
	tab_text = ("%s · %s" % [tr("SELECT YOUR SIDE"), tr(definition.display_name).to_upper()])
	for card in _cards:
		_row.remove_child(card)
		card.queue_free()
	_cards.clear()
	for index in definition.sides.size():
		var card := _build_card(index)
		_row.add_child(card)
		_cards.append(card)
	_seed_label.text = "%s %d" % [tr("SEED"), seed_value]
	_picked = -1
	_refresh()
	show()
	reset_size()
	position = ((viewport - size) / 2.0).floor()
	if not _cards.is_empty():
		_cards[0].grab_focus()


## Picks card `index` (a click, Space or Enter on it); START becomes available.
func pick(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	_picked = index
	_refresh()


## The picked side's id; empty when nothing is picked.
func picked_side() -> StringName:
	if _picked < 0 or _definition == null:
		return &""
	return _definition.sides[_picked].id


## START: emits the picked side (nothing while none is picked).
func start() -> void:
	if _picked >= 0:
		start_requested.emit(picked_side())


func card(index: int) -> Button:
	return _cards[index]


func card_count() -> int:
	return _cards.size()


func start_button() -> Button:
	return _start


func back_button() -> Button:
	return _back


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_ESCAPE:
		cancelled.emit()
	elif key == KEY_ENTER or key == KEY_KP_ENTER:
		start()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_start() -> void:
	start()


## Restyles the cards for the current pick: picked = own (rectangle, blue), other = enemy
## (diamond, red); with nothing picked both are neutral.
func _refresh() -> void:
	for index in _cards.size():
		var card := _cards[index]
		var picked := index == _picked
		var other := _picked >= 0 and not picked
		var colour := _palette.side_neutral
		if picked:
			colour = _palette.side_own
		elif other:
			colour = _palette.side_enemy
		card.set_pressed_no_signal(picked)
		var edge := colour if picked else CARD_EDGE
		var normal := MenuStyle.box(Color(colour, 0.08) if picked else Color(1, 1, 1, 0.02), edge)
		normal.set_border_width_all(2 if picked else 1)
		card.add_theme_stylebox_override(&"normal", normal)
		card.add_theme_stylebox_override(&"pressed", normal)
		var hover := MenuStyle.box(Color(1, 1, 1, 0.07), edge)
		hover.set_border_width_all(2 if picked else 1)
		card.add_theme_stylebox_override(&"hover", hover)
		card.add_theme_stylebox_override(&"hover_pressed", hover)
		var focus := MenuStyle.box(
			Color(colour, 0.08) if picked else Color(0, 0, 0, 0),
			edge if picked else UiPalette.AMBER
		)
		focus.set_border_width_all(2)
		card.add_theme_stylebox_override(&"focus", focus)
		var tag := card.find_child("Tag", true, false) as Label
		tag.text = ("◆ " + tr("YOU COMMAND") if picked else (tr("OPPONENT · AI") if other else " "))
		tag.add_theme_color_override(&"font_color", colour if picked else UiPalette.HUD_MUTED)
		var shape := card.find_child("Shape", true, false) as Control
		shape.set_meta(&"colour", colour)
		shape.set_meta(&"kind", &"rect" if picked else (&"diamond" if other else &"circle"))
		shape.queue_redraw()
		(card.find_child("Flag", true, false) as SideFlag).setup(_definition.sides[index], colour)
	_start.disabled = _picked < 0


func _build_card(index: int) -> Button:
	var side := _definition.sides[index]
	var card := Button.new()
	card.name = "Card%d" % index
	card.toggle_mode = true
	card.focus_mode = Control.FOCUS_ALL
	card.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	card.custom_minimum_size = CARD_SIZE
	card.pressed.connect(pick.bind(index))
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 20
	column.offset_right = -20
	column.offset_top = 16
	column.offset_bottom = -16
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 8)
	card.add_child(column)
	var tag := MenuStyle.label(" ", HudTheme.mono(700, 0), 11, UiPalette.HUD_MUTED)
	tag.name = "Tag"
	column.add_child(tag)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override(&"separation", 12)
	column.add_child(head)
	var flag := SideFlag.new(Vector2(64, 42))
	head.add_child(flag)
	var shape := _SideShape.new()
	shape.name = "Shape"
	head.add_child(shape)
	head.add_child(
		MenuStyle.label(
			tr(side.display_name).to_upper(), HudTheme.display(700, 1), 26, UiPalette.HUD_TEXT
		)
	)
	var brief := MenuStyle.label(
		tr(side.briefing), HudTheme.font("IBMPlexSansCondensed-Medium"), 13, UiPalette.HUD_TEXT
	)
	brief.name = "Briefing"
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.custom_minimum_size = Vector2(CARD_SIZE.x - 40, 52)
	column.add_child(brief)
	var lead := FactionRegistry.get_faction(side.lead_faction)
	var lead_name := tr(lead.display_name) if lead != null else String(side.lead_faction)
	column.add_child(_info(tr("LEAD FACTION"), lead_name.to_upper(), UiPalette.AMBER))
	column.add_child(
		_info(tr("ALLIANCE DECISION"), tr(side.alliance_decision_name), UiPalette.AMBER)
	)
	column.add_child(
		_info(
			tr("NUCLEAR OPTION"),
			tr("Yes").to_upper() if side.may_use_nuclear else tr("No").to_upper(),
			_palette.ui_alert if side.may_use_nuclear else UiPalette.AMBER
		)
	)
	column.add_child(
		_info(tr("FORMATIONS"), str(formation_count(_definition, index)), UiPalette.AMBER)
	)
	return card


## Formations `definition` places for player `player`.
static func formation_count(definition: OperationDefinition, player: int) -> int:
	var count := 0
	for placement in definition.formations:
		if placement.player == player:
			count += 1
	return count


func _info(label_text: String, value: String, value_colour: Color) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := MenuStyle.label(label_text, HudTheme.mono(500, 0), 12, UiPalette.HUD_MUTED)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	row.add_child(MenuStyle.label(value, HudTheme.mono(700, 0), 12, value_colour))
	return row


## The side shape beside the name: rectangle (the player), diamond (the opponent), circle (not
## picked yet) – meaning by shape as well as colour.
class _SideShape:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(SHAPE_SIZE, SHAPE_SIZE)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var colour: Color = get_meta(&"colour", UiPalette.HUD_MUTED)
		var centre := size / 2.0
		match get_meta(&"kind", &"circle"):
			&"rect":
				draw_rect(Rect2(Vector2.ZERO, size), colour)
			&"diamond":
				draw_colored_polygon(
					PackedVector2Array(
						[
							Vector2(centre.x, 0),
							Vector2(size.x, centre.y),
							Vector2(centre.x, size.y),
							Vector2(0, centre.y)
						]
					),
					colour
				)
			_:
				draw_circle(centre, size.x / 2.0, colour)
