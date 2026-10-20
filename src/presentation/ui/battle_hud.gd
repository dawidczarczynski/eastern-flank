class_name BattleHud
extends Control
## Battle HUD built in code: top bar (turn + both sides), end-turn block, controls hint and
## turn/result banner. Reads state only through HudModel; all containers ignore the mouse except
## the end-turn button.

signal end_turn_pressed

const SHADE_HEIGHT := 120
const BANNER_SECONDS := 1.5
const SIDE_WIDTH := 230
const TEXT_ON_FACTION := Color("#121410")
const SANS_BOLD := "IBMPlexSansCondensed-Bold"
const SANS_SEMIBOLD := "IBMPlexSansCondensed-SemiBold"
const MONO_REGULAR := "IBMPlexMono-Regular"
const MONO_MEDIUM := "IBMPlexMono-Medium"
const MONO_SEMIBOLD := "IBMPlexMono-SemiBold"
const HINT := (
	"LMB – select/move/attack · drag – pan · RMB – rotate/deselect · wheel – zoom"
	+ " · WASD/QE – camera · Enter – end turn · F5 – save match"
)

var _human_player := 0
var _sides: Array[Dictionary] = []  # per player: {panel, style, badge_style, badge, name, status}
var _turn_label: Label
var _move_swatch: ColorRect
var _move_label: Label
var _ready_label: Label
var _end_button: Button
var _hint_label: Label
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
	_build_hint()
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
	var active_name := tr(active["name"] as String).to_upper()
	_turn_label.text = bar["turn_text"]
	_move_swatch.color = color
	_move_label.text = tr("MOVE: %s") % active_name
	_ready_label.text = "%d / %d" % [active["ready"], active["units"]]
	_style_button(color)


func _apply_side(index: int, data: Dictionary) -> void:
	var side := _sides[index]
	var style: StyleBoxFlat = side["style"]
	var active: bool = data["active"]
	var color: Color = data["color"]
	style.border_color = color if active else Color(0, 0, 0, 0)
	(side["badge_style"] as StyleBoxFlat).bg_color = color
	var panel: Control = side["panel"]
	var previous: Tween = side.get("tween")
	if previous != null:
		previous.kill()
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0 if active else 0.5, 0.3)
	side["tween"] = tween
	(side["name"] as Label).text = tr(data["name"] as String)
	var badge := side["badge"] as Label
	badge.text = tr(data["short"] as String)
	badge.add_theme_color_override(&"font_color", data["ink"] as Color)
	var status := tr(data["status"] as String)
	var units := tr("%d UNITS") % data["units"]
	var line := "%s · %s" % [status, units] if index == 0 else "%s · %s" % [units, status]
	(side["status"] as Label).text = line.to_upper()


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
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override(&"panel", _panel_style(UiPalette.PANEL_BG, 0, 0))
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.offset_top = 14
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(bar)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 0)
	bar.add_child(row)
	_sides.append(_build_side(row, false))
	row.add_child(_build_centre())
	_sides.append(_build_side(row, true))


func _build_side(parent: Control, mirrored: bool) -> Dictionary:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_bottom = 3
	style.border_color = Color(0, 0, 0, 0)
	style.content_margin_left = 16 if mirrored else 10
	style.content_margin_right = 10 if mirrored else 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size.x = SIDE_WIDTH
	panel.add_theme_stylebox_override(&"panel", style)
	parent.add_child(panel)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_END if mirrored else BoxContainer.ALIGNMENT_BEGIN
	panel.add_child(row)

	var badge_box := PanelContainer.new()
	badge_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_box.custom_minimum_size = Vector2(42, 42)
	badge_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Faction colours are applied from the state in _apply_side().
	var badge_style := _panel_style(UiPalette.NEUTRAL_FACTION, 0, 0, false)
	badge_box.add_theme_stylebox_override(&"panel", badge_style)
	var badge := _label(MONO_SEMIBOLD, 15, UiPalette.NEUTRAL_INK)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_box.add_child(badge)

	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_theme_constant_override(&"separation", 3)
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_label := _label(SANS_SEMIBOLD, 16, UiPalette.TEXT)
	var status := _label(MONO_MEDIUM, 10, UiPalette.TEXT_SECONDARY, 1)
	if mirrored:
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	texts.add_child(name_label)
	texts.add_child(status)

	if mirrored:
		row.add_child(texts)
		row.add_child(badge_box)
	else:
		row.add_child(badge_box)
		row.add_child(texts)
	return {
		"panel": panel,
		"style": style,
		"badge_style": badge_style,
		"badge": badge,
		"name": name_label,
		"status": status,
	}


func _build_centre() -> Control:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_color = UiPalette.DIVIDER
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(&"panel", style)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 2)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(column)

	var caption := _label(MONO_MEDIUM, 10, UiPalette.TEXT_SECONDARY, 2)
	caption.text = tr("TURN")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(caption)
	_turn_label = _label(MONO_SEMIBOLD, 32, UiPalette.TEXT)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_turn_label)

	var move_row := HBoxContainer.new()
	move_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_row.alignment = BoxContainer.ALIGNMENT_CENTER
	move_row.add_theme_constant_override(&"separation", 6)
	_move_swatch = ColorRect.new()
	_move_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_move_swatch.custom_minimum_size = Vector2(7, 7)
	_move_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	move_row.add_child(_move_swatch)
	_move_label = _label(MONO_MEDIUM, 11, UiPalette.TEXT_MUTED, 1)
	move_row.add_child(_move_label)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_top", 3)
	margin.add_child(move_row)
	column.add_child(margin)
	return panel


func _build_hint() -> void:
	var box := PanelContainer.new()
	box.name = "ControlsHint"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override(
		&"panel", _panel_style(Color(17 / 255.0, 19 / 255.0, 15 / 255.0, 0.6), 10, 7, false)
	)
	_anchor_bottom_centre(box, 16)  # between the terrain panel and the end-turn block
	add_child(box)
	_hint_label = _label(MONO_REGULAR, 10, UiPalette.TEXT_MUTED)
	_hint_label.text = tr(HINT)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.custom_minimum_size.x = 440
	_hint_label.add_theme_constant_override(&"line_spacing", 5)
	box.add_child(_hint_label)


func _build_end_block() -> void:
	var block := PanelContainer.new()
	block.name = "EndTurnBlock"
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_theme_stylebox_override(&"panel", _panel_style(UiPalette.PANEL_BG, 0, 0))
	_anchor_bottom_right(block, 16, 16)
	add_child(block)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 0)
	block.add_child(row)

	var info_margin := MarginContainer.new()
	info_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_margin.add_theme_constant_override(&"margin_left", 16)
	info_margin.add_theme_constant_override(&"margin_right", 16)
	info_margin.add_theme_constant_override(&"margin_top", 8)
	info_margin.add_theme_constant_override(&"margin_bottom", 8)
	row.add_child(info_margin)
	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override(&"separation", 2)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info_margin.add_child(info)
	var caption := _label(MONO_MEDIUM, 9, UiPalette.TEXT_SECONDARY, 1)
	caption.text = tr("READY UNITS")
	info.add_child(caption)
	_ready_label = _label(MONO_SEMIBOLD, 20, UiPalette.TEXT)
	info.add_child(_ready_label)

	_end_button = Button.new()
	_end_button.name = "EndTurnButton"
	_end_button.text = tr("End turn").to_upper()
	_end_button.focus_mode = Control.FOCUS_NONE  # Enter must not double as a button press
	_end_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_end_button.add_theme_font_override(&"font", HudTheme.font(SANS_BOLD, 2))
	_end_button.add_theme_font_size_override(&"font_size", 15)
	for color_name: StringName in [
		&"font_color",
		&"font_hover_color",
		&"font_pressed_color",
		&"font_disabled_color",
		&"font_focus_color",
		&"font_hover_pressed_color"
	]:
		_end_button.add_theme_color_override(color_name, TEXT_ON_FACTION)
	_end_button.pressed.connect(func() -> void: end_turn_pressed.emit())
	row.add_child(_end_button)
	_style_button(UiPalette.NEUTRAL_FACTION)  # recoloured by the first refresh()


func _style_button(color: Color) -> void:
	var factors := {
		&"normal": 1.0, &"hover": 1.12, &"pressed": 0.92, &"disabled": 1.0, &"focus": 1.0
	}
	for state: StringName in factors:
		var style := StyleBoxFlat.new()
		var f: float = factors[state]
		style.bg_color = Color(
			minf(color.r * f, 1.0), minf(color.g * f, 1.0), minf(color.b * f, 1.0), 1.0
		)
		style.content_margin_left = 26
		style.content_margin_right = 26
		_end_button.add_theme_stylebox_override(state, style)


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


func _panel_style(fill: Color, margin_h: int, margin_v: int, bordered: bool = true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	if bordered:
		style.set_border_width_all(1)
		style.border_color = UiPalette.PANEL_BORDER
	style.content_margin_left = margin_h
	style.content_margin_right = margin_h
	style.content_margin_top = margin_v
	style.content_margin_bottom = margin_v
	return style


## Centres a control horizontally with its bottom edge `bottom` px above the viewport bottom.
func _anchor_bottom_centre(control: Control, bottom: int) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_bottom = -bottom
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_BEGIN


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
