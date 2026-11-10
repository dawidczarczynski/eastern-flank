class_name StaffMapStrikeChip
extends FramedPanel
## The collapsed strike report (TASK-097b): a compact 30 px chip "▮ STRIKE  CRUISE ×3 · 2 HIT  ✕".
## When several reports are queued a small muted "1/3" with ◂ ▸ is added. J (and the arrow keys)
## work as before but are not printed; X dismisses the report. Pure view fed by
## StaffMapStrikeReports.

signal toggle_requested
signal browse_requested(delta: int)
signal close_requested

const HEIGHT := 30.0
const MAX_WIDTH := 400.0

var _palette: StaffMapPalette
var _row: HBoxContainer
var _marker: Control
var _side: Label
var _summary: Label
var _position: Label
var _prev: Button
var _next: Button
var _close: StaffMapCloseButton
var _own := true
var _colour := Color.WHITE
var _ink := Color.BLACK


func _init(palette: StaffMapPalette = null) -> void:
	super()
	_palette = palette if palette != null else StaffMapPalette.new()
	name = "StrikeChip"
	mouse_filter = Control.MOUSE_FILTER_STOP
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size = Vector2(0, HEIGHT)
	chamfers = Vector4(0, 9, 0, 9)
	fill = UiPalette.PANEL_STRONG
	padding = Vector2(12, 0)
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override(&"separation", 7)
	add_child(_row)
	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.custom_minimum_size = Vector2(14, 14)
	_marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_marker.draw.connect(_draw_marker)
	_row.add_child(_marker)
	_side = _label(HudTheme.display(700, 2), 11)
	_row.add_child(_side)
	_summary = _label(HudTheme.mono(600, 0), 12)
	_summary.add_theme_color_override(&"font_color", UiPalette.HUD_MUTED)
	_row.add_child(_summary)
	_prev = _small_button("◂", func() -> void: browse_requested.emit(-1))
	_row.add_child(_prev)
	_position = _label(HudTheme.mono(600, 0), 11)
	_position.add_theme_color_override(&"font_color", UiPalette.HUD_MUTED)
	_row.add_child(_position)
	_next = _small_button("▸", func() -> void: browse_requested.emit(1))
	_row.add_child(_next)
	_close = StaffMapCloseButton.new()
	_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close.pressed.connect(func() -> void: close_requested.emit())
	_row.add_child(_close)
	hide()


func close_button() -> StaffMapCloseButton:
	return _close


## "STRIKE CRUISE ×3 · 1 HIT 1/3" (tests).
func text_of() -> String:
	return "%s %s %s" % [_side.text, _summary.text, _position.text]


func present(model: Dictionary, index: int, total: int, max_width := MAX_WIDTH) -> void:
	_summary.clip_text = false
	_summary.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_summary.custom_minimum_size.x = 0.0
	_own = model["own"]
	_colour = StaffMapFormations.side_colour(_palette, model["striker"])
	_ink = StaffMapFormations.side_ink(_palette, model["striker"])
	_marker.queue_redraw()
	if model["threshold"]:
		_colour = _palette.ui_alert
	_side.text = (tr("STRIKE") if _own else (model["side_name"] as String).to_upper())
	_side.add_theme_color_override(&"font_color", _palette.ui_amber if _own else _colour)
	_summary.text = _summary_of(model)
	var queued := total > 1
	_prev.visible = queued
	_next.visible = queued
	_position.visible = queued
	_position.text = "%d/%d" % [index + 1, total]
	_prev.disabled = index <= 0
	_next.disabled = index >= total - 1
	line_color = Color(_palette.ui_alert, 0.6) if model["threshold"] else UiPalette.LINE
	show()
	reset_size()
	if size.x > max_width:  # trim the summary with an ellipsis
		_summary.clip_text = true
		_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_summary.custom_minimum_size.x = maxf(
			40.0, _summary.get_minimum_size().x - (size.x - max_width)
		)
		reset_size()


func _summary_of(model: Dictionary) -> String:
	if model.has("chip_name"):
		return ("%s · %s" % [model["chip_name"], model["chip_result"]]).to_upper()
	return (model["chip"] as String).to_upper()


func _label(font: Font, size_px: int) -> Label:
	var label := MenuStyle.label("", font, size_px, _palette.ui_amber)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return label


func _small_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_override(&"font", HudTheme.mono(700, 0))
	button.add_theme_font_size_override(&"font_size", 12)
	button.add_theme_color_override(&"font_color", _palette.ui_amber)
	button.add_theme_color_override(&"font_hover_color", UiPalette.HUD_TEXT)
	button.add_theme_color_override(&"font_disabled_color", Color(UiPalette.HUD_MUTED, 0.5))
	button.pressed.connect(action)
	return button


func _draw_marker() -> void:
	if _own:
		_marker.draw_rect(Rect2(0, 2.5, 14, 9), _colour)
	else:
		_marker.draw_set_transform(Vector2(7, 7), PI / 4.0)
		_marker.draw_rect(Rect2(-5, -5, 10, 10), _colour)
