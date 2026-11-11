class_name StaffMapTurnBar
extends VBoxContainer
## Turn bar of the staff map (TASK-093b, look: docs/design/operational_map "Turn bar" – the same
## bar as the battle HUD, so it reuses TurnBarFrame, HatchBar and EndTurnButton; a SideFlag
## stands in place of the faction badge):
## the viewed side on the left, TURN n / date / day-night / side moving in the middle, the
## opponent on the right (dimmed while waiting), End turn filled in the colour of the side to
## move. Under the frame the escalation chip (TASK-115) and the strike button.
## Reads the OperationalState only; the buttons just emit signals.

signal end_turn_pressed
signal escalation_pressed
signal strike_pressed

const SIDE_WIDTH := 200.0
const ACTIVE_ALPHA := 1.0
const INACTIVE_ALPHA := 0.6
const TURN_SIZE := 32
## End turn button height in the staff map design (the battle HUD's is 52).
const END_BUTTON_HEIGHT := 46.0
const MONTHS: Array[String] = [
	"JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"
]

var _palette: StaffMapPalette
var _viewer := 0
var _sides: Array[Dictionary] = []  # [viewer's side, opponent]
var _turn_label: Label
var _date_label: Label
var _icon: DayNightIcon
var _mover: Label
var _chip: StaffMapEscalationChip
var _strike_button: Button
var _end_button: EndTurnButton
var _end_divider: ColorRect
var _day := true
var _busy := false  # the counters are sliding: End turn is off


## Sun (day) or crescent moon (night), drawn.
class DayNightIcon:
	extends Control
	var day := true
	var colour := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(13, 13)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_day(p_day: bool, p_colour: Color) -> void:
		day = p_day
		colour = p_colour
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		if day:
			draw_arc(c, 2.6, 0.0, TAU, 16, colour, 1.2)
			for i in 8:
				var dir := Vector2.from_angle(TAU * i / 8.0)
				draw_line(c + dir * 4.0, c + dir * 6.0, colour, 1.2)
		else:
			draw_circle(c, 5.0, colour)
			draw_circle(c + Vector2(2.5, -1.8), 4.4, UiPalette.PANEL_STRONG)


func _init() -> void:
	name = "TurnBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_theme_constant_override(&"separation", 5)
	var frame := TurnBarFrame.new()
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(frame)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 18)
	frame.add_child(row)
	_sides.append(_build_side(row, false))
	row.add_child(_build_centre())
	_sides.append(_build_side(row, true))
	_end_divider = _divider()
	row.add_child(_end_divider)
	_end_button = EndTurnButton.new()
	_end_button.name = "EndTurnButton"
	_end_button.min_height = END_BUTTON_HEIGHT
	_end_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_end_button.pressed.connect(func() -> void: end_turn_pressed.emit())
	row.add_child(_end_button)
	var under := HBoxContainer.new()
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	under.alignment = BoxContainer.ALIGNMENT_CENTER
	under.add_theme_constant_override(&"separation", 8)
	add_child(under)
	_chip = StaffMapEscalationChip.new()
	_chip.pressed.connect(func() -> void: escalation_pressed.emit())
	under.add_child(_chip)
	_strike_button = MenuStyle.button("", true)
	_strike_button.name = "StrikeButton"
	_strike_button.focus_mode = Control.FOCUS_NONE
	_strike_button.custom_minimum_size = Vector2(0, 24)
	_strike_button.add_theme_font_size_override(&"font_size", 10)
	_strike_button.toggled.connect(func(_on: bool) -> void: strike_pressed.emit())
	under.add_child(_strike_button)


## Fills the bar from `state`; `viewer` picks the side shown on the left and the YOUR / ENEMY
## labels (colours belong to the sides).
func show_state(state: OperationalState, palette: StaffMapPalette, viewer: int) -> void:
	_palette = palette
	_viewer = viewer
	var mover := state.current_player
	_apply_side(0, state, viewer, mover == viewer)
	_apply_side(1, state, 1 - viewer, mover == 1 - viewer)
	_turn_label.text = "%02d" % state.turn
	_day = OperationalClock.is_day(state.turn)
	_icon.set_day(_day, Color("#e2c069"))
	_date_label.text = (
		"%s · %s"
		% [
			_date_text(OperationalClock.date(state.turn, state.start_date)),
			OperationalClock.time_of_day(state.turn),
		]
	)
	_mover.text = ("▸ %s" % tr("%s MOVING") % side_name(state, mover)).to_upper()
	_mover.add_theme_color_override(&"font_color", _colour(mover))
	_chip.show_state(state, palette)
	_strike_button.text = tr("STRIKE").to_upper() + "  [S]"
	_strike_button.tooltip_text = tr(
		"Deep strike: pick a means and a target on the map (key S, Esc leaves)"
	)
	_end_button.caption = tr("End turn").to_upper()
	_end_button.fill = _colour(mover)
	_end_button.detail = (
		(tr("ORDERS %d / %d") % [StaffMapOrders.ordered_count(state, mover), _count(state, mover)])
		. to_upper()
	)
	var blocker := _end_turn_blocker(state)
	_end_button.disabled = blocker != "" or _busy
	_end_button.modulate.a = 0.45 if _end_button.disabled else 1.0
	_end_button.tooltip_text = tr("END_TURN_BLOCKED_" + blocker.to_upper()) if blocker != "" else ""
	reset_size()


## Switches End turn off while the counters slide (TASK-092e); takes effect with show_state.
func set_busy(busy: bool) -> void:
	_busy = busy


func escalation_chip() -> StaffMapEscalationChip:
	return _chip


## The Strike button next to the chip (TASK-097b); lit while the strike mode is open.
func strike_button() -> Button:
	return _strike_button


func set_strike_open(open: bool) -> void:
	_strike_button.set_pressed_no_signal(open)


## Hands the End turn button to the bottom bar (TASK-139: same place as in the battle). The bar
## keeps updating it (caption, side colour, ORDERS detail, disabled), so it stays this object.
func take_end_button() -> EndTurnButton:
	_end_button.get_parent().remove_child(_end_button)
	_end_divider.get_parent().remove_child(_end_divider)
	_end_divider.queue_free()
	_end_button.min_height = EndTurnButton.MIN_HEIGHT
	return _end_button


func end_button() -> EndTurnButton:
	return _end_button


func turn_text() -> String:
	return _turn_label.text


func date_text() -> String:
	return _date_label.text


func is_day_shown() -> bool:
	return _day


func mover_text() -> String:
	return _mover.text


func viewed_side_text() -> String:
	return (_sides[0]["name"] as Label).text


func side_meta_text(index: int) -> String:
	return (_sides[index]["meta"] as Label).text


func side_flag(index: int) -> SideFlag:
	return _sides[index]["flag"]


func side_alpha(index: int) -> float:
	return (_sides[index]["block"] as Control).modulate.a


## Translated name of `player`'s side.
static func side_name(state: OperationalState, player: int) -> String:
	var side := SideDefinition.find(state.player_sides[player])
	return TranslationServer.translate(side.display_name) if side != null else ""


## "14 JUN 2027" from an ISO date; "" for no date.
static func _date_text(iso: String) -> String:
	var parts := iso.split("-")
	if parts.size() != 3:
		return ""
	return "%d %s %s" % [int(parts[2]), MONTHS[clampi(int(parts[1]) - 1, 0, 11)], parts[0]]


static func _end_turn_blocker(state: OperationalState) -> String:
	if not state.result.is_empty():
		return "operation_over"
	return EndOperationalTurnCommand.new().validate(state)


static func _count(state: OperationalState, player: int) -> int:
	var n := 0
	for f in state.formations:
		if f.owner_id == player:
			n += 1
	return n


func _apply_side(index: int, state: OperationalState, player: int, active: bool) -> void:
	var side := _sides[index]
	var colour := _colour(player)
	var own := player == _viewer
	(side["name"] as Label).text = side_name(state, player).to_upper()
	(side["flag"] as SideFlag).setup(SideDefinition.find(state.player_sides[player]), colour)
	var status := tr("WAITING")
	if active:
		status = tr("YOUR MOVE") if own else tr("ENEMY MOVE")
	(side["meta"] as Label).text = (
		("%s · %s" % [status, tr("%d FMN") % _count(state, player)]).to_upper()
	)
	var bar: HatchBar = side["bar"]
	bar.color = colour
	bar.visible = active
	(side["block"] as Control).modulate.a = ACTIVE_ALPHA if active else INACTIVE_ALPHA


func _build_side(parent: Control, mirrored: bool) -> Dictionary:
	var block := VBoxContainer.new()
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
	var flag := SideFlag.new(SideFlag.BAR)
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_theme_constant_override(&"separation", 3)
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_label := MenuStyle.label("", HudTheme.display(600, 1), 15, UiPalette.HUD_TEXT)
	var meta := MenuStyle.label("", HudTheme.mono(500, 1), 10, UiPalette.HUD_MUTED)
	if mirrored:
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	texts.add_child(name_label)
	texts.add_child(meta)
	if mirrored:
		row.add_child(texts)
		row.add_child(flag)
	else:
		row.add_child(flag)
		row.add_child(texts)
	# The slot keeps its height when the hatch is hidden on the waiting side.
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size.y = 4
	block.add_child(slot)
	var bar := HatchBar.new(UiPalette.AMBER, Vector2(1, 4), true)
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(bar)
	return {"block": block, "flag": flag, "name": name_label, "meta": meta, "bar": bar}


func _build_centre() -> Control:
	var group := HBoxContainer.new()
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
	var caption := MenuStyle.label(
		tr("TURN").to_upper(), HudTheme.mono(500, 3), 10, UiPalette.HUD_MUTED
	)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(caption)
	_turn_label = MenuStyle.label("", HudTheme.mono(700), TURN_SIZE, UiPalette.HUD_TEXT)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_turn_label)
	var when := HBoxContainer.new()
	when.mouse_filter = Control.MOUSE_FILTER_IGNORE
	when.alignment = BoxContainer.ALIGNMENT_CENTER
	when.add_theme_constant_override(&"separation", 5)
	_icon = DayNightIcon.new()
	when.add_child(_icon)
	_date_label = MenuStyle.label("", HudTheme.mono(600, 1), 10, UiPalette.HUD_DESC)
	when.add_child(_date_label)
	column.add_child(when)
	_mover = MenuStyle.label("", HudTheme.mono(600, 1), 10, UiPalette.AMBER)
	_mover.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_mover)
	group.add_child(_divider())
	return group


func _colour(player: int) -> Color:
	return StaffMapFormations.side_colour(_palette, player)


func _divider() -> ColorRect:
	var line := ColorRect.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.color = UiPalette.LINE
	line.custom_minimum_size = Vector2(1, 0)
	line.size_flags_vertical = Control.SIZE_FILL
	return line
