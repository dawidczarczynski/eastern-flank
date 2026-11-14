class_name StaffMapContactNotice
extends FramedPanel
## Contact notice of the staff map (TASK-094a, look: docs/design/operational_map "Panels" →
## contact notice, mockup 03): a card next to the battle hex with the attacker and the defender
## as counters (own rectangle / enemy diamond relative to the viewer, StaffMapCounter), names,
## role, strength and posture, the odds line (strength totals as 1 : x), place, terrain and the
## attacker's mission. Buttons: Play battle (`B`, TASK-094c: the owner opens the battle; a
## reason under it only when it cannot) and, with --debug, Resolve as draw. NOT adopted from the
## mockup: the 3-band forecast. Auto-resolve (TASK-120) sits next to
## Play battle. Pure view: the owner
## (StaffMapContacts) feeds it a BattleSetup and the formations.

signal play_pressed
signal auto_pressed
signal resolve_pressed

const WIDTH := 540.0
const CARD_SIZE := Vector2(60, 52)
const COUNTER_AT := Vector2(30, 24)
const ALERT := Color("#e07c5e")

## (Vector2i) -> String: a place-based name of a hex, set by the owner; "" = use the hex number.
var place_namer: Callable
var _palette: StaffMapPalette
var _title: Label
var _counter_boxes: Array[Control] = []
var _names: Array[Label] = []
var _roles: Array[Label] = []
var _strengths: Array[Label] = []
var _conditions: Array[Array] = []  # per card: [fire support Label]
var _conditions_reduced: Array[bool] = [false, false]
var _odds: Label
var _rows := {}  # row key -> value Label
var _captions := {}  # row key -> caption Label
var _play: Button
var _auto: Button
var _reason: Label
var _resolve: Button
var _role_flags: Array[SideFlag] = []


func _init() -> void:
	super()
	name = "ContactNotice"
	mouse_filter = Control.MOUSE_FILTER_STOP
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size = Vector2(WIDTH, 0)
	chamfers = Vector4(0, 16, 0, 16)
	padding = Vector2(16, 14)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 12)
	add_child(column)
	_title = MenuStyle.label("", HudTheme.display(700, 1), 22, UiPalette.HUD_TEXT)
	_title.name = "Title"
	column.add_child(_title)
	column.add_child(_build_sides())
	for key in ["LOCATION", "FORCES", "MISSION"]:
		column.add_child(_row(key))
	column.add_child(_build_buttons())
	hide()


## Fills the card from the first pending battle. `attacker` / `defender` are the formations,
## `index` / `total` the place in the queue (0-based / count).
func present(
	state: OperationalState,
	setup: BattleSetup,
	attacker: Formation,
	defender: Formation,
	at: Vector2i,
	viewer: int,
	queue: Vector2i,
	palette: StaffMapPalette,
	place_name := ""
) -> void:
	_palette = palette
	tab_text = tr("CONTACT").to_upper()
	tab_color = ALERT
	line_color = Color(ALERT, 0.45)
	tab_right_text = ("%s %02d · %d/%d" % [tr("TURN"), state.turn, queue.x, queue.y])
	var attacking_viewer := attacker.owner_id == viewer
	var place := place_name if place_name != "" else tr("HEX %s") % hex_text(at)
	_title.text = (
		(
			"%s – %s"
			% [
				tr("CONTACT_TITLE_ATTACK") if attacking_viewer else tr("CONTACT_TITLE_DEFEND"),
				place
			]
		)
		. to_upper()
	)
	var sides: Array[Formation] = [attacker, defender]
	for i in 2:
		_fill_card(i, state, setup, sides[i], viewer)
	var totals := strength_totals(setup)
	_odds.text = odds_text(totals.x, totals.y)
	_captions["LOCATION"].text = tr("Location").to_upper()
	_captions["FORCES"].text = tr("CONTACT_FORCES").to_upper()
	_captions["MISSION"].text = tr("CONTACT_MISSION").to_upper()
	var here := place_name if place_name != "" else hex_text(at)
	_rows["LOCATION"].text = ("%s · %s" % [here, terrain_name(setup.terrain)]).to_upper()
	_rows["FORCES"].text = "%d : %d" % [totals.x, totals.y]
	_rows["MISSION"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows["MISSION"].custom_minimum_size.x = 280.0
	_rows["MISSION"].text = mission_text(setup.missions[setup.attacker], place_namer).to_upper()
	_play.text = tr("CONTACT_PLAY").to_upper() + "  [B]"
	_auto.text = tr("CONTACT_AUTO").to_upper()
	set_play_problem("")
	_resolve.text = tr("CONTACT_RESOLVE_DEBUG").to_upper()
	show()
	reset_size()


func role_flag(i: int) -> SideFlag:
	return _role_flags[i]


func set_debug(enabled: bool) -> void:
	_resolve.visible = enabled


## Total company strength per side: x = attacker, y = defender.
static func strength_totals(setup: BattleSetup) -> Vector2i:
	var totals := Vector2i.ZERO
	for company in setup.companies:
		if company.player == setup.attacker:
			totals.x += company.strength
		else:
			totals.y += company.strength
	return totals


## "1 : 1.4" – attacker to defender strength; "–" when the attacker has none.
static func odds_text(attacker: int, defender: int) -> String:
	if attacker <= 0:
		return "–"
	return "1 : %.1f" % (float(defender) / attacker)


## Offset hex text "06·01" of an axial coordinate (same as the formation panel).
static func hex_text(c: Vector2i) -> String:
	var offset := MapGenerator.axial_to_offset(c)
	return "%02d·%02d" % [offset.x + 1, offset.y + 1]


## Translated name of the terrain with this id ("" id: "?").
static func terrain_name(id: StringName) -> String:
	for type: Terrain.Type in Terrain.Type.values():
		var definition := Terrain.definition(type)
		if definition != null and definition.id == id:
			return TranslationServer.translate(definition.display_name)
	return "?"


## "Attack · Advance to hex 06·01" – the task and the intent of a mission.
static func mission_text(mission: BattleSetup.Mission, namer := Callable()) -> String:
	if mission == null:
		return "?"
	var intent := intent_text(mission, namer)
	var task := TranslationServer.translate("MISSION_TASK_" + String(mission.task).to_upper())
	return "%s · %s" % [task, intent] if intent != "" else task


## "Advance to hex 06·01" – the leader's order behind a mission (its intent); "" without one.
static func intent_text(mission: BattleSetup.Mission, namer := Callable()) -> String:
	if mission == null or mission.intent_key == "":
		return ""
	var intent := TranslationServer.translate(mission.intent_key)
	if mission.intent_args.size() >= 2:
		var hex := Vector2i(int(mission.intent_args[0]), int(mission.intent_args[1]))
		var named := StaffMapPlaceName.named(namer, hex)
		intent += " " + (named if named != "" else hex_text(hex))
	return intent


func title_text() -> String:
	return _title.text


## Formation name on card `side` (0 = attacker, 1 = defender), as shown.
func name_text(side: int) -> String:
	return _names[side].text


func role_text(side: int) -> String:
	return _roles[side].text


func strength_text(side: int) -> String:
	return _strengths[side].text


## The counter of card `side`: its relation tells own (rectangle) or enemy (diamond).
func counter(side: int) -> StaffMapCounter:
	return _counter_boxes[side].get_child(0) as StaffMapCounter


func odds_line() -> String:
	return _odds.text


func row_text(key: String) -> String:
	return (_rows[key] as Label).text


func play_enabled() -> bool:
	return not _play.disabled


func reason_text() -> String:
	return _reason.text


func resolve_visible() -> bool:
	return _resolve.visible and visible


## Disables Play battle with a reason (translation key) under it; "" enables it again.
func set_play_problem(key: String) -> void:
	_play.disabled = key != ""
	_reason.text = tr(key) if key != "" else ""
	_reason.visible = key != ""


## B: emits play_pressed unless Play battle is disabled; true when it did.
func press_play() -> bool:
	if _play.disabled:
		return false
	play_pressed.emit()
	return true


## Whether the Auto-resolve button is shown and enabled.
func auto_enabled() -> bool:
	return _auto.visible and not _auto.disabled


func press_auto() -> void:
	_auto.pressed.emit()


func press_resolve() -> void:
	_resolve.pressed.emit()


func _fill_card(
	i: int, state: OperationalState, setup: BattleSetup, formation: Formation, viewer: int
) -> void:
	var colour := StaffMapFormations.side_colour(_palette, formation.owner_id)
	var box := _counter_boxes[i]
	var counter_node := box.get_child(0) as StaffMapCounter
	counter_node.setup(formation, viewer, _palette)
	counter_node.designation = ""
	counter_node.position = COUNTER_AT
	_names[i].text = tr(formation.display_name).to_upper()
	var mission := setup.missions[formation.owner_id]
	var role := (
		"CONTACT_ROLE_ATTACKER"
		if i == 0
		else ("CONTACT_ROLE_HOLD_OUT" if mission.task == &"hold_out" else "CONTACT_ROLE_DEFENDER")
	)
	var side := SideDefinition.find(state.player_sides[formation.owner_id])
	_roles[i].text = (
		("%s · %s" % [tr(side.display_name) if side != null else "?", tr(role)]).to_upper()
	)
	_roles[i].add_theme_color_override(&"font_color", colour)
	_role_flags[i].setup(side, colour)
	var percent := 100 * formation.strength() / maxi(formation.max_strength(), 1)
	var posture := TranslationServer.translate(
		"POSTURE_" + String(setup.conditions[formation.owner_id].posture).to_upper()
	)
	_strengths[i].text = (
		("%s · %s" % ["%s %d%%" % [tr("CONTACT_STRENGTH"), percent], posture]).to_upper()
	)
	_fill_conditions(i, setup.conditions[formation.owner_id])


## The fire support line of card `i` (TASK-099b); a reduced value is tagged and drawn in the
## alert colour. Command points are not shown: the C2 limits orders on the staff map, not a battle.
func _fill_conditions(i: int, conditions: BattleSetup.Conditions) -> void:
	var reduced := ConditionsModel.fire_support_reduced(conditions)
	_conditions_reduced[i] = reduced
	var label := _conditions[i][0] as Label
	var text := ConditionsModel.fire_support_text(conditions)
	label.text = (text + (" · " + tr("reduced") if reduced else "")).to_upper()
	label.add_theme_color_override(&"font_color", ALERT if reduced else UiPalette.HUD_TEXT)


## Line `line` (0 = fire support) of card `side`, as shown.
func conditions_text(side: int, line: int) -> String:
	return (_conditions[side][line] as Label).text


## Whether card `side` shows a reduced value.
func conditions_reduced(side: int) -> bool:
	return _conditions_reduced[side]


func _build_sides() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	for i in 2:
		row.add_child(_build_card())
		if i == 0:
			row.add_child(_build_versus())
	return row


func _build_card() -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := MenuStyle.box(Color(UiPalette.HUD_TEXT, 0.03), Color(UiPalette.HUD_MUTED, 0.18))
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override(&"panel", style)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 5)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(column)
	var box := Control.new()
	box.custom_minimum_size = CARD_SIZE
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var counter_node := StaffMapCounter.new()
	box.add_child(counter_node)
	column.add_child(box)
	_counter_boxes.append(box)
	var name_label := MenuStyle.label("", HudTheme.display(600, 1), 14, UiPalette.HUD_TEXT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	_names.append(name_label)
	var role := MenuStyle.label("", HudTheme.mono(500, 0), 10, UiPalette.HUD_TEXT)
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var role_row := HBoxContainer.new()
	role_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	role_row.alignment = BoxContainer.ALIGNMENT_CENTER
	role_row.add_theme_constant_override(&"separation", 6)
	var flag := SideFlag.new()
	role_row.add_child(flag)
	role_row.add_child(role)
	column.add_child(role_row)
	_roles.append(role)
	_role_flags.append(flag)
	var strength := MenuStyle.label("", HudTheme.mono(500, 0), 10, UiPalette.HUD_MUTED)
	strength.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(strength)
	_strengths.append(strength)
	var lines: Array[Label] = []
	var line := MenuStyle.label("", HudTheme.mono(500, 0), 10, UiPalette.HUD_TEXT)
	line.name = "Conditions0"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(line)
	lines.append(line)
	_conditions.append(lines)
	return panel


func _build_versus() -> Control:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(MenuStyle.label("VS", HudTheme.mono(700, 0), 13, UiPalette.AMBER))
	_odds = MenuStyle.label("", HudTheme.mono(500, 0), 10, UiPalette.HUD_MUTED)
	_odds.name = "Odds"
	_odds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_odds)
	return column


## "CAPTION ........ value" like the mockup's dotted rows.
func _row(key: String) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 8)
	var caption := MenuStyle.label("", HudTheme.mono(500, 0), 11, UiPalette.HUD_MUTED)
	caption.text = key
	row.add_child(caption)
	var rule := ColorRect.new()
	rule.color = Color(UiPalette.HUD_MUTED, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rule)
	var value := MenuStyle.label("", HudTheme.mono(500, 0), 11, UiPalette.HUD_TEXT)
	value.name = key.capitalize()
	if key == "LOCATION":  # a place name with distance and direction can be long: wrap it
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.custom_minimum_size.x = 280.0
	row.add_child(value)
	_rows[key] = value
	_captions[key] = caption
	return row


func _build_buttons() -> Control:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 4)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	column.add_child(row)
	_play = MenuStyle.button("")
	_play.name = "Play"
	_play.focus_mode = Control.FOCUS_NONE
	_play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play.pressed.connect(func() -> void: play_pressed.emit())
	row.add_child(_play)
	_auto = MenuStyle.button("")
	_auto.name = "Auto"
	_auto.focus_mode = Control.FOCUS_NONE
	_auto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto.pressed.connect(func() -> void: auto_pressed.emit())
	row.add_child(_auto)
	_resolve = MenuStyle.button("")
	_resolve.name = "Resolve"
	_resolve.focus_mode = Control.FOCUS_NONE
	_resolve.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resolve.pressed.connect(func() -> void: resolve_pressed.emit())
	_resolve.visible = false
	row.add_child(_resolve)
	_reason = MenuStyle.label("", HudTheme.mono(500, 0), 10, UiPalette.DISABLED)
	_reason.name = "Reason"
	column.add_child(_reason)
	return column
