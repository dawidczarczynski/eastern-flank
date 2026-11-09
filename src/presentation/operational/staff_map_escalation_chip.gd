class_name StaffMapEscalationChip
extends Button
## Escalation chip under the turn bar (TASK-115, docs/design/operational_map "Turn bar"): the level
## number and name plus five ticks coloured green -> red up to the current level. Click toggles the
## ladder card (the owner connects `pressed`). Reads nothing itself; `show_state` feeds it.

const WIDTH := 290.0
const HEIGHT := 24.0
const TICK_SIZE := Vector2(12, 5)
const TICK_GAP := 3.0

var _ticks: TickRow


## The five ticks, drawn right-aligned inside the chip.
class TickRow:
	extends Control
	var colours: Array[Color] = []
	var lit := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var n := colours.size()
		var total := (
			n * StaffMapEscalationChip.TICK_SIZE.x + (n - 1) * StaffMapEscalationChip.TICK_GAP
		)
		var x := size.x - total - 8.0
		var y := (size.y - StaffMapEscalationChip.TICK_SIZE.y) / 2.0
		for i in n:
			var colour := colours[i] if i <= lit else UiPalette.TRACK
			draw_rect(Rect2(Vector2(x, y), StaffMapEscalationChip.TICK_SIZE), colour)
			x += StaffMapEscalationChip.TICK_SIZE.x + TICK_GAP


func _init() -> void:
	name = "EscalationChip"
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_theme_font_override(&"font", HudTheme.mono(600, 1))
	add_theme_font_size_override(&"font_size", 10)
	var plain := MenuStyle.button("")
	for style in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		var box := plain.get_theme_stylebox(style).duplicate() as StyleBoxFlat
		box.content_margin_left = 10
		add_theme_stylebox_override(style, box)
	for colour in [&"font_color", &"font_hover_color", &"font_pressed_color"]:
		add_theme_color_override(colour, UiPalette.HUD_TEXT)
	plain.free()
	_ticks = TickRow.new()
	add_child(_ticks)


func show_state(state: OperationalState, palette: StaffMapPalette) -> void:
	var top := state.ladder.top()
	text = StaffMapEscalation.chip_text(state).to_upper()
	tooltip_text = tr("ESC_CHIP_TOOLTIP")
	var colours: Array[Color] = []
	for level in top + 1:
		colours.append(StaffMapEscalation.level_colour(level, top, palette))
	_ticks.colours = colours
	_ticks.lit = state.escalation_level
	_ticks.queue_redraw()
	add_theme_color_override(
		&"font_color", StaffMapEscalation.level_colour(state.escalation_level, top, palette)
	)


## Lit tick count (tests).
func lit_ticks() -> int:
	return _ticks.lit + 1


func tick_count() -> int:
	return _ticks.colours.size()
