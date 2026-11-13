class_name StaffMapDecisionsPanel
extends Control
## The Politics screen of the staff map (TASK-117, docs/design/operational_map/
## political_decisions.html variant B): a full-screen sheet over the dimmed map. Left: the five
## decision cards in two groups (key chip, title, cost chip, one-line effect, country chips with
## stance word and shape, reason + Take, inline confirmation with the new level on the ladder
## ticks). Russia's side (SideDefinition.may_use_nuclear) also gets the red *Use nuclear weapon*
## card under "Last resort" with a heavy red confirmation (TASK-140). Header: budget, stand-down
## counter, result line. Right: the read-only overview (StaffMapOverviewColumn, TASK-119b).
## Everything shown comes from StaffMapDecisionsModel; the panel only emits
## `decision_chosen`, the hud issues the command. Built on open and on a state change only (never
## per frame).

signal decision_chosen(id: StringName, country: StringName)
signal close_requested

const OPEN_KEY := KEY_H
const SHEET_MARGIN := Vector4(70, 36, 70, 28)  # left, top, right, bottom
const CARD_WIDTH := 340.0  # minimum; the cards grow to 394 px on a 1440 px screen
const OVERVIEW_WIDTH := 400.0
const FADE_SECONDS := 0.15
const NUMBER_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]
const KEYPAD_KEYS := [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6]
# gdlint: disable=max-line-length
const RULES_TEXT := "One decision per turn. A decision that raises the level asks to confirm and shows the new level. Standing down locks escalating for %d turns."
# gdlint: enable=max-line-length
const TAB_DECISIONS := &"decisions"
const TAB_SUPPORT := &"support"
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
var _ladder_expanded := false  # the overview's ladder table shows every level
var _fade: Tween
var _tab := TAB_DECISIONS  # the open tab (TASK-121: Support next to the decisions)


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


## Opens the tab `tab` (TAB_DECISIONS / TAB_SUPPORT); the support tab only exists when the
## operation has packages.
func open_tab(tab: StringName) -> void:
	if tab == TAB_SUPPORT and (_state == null or _state.support.is_empty()):
		return
	_tab = tab
	_confirming = {}
	refresh()


func tab() -> StringName:
	return _tab


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


## Hot-key card pick (1-6); ignored while a confirmation is open or for a card not shown.
func select_card(id: StringName) -> void:
	if is_confirming() or _choices_of(id).is_empty():
		return
	_selected = id
	refresh()


## Keys while the sheet is open: Esc cancels a confirmation, else closes; 1-6 pick a card, left /
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
	if keycode == KEY_TAB:
		open_tab(TAB_DECISIONS if _tab == TAB_SUPPORT else TAB_SUPPORT)
		return true
	var number := NUMBER_KEYS.find(keycode)
	if number < 0:
		number = KEYPAD_KEYS.find(keycode)
	if _tab == TAB_SUPPORT:
		if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
			_activate()
	elif number >= 0:
		select_card(_id_of_key(number + 1))
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


func _id_of_key(key: int) -> StringName:
	for row in _rows:
		if StaffMapDecisionsModel.hot_key(row["id"]) == key:
			return row["id"]
	return &""


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
	if _state.support.is_empty():
		_tab = TAB_DECISIONS
	else:
		_content.add_child(_tab_row())
	var body := HBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 20)
	if _tab == TAB_SUPPORT:
		body.add_child(_supporters_column())
		body.add_child(_other_bloc_column())
	else:
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
	if _choices_of(StaffMapDecisionsModel.NUCLEAR).size() > 0:
		_add_cards(small, tr("Last resort"), StaffMapDecisionsModel.LAST_RESORT)
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
	_add_cards(group, caption, ids)
	return group


## A group caption and the cards of `ids` (those listed in the rows) appended to `group`.
func _add_cards(group: VBoxContainer, caption: String, ids: Array[StringName]) -> void:
	group.add_child(
		MenuStyle.label(caption.to_upper(), HudTheme.display(700, 2), 11, UiPalette.HUD_MUTED)
	)
	for id in ids:
		for row in _rows:
			if row["id"] == id:
				group.add_child(_card(row))


## Right column: the read-only politics overview (TASK-119b).
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
	var column := StaffMapOverviewColumn.new()
	column.ladder_expanded = _ladder_expanded
	column.ladder_toggled.connect(
		func() -> void:
			_ladder_expanded = column.ladder_expanded
			refresh()
	)
	column.show_state(_state, _palette, _viewer)
	wrap.add_child(column)
	return wrap


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
	card.line_color = _edge_of(id, usable, confirming_here, picked)
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


func _edge_of(id: StringName, usable: bool, confirming: bool, picked: bool) -> Color:
	var nuclear := id == StaffMapDecisionsModel.NUCLEAR
	if confirming:
		return _palette.ui_alert if nuclear else UiPalette.AMBER
	if not usable:
		return StaffMapDecisionParts.WARN_EDGE
	if nuclear:
		return _palette.ui_alert
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


## Foot of a card: BLOCKED tag with the reason (or nothing when it works) and Take (red for the
## nuclear decision).
func _foot(id: StringName, chosen: Dictionary, waiting: bool) -> Control:
	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_theme_constant_override(&"separation", 8)
	var reason_text := ""
	if waiting:
		reason_text = tr("Confirm or cancel %s first") % _confirming_title()
	elif not chosen["enabled"]:
		reason_text = chosen["reason"]
	var why := HBoxContainer.new()
	why.mouse_filter = Control.MOUSE_FILTER_IGNORE
	why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	why.add_theme_constant_override(&"separation", 6)
	if reason_text != "":
		why.add_child(
			StaffMapDecisionParts.chip(
				tr("Blocked").to_upper(),
				HudTheme.mono(700, 1),
				10,
				UiPalette.AMBER,
				UiPalette.AMBER
			)
		)
		var reason := MenuStyle.label(
			reason_text, StaffMapDecisionParts.body_font(), 12, UiPalette.AMBER
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
	if not take.disabled and id == StaffMapDecisionsModel.NUCLEAR:
		StaffMapDecisionParts.paint_danger(take, _palette.ui_alert)
	if not take.disabled:
		take.pressed.connect(func() -> void: _take(chosen["id"], chosen))
	foot.add_child(take)
	_buttons[id] = take
	return foot


## Inline confirmation: the question, the ladder with the new level and Cancel / Confirm. The
## nuclear decision gets the heavy form: red rule, a filled red "▲ ENDS THE OPERATION" tag, a larger
## red question and a red button named after the decision.
func _confirmation(id: StringName, chosen: Dictionary) -> Control:
	var nuclear := id == StaffMapDecisionsModel.NUCLEAR
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 6)
	var rule := ColorRect.new()
	rule.color = _palette.ui_alert if nuclear else StaffMapDecisionParts.WARN_EDGE
	rule.custom_minimum_size.y = 2.0 if nuclear else 1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	if nuclear:
		var tag := StaffMapDecisionParts.chip(
			"▲ " + tr("This ends the operation").to_upper(),
			HudTheme.mono(700, 1),
			10,
			UiPalette.INK,
			_palette.ui_alert,
			_palette.ui_alert
		)
		tag.name = "NuclearTag"
		tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		box.add_child(tag)
	var danger: bool = chosen["danger"]
	var ask := MenuStyle.label(
		chosen["confirm"],
		HudTheme.display(700, 0),
		15 if nuclear else 13,
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
		MenuStyle.label(
			"%d ▸ %d" % [from, to],
			HudTheme.mono(700, 0),
			11,
			_palette.ui_alert if nuclear else UiPalette.AMBER
		)
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
	var yes := StaffMapDecisionParts.button(tr("Use nuclear weapon") if nuclear else tr("Confirm"))
	yes.name = "ConfirmButton"
	if nuclear:
		StaffMapDecisionParts.paint_danger(yes, _palette.ui_alert)
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
	if _confirming.get("id") == StaffMapSupportModel.DECISION:
		return tr("Request support")
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


# --- Support tab (TASK-121) ---


func _tab_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "Tabs"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 8)
	for entry: Array in [[TAB_DECISIONS, "Decisions"], [TAB_SUPPORT, "Support"]]:
		var current: bool = entry[0] == _tab
		var chip := StaffMapDecisionParts.Chip.new(true)
		chip.name = "Tab" + String(entry[0]).capitalize()
		chip.edge = UiPalette.AMBER if current else StaffMapDecisionParts.MUTED_EDGE
		chip.wash = Color(UiPalette.AMBER, 0.16) if current else Color(0, 0, 0, 0)
		var text_colour := UiPalette.AMBER if current else UiPalette.HUD_TEXT
		chip.add_child(
			MenuStyle.label(tr(entry[1]).to_upper(), HudTheme.display(700, 2), 12, text_colour)
		)
		var target: StringName = entry[0]
		chip.clicked.connect(func() -> void: open_tab(target))
		row.add_child(chip)
	row.add_child(MenuStyle.label("TAB", HudTheme.mono(500, 0), 10, UiPalette.HUD_MUTED))
	return row


func _scroll_column(ratio: float) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = ratio
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 10)
	scroll.add_child(column)
	column.set_meta(&"scroll", scroll)
	return column


## Left: each supporter of the viewer's side with its status and package cards.
func _supporters_column() -> Control:
	var column := _scroll_column(1.9)
	column.name = "Supporters"
	var found := StaffMapSupportModel.supporters(_state, _viewer)
	if found.is_empty():
		column.add_child(_note(tr("No supporter can help this side.")))
	for supporter: Dictionary in found:
		column.add_child(_supporter_head(supporter))
		for package: Dictionary in supporter["packages"]:
			column.add_child(_package_card(package))
	return column.get_meta(&"scroll")


func _supporter_head(supporter: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.name = "Supporter_" + String(supporter["id"])
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	row.add_child(
		MenuStyle.label(
			String(supporter["name"]).to_upper(), HudTheme.display(700, 2), 12, UiPalette.HUD_TEXT
		)
	)
	var tint := UiPalette.HUD_MUTED
	if supporter["status"] == &"supporting":
		tint = _palette.side_own
	elif supporter["status"] == &"considering":
		tint = UiPalette.AMBER
	row.add_child(
		StaffMapDecisionParts.chip(
			String(supporter["status_text"]).to_upper(), HudTheme.mono(700, 0), 10, tint, tint
		)
	)
	return row


## Right: what the other bloc asked for and the free answers it opens (cards with Take).
func _other_bloc_column() -> Control:
	var wrap := HBoxContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_theme_constant_override(&"separation", 20)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var line := ColorRect.new()
	line.color = Color("#2a2e27")
	line.custom_minimum_size.x = 1.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(line)
	var column := _scroll_column(1.0)
	column.name = "OtherBloc"
	column.add_child(
		MenuStyle.label(
			tr("Requests of the other bloc").to_upper(),
			HudTheme.display(700, 2),
			11,
			UiPalette.HUD_MUTED
		)
	)
	var found := StaffMapSupportModel.other_bloc(_state, _viewer)
	if found.is_empty():
		column.add_child(_note(tr("The other bloc has requested no support.")))
	for request: Dictionary in found:
		var head := MenuStyle.label(
			"%s · %s" % [request["text"], request["turns_text"]],
			StaffMapDecisionParts.body_font(),
			13,
			UiPalette.HUD_TEXT
		)
		head.name = "Request_" + String(request["id"])
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(head)
		for answer: Dictionary in request["responses"]:
			column.add_child(_package_card(answer))
	wrap.add_child(column.get_meta(&"scroll"))
	return wrap


func _note(text: String) -> Label:
	var note := MenuStyle.label(text, StaffMapDecisionParts.body_font(), 12, UiPalette.HUD_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return note


## One package: title, cost chip, what arrives, entry / delay / band / conditions lines, then the
## state (on its way, waiting, arrived, withdrawn) or the Take foot / inline confirmation.
func _package_card(pack: Dictionary) -> Control:
	var key: StringName = pack["package"]
	var open: bool = pack["state"] == &"open"
	var confirming_here := _is_confirming(pack["id"], pack)
	var waiting := is_confirming() and not confirming_here
	var usable: bool = open and pack["enabled"] and not waiting
	var card := FramedPanel.new()
	card.name = "Package_" + String(key)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.chamfers = Vector4(0, 9, 0, 9)
	card.padding = Vector2(12, 7)
	card.fill = UiPalette.CARD
	card.line_color = UiPalette.CARD_EDGE
	if confirming_here:
		card.line_color = UiPalette.AMBER
	elif open and not usable:
		card.line_color = StaffMapDecisionParts.WARN_EDGE
	card.custom_minimum_size.x = CARD_WIDTH
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 4)
	card.add_child(box)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override(&"separation", 8)
	var title := MenuStyle.label(
		pack["title"],
		HudTheme.display(700, 0),
		15,
		UiPalette.HUD_TEXT if usable or not open else StaffMapDecisionParts.OFF_TEXT
	)
	title.name = "TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	var tint := UiPalette.AMBER if pack["cost_kind"] == &"up" else UiPalette.HUD_MUTED
	if pack["response"]:
		tint = _palette.side_own
	var cost := StaffMapDecisionParts.chip(
		String(pack["cost_text"]).to_upper(), HudTheme.mono(700, 0), 11, tint, tint
	)
	cost.name = "Cost"
	head.add_child(cost)
	box.add_child(head)
	box.add_child(_package_line("What", pack["what"], 13, StaffMapDecisionParts.BODY_TEXT))
	for field in ["entry", "delay", "band", "conditions"]:
		if pack[field] != "":
			box.add_child(
				_package_line(field.capitalize(), pack[field], 12, StaffMapDecisionParts.OFF_TEXT)
			)
	if not open:
		box.add_child(_package_state(pack))
	elif confirming_here:
		box.add_child(_confirmation(pack["id"], pack))
		_buttons[key] = _buttons[pack["id"]]
		_buttons.erase(pack["id"])
	else:
		box.add_child(_foot(key, pack, waiting))
	return card


func _package_line(name_text: String, text: String, size: int, colour: Color) -> Label:
	var label := MenuStyle.label(text, StaffMapDecisionParts.body_font(), size, colour)
	label.name = "Line" + name_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## Status line of a package that is no longer open to a request.
func _package_state(pack: Dictionary) -> Control:
	var kind: StringName = pack["state"]
	var tint := UiPalette.AMBER
	if kind == &"delivered":
		tint = _palette.side_own
	elif kind == &"withdrawn":
		tint = _palette.ui_alert
	var chip := StaffMapDecisionParts.chip(
		String(pack["state_text"]).to_upper(), HudTheme.mono(700, 1), 10, tint, tint
	)
	chip.name = "State"
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return chip
