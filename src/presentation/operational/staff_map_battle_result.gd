class_name StaffMapBattleResult
extends FramedPanel
## Result notice of the staff map (TASK-094c, reworked for readability) after "Report to staff"
## or Auto-resolve (TASK-120): headline (who won) with the reason, the outcome strip (who holds
## the field / retreats), then one tab per side (attacker first, side colour + formation name)
## with a summary line and a table Unit | Start | Left | Lost (+ bar) with a totals row;
## destroyed companies are marked. Continue (Enter) closes it. HUD v3 frame like the contact
## notice. TASK-095 replaces it with the full after-action report (front, escalation effect).

signal closed

const WIDTH := 540.0
const MAX_LIST_HEIGHT := 260.0
const BAR_WIDTH := 80.0
const LOSS_COLOUR := UiPalette.DISABLED

var _title: Label
var _title_flag: SideFlag
var _subtitle: Label
var _outcome: PanelContainer
var _outcome_box: HBoxContainer
var _tabs: HBoxContainer
var _summary: Label
var _scroll: ScrollContainer
var _table: GridContainer
var _continue: Button
var _state: OperationalState
var _report: BattleResult
var _side_rows: Array[Dictionary] = []
var _side_colours: Array[Color] = []
var _selected := 0
var _company_rows := 0
var _outcome_count := 0


## Strength bar: the side colour is the strength left, the red tail the strength lost.
class StrengthBar:
	extends Control
	var before := 0
	var after := 0
	var colour := Color.WHITE

	func _init(bar_width: float, bar_height: float) -> void:
		custom_minimum_size = Vector2(bar_width, bar_height)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiPalette.TRACK)
		if before <= 0:
			return
		var kept := size.x * clampf(float(after) / before, 0.0, 1.0)
		draw_rect(Rect2(0, 0, kept, size.y), colour)
		var lost_colour := StaffMapBattleResult.LOSS_COLOUR
		lost_colour.a = 0.55
		draw_rect(Rect2(kept, 0, size.x - kept, size.y), lost_colour)


func _init() -> void:
	super()
	name = "BattleResultNotice"
	mouse_filter = Control.MOUSE_FILTER_STOP
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size = Vector2(WIDTH, 0)
	chamfers = Vector4(0, 16, 0, 16)
	padding = Vector2(18, 14)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 10)
	add_child(column)
	_title = MenuStyle.label("", HudTheme.display(700, 1), 26, UiPalette.HUD_TEXT)
	_title.name = "Title"
	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_theme_constant_override(&"separation", 10)
	_title_flag = SideFlag.new(SideFlag.LARGE)
	_title_flag.name = "TitleFlag"
	title_row.add_child(_title_flag)
	title_row.add_child(_title)
	column.add_child(title_row)
	_subtitle = MenuStyle.label("", HudTheme.mono(500, 0), 13, UiPalette.HUD_DESC)
	_subtitle.name = "Subtitle"
	column.add_child(_subtitle)
	_outcome = PanelContainer.new()
	_outcome.name = "Outcome"
	_outcome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outcome.add_theme_stylebox_override(
		&"panel", _strip_style(UiPalette.NOTE_BG, UiPalette.AMBER_BORDER)
	)
	column.add_child(_outcome)
	_outcome_box = HBoxContainer.new()
	_outcome_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outcome_box.add_theme_constant_override(&"separation", 24)
	_outcome.add_child(_outcome_box)
	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	_tabs.add_theme_constant_override(&"separation", 6)
	column.add_child(_tabs)
	_summary = MenuStyle.label("", HudTheme.mono(500, 0), 13, UiPalette.HUD_TEXT)
	_summary.name = "Summary"
	column.add_child(_summary)
	_scroll = ScrollContainer.new()
	_scroll.name = "Table"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_table = GridContainer.new()
	_table.columns = 5
	_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table.add_theme_constant_override(&"h_separation", 14)
	_table.add_theme_constant_override(&"v_separation", 5)
	_scroll.add_child(_table)
	_continue = MenuStyle.button("")
	_continue.name = "Continue"
	_continue.focus_mode = Control.FOCUS_NONE
	_continue.pressed.connect(close)
	column.add_child(_continue)
	hide()


static func _strip_style(fill_colour: Color, border: Color) -> StyleBoxFlat:
	var box := MenuStyle.box(fill_colour, border)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	return box


## Per side, attacker first: {player, formation_name (translation key), before, after} – the
## summed company strengths of the result.
static func sides(setup: BattleSetup, result: BattleResult) -> Array[Dictionary]:
	var order: Array[int] = [0, 1]
	if setup.attacker >= 0:
		order = [setup.attacker, 1 - setup.attacker]
	var rows: Array[Dictionary] = []
	for player in order:
		var row := {"player": player, "formation_name": "", "before": 0, "after": 0}
		if player < setup.missions.size():
			row["formation_name"] = setup.missions[player].formation_name
		for company in result.companies:
			if company.player == player:
				row["before"] += company.strength_start
				row["after"] += company.strength_end
		rows.append(row)
	return rows


## "Victory: <side>" or "Draw" (translated).
static func winner_text(state: OperationalState, result: BattleResult) -> String:
	if result.winner < 0 or result.winner >= state.player_sides.size():
		return TranslationServer.translate("BATTLE_RESULT_DRAW")
	var side := SideDefinition.find(state.player_sides[result.winner])
	var side_name: String = TranslationServer.translate(side.display_name) if side != null else "?"
	return TranslationServer.translate("Victory: %s") % side_name


## "Objective taken · turn 7" – why and when the battle ended (translated, neutral wording).
static func reason_text(result: BattleResult) -> String:
	var turn := "%s %d" % [TranslationServer.translate("TURN"), result.turns]
	if result.reason == &"":
		return turn
	var key := "BATTLE_REASON_" + String(result.reason).to_upper()
	return "%s · %s" % [TranslationServer.translate(key), turn]


## "Holds the field: <side>" / "Retreats: <side>" lines of a result (translated; "" parts are
## left out): who holds the field (`field_holder`) and who retreats (`retreat`), TASK-120.
static func outcome_lines(state: OperationalState, result: BattleResult) -> Array[String]:
	var lines: Array[String] = []
	var keys := {"%s holds the field": result.field_holder, "%s retreats": result.retreat}
	for key: String in keys:
		var player: int = keys[key]
		if player < 0 or player >= state.player_sides.size():
			continue
		var side := SideDefinition.find(state.player_sides[player])
		var side_name: String = (
			TranslationServer.translate(side.display_name) if side != null else "?"
		)
		lines.append(TranslationServer.translate(key) % side_name)
	return lines


## Players of the `outcome_lines`, in the same order (field holder, then retreating side).
static func outcome_players(state: OperationalState, result: BattleResult) -> Array[int]:
	var players: Array[int] = []
	for player in [result.field_holder, result.retreat]:
		if player >= 0 and player < state.player_sides.size():
			players.append(player)
	return players


## "Strength at start 40 · Strength left 15 · Lost 25 (63%)" (translated) for one row of `sides`.
static func summary_text(row: Dictionary) -> String:
	var lost: int = row["before"] - row["after"]
	var percent := "%d%%" % roundi(100.0 * lost / maxi(row["before"], 1))
	return (
		TranslationServer.translate("Strength at start %d · Strength left %d · Lost %d (%s)")
		% [row["before"], row["after"], lost, percent]
	)


## Companies of `player` as {name (translated short name), before, after}, in result order.
static func company_rows(
	state: OperationalState, result: BattleResult, player: int
) -> Array[Dictionary]:
	var faction := FactionRegistry.get_faction(state.player_factions[player])
	var rows: Array[Dictionary] = []
	for company in result.companies:
		if company.player != player:
			continue
		var definition := faction.find_unit(company.unit_type) if faction != null else null
		var unit_name := String(company.unit_type)
		if definition != null:
			unit_name = TranslationServer.translate(definition.display_name)
		rows.append(
			{"name": unit_name, "before": company.strength_start, "after": company.strength_end}
		)
	return rows


func present(
	state: OperationalState,
	setup: BattleSetup,
	report: BattleResult,
	palette: StaffMapPalette,
	viewer := -1
) -> void:
	_state = state
	_report = report
	tab_text = tr("BATTLE_RESULT").to_upper()
	tab_color = UiPalette.AMBER
	tab_right_text = "%s %02d" % [tr("TURN"), state.turn]
	_title.text = winner_text(state, report)
	var title_colour := UiPalette.HUD_TEXT
	if report.winner >= 0 and report.winner < state.player_sides.size():
		title_colour = StaffMapFormations.side_colour(palette, report.winner)
	_title.add_theme_color_override(&"font_color", title_colour)
	var winner_side: SideDefinition = null
	if report.winner >= 0 and report.winner < state.player_sides.size():
		winner_side = SideDefinition.find(state.player_sides[report.winner])
	_title_flag.setup(winner_side, title_colour)
	_subtitle.text = reason_text(report)
	_clear(_outcome_box)
	var lines := outcome_lines(state, report)
	_outcome_count = lines.size()
	var outcome_players := outcome_players(state, report)
	for k in lines.size():
		var line_row := HBoxContainer.new()
		line_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line_row.add_theme_constant_override(&"separation", 6)
		var line_flag := SideFlag.new()
		line_flag.setup(
			SideDefinition.find(state.player_sides[outcome_players[k]]), UiPalette.NOTE_TEXT
		)
		line_row.add_child(line_flag)
		line_row.add_child(
			MenuStyle.label(lines[k], HudTheme.display(600, 1), 15, UiPalette.NOTE_TEXT)
		)
		_outcome_box.add_child(line_row)
	_outcome.visible = not lines.is_empty()
	_side_rows = sides(setup, report)
	_side_colours.clear()
	_clear(_tabs)
	var group := ButtonGroup.new()
	_selected = 0
	for i in _side_rows.size():
		var row := _side_rows[i]
		var colour := StaffMapFormations.side_colour(palette, row["player"])
		_side_colours.append(colour)
		var tab := MenuStyle.button(TranslationServer.translate(row["formation_name"]), true)
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.focus_mode = Control.FOCUS_NONE
		tab.clip_text = true
		tab.add_theme_font_size_override(&"font_size", 13)
		for key in [&"font_color", &"font_hover_color"]:
			tab.add_theme_color_override(key, colour)
		for key in [&"font_pressed_color", &"font_hover_pressed_color"]:
			tab.add_theme_color_override(key, UiPalette.INK)
		var selected_box := MenuStyle.box(colour, colour)
		tab.add_theme_stylebox_override(&"pressed", selected_box)
		tab.add_theme_stylebox_override(&"hover_pressed", selected_box)
		var tab_flag := SideFlag.new()
		tab_flag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
		tab_flag.position = Vector2(8, 0)
		tab_flag.grow_vertical = Control.GROW_DIRECTION_BOTH
		tab_flag.setup(SideDefinition.find(state.player_sides[row["player"]]), colour)
		tab.add_child(tab_flag)
		tab.pressed.connect(select_side.bind(i))
		_tabs.add_child(tab)
		if row["player"] == viewer:
			_selected = i
	select_side(_selected)
	_continue.text = tr("CONTINUE").to_upper() + "  [↵]"
	show()
	reset_size()


## Shows the table of tab `i` (0 = attacker).
func select_side(i: int) -> void:
	if i < 0 or i >= _side_rows.size():
		return
	_selected = i
	for t in _tabs.get_child_count():
		var tab := _tabs.get_child(t) as Button
		tab.set_pressed_no_signal(t == i)
		(tab.get_node("Flag") as SideFlag).frame_colour = (
			UiPalette.INK if t == i else _side_colours[t]
		)
		tab.get_node("Flag").queue_redraw()
	var row := _side_rows[i]
	var colour := _side_colours[i]
	_summary.text = summary_text(row)
	_clear(_table)
	_table.add_child(_cell(tr("BATTLE_RESULT_COL_UNIT").to_upper(), UiPalette.HUD_MUTED, 11, false))
	_table.add_child(_cell(tr("BATTLE_RESULT_COL_START").to_upper(), UiPalette.HUD_MUTED, 11, true))
	_table.add_child(_cell(tr("BATTLE_RESULT_COL_LEFT").to_upper(), UiPalette.HUD_MUTED, 11, true))
	_table.add_child(_cell(tr("BATTLE_RESULT_COL_LOST").to_upper(), UiPalette.HUD_MUTED, 11, true))
	_table.add_child(_cell("", UiPalette.HUD_MUTED, 11, false))
	_company_rows = 0
	for company in company_rows(_state, _report, row["player"]):
		_add_row(company["name"], company["before"], company["after"], colour, false)
		_company_rows += 1
	_add_row(tr("BATTLE_RESULT_COL_TOTAL"), row["before"], row["after"], colour, true)
	_scroll.custom_minimum_size.y = minf(_table.get_combined_minimum_size().y, MAX_LIST_HEIGHT)
	_scroll.custom_minimum_size.x = WIDTH - 2.0 * padding.x
	reset_size()


func _cell(text: String, colour: Color, size_px: int, right: bool, bold := false) -> Label:
	var label := MenuStyle.label(text, HudTheme.mono(600 if bold else 500, 0), size_px, colour)
	label.clip_text = true
	if right:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.custom_minimum_size.x = 52
	else:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size.x = 200
	return label


func _add_row(name_text: String, before: int, after: int, colour: Color, total: bool) -> void:
	if total:
		for i in 5:
			var rule := ColorRect.new()
			rule.color = UiPalette.LINE
			rule.custom_minimum_size = Vector2(0, 1)
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_table.add_child(rule)
	var destroyed := not total and after <= 0 and before > 0
	var name_colour := UiPalette.HUD_MUTED if destroyed else UiPalette.HUD_TEXT
	_table.add_child(_cell(name_text, name_colour, 13, false, total))
	_table.add_child(_cell(str(before), UiPalette.HUD_TEXT, 13, true, total))
	_table.add_child(_cell(str(after), name_colour, 13, true, total))
	var lost := before - after
	var lost_colour := LOSS_COLOUR if lost > 0 else UiPalette.HUD_MUTED
	_table.add_child(_cell(str(lost), lost_colour, 13, true, total))
	if destroyed:
		var mark := _cell(tr("BATTLE_RESULT_DESTROYED").to_upper(), LOSS_COLOUR, 11, true)
		mark.custom_minimum_size.x = BAR_WIDTH
		_table.add_child(mark)
	else:
		var bar := StrengthBar.new(BAR_WIDTH, total as int * 4 + 6)
		bar.before = before
		bar.after = after
		bar.colour = colour
		_table.add_child(bar)


static func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func title_text() -> String:
	return _title.text


## Number of company rows in the table shown (without header and totals).
func detail_count() -> int:
	return _company_rows


## Number of outcome lines (holds the field / retreats) in the strip.
func outcome_count() -> int:
	return _outcome_count


## Number of side tabs (always the two sides).
func row_count() -> int:
	return _side_rows.size()


## Text of tab `i` (the formation name).
func row_label(i: int) -> String:
	return (_tabs.get_child(i) as Button).text


func selected_side() -> int:
	return _selected


func summary_label() -> String:
	return _summary.text


func close() -> void:
	if visible:
		hide()
		closed.emit()


func title_flag() -> SideFlag:
	return _title_flag


func tab_flag(i: int) -> SideFlag:
	return _tabs.get_child(i).get_node("Flag")
