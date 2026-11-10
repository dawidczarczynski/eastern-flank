class_name StaffMapDecisionsPanel
extends Control
## The Politics screen of the staff map (TASK-117, docs/design/operational_map/
## political_decisions.html variant B): a full-screen sheet over the dimmed map. Left: the five
## decision cards in two groups (key chip, title, cost chip, one-line effect, country chips with
## stance word and shape, reason + Take, inline confirmation with the new level on a 5-tick
## ladder). Header: budget, stand-down counter, result line. Right: dashed placeholders for the
## read-only overview of TASK-119. Everything shown comes from StaffMapDecisionsModel; the panel
## only emits `decision_chosen`, the hud issues the command. Built on open and on a state change
## only (never per frame).

signal decision_chosen(id: StringName, country: StringName)
signal close_requested

const OPEN_KEY := KEY_H
const SHEET_MARGIN := Vector4(70, 36, 70, 28)  # left, top, right, bottom
const CARD_WIDTH := 340.0  # minimum; the cards grow to 394 px on a 1440 px screen
const OVERVIEW_WIDTH := 280.0
const FADE_SECONDS := 0.15
const NUMBER_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
const KEYPAD_KEYS := [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5]
# gdlint: disable=max-line-length
const RULES_TEXT := "One decision per turn. A decision that raises the level asks to confirm and shows the new level. Standing down locks escalating for %d turns."
# gdlint: enable=max-line-length
const SHEET_FILL := Color(11 / 255.0, 13 / 255.0, 11 / 255.0, 0.97)

var _sheet := FramedPanel.new()
var _content := VBoxContainer.new()
var _palette: StaffMapPalette
var _state: OperationalState
var _viewer := 0
var _rows: Array[Dictionary] = []
var _picked := {}  # decision id -> chosen country id
var _confirming := {}  # {"id", "country"} while a confirmation is open
var _selected := &""  # the card the hot keys act on
var _result_id := &""  # the decision taken in this sitting (result line)
var _buttons := {}  # decision id -> the Take / Confirm button (tests)
var _reasons := {}  # decision id -> the reason Label (tests)
var _fade: Tween


func _init() -> void:
	name = "DecisionsPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP  # the dimmed map takes no input
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_bottom = -ActionBar.HEIGHT  # the command bar stays live
	var scrim := ColorRect.new()
	scrim.color = UiPalette.SCRIM_SCREEN
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	_sheet.name = "Sheet"
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet.chamfers = Vector4(0, 9, 0, 9)
	_sheet.padding = Vector2(24, 18)
	_sheet.fill = SHEET_FILL
	_sheet.line_color = Color(UiPalette.AMBER, 0.45)
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet.offset_left = SHEET_MARGIN.x
	_sheet.offset_top = SHEET_MARGIN.y
	_sheet.offset_right = -SHEET_MARGIN.z
	_sheet.offset_bottom = -SHEET_MARGIN.w
	add_child(_sheet)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override(&"separation", 12)
	_sheet.add_child(_content)
	hide()


## Rebuilds the cards from the state as seen by `viewer` and shows the sheet (fade-in).
func show_state(state: OperationalState, palette: StaffMapPalette, viewer: int) -> void:
	_state = state
	_palette = palette
	_viewer = viewer
	_confirming = {}
	_selected = &""
	_result_id = &""
	_rebuild()
	show()
	if _fade != null:
		_fade.kill()
	modulate.a = 0.0
	if is_inside_tree():
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 1.0, FADE_SECONDS)
	else:
		modulate.a = 1.0


## Ends the fade-in at once (screenshots, where the tree does not process).
func finish_fade() -> void:
	if _fade != null:
		_fade.kill()
	modulate.a = 1.0


## Rebuilds in place when open (the state changed).
func refresh() -> void:
	if visible and _state != null:
		_rebuild()


## Shows the result line for decision `id` (taken just now).
func set_result(id: StringName) -> void:
	_result_id = id
	_confirming = {}
	refresh()


## The button of decision `id` (Take, or Confirm while confirming); null for an unknown id.
func button_of(id: StringName) -> Button:
	return _buttons.get(id) as Button


## The reason text shown for a disabled decision ("" when it is enabled).
func reason_of(id: StringName) -> String:
	var label := _reasons.get(id) as Label
	return "" if label == null else label.text


func is_confirming() -> bool:
	return not _confirming.is_empty()


func selected() -> StringName:
	return _selected


## Chooses the target of a targeted decision (a chip click or the arrow keys).
func pick(id: StringName, country: StringName) -> void:
	_picked[id] = country
	_selected = id
	_confirming = {}
	refresh()


## Hot-key card pick (1-5); ignored while a confirmation is open.
func select_card(id: StringName) -> void:
	if is_confirming() or not StaffMapDecisionsModel.ORDER.has(id):
		return
	_selected = id
	refresh()


## Keys while the sheet is open: Esc cancels a confirmation, else closes; 1-5 pick a card, left /
## right the country, Enter takes / confirms, the open key closes. Always consumes the key (the map
## below takes none).
func handle_key(keycode: Key) -> bool:
	if keycode == KEY_ESCAPE:
		if is_confirming():
			cancel_confirmation()
		else:
			close_requested.emit()
		return true
	if keycode == OPEN_KEY:
		close_requested.emit()
		return true
	var number := NUMBER_KEYS.find(keycode)
	if number < 0:
		number = KEYPAD_KEYS.find(keycode)
	if number >= 0:
		select_card(StaffMapDecisionsModel.ORDER[number])
	elif keycode == KEY_LEFT or keycode == KEY_RIGHT:
		_step_country(-1 if keycode == KEY_LEFT else 1)
	elif keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		_activate()
	return true


func cancel_confirmation() -> void:
	_confirming = {}
	refresh()


func _step_country(step: int) -> void:
	if _selected == &"" or is_confirming():
		return
	var choices := _choices_of(_selected)
	if choices.size() < 2:
		return
	var current := choices.find(_choice_of(_selected, choices))
	var next: Dictionary = choices[posmod(current + step, choices.size())]
	pick(_selected, next["country"])


func _activate() -> void:
	if is_confirming():
		var id: StringName = _confirming["id"]
		var country: StringName = _confirming["country"]
		_confirming = {}
		decision_chosen.emit(id, country)
		return
	if _selected == &"":
		return
	var chosen := _choice_of(_selected, _choices_of(_selected))
	if chosen["enabled"]:
		_take(_selected, chosen)


func _choices_of(id: StringName) -> Array:
	for row in _rows:
		if row["id"] == id:
			return row["choices"]
	return []


func _rebuild() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_reasons.clear()
	_rows = StaffMapDecisionsModel.rows(_state, _viewer)
	var head := StaffMapDecisionsModel.header(_state, _viewer)
	_content.add_child(_title_row())
	_content.add_child(_budget_row(head))
	if _result_id != &"":
		_content.add_child(_result_row())
	var body := HBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 20)
	body.add_child(_decisions_column())
	body.add_child(_overview_column())
	_content.add_child(body)


func _title_row() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 16)
	var title := MenuStyle.label(
		tr("Politics").to_upper(), HudTheme.display(700, 4), 24, UiPalette.HUD_TEXT
	)
	title.name = "Title"
	row.add_child(title)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var hint := MenuStyle.label(
		"ESC · %s" % OS.get_keycode_string(OPEN_KEY), HudTheme.mono(500, 0), 11, UiPalette.HUD_MUTED
	)
	row.add_child(hint)
	var close := MenuStyle.button("X")
	close.name = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(28, 28)
	close.tooltip_text = tr("CLOSE")
	close.pressed.connect(close_requested.emit)
	row.add_child(close)
	return row


func _budget_row(head: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 14)
	var side := HBoxContainer.new()
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_theme_constant_override(&"separation", 7)
	side.add_child(StaffMapDecisionParts.Shape.new(&"own", _palette))
	side.add_child(
		MenuStyle.label(
			String(head["side"]).to_upper(), HudTheme.display(700, 2), 12, UiPalette.HUD_TEXT
		)
	)
	row.add_child(side)
	var budget := HBoxContainer.new()
	budget.name = "Budget"
	budget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	budget.add_theme_constant_override(&"separation", 7)
	var budget_text := tr("Decisions %d of %d") % [head["left"], head["per_turn"]]
	budget.add_child(
		MenuStyle.label(budget_text.to_upper(), HudTheme.display(700, 1), 13, UiPalette.HUD_TEXT)
	)
	for index in int(head["per_turn"]):
		budget.add_child(
			StaffMapDecisionParts.Pip.new(index < int(head["left"]), UiPalette.HUD_TEXT)
		)
	row.add_child(budget)
	var level_text := tr("Level %s") % ("%d · %s" % [head["level_value"], head["level_name"]])
	row.add_child(
		MenuStyle.label(level_text.to_upper(), HudTheme.display(500, 1), 13, UiPalette.HUD_MUTED)
	)
	if int(head["cooldown"]) > 0:
		row.add_child(_cooldown_chip(int(head["cooldown"])))
	return row


func _cooldown_chip(turns: int) -> Control:
	var chip := StaffMapDecisionParts.Chip.new()
	chip.name = "Cooldown"
	chip.edge = UiPalette.AMBER
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 6)
	box.add_child(
		MenuStyle.label(
			(tr("Standing down · %d turns") % turns).to_upper(),
			HudTheme.mono(700, 0),
			11,
			UiPalette.AMBER
		)
	)
	for index in _state.ladder.stand_down_cooldown_turns:
		box.add_child(StaffMapDecisionParts.Pip.new(index < turns, UiPalette.AMBER, 9.0))
	chip.add_child(box)
	return chip


func _result_row() -> Control:
	var chip := StaffMapDecisionParts.Chip.new()
	chip.name = "Result"
	chip.edge = UiPalette.LINE
	chip.wash = UiPalette.NOTE_BG
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var line := StaffMapDecisionsModel.result_line(_state, _viewer, _result_id)
	chip.add_child(MenuStyle.label(line.to_upper(), HudTheme.display(700, 1), 12, UiPalette.AMBER))
	return chip


## Left: the two card groups side by side, then the one-line rules under the second group.
func _decisions_column() -> Control:
	var columns := HBoxContainer.new()
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_theme_constant_override(&"separation", 12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_stretch_ratio = 1.9
	var widen := _group(tr("Widen the war"), StaffMapDecisionsModel.WIDEN)
	var small := _group(tr("Keep it small"), StaffMapDecisionsModel.KEEP_SMALL)
	var rules := MenuStyle.label(
		tr(RULES_TEXT) % _state.ladder.stand_down_cooldown_turns,
		HudTheme.mono(500, 0),
		11,
		UiPalette.HUD_MUTED
	)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	small.add_child(rules)
	var keys := MenuStyle.label(
		tr("1-5 pick a card · left / right country · Enter take, confirm · Esc cancel, close"),
		HudTheme.mono(500, 0),
		11,
		UiPalette.HUD_MUTED
	)
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	small.add_child(keys)
	columns.add_child(widen)
	columns.add_child(small)
	return columns


func _group(caption: String, ids: Array[StringName]) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.custom_minimum_size.x = CARD_WIDTH
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_theme_constant_override(&"separation", 10)
	group.add_child(
		MenuStyle.label(caption.to_upper(), HudTheme.display(700, 2), 11, UiPalette.HUD_MUTED)
	)
	for id in ids:
		for row in _rows:
			if row["id"] == id:
				group.add_child(_card(row))
	return group


## Right column: dashed placeholders for the read-only overview of TASK-119.
func _overview_column() -> Control:
	var wrap := HBoxContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_theme_constant_override(&"separation", 20)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var line := ColorRect.new()
	line.color = Color("#2a2e27")
	line.custom_minimum_size.x = 1.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(line)
	var column := VBoxContainer.new()
	column.name = "Overview"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.custom_minimum_size.x = OVERVIEW_WIDTH
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 10)
	column.add_child(
		MenuStyle.label(
			tr("Overview · coming with the politics report").to_upper(),
			HudTheme.display(700, 2),
			11,
			UiPalette.HUD_MUTED
		)
	)
	column.add_child(_placeholder(tr("Escalation ladder table"), 170.0, false))
	column.add_child(_placeholder(tr("Countries list"), 150.0, false))
	column.add_child(_placeholder(tr("Event log"), 0.0, true))
	wrap.add_child(column)
	return wrap


func _placeholder(text: String, height: float, grow: bool) -> Control:
	var chip := StaffMapDecisionParts.Chip.new()
	chip.edge = StaffMapDecisionParts.MUTED_EDGE
	chip.dashed = true
	chip.custom_minimum_size.y = height
	if grow:
		chip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var label := MenuStyle.label(text, HudTheme.mono(500, 0), 11, UiPalette.HUD_MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(label)
	return chip


func _card(row: Dictionary) -> Control:
	var id: StringName = row["id"]
	var choices: Array = row["choices"]
	var chosen := _choice_of(id, choices)
	var confirming_here := _is_confirming(id, chosen)
	var waiting := is_confirming() and not confirming_here
	var usable: bool = chosen["enabled"] and not waiting
	var picked := _selected == id
	var card := FramedPanel.new()
	card.name = String(id)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.chamfers = Vector4(0, 9, 0, 9)
	card.padding = Vector2(12, 7)
	card.fill = UiPalette.CARD
	card.line_color = _edge_of(chosen, usable, confirming_here, picked)
	card.custom_minimum_size.x = CARD_WIDTH
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 4)
	card.add_child(box)
	box.add_child(_card_head(row, chosen, usable, picked))
	var effect := MenuStyle.label(
		chosen["effect"],
		StaffMapDecisionParts.body_font(),
		13,
		StaffMapDecisionParts.BODY_TEXT if usable else StaffMapDecisionParts.OFF_TEXT
	)
	effect.name = "Effect"
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(effect)
	if choices.size() > 1 or String(choices[0]["country"]) != "":
		box.add_child(_picker(id, choices, chosen))
	if confirming_here:
		box.add_child(_confirmation(id, chosen))
	else:
		box.add_child(_foot(id, chosen, waiting))
	return card


func _edge_of(chosen: Dictionary, usable: bool, confirming: bool, picked: bool) -> Color:
	if confirming:
		return UiPalette.AMBER
	if not usable:
		if chosen["tag"] == &"threshold":
			return StaffMapDecisionParts.DANGER_EDGE
		return StaffMapDecisionParts.WARN_EDGE
	return Color(UiPalette.AMBER, 0.6) if picked else UiPalette.CARD_EDGE


func _card_head(row: Dictionary, chosen: Dictionary, usable: bool, picked: bool) -> Control:
	var id: StringName = row["id"]
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override(&"separation", 8)
	var key := StaffMapDecisionParts.chip(
		str(StaffMapDecisionsModel.hot_key(id)),
		HudTheme.mono(700, 0),
		11,
		UiPalette.AMBER if picked else UiPalette.HUD_TEXT,
		UiPalette.AMBER if picked else UiPalette.HUD_MUTED,
		Color(UiPalette.AMBER, 0.16) if picked else Color(0, 0, 0, 0)
	)
	key.name = "Key"
	head.add_child(key)
	var title := MenuStyle.label(
		row["title"],
		HudTheme.display(700, 0),
		15,
		UiPalette.HUD_TEXT if usable else StaffMapDecisionParts.OFF_TEXT
	)
	title.name = "TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	var kind: StringName = chosen["cost_kind"]
	var tint := UiPalette.HUD_MUTED
	if kind == &"up":
		tint = UiPalette.AMBER
	elif kind == &"down":
		tint = _palette.side_own
	var edge := tint if kind != &"free" else UiPalette.HUD_MUTED
	if kind == &"up" and chosen["danger"]:
		tint = _palette.ui_alert
		edge = tint
	var cost := StaffMapDecisionParts.chip(
		String(chosen["cost_text"]).to_upper(), HudTheme.mono(700, 0), 11, tint, edge
	)
	cost.name = "Cost"
	head.add_child(cost)
	return head


## Country chips: shape, name, stance word; the picked one amber, the ones that cannot be chosen
## dashed. A click picks the country (its reason then shows on the card).
func _picker(id: StringName, choices: Array, chosen: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.name = "Target"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 6)
	var caption := tr("Ally") if id == StaffMapDecisionsModel.INVOKE else tr("Target")
	row.add_child(
		MenuStyle.label(caption.to_upper(), HudTheme.display(700, 2), 10, UiPalette.HUD_MUTED)
	)
	for choice: Dictionary in choices:
		row.add_child(_country_chip(id, choice, choice["country"] == chosen["country"]))
	return row


func _country_chip(id: StringName, choice: Dictionary, current: bool) -> Control:
	var chip := StaffMapDecisionParts.Chip.new(true)
	var unfit := StaffMapDecisionsModel.is_country_block(choice["code"])
	chip.edge = UiPalette.AMBER if current else StaffMapDecisionParts.MUTED_EDGE
	chip.wash = Color(UiPalette.AMBER, 0.16) if current else Color(0, 0, 0, 0)
	chip.dashed = unfit and not current
	chip.tooltip_text = choice["reason"]
	var text_colour := UiPalette.HUD_TEXT
	if current:
		text_colour = UiPalette.AMBER
	elif unfit:
		text_colour = StaffMapDecisionParts.DISABLED_TEXT
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 5)
	box.add_child(StaffMapDecisionParts.Shape.new(choice["relation"], _palette))
	box.add_child(MenuStyle.label(choice["name"], HudTheme.mono(500, 0), 11, text_colour))
	box.add_child(
		MenuStyle.label(
			String(choice["stance_text"]).to_upper(), HudTheme.mono(500, 0), 9, UiPalette.HUD_MUTED
		)
	)
	chip.add_child(box)
	chip.clicked.connect(func() -> void: pick(id, choice["country"]))
	return chip


## Foot of a card: BLOCKED / THRESHOLD tag with the reason (or nothing when it works) and Take.
func _foot(id: StringName, chosen: Dictionary, waiting: bool) -> Control:
	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_theme_constant_override(&"separation", 8)
	var reason_text := ""
	var tag: StringName = chosen["tag"]
	if waiting:
		reason_text = tr("Confirm or cancel %s first") % _confirming_title()
		tag = &"blocked"
	elif not chosen["enabled"]:
		reason_text = chosen["reason"]
	var why := HBoxContainer.new()
	why.mouse_filter = Control.MOUSE_FILTER_IGNORE
	why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	why.add_theme_constant_override(&"separation", 6)
	if reason_text != "":
		var danger := tag == &"threshold"
		why.add_child(_tag_chip(danger))
		var reason := MenuStyle.label(
			reason_text,
			StaffMapDecisionParts.body_font(),
			12,
			_palette.ui_alert if danger else UiPalette.AMBER
		)
		reason.name = "Reason"
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		why.add_child(reason)
		_reasons[id] = reason
	foot.add_child(why)
	var take := StaffMapDecisionParts.button(tr("Take"))
	take.name = "Take"
	take.disabled = reason_text != ""
	if not take.disabled:
		take.pressed.connect(func() -> void: _take(id, chosen))
	foot.add_child(take)
	_buttons[id] = take
	return foot


func _tag_chip(danger: bool) -> Control:
	if danger:
		return StaffMapDecisionParts.chip(
			"▲ " + tr("Threshold").to_upper(),
			HudTheme.mono(700, 1),
			10,
			UiPalette.INK,
			_palette.ui_alert,
			_palette.ui_alert
		)
	return StaffMapDecisionParts.chip(
		tr("Blocked").to_upper(), HudTheme.mono(700, 1), 10, UiPalette.AMBER, UiPalette.AMBER
	)


## Inline confirmation: the question, the ladder with the new level and Cancel / Confirm.
func _confirmation(id: StringName, chosen: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 6)
	var rule := ColorRect.new()
	rule.color = StaffMapDecisionParts.WARN_EDGE
	rule.custom_minimum_size.y = 1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	var danger: bool = chosen["danger"]
	var ask := MenuStyle.label(
		chosen["confirm"],
		HudTheme.display(700, 0),
		13,
		_palette.ui_alert if danger else UiPalette.HUD_TEXT
	)
	ask.name = "Confirm"
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(ask)
	var ladder := HBoxContainer.new()
	ladder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ladder.add_theme_constant_override(&"separation", 8)
	var from := _state.escalation_level
	var to: int = chosen["new_level"]
	ladder.add_child(
		StaffMapDecisionParts.Ticks.new(
			_state.ladder.top() + 1, from, to if to > from else -1, _palette.ui_alert
		)
	)
	ladder.add_child(
		MenuStyle.label("%d ▸ %d" % [from, to], HudTheme.mono(700, 0), 11, UiPalette.AMBER)
	)
	ladder.add_child(
		MenuStyle.label(
			String(chosen["new_level_name"]).to_upper(),
			HudTheme.mono(500, 0),
			11,
			UiPalette.HUD_MUTED
		)
	)
	box.add_child(ladder)
	var buttons := HBoxContainer.new()
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override(&"separation", 8)
	var no := StaffMapDecisionParts.button(tr("Cancel"), true)
	no.name = "Cancel"
	no.pressed.connect(cancel_confirmation)
	buttons.add_child(no)
	buttons.add_child(KeyCap.new("ESC"))
	var yes := StaffMapDecisionParts.button(tr("Confirm"))
	yes.name = "ConfirmButton"
	yes.pressed.connect(
		func() -> void:
			_confirming = {}
			decision_chosen.emit(id, chosen["country"])
	)
	buttons.add_child(yes)
	buttons.add_child(KeyCap.new(KeyCap.ENTER))
	box.add_child(buttons)
	_buttons[id] = yes
	return box


func _confirming_title() -> String:
	for row in _rows:
		if row["id"] == _confirming.get("id"):
			return row["title"]
	return ""


func _is_confirming(id: StringName, chosen: Dictionary) -> bool:
	return _confirming.get("id") == id and _confirming.get("country") == chosen["country"]


func _choice_of(id: StringName, choices: Array) -> Dictionary:
	var wanted: StringName = _picked.get(id, &"")
	for choice: Dictionary in choices:
		if choice["country"] == wanted:
			return choice
	# Default: the first choice that works, else the first.
	for choice: Dictionary in choices:
		if choice["enabled"]:
			return choice
	return choices[0]


## A decision that changes the level asks first; the others go straight through.
func _take(id: StringName, chosen: Dictionary) -> void:
	_selected = id
	if int(chosen["new_level"]) != _state.escalation_level:
		_confirming = {"id": id, "country": chosen["country"]}
		refresh()
		return
	decision_chosen.emit(id, chosen["country"])
