class_name BattleHud
extends Control
## Battle HUD built in code (HUD v3, ADR 0013): the top turn bar with both sides and the tick
## ruler, the end-turn module (ready counter + button), the key hints and the turn/result
## banner. Reads state only through HudModel; everything ignores the mouse except the end-turn
## button.

signal end_turn_pressed

const SHADE_HEIGHT := 120
const TOAST_BOTTOM := 130
const TARGETING_TOP := 118
const SIDE_WIDTH := 236
const ACTIVE_ALPHA := 1.0
const INACTIVE_ALPHA := 0.6
const FADE_SECONDS := 0.3
## Key hints (keycap, label), both translation keys (unknown keys show as written). Only keys
## the game really has; the order keys 1-6 follow with the radial menu (TASK-082).
const KEY_HINTS: Array[Array] = [
	["LMB", "SELECT / MOVE / ATTACK"],
	["RMB", "ROTATE / DESELECT"],
	["RMB ON UNIT", "UNIT MENU"],
	["LMB DRAG", "PAN"],
	["WASD/QE", "CAMERA"],
	["WHEEL", "ZOOM"],
	["CTRL+WHEEL/RF", "TILT"],
	["HOME", "RESET VIEW"],
	["G", "GRID"],
	["F5", "SAVE MATCH"],
	["↵", "END TURN"],
]
const HINT_WIDTH := 400
const END_MODULE_MARGIN := 24
const HINT_BOTTOM := 92
const TURN_SIZE := 32
const TURN_LIMIT_SIZE := 16

var _human_player := 0
var _sides: Array[Dictionary] = []  # per player: {block, badge, name, meta, bar, tween}
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


func setup(human_player: int) -> void:
	_human_player = human_player
	name = "BattleHud"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Text is composed in code from already translated parts.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_build_shade()
	_build_top_bar()
	_build_key_hints()
	_build_end_block()
	_build_notices()


## Full refresh from the current simulation state (the view has caught up with it).
func refresh(state: GameState) -> void:
	_apply(state, HudModel.top_bar(state, _human_player))
	var result := HudModel.result_banner(state, _human_player)
	if result != "":
		_show_result(result, state)
	else:
		_hide_result()


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
	var badge: HexBadge = side["badge"]
	badge.fill = color
	badge.ink = data["ink"]
	badge.text = tr(data["short"] as String)
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
	# A draw has no winner: faction_color(-1) is the neutral colour.
	var color := UiPalette.faction_color(state, state.winner)
	var reason := HudModel.result_reason(state, _human_player)
	_banner.show_held(
		caption.to_upper(),
		tr(result).to_upper(),
		color,
		tr(reason).to_upper() if reason != "" else ""
	)


func _hide_result() -> void:
	if _result_shown:
		_result_shown = false
		_banner.release()


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
	var frame := TurnBarFrame.new()
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


func _build_side(parent: Control, index: int, mirrored: bool) -> Dictionary:
	var block := VBoxContainer.new()
	block.name = "Side%d" % index
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.custom_minimum_size.x = SIDE_WIDTH
	block.alignment = BoxContainer.ALIGNMENT_CENTER
	block.add_theme_constant_override(&"separation", 6)
	parent.add_child(block)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END if mirrored else BoxContainer.ALIGNMENT_BEGIN
	block.add_child(row)

	var badge := HexBadge.new()
	badge.name = "Badge"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	name_box.custom_minimum_size.x = SIDE_WIDTH - 50  # badge 40 + gap 10: the rest of the block
	texts.add_child(name_box)
	texts.add_child(meta)
	if mirrored:
		row.add_child(texts)
		row.add_child(badge)
	else:
		row.add_child(badge)
		row.add_child(texts)

	# The bar slot keeps its height when the hatch is hidden on the waiting side.
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size.y = 4
	block.add_child(slot)
	var bar := HatchBar.new(UiPalette.AMBER, Vector2(1, 4), true)
	bar.name = "ActiveBar"
	bar.scrolling = true
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(bar)
	return {
		"block": block,
		"badge": badge,
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


func _build_key_hints() -> void:
	var panel := FramedPanel.new()
	panel.name = "KeyHints"
	panel.chamfers = Vector4(8, 0, 0, 0)
	panel.fill = UiPalette.PANEL_HINT
	panel.padding = Vector2(10, 6)
	_anchor_bottom_right(panel, END_MODULE_MARGIN, HINT_BOTTOM)
	add_child(panel)
	var flow := HFlowContainer.new()
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.alignment = FlowContainer.ALIGNMENT_END
	flow.add_theme_constant_override(&"h_separation", 12)
	flow.add_theme_constant_override(&"v_separation", 5)
	flow.custom_minimum_size.x = HINT_WIDTH
	panel.add_child(flow)
	for hint in KEY_HINTS:
		var pair := HBoxContainer.new()
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pair.add_theme_constant_override(&"separation", 5)
		pair.add_child(KeyCap.new(tr(hint[0] as String).to_upper()))
		var label := _label_font(HudTheme.mono(500, 0), 10, UiPalette.HUD_TEXT)
		label.text = tr(hint[1] as String).to_upper()
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pair.add_child(label)
		flow.add_child(pair)


func _build_end_block() -> void:
	var row := HBoxContainer.new()
	row.name = "EndTurnBlock"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 6)
	_anchor_bottom_right(row, END_MODULE_MARGIN, END_MODULE_MARGIN)
	add_child(row)

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


## Anchors a control's bottom-right corner `right` / `bottom` px from the viewport corner.
func _anchor_bottom_right(control: Control, right: int, bottom: int) -> void:
	control.anchor_left = 1.0
	control.anchor_right = 1.0
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_right = -right
	control.offset_bottom = -bottom
	control.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	control.grow_vertical = Control.GROW_DIRECTION_BEGIN
