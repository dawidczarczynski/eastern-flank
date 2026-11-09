class_name BattleBriefing
extends FramedPanel
## Commander's briefing at the start of a campaign battle (TASK-094c, GDD "Player roles"): the
## formation, **Mission** (the task and the objectives in words) and **Intent** (the leader's
## order, StaffMapContactNotice.intent_text) from `BattleSetup.Mission`, a Take command button
## (Enter / Esc / click). HUD v3 frame with the dotted "CAPTION .... value" rows of the staff map's
## contact notice. The statics also give the battle HUD's one-line mission reminder.

signal closed

const WIDTH := 560.0

var _title: Label
var _role: Label
var _captions := {}  # row key -> caption Label
var _values := {}  # row key -> value Label
var _button: Button


func _init() -> void:
	super()
	name = "BattleBriefing"
	mouse_filter = Control.MOUSE_FILTER_STOP
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size = Vector2(WIDTH, 0)
	chamfers = Vector4(0, 16, 0, 16)
	padding = Vector2(18, 16)
	brackets = true
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 12)
	add_child(column)
	_title = MenuStyle.label("", HudTheme.display(700, 1), 22, UiPalette.HUD_TEXT)
	_title.name = "Title"
	column.add_child(_title)
	_role = MenuStyle.label("", HudTheme.mono(500, 1), 11, UiPalette.AMBER)
	_role.name = "Role"
	column.add_child(_role)
	for key in ["MISSION", "INTENT"]:
		column.add_child(_row(key))
	_button = MenuStyle.button("")
	_button.name = "TakeCommand"
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(close)
	column.add_child(_button)
	hide()


## True when the setup carries a mission for `player` (contact battles; scenario battles have none).
static func has_mission(setup: BattleSetup, player: int) -> bool:
	return setup != null and player >= 0 and player < setup.missions.size()


## The task, then one sentence per objective of `player` and the turn limit (translated).
static func mission_lines(setup: BattleSetup, player: int) -> Array[String]:
	var lines: Array[String] = []
	if not has_mission(setup, player):
		return lines
	lines.append(_task(setup, player))
	var limit := setup.objectives.turn_limit
	for condition in setup.objectives.conditions:
		if not condition.applies_to(player):
			continue
		match condition.kind:
			VictoryCondition.Kind.TAKE_HEXES:
				lines.append(_tr("BRIEF_TAKE"))
			VictoryCondition.Kind.HOLD_HEXES:
				lines.append(_tr("Hold the objective until the end of turn %d") % limit)
			VictoryCondition.Kind.ELIMINATE:
				lines.append(_tr("BRIEF_ELIMINATE"))
			VictoryCondition.Kind.DESTROY_SHARE:
				lines.append(_tr("Destroy %d%% of the enemy's strength") % condition.share_percent)
	if limit > 0:
		lines.append(_tr("The battle ends after turn %d") % limit)
	return lines


## The leader's order behind `player`'s mission ("Advance to hex 06·01").
static func intent(setup: BattleSetup, player: int) -> String:
	if not has_mission(setup, player):
		return ""
	return StaffMapContactNotice.intent_text(setup.missions[player])


## One line for the battle HUD: "Mission · Attack · Take the objective · 12 turns"; "" without a
## mission.
static func reminder(setup: BattleSetup, player: int) -> String:
	if not has_mission(setup, player):
		return ""
	var parts: Array[String] = [_tr("CONTACT_MISSION"), _task(setup, player)]
	for condition in setup.objectives.conditions:
		if not condition.applies_to(player):
			continue
		if condition.kind == VictoryCondition.Kind.TAKE_HEXES:
			parts.append(_tr("BRIEF_SHORT_TAKE"))
			break
		if condition.kind == VictoryCondition.Kind.HOLD_HEXES:
			parts.append(_tr("BRIEF_SHORT_HOLD"))
			break
	if setup.objectives.turn_limit > 0:
		parts.append(_tr("%d turns") % setup.objectives.turn_limit)
	return " · ".join(parts)


## Fills the panel for `player` and shows it.
func present(setup: BattleSetup, player: int) -> void:
	tab_text = tr("BRIEFING").to_upper()
	tab_right_text = setup.operation_name.to_upper()
	var mission := setup.missions[player] if has_mission(setup, player) else null
	_title.text = tr(mission.formation_name).to_upper() if mission != null else ""
	_role.text = tr("BRIEF_COMMANDER").to_upper()
	_captions["MISSION"].text = tr("CONTACT_MISSION").to_upper()
	_captions["INTENT"].text = tr("BRIEF_INTENT").to_upper()
	_values["MISSION"].text = "\n".join(mission_lines(setup, player)).to_upper()
	_values["INTENT"].text = intent(setup, player).to_upper()
	_button.text = tr("BRIEF_TAKE_COMMAND").to_upper() + "  [↵]"
	show()
	reset_size()


func title_text() -> String:
	return _title.text


func mission_text() -> String:
	return (_values["MISSION"] as Label).text


func intent_text() -> String:
	return (_values["INTENT"] as Label).text


func close() -> void:
	if visible:
		hide()
		closed.emit()


static func _task(setup: BattleSetup, player: int) -> String:
	return _tr("MISSION_TASK_" + String(setup.missions[player].task).to_upper())


static func _tr(key: String) -> String:
	return TranslationServer.translate(key)


## "CAPTION ...." over a value that may wrap to several lines.
func _row(key: String) -> Control:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 4)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override(&"separation", 8)
	column.add_child(head)
	var caption := MenuStyle.label(key, HudTheme.mono(500, 0), 11, UiPalette.HUD_MUTED)
	head.add_child(caption)
	var rule := ColorRect.new()
	rule.color = Color(UiPalette.HUD_MUTED, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(rule)
	var value := MenuStyle.label("", HudTheme.mono(500, 0), 12, UiPalette.HUD_TEXT)
	value.name = key.capitalize()
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.custom_minimum_size.x = WIDTH - padding.x * 2.0  # a wrapping label needs a width
	column.add_child(value)
	_captions[key] = caption
	_values[key] = value
	return column
