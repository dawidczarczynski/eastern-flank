class_name ActionBar
extends PanelContainer
## Bottom command bar (docs/design/hud_v3/README.md "07 Bottom command bar"): full width, docked
## to the bottom edge, three zones divided by 1 px lines. Left = info (operation label, hex
## strip), centre = buttons with key caps, right = the view's own module (battle: ready counter
## and End turn). Holds no game rules: a button emits `action_pressed(id)` and the owner acts.

signal action_pressed(id: StringName)

const HEIGHT := 76
## Toasts and prompts float this far above the bar's top edge.
const NOTICE_GAP := 18
const HATCH_HEIGHT := 4.0
const ZONE_PADDING := 14
const GAP := 6

var _left := HBoxContainer.new()
var _centre := HBoxContainer.new()
var _right := HBoxContainer.new()
var _left_divider := _divider()
var _right_divider := _divider()
var _buttons: Dictionary = {}  # id -> ActionBarButton


func _init() -> void:
	name = "ActionBar"
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = HEIGHT
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_top = -HEIGHT
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_STRONG
	style.border_color = UiPalette.LINE
	style.border_width_top = 1
	add_theme_stylebox_override(&"panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 0)
	add_child(row)
	for zone in [_left, _centre, _right]:
		var box := zone as HBoxContainer
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override(&"separation", GAP)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
	_centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_divider.hide()
	_right_divider.hide()
	row.add_child(_padded(_left))
	row.add_child(_left_divider)
	row.add_child(_padded(_centre))
	row.add_child(_right_divider)
	row.add_child(_padded(_right))


func _draw() -> void:
	# The thin hatch above the top edge (HUD v3 hatch: 2 px stripes every 6 px at 135 degrees).
	var x := 0.0
	while x < size.x + HATCH_HEIGHT:
		draw_line(
			Vector2(x, -1.0), Vector2(x - HATCH_HEIGHT, -1.0 - HATCH_HEIGHT), UiPalette.LINE, 2.0
		)
		x += 6.0


func _ready() -> void:
	resized.connect(queue_redraw)


## Puts a control into the left zone (info: operation label, hex strip).
func add_left(control: Control) -> void:
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_left.add_child(control)
	_left_divider.show()


## Thin vertical line between two items of the left zone.
func add_left_divider() -> void:
	var line := _divider()
	line.custom_minimum_size = Vector2(1, 36)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_left.add_child(line)


## Puts a control into the right zone (the view's own module).
func add_right(control: Control) -> void:
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_right.add_child(control)
	_right_divider.show()


## Adds an icon button (the icon is ActionIcons[id]). `label_key`, `key_text` and `tip_key` are
## translation keys; they only show in the hover tooltip.
func add_action(
	id: StringName, label_key: String, key_text: String, toggle := false, tip_key := ""
) -> ActionBarButton:
	var button := ActionBarButton.new(id, label_key, key_text, toggle, tip_key)
	button.name = String(id)
	button.pressed.connect(func() -> void: action_pressed.emit(id))
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_buttons[id] = button
	_centre.add_child(button)
	return button


## Thin separator between groups of buttons.
func add_separator() -> void:
	var line := _divider()
	line.custom_minimum_size = Vector2(1, 22)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_centre.add_child(line)


func button(id: StringName) -> ActionBarButton:
	return _buttons.get(id) as ActionBarButton


func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_buttons.keys())
	return result


## Lights or dims a toggle button without emitting `action_pressed`.
func set_active(id: StringName, active: bool) -> void:
	var b := button(id)
	if b != null:
		b.set_pressed_no_signal(active)


func set_enabled(id: StringName, enabled: bool) -> void:
	var b := button(id)
	if b != null:
		b.disabled = not enabled


## Re-translates every label (language switch).
func refresh_texts() -> void:
	for b: ActionBarButton in _buttons.values():
		b.refresh_texts()


static func _divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = UiPalette.LINE
	line.custom_minimum_size = Vector2(1, 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


static func _padded(zone: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.size_flags_horizontal = zone.size_flags_horizontal
	margin.add_theme_constant_override(&"margin_left", ZONE_PADDING)
	margin.add_theme_constant_override(&"margin_right", ZONE_PADDING)
	margin.add_child(zone)
	return margin
