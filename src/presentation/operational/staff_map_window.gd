class_name StaffMapWindow
extends FramedPanel
## The one docked window of the staff map (docs/design/operational_map/bottom_bar_windows.html,
## variant A): a FramedPanel with the strong panel fill, a 1 px `LINE` outline, chamfers
## (0, 16, 0, 16), a tab, the X in the top-right corner, a width tier (330 default, 420 reports)
## and a dock: the left edge (x 16 / y 110) or the right edge (x = viewport width - 16 - width).
## The height follows the content. Subclasses only fill the content; the owner (StaffMap) keeps
## one left window at a time and closes them all on a click on the map.
##
## Shared row builders: `toggle_row` (36 px, check box, label, ON/OFF, key cap), `info_row`
## (label left, mono value right) and `hint_line`.

signal close_requested

enum Dock { LEFT, RIGHT }

const WIDTH_DEFAULT := 330.0
const WIDTH_REPORT := 420.0
const MARGIN := 16.0
const TOP := 110.0
const CHAMFERS := Vector4(0, 16, 0, 16)
const ROW_HEIGHT := 36.0
const INFO_SIZE := 12

var dock_side := Dock.LEFT

var _close: StaffMapCloseButton


func _init(title := " ", width := WIDTH_DEFAULT) -> void:
	super()
	mouse_filter = Control.MOUSE_FILTER_STOP
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size = Vector2(width, 0)
	fill = UiPalette.PANEL_STRONG
	line_color = UiPalette.LINE
	chamfers = CHAMFERS
	padding = Vector2(14, 12)
	tab_text = title
	tab_color = UiPalette.AMBER
	_close = StaffMapCloseButton.attach(self)
	_close.pressed.connect(func() -> void: close_requested.emit())
	hide()


func close_button() -> StaffMapCloseButton:
	return _close


func is_open() -> bool:
	return visible


## Hides the window; true when it was open.
func close() -> bool:
	var was_open := visible
	hide()
	return was_open


## Top-left corner of a window of `width` docked on `side` in a viewport `viewport_width` wide.
static func dock_position(side: Dock, viewport_width: float, width: float) -> Vector2:
	if side == Dock.RIGHT:
		return Vector2(viewport_width - MARGIN - width, TOP)
	return Vector2(MARGIN, TOP)


## Sizes the window to its content and puts it on its dock.
func dock(viewport_width: float) -> void:
	reset_size()
	position = dock_position(dock_side, viewport_width, size.x)
	var parent := get_parent_control()
	if parent != null:  # keep clear of the bottom bar
		var floor_y := parent.size.y - float(ActionBar.HEIGHT) - MARGIN
		position.y = clampf(position.y, 8.0, maxf(floor_y - size.y, 8.0))


## Shows the window on its dock.
func open(viewport_width: float) -> void:
	show()
	dock(viewport_width)


# --- shared rows -----------------------------------------------------------------------------


## A toggle row: check box, label, state text (ON / OFF) and the key cap. `set_on` lights it.
class ToggleRow:
	extends Button

	var _box: Control
	var _state: Label
	var _text_on := "ON"
	var _text_off := "OFF"

	func _init(label_text: String, key_text: String, on_text := "ON", off_text := "OFF") -> void:
		toggle_mode = true
		focus_mode = Control.FOCUS_NONE
		auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		custom_minimum_size = Vector2(0, StaffMapWindow.ROW_HEIGHT)
		_text_on = on_text
		_text_off = off_text
		var dim := Color(UiPalette.AMBER, 0.2)
		add_theme_stylebox_override(&"normal", MenuStyle.box(Color(0, 0, 0, 0), dim))
		add_theme_stylebox_override(&"hover", MenuStyle.box(Color(UiPalette.AMBER, 0.06), dim))
		var lit := MenuStyle.box(Color(UiPalette.AMBER, 0.12), Color(UiPalette.AMBER, 0.6))
		add_theme_stylebox_override(&"pressed", lit)
		add_theme_stylebox_override(&"hover_pressed", lit)
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 10
		row.offset_right = -10
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override(&"separation", 10)
		add_child(row)
		_box = Control.new()
		_box.custom_minimum_size = Vector2(14, 14)
		_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.draw.connect(_draw_box)
		row.add_child(_box)
		var name_label := MenuStyle.label(
			label_text, HudTheme.display(700, 1), 12, UiPalette.HUD_TEXT
		)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		_state = MenuStyle.label("", HudTheme.mono(600, 0), 10, UiPalette.HUD_MUTED)
		_state.name = "State"
		_state.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_state)
		var cap := KeyCap.new(key_text)
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cap)
		set_on(false)

	## Lights or dims the row without emitting.
	func set_on(on: bool) -> void:
		set_pressed_no_signal(on)
		_state.text = _text_on if on else _text_off
		_state.add_theme_color_override(
			&"font_color", UiPalette.AMBER if on else UiPalette.HUD_MUTED
		)
		_box.queue_redraw()

	func state_text() -> String:
		return _state.text

	func _draw_box() -> void:
		var colour := UiPalette.AMBER if button_pressed else UiPalette.HUD_MUTED
		_box.draw_rect(Rect2(Vector2.ZERO, _box.size), colour, false, 1.0)
		if button_pressed:
			var points := PackedVector2Array([Vector2(3, 7), Vector2(6, 10), Vector2(11, 4)])
			_box.draw_polyline(points, colour, 1.6)


static func toggle_row(
	label_text: String, key_text: String, on_text := "ON", off_text := "OFF"
) -> ToggleRow:
	return ToggleRow.new(label_text, key_text, on_text, off_text)


## An info row: `caption` left (display 400), mono value right. The value label is the child
## named "Value" (see `row_value`).
static func info_row(caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := MenuStyle.label(caption, HudTheme.display(400), INFO_SIZE, UiPalette.HUD_MUTED)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cap)
	var value := MenuStyle.label("", HudTheme.mono(600), INFO_SIZE, UiPalette.HUD_TEXT)
	value.name = "Value"
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return row


static func row_value(row: Control) -> Label:
	return row.get_node("Value") as Label


## A hint line under a rule (mono 11, muted).
static func hint_line(text: String) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 6)
	var rule := ColorRect.new()
	rule.color = Color("#2e3329")
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	var label := MenuStyle.label(text, HudTheme.mono(400), 11, UiPalette.HUD_MUTED)
	label.name = "Hint"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	return box
