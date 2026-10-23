class_name BattleHud
extends Control
## Battle HUD built in code (HUD v3, ADR 0013): the top turn bar with both sides and the tick
## ruler, the end-turn module (ready counter + button), the key hints and the turn/result
## banner. Reads state only through HudModel; everything ignores the mouse except the end-turn
## button.

signal end_turn_pressed

const SHADE_HEIGHT := 120
const BANNER_SECONDS := 1.5
const SIDE_WIDTH := 236
const ACTIVE_ALPHA := 1.0
const INACTIVE_ALPHA := 0.6
const FADE_SECONDS := 0.3
const SANS_BOLD := "IBMPlexSansCondensed-Bold"
const MONO_MEDIUM := "IBMPlexMono-Medium"
## Key hints (keycap, label), both translation keys (unknown keys show as written). Only keys
## the game really has; the order keys 1-6 follow with the radial menu (TASK-082).
const KEY_HINTS: Array[Array] = [
	["LMB", "SELECT / MOVE / ATTACK"],
	["RMB", "ROTATE / DESELECT"],
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

var _human_player := 0
var _sides: Array[Dictionary] = []  # per player: {block, badge, name, meta, bar, tween}
var _turn_label: Label
var _active_label: Label
var _ready_value: Label
var _ready_blocks: ReadyBlocks
var _end_button: EndTurnButton
var _banner: PanelContainer
var _banner_turn: Label
var _banner_name: Label
var _banner_timer: Timer
var _result_shown := false
var _prev_turn := -1
var _prev_player := -1


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
	_build_banner()


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
	_active_label.text = "▸ %s" % tr(active["name"] as String).to_upper()
	_active_label.add_theme_color_override(&"font_color", color)
	_ready_value.text = "%d / %d" % [active["ready"], active["units"]]
	_ready_blocks.set_counts(active["ready"], active["units"], color)
	_end_button.fill = color


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
	_banner_turn.text = "%s %02d" % [tr("TURN"), turn]
	_banner_name.text = tr(UiPalette.faction_name(state, player)).to_upper()
	_banner_name.add_theme_color_override(&"font_color", UiPalette.faction_color(state, player))
	_banner.show()
	_banner_timer.start(BANNER_SECONDS)  # restarts a running timer


func _show_result(result: String, state: GameState) -> void:
	_result_shown = true
	_banner_timer.stop()
	_banner_turn.text = "%s %02d" % [tr("TURN"), state.turn]
	_banner_name.text = tr(result).to_upper()
	_banner_name.add_theme_color_override(
		&"font_color", UiPalette.faction_color(state, state.winner)
	)
	_banner.show()


func _hide_result() -> void:
	if _result_shown:
		_result_shown = false
		_banner.hide()


func _on_banner_timeout() -> void:
	if not _result_shown:
		_banner.hide()


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
	texts.add_child(name_label)
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
	_turn_label = _label_font(HudTheme.mono(700), 32, UiPalette.HUD_TEXT)
	_turn_label.name = "TurnNumber"
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_turn_label)
	_active_label = _label_font(HudTheme.mono(600, 1), 10, UiPalette.HUD_MUTED)
	_active_label.name = "ActiveSide"
	_active_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_active_label)
	group.add_child(_divider())
	return group


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


func _build_banner() -> void:
	var edge := Color(17 / 255.0, 19 / 255.0, 15 / 255.0, 0.0)
	var mid := Color(17 / 255.0, 19 / 255.0, 15 / 255.0, 0.85)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	gradient.colors = PackedColorArray([edge, mid, mid, edge])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(1, 0)
	texture.width = 256
	texture.height = 4

	_banner = PanelContainer.new()
	_banner.name = "TurnBanner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	_banner.add_theme_stylebox_override(&"panel", style)
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.34
	_banner.anchor_bottom = 0.34
	_banner.grow_vertical = Control.GROW_DIRECTION_END
	add_child(_banner)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 6)
	_banner.add_child(column)
	_banner_turn = _label(MONO_MEDIUM, 12, UiPalette.TEXT_SECONDARY, 4)
	_banner_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_banner_turn)
	_banner_name = _label(SANS_BOLD, 40, UiPalette.TEXT, 2)
	_banner_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_banner_name)
	_banner.hide()

	_banner_timer = Timer.new()
	_banner_timer.one_shot = true
	_banner_timer.timeout.connect(_on_banner_timeout)
	add_child(_banner_timer)


# --- helpers -------------------------------------------------------------------------------


func _label(file: String, size: int, color: Color, spacing: int = 0) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", HudTheme.font(file, spacing))
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label


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
