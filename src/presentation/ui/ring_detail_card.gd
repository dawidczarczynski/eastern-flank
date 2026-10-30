class_name RingDetailCard
extends FramedPanel
## The 272 px detail card beside the radial ring (docs/design/hud_v3/README.md §04): tab (accent,
## #e07c5e when disabled) + `[n]`, title, description, an optional forecast block (big expected
## damage, 10–90 % range bar), `▸` effect rows and the footer (COST / value, or UNAVAILABLE /
## reason in red). Filled from a detail dictionary of TargetRingModel (keys are translated here);
## the orders ring (TASK-082) can use the same format. Ignores the mouse.

const WIDTH := 272
const INNER := WIDTH - 2 - 24  # frame + side padding
const BAR_HEIGHT := 10.0

var _title: Label
var _description: Label
var _forecast: VBoxContainer
var _expected: Label
var _expected_caption: Label
var _range_value: Label
var _bar: _RangeBar
var _effects: VBoxContainer
var _footer: Control
var _footer_label: Label
var _footer_value: Label


## 0..max scale with one tick per HP, the 10–90 % band and a marker at the average.
class _RangeBar:
	extends Control
	var low := 0
	var high := 0
	var expected := 0.0
	var maximum := 1
	var accent := UiPalette.AMBER

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, BAR_HEIGHT)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var scale := w / float(maxi(maximum, 1))
		draw_rect(Rect2(0, 2, w, h - 4), UiPalette.TRACK)
		var band := Rect2(low * scale, 2, maxf((high - low) * scale, 2.0), h - 4)
		draw_rect(band, Color(accent, 0.55))
		for i in range(1, maximum):
			draw_rect(Rect2(i * scale - 0.5, 2, 1, h - 4), UiPalette.TICK_GAP)
		var x := clampf(expected * scale, 1.0, w - 1.0)
		draw_rect(Rect2(x - 1.0, 0, 2, h), UiPalette.HUD_TEXT)


func _init() -> void:
	super()
	name = "RingDetailCard"
	custom_minimum_size = Vector2(WIDTH, 0)
	chamfers = Vector4(0, 14, 0, 14)
	fill = UiPalette.PANEL_STRONG
	padding = Vector2(12, 9)
	tab_right_color = UiPalette.AMBER
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 9)
	add_child(column)
	var head := VBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override(&"separation", 4)
	_title = _label(HudTheme.display(600, 1), 20, UiPalette.HUD_TEXT)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = INNER
	_description = _label(HudTheme.display(400), 12, UiPalette.HUD_DESC)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size.x = INNER
	head.add_child(_title)
	head.add_child(_description)
	column.add_child(head)
	column.add_child(_build_forecast())
	_effects = VBoxContainer.new()
	_effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effects.add_theme_constant_override(&"separation", 3)
	column.add_child(_effects)
	column.add_child(_build_footer())
	hide()


## Fills the card from a TargetRingModel detail dictionary; `accent` colours the tab and the
## forecast band (the tab turns red when the action is disabled).
func show_detail(detail: Dictionary, accent: Color) -> void:
	var disabled: bool = detail.get("disabled", false)
	tab_text = tr(String(detail.get("tab", ""))).to_upper()
	tab_color = UiPalette.DISABLED if disabled else accent
	var key: int = detail.get("key", 0)
	tab_right_text = "[%d]" % key if key > 0 else ""
	_title.text = tr(String(detail.get("title", ""))).to_upper()
	_title.visible = _title.text != ""
	_description.text = tr(String(detail.get("description", "")))
	_description.visible = _description.text != ""
	_fill_forecast(detail.get("forecast", {}), accent)
	_fill_effects(detail.get("effects", []))
	var footer_label := String(detail.get("footer_label", ""))
	_footer.visible = footer_label != ""
	_footer_label.text = tr(footer_label).to_upper()
	_footer_value.text = tr(String(detail.get("footer_value", ""))).to_upper()
	_footer_value.add_theme_color_override(
		&"font_color", UiPalette.DISABLED if disabled else UiPalette.HUD_TEXT
	)
	reset_size()
	show()


## Real card size for placement (layout is deferred, so ask the minimum).
func card_size() -> Vector2:
	var minimum := get_combined_minimum_size()
	return Vector2(maxf(minimum.x, WIDTH), minimum.y)


func _fill_forecast(forecast: Dictionary, accent: Color) -> void:
	_forecast.visible = not forecast.is_empty()
	if forecast.is_empty():
		return
	_expected.text = "~" + String(forecast["expected_text"])
	_range_value.text = forecast["range_text"]
	_bar.low = forecast["low"]
	_bar.high = forecast["high"]
	_bar.expected = forecast["expected"]
	_bar.maximum = forecast["max"]
	_bar.accent = accent
	_bar.queue_redraw()


func _fill_effects(effects: Array) -> void:
	for child in _effects.get_children():
		_effects.remove_child(child)
		child.queue_free()
	for line: Dictionary in effects:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override(&"separation", 7)
		var bullet := _label(HudTheme.mono(500), 11, UiPalette.AMBER)
		bullet.text = "▸"
		var caption := _label(HudTheme.mono(500), 11, UiPalette.HUD_TEXT)
		caption.text = tr(String(line["label"])).to_upper()
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value := _label(HudTheme.mono(600), 12, UiPalette.HUD_TEXT)
		value.text = line["value"]
		row.add_child(bullet)
		row.add_child(caption)
		row.add_child(value)
		_effects.add_child(row)
	_effects.visible = not effects.is_empty()


func _build_forecast() -> Control:
	_forecast = VBoxContainer.new()
	_forecast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_forecast.add_theme_constant_override(&"separation", 4)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override(&"separation", 10)
	_expected = _label(HudTheme.display(700), 34, UiPalette.HUD_TEXT)
	_expected_caption = _label(HudTheme.mono(500, 1), 10, UiPalette.HUD_MUTED)
	_expected_caption.text = tr("AVG DAMAGE").to_upper()
	_expected_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_expected)
	top.add_child(_expected_caption)
	var range_row := HBoxContainer.new()
	range_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var range_caption := _label(HudTheme.mono(500, 1), 10, UiPalette.HUD_MUTED)
	range_caption.text = tr("RANGE 10–90 %").to_upper()
	range_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_range_value = _label(HudTheme.mono(600), 12, UiPalette.HUD_TEXT)
	range_row.add_child(range_caption)
	range_row.add_child(_range_value)
	_bar = _RangeBar.new()
	_forecast.add_child(top)
	_forecast.add_child(range_row)
	_forecast.add_child(_bar)
	return _forecast


func _build_footer() -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 8)
	var line := ColorRect.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.color = UiPalette.LINE
	line.custom_minimum_size = Vector2(0, 1)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 8)
	_footer_label = _label(HudTheme.mono(500), 11, UiPalette.HUD_MUTED)
	_footer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_value = _label(HudTheme.mono(500), 11, UiPalette.HUD_TEXT)
	_footer_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_footer_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer_value.custom_minimum_size.x = 150
	row.add_child(_footer_label)
	row.add_child(_footer_value)
	box.add_child(line)
	box.add_child(row)
	_footer = box
	return box


func _label(font: Font, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label
