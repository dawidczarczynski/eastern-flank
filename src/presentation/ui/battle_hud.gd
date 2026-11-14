class_name BattleHud
extends Control
## Battle HUD built in code (HUD v3, ADR 0013): the top turn bar with both sides and the tick
## ruler, the end-turn module (ready counter + button), the bottom action bar and the turn/result
## banner. Reads state only through HudModel; everything ignores the mouse except the end-turn
## button. A campaign battle (TASK-094c) adds a one-line mission reminder under the turn bar and
## turns the end screen into the commander's report with a Report to staff button.

signal end_turn_pressed
signal report_pressed
## The mission line was clicked: the owner shows the briefing again.
signal mission_pressed
## A button of the bottom action bar (ids: ACTION_*).
signal action_pressed(id: StringName)

const ACTION_GRID := &"grid"
const ACTION_RESET_VIEW := &"reset_view"
const ACTION_DESELECT := &"deselect"
const ACTION_SAVE := &"save"
const ACTION_FIRE_SUPPORT := &"fire_support"
const ACTION_OBJECTIVES := &"objectives"

const SHADE_HEIGHT := 120
const TOAST_BOTTOM := ActionBar.HEIGHT + ActionBar.NOTICE_GAP
const TARGETING_TOP := 118
const SIDE_WIDTH := 236
## Side flag + faction flag per player (TASK-130); the second is hidden when it repeats the first.
const FLAGS_PER_SIDE := 2
const FLAGS_GAP := 4
const FLAGS_WIDTH := 2 * 32 + FLAGS_GAP
const ACTIVE_ALPHA := 1.0
const INACTIVE_ALPHA := 0.6
const FADE_SECONDS := 0.3
const TURN_SIZE := 32
const TURN_LIMIT_SIZE := 16
## The Report to staff button sits this far below the screen centre (under the result banner).
const REPORT_BUTTON_OFFSET := 120

var _human_player := 0
var _fire_support_start := 0
var _action_bar: ActionBar
var _sides: Array[Dictionary] = []  # per player: {block, flags, name, meta, bar, tween}
var _turn_label: Label
var _turn_limit_label: Label  # "/08" after the turn number; hidden without a turn limit
var _turn_row: HBoxContainer
var _turn_box: Control
var _active_label: Label
var _active_arrow: Label
var _points_label: Label  # "C2 2/3" under the active side; hidden without command points
var _ready_value: Label
var _ready_blocks: ReadyBlocks
var _end_button: EndTurnButton
var _banner: TurnBanner
var _toast: Toast
var _targeting: TargetingBar
var _result_shown := false
var _prev_turn := -1
var _prev_player := -1
var _toast_color := UiPalette.AMBER
var _mission_line: Label
var _report_button: Button
## True in a campaign battle: the result banner reads as a report and offers Report to staff.
var _report_mode := false


func setup(human_player: int) -> void:
	_human_player = human_player
	name = "BattleHud"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Text is composed in code from already translated parts.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_build_shade()
	_build_top_bar()
	_build_action_bar()
	_build_end_block()
	_build_notices()


## Full refresh from the current simulation state (the view has caught up with it).
func refresh(state: GameState) -> void:
	_apply(state, HudModel.top_bar(state, _human_player))
	_refresh_fire_support(state)
	var result := HudModel.result_banner(state, _human_player)
	if result != "":
		_show_result(result, state)
	else:
		_hide_result()


## Missions the human side started the battle with (Conditions.fire_support): 0 hides the button.
func set_fire_support_start(missions: int) -> void:
	_fire_support_start = missions
	var button := _action_bar.button(ACTION_FIRE_SUPPORT)
	button.visible = FireSupportModel.shown(missions)


func _refresh_fire_support(state: GameState) -> void:
	if not FireSupportModel.shown(_fire_support_start):
		return
	var button := _action_bar.button(ACTION_FIRE_SUPPORT)
	var problem := FireSupportModel.problem(state, _human_player)
	button.badge = FireSupportModel.counter_text(state, _human_player)
	button.reason = problem
	_action_bar.set_enabled(ACTION_FIRE_SUPPORT, problem == "")
	if problem != "":
		_action_bar.set_active(ACTION_FIRE_SUPPORT, false)


## A `turn_started` event is being played back: show the banner and the turn/side it names.
func on_turn_started(state: GameState, turn: int, player: int) -> void:
	_apply(state, HudModel.top_bar_at(state, _human_player, turn, player))
	if (
		_prev_turn != -1
		and HudModel.banner_for(_prev_turn, _prev_player, turn, player)
		and not _result_shown
	):
		_show_turn_banner(state, turn, player)
	_prev_turn = turn
	_prev_player = player


## Campaign battle (TASK-094c): `mission` is the one-line reminder under the turn bar; the end
## screen becomes the commander's report.
func set_campaign(mission: String) -> void:
	_report_mode = true
	if _report_button == null:
		_build_report_button()
	_mission_line.text = mission.to_upper()
	_action_bar.button(ACTION_OBJECTIVES).visible = true
	_mission_line.visible = mission != ""
	# Only a campaign battle has a briefing to reopen.
	_mission_line.mouse_filter = (
		Control.MOUSE_FILTER_STOP if mission != "" else Control.MOUSE_FILTER_IGNORE
	)


func _on_mission_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		mission_pressed.emit()


func mission_line() -> String:
	return _mission_line.text if _mission_line.visible else ""


## The Report to staff button (shown on the end screen of a campaign battle); null outside one.
func report_button() -> Button:
	return _report_button


## The end-turn button (the controller hooks its click and hover sounds to it).
func end_button() -> Button:
	return _end_button


func set_end_enabled(enabled: bool) -> void:
	_end_button.disabled = not enabled
	_end_button.modulate.a = 1.0 if enabled else 0.5


func _apply(state: GameState, bar: Dictionary) -> void:
	var active_player: int = bar["active_player"]
	if _prev_turn == -1:
		_prev_turn = state.turn
		_prev_player = state.current_player
	var players: Array = bar["players"]
	for i in players.size():
		_apply_side(i, players[i])
	var active: Dictionary = players[active_player]
	var color: Color = active["color"]
	_turn_label.text = bar["turn_text"]
	_turn_limit_label.text = bar["turn_limit_text"]
	_turn_limit_label.get_parent().visible = _turn_limit_label.text != ""
	_turn_box.custom_minimum_size.x = _turn_row.get_combined_minimum_size().x
	_active_label.text = tr(active["name"] as String).to_upper()
	_active_label.add_theme_color_override(&"font_color", color)
	_points_label.text = bar["command_points_text"]
	_points_label.visible = _points_label.text != ""
	_points_label.add_theme_color_override(&"font_color", color)
	_active_arrow.add_theme_color_override(&"font_color", color)
	_ready_value.text = "%d / %d" % [active["ready"], active["units"]]
	_ready_blocks.set_counts(active["ready"], active["units"], color)
	_end_button.fill = color
	_toast_color = color


func _apply_side(index: int, data: Dictionary) -> void:
	if index >= _sides.size():
		return
	var side := _sides[index]
	var active: bool = data["active"]
	var color: Color = data["color"]
	var bar: HatchBar = side["bar"]
	bar.color = color
	bar.visible = active
	var flags: Array = data["flags"]
	for i in FLAGS_PER_SIDE:
		var flag: SideFlag = side["flags"][i]
		flag.show_texture(flags[i] if i < flags.size() else null, color)
	(side["name"] as Label).text = tr(data["name"] as String).to_upper()
	var status := tr("ACTIVE") if active else tr("WAITING")
	var units := tr("%d UNITS") % data["units"]
	(side["meta"] as Label).text = ("%s · %s" % [status, units]).to_upper()
	_fade(side, ACTIVE_ALPHA if active else INACTIVE_ALPHA)


## Fades a side block to `alpha`; without a scene tree (headless tests) it jumps.
func _fade(side: Dictionary, alpha: float) -> void:
	var block: Control = side["block"]
	var previous: Tween = side.get("tween")
	if previous != null:
		previous.kill()
	if not is_inside_tree():
		block.modulate.a = alpha
		return
	var tween := create_tween()
	tween.tween_property(block, "modulate:a", alpha, FADE_SECONDS)
	side["tween"] = tween


# --- turn banner ---------------------------------------------------------------------------


func _show_turn_banner(state: GameState, turn: int, player: int) -> void:
	var status := "YOUR TURN" if player == _human_player else "AI TURN"
	var caption := "%s %02d // %s" % [tr("TURN"), turn, tr(status)]
	var title := tr(UiPalette.faction_name(state, player)).to_upper()
	_banner.show_timed(caption.to_upper(), title, UiPalette.faction_color(state, player))


func _show_result(result: String, state: GameState) -> void:
	_result_shown = true
	var turn := HudModel.turn_text(state.turn, HudModel.turn_limit_of(state))
	var caption := "%s %s" % [tr("TURN"), turn]
	if _report_mode:
		caption = "%s // %s" % [tr("BATTLE_REPORT"), caption]
		_report_button.visible = true
	# A draw has no winner: faction_color(-1) is the neutral colour.
	var color := UiPalette.faction_color(state, state.winner)
	var reason := tr(HudModel.result_reason(state, _human_player)).to_upper()
	var fire := FireSupportModel.report_text(state, _human_player, _fire_support_start)
	if fire != "":
		reason = fire.to_upper() if reason == "" else "%s · %s" % [reason, fire.to_upper()]
	_banner.show_held(caption.to_upper(), tr(result).to_upper(), color, reason)


func _hide_result() -> void:
	if _result_shown:
		_result_shown = false
		_banner.release()
		if _report_button != null:
			_report_button.visible = false


## Toast above the end-turn module; the `>>` takes the colour of the side to move.
## `message` is a translation key (or plain text).
func show_toast(message: String) -> void:
	_toast.show_message(tr(message), _toast_color)


## Targeting bar below the turn bar; all three texts are translation keys (TASK-082 calls this).
func show_targeting(title: String, unit_text: String, instruction: String) -> void:
	_targeting.show_targeting(title, unit_text, instruction)


func hide_targeting() -> void:
	_targeting.hide_targeting()


# --- building ------------------------------------------------------------------------------


func _build_shade() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(10 / 255.0, 12 / 255.0, 9 / 255.0, 0.55))
	gradient.set_color(1, Color(10 / 255.0, 12 / 255.0, 9 / 255.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 4
	texture.height = SHADE_HEIGHT
	var shade := TextureRect.new()
	shade.name = "TopShade"
	shade.texture = texture
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	shade.offset_bottom = SHADE_HEIGHT
	add_child(shade)


func _build_top_bar() -> void:
	var column := VBoxContainer.new()
	column.name = "TopBar"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 3)
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(column)
	var frame := TurnBarFrame.new(TurnBarFrame.COMPACT_PADDING)
	frame.name = "TurnBarFrame"
	column.add_child(frame)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 18)
	frame.add_child(row)
	_sides.append(_build_side(row, 0, false))
	row.add_child(_build_centre())
	_sides.append(_build_side(row, 1, true))
	var ruler := TickRuler.new()
	ruler.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(ruler)
	_mission_line = _label_font(HudTheme.mono(500, 1), 10, UiPalette.AMBER)
	_mission_line.name = "MissionLine"
	_mission_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mission_line.visible = false
	_mission_line.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_mission_line.tooltip_text = tr("TIP_MISSION")
	_mission_line.gui_input.connect(_on_mission_input)
	column.add_child(_mission_line)


func _build_side(parent: Control, index: int, mirrored: bool) -> Dictionary:
	var block := VBoxContainer.new()
	block.name = "Side%d" % index
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.custom_minimum_size.x = SIDE_WIDTH
	block.alignment = BoxContainer.ALIGNMENT_CENTER
	block.add_theme_constant_override(&"separation", 3)
	parent.add_child(block)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END if mirrored else BoxContainer.ALIGNMENT_BEGIN
	block.add_child(row)

	var flag_box := HBoxContainer.new()
	flag_box.name = "Flags"
	flag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flag_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flag_box.custom_minimum_size.x = FLAGS_WIDTH
	flag_box.add_theme_constant_override(&"separation", FLAGS_GAP)
	flag_box.alignment = BoxContainer.ALIGNMENT_END if mirrored else BoxContainer.ALIGNMENT_BEGIN
	var flags: Array[SideFlag] = []
	for i in FLAGS_PER_SIDE:
		var flag := SideFlag.new(SideFlag.PAIR)
		flag.name = "Flag%d" % i
		flag_box.add_child(flag)
		flags.append(flag)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_theme_constant_override(&"separation", 3)
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_label := _label_font(HudTheme.display(600, 1), 15, UiPalette.HUD_TEXT)
	name_label.name = "Name"
	var meta := _label_font(HudTheme.mono(500, 1), 10, UiPalette.HUD_MUTED)
	meta.name = "Meta"
	if mirrored:
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var name_box := _pin_line(name_label, 15)
	# The rest of the block after the flags and a gap of 10.
	name_box.custom_minimum_size.x = SIDE_WIDTH - FLAGS_WIDTH - 10
	texts.add_child(name_box)
	texts.add_child(meta)
	if mirrored:
		row.add_child(texts)
		row.add_child(flag_box)
	else:
		row.add_child(flag_box)
		row.add_child(texts)

	# The bar slot keeps its height when the hatch is hidden on the waiting side.
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size.y = 3
	block.add_child(slot)
	var bar := HatchBar.new(UiPalette.AMBER, Vector2(1, 3), true)
	bar.name = "ActiveBar"
	bar.scrolling = true
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(bar)
	return {
		"block": block,
		"flags": flags,
		"name": name_label,
		"meta": meta,
		"bar": bar,
	}


func _build_centre() -> Control:
	var group := HBoxContainer.new()
	group.name = "Centre"
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override(&"separation", 0)
	group.add_child(_divider())
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 18)
	margin.add_theme_constant_override(&"margin_right", 18)
	group.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 2)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(column)

	var caption := _label_font(HudTheme.mono(500, 3), 10, UiPalette.HUD_MUTED)
	caption.name = "TurnCaption"
	caption.text = tr("TURN")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(caption)
	column.add_child(_build_turn_number())
	_active_label = _label_font(HudTheme.mono(600, 1), 10, UiPalette.HUD_MUTED)
	_active_label.name = "ActiveSide"
	_active_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_active_label)
	# The arrow hangs to the left of the name so the name (not arrow + name) is what is centred.
	_active_arrow = _label_font(HudTheme.mono(600, 1), 10, UiPalette.HUD_MUTED)
	_active_arrow.name = "ActiveArrow"
	_active_arrow.text = "▸"
	_active_arrow.anchor_left = 0.0
	_active_arrow.anchor_right = 0.0
	_active_arrow.offset_left = 0.0
	_active_arrow.offset_right = -5.0
	_active_arrow.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_active_label.add_child(_active_arrow)
	_points_label = _label_font(HudTheme.mono(600, 1), 10, UiPalette.HUD_MUTED)
	_points_label.name = "CommandPoints"
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_label.visible = false
	column.add_child(_points_label)
	group.add_child(_divider())
	return group


## The big turn number and, with a turn limit, a smaller "/08" on its baseline (TASK-088). The
## row is pinned to a TURN_SIZE line like _pin_line; _apply sizes the box to the row.
func _build_turn_number() -> Control:
	var number_font := HudTheme.mono(700)
	_turn_label = _label_font(number_font, TURN_SIZE, UiPalette.HUD_TEXT)
	_turn_label.name = "TurnNumber"
	var limit_font := HudTheme.mono(600)
	_turn_limit_label = _label_font(limit_font, TURN_LIMIT_SIZE, UiPalette.HUD_MUTED)
	_turn_limit_label.name = "TurnLimit"
	var lift := MarginContainer.new()  # puts the small text on the number's baseline
	lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lift.size_flags_vertical = Control.SIZE_SHRINK_END
	var descent_gap := number_font.get_descent(TURN_SIZE) - limit_font.get_descent(TURN_LIMIT_SIZE)
	lift.add_theme_constant_override(&"margin_bottom", roundi(descent_gap))
	lift.add_child(_turn_limit_label)
	lift.hide()
	_turn_row = HBoxContainer.new()
	_turn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_turn_row.add_theme_constant_override(&"separation", 2)
	_turn_row.add_child(_turn_label)
	_turn_row.add_child(lift)
	_turn_box = Control.new()
	_turn_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_box.custom_minimum_size.y = TURN_SIZE
	var natural := number_font.get_height(TURN_SIZE)
	_turn_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_turn_row.offset_top = (TURN_SIZE - natural) / 2.0
	_turn_row.offset_bottom = _turn_row.offset_top + natural
	_turn_box.add_child(_turn_row)
	return _turn_box


func _divider() -> ColorRect:
	var line := ColorRect.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.color = UiPalette.LINE
	line.custom_minimum_size.x = 1
	return line


func _build_action_bar() -> void:
	_action_bar = ActionBar.new()
	_action_bar.add_action(ACTION_GRID, "GRID", "G", true, "TIP_GRID_BATTLE")
	_action_bar.add_action(ACTION_RESET_VIEW, "RESET VIEW", "HOME", false, "TIP_RESET_VIEW")
	_action_bar.add_action(ACTION_DESELECT, "DESELECT", "ESC", false, "TIP_DESELECT")
	_action_bar.add_action(ACTION_SAVE, "SAVE MATCH", "F5", false, "TIP_SAVE_MATCH")
	var objectives := _action_bar.add_action(
		ACTION_OBJECTIVES, "OBJECTIVES", "O", false, "TIP_MISSION"
	)
	objectives.visible = false  # only a campaign battle has a briefing (set_campaign)
	_action_bar.add_separator()
	var fire := _action_bar.add_action(
		ACTION_FIRE_SUPPORT, "FIRE SUPPORT", "F", true, "TIP_FIRE_SUPPORT"
	)
	fire.visible = false  # shown once the side has missions (set_fire_support_start)
	_action_bar.action_pressed.connect(func(id: StringName) -> void: action_pressed.emit(id))
	add_child(_action_bar)


func action_bar() -> ActionBar:
	return _action_bar


func _build_end_block() -> void:
	var row := HBoxContainer.new()
	row.name = "EndTurnBlock"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 6)
	_action_bar.add_right(row)  # the right zone of the bottom bar

	var counter := FramedPanel.new()
	counter.name = "ReadyCounter"
	counter.chamfers = Vector4(10, 0, 0, 0)
	counter.padding = Vector2(14, 8)
	row.add_child(counter)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 5)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	counter.add_child(column)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override(&"separation", 14)
	column.add_child(head)
	var caption := _label_font(HudTheme.mono(500, 1), 10, UiPalette.HUD_MUTED)
	caption.text = tr("READY UNITS").to_upper()
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(caption)
	_ready_value = _label_font(HudTheme.mono(500, 1), 10, UiPalette.HUD_TEXT)
	_ready_value.name = "ReadyValue"
	head.add_child(_ready_value)
	_ready_blocks = ReadyBlocks.new()
	_ready_blocks.name = "ReadyBlocks"
	column.add_child(_ready_blocks)

	_end_button = EndTurnButton.new()
	_end_button.name = "EndTurnButton"
	_end_button.caption = tr("End turn").to_upper()
	_end_button.pressed.connect(func() -> void: end_turn_pressed.emit())
	row.add_child(_end_button)


func _build_notices() -> void:
	_banner = TurnBanner.new()
	add_child(_banner)
	_toast = Toast.new()
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_bottom = -TOAST_BOTTOM
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_toast)
	_targeting = TargetingBar.new()
	_targeting.anchor_left = 0.5
	_targeting.anchor_right = 0.5
	_targeting.offset_top = TARGETING_TOP
	_targeting.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_targeting)


func _build_report_button() -> void:
	_report_button = MenuStyle.button(tr("REPORT_TO_STAFF") + "  [↵]")
	_report_button.name = "ReportToStaff"
	_report_button.focus_mode = Control.FOCUS_NONE
	_report_button.anchor_left = 0.5
	_report_button.anchor_right = 0.5
	_report_button.anchor_top = 0.5
	_report_button.anchor_bottom = 0.5
	_report_button.offset_top = REPORT_BUTTON_OFFSET
	_report_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_report_button.custom_minimum_size.x = 260
	_report_button.pressed.connect(func() -> void: report_pressed.emit())
	_report_button.visible = false
	add_child(_report_button)


# --- helpers -------------------------------------------------------------------------------


## Wraps `label` in a box exactly `line_height` px tall with the text centred in it, like CSS
## `line-height: 1`. Godot's default line box is the font's ascent + descent (~1.3 em), which
## stretches the turn bar beyond the design.
func _pin_line(label: Label, line_height: float) -> Control:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size.y = line_height
	var font := label.get_theme_font(&"font")
	var natural := font.get_height(label.get_theme_font_size(&"font_size"))
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.offset_top = (line_height - natural) / 2.0
	label.offset_bottom = label.offset_top + natural
	box.add_child(label)
	return box


## Label with an already built font (HudTheme.display / mono).
func _label_font(font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label
