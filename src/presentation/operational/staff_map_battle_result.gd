class_name StaffMapBattleResult
extends FramedPanel
## Short result notice of the staff map (TASK-094c) after "Report to staff": the winner and, per
## formation, the companies' strength before -> after; Continue (Enter) closes it. HUD v3 frame
## like the contact notice (docs/design/operational_map "Panels": the after-action report's
## "strength before -> after" lines). TASK-120's auto-resolve reuses it; TASK-095 replaces it with
## the full after-action report (who holds, retreat, losses, front).

signal closed

const WIDTH := 460.0

var _title: Label
var _subtitle: Label
var _rows: VBoxContainer
var _continue: Button


func _init() -> void:
	super()
	name = "BattleResultNotice"
	mouse_filter = Control.MOUSE_FILTER_STOP
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size = Vector2(WIDTH, 0)
	chamfers = Vector4(0, 16, 0, 16)
	padding = Vector2(16, 14)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 10)
	add_child(column)
	_title = MenuStyle.label("", HudTheme.display(700, 1), 22, UiPalette.HUD_TEXT)
	_title.name = "Title"
	column.add_child(_title)
	_subtitle = MenuStyle.label("", HudTheme.mono(500, 0), 11, UiPalette.HUD_MUTED)
	_subtitle.name = "Subtitle"
	column.add_child(_subtitle)
	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override(&"separation", 6)
	column.add_child(_rows)
	_continue = MenuStyle.button("")
	_continue.name = "Continue"
	_continue.focus_mode = Control.FOCUS_NONE
	_continue.pressed.connect(close)
	column.add_child(_continue)
	hide()


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


## "FORMATION · 18 → 12" for one row of `sides`.
static func row_text(row: Dictionary) -> String:
	return (
		"%s · %d → %d"
		% [TranslationServer.translate(row["formation_name"]), row["before"], row["after"]]
	)


func present(
	state: OperationalState, setup: BattleSetup, report: BattleResult, palette: StaffMapPalette
) -> void:
	tab_text = tr("BATTLE_RESULT").to_upper()
	tab_color = UiPalette.AMBER
	tab_right_text = "%s %02d" % [tr("TURN"), state.turn]
	_title.text = winner_text(state, report).to_upper()
	_subtitle.text = reason_text(report).to_upper()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for row in sides(setup, report):
		var label := MenuStyle.label(
			row_text(row).to_upper(),
			HudTheme.mono(500, 0),
			12,
			StaffMapFormations.side_colour(palette, row["player"])
		)
		_rows.add_child(label)
	_continue.text = tr("CONTINUE").to_upper() + "  [↵]"
	show()
	reset_size()


func title_text() -> String:
	return _title.text


func row_count() -> int:
	return _rows.get_child_count()


## The text of row `i` as shown.
func row_label(i: int) -> String:
	return (_rows.get_child(i) as Label).text


func close() -> void:
	if visible:
		hide()
		closed.emit()
