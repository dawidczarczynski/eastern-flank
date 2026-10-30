class_name RadialRing
extends Control
## HUD v3 radial ring (docs/design/hud_v3/README.md "04 Radial orders menu"): six trapezoid
## segments around a unit, dashed inner hex, tick ring and key numbers, drawn in `_draw` from
## RadialRingGeometry. Shared by the target ring (TASK-089b) and the orders ring (TASK-082).
## Slots come as dictionaries in the TargetRingModel "slots" format (label keys are translated
## here). Redraws only when the slots, the hover or the accent change; the owner moves it.
## Mouse: only the disc up to the outer radius takes input; hovering, clicking a slot and clicking
## the hole or a gap are reported as signals (the owner decides what they mean).

signal slot_hovered(slot: int)
signal slot_pressed(slot: int)
## A click inside the ring that hit no usable slot (the hole, a gap, an empty slot) or any RMB.
signal dismissed

const NORMAL_FILL := Color(8 / 255.0, 11 / 255.0, 8 / 255.0, 0.88)
const NORMAL_STROKE := Color(232 / 255.0, 176 / 255.0, 74 / 255.0, 0.4)
const DISABLED_FILL := Color(8 / 255.0, 11 / 255.0, 8 / 255.0, 0.62)
const DISABLED_INK := Color(223 / 255.0, 229 / 255.0, 214 / 255.0, 0.3)
const HOVER_DISABLED_FILL := Color(58 / 255.0, 26 / 255.0, 20 / 255.0, 0.94)
## Empty slots (no action yet): dimmer than disabled, faint frame.
const EMPTY_FILL := Color(8 / 255.0, 11 / 255.0, 8 / 255.0, 0.3)
const EMPTY_STROKE := Color(232 / 255.0, 176 / 255.0, 74 / 255.0, 0.2)
const CENTER_TEXT := Color("#6f7768")
## Drop shadow "0 10px 22px rgba(0,0,0,.5)", approximated by offset copies of the segments.
const SHADOW_LAYERS: Array[Vector3] = [
	Vector3(0, 6, 0.16), Vector3(0, 10, 0.14), Vector3(0, 15, 0.1)
]
const LABEL_SIZE := 11
const LABEL_LINE := 12.0
const KEY_SIZE := 10
const CENTER_SIZE := 10
const ICON_BOX := 20.0  # the 24 x 24 icon drawn at .84 scale
const ICON_STROKE := 1.5
const DASH := 6.0
const DASH_GAP := 4.0
## Stroke icons in a 24 x 24 box (icons.svg style); circles are [centre x, centre y, radius].
const ICON_LINES := {
	&"attack": [[2, 12, 7, 12], [17, 12, 22, 12], [12, 2, 12, 7], [12, 17, 12, 22]],
	&"info": [[12, 10.5, 12, 17.5], [12, 6.5, 12, 8.3]],
}
const ICON_CIRCLES := {
	&"attack": [[12, 12, 6], [12, 12, 1]],
	&"info": [[12, 12, 9.5]],
}

var slots: Array[Dictionary] = []:
	set(value):
		slots = value
		queue_redraw()
## Fill and stroke of a hovered slot and the dashed inner hex (the acting side's colour).
var accent := UiPalette.AMBER:
	set(value):
		accent = value
		queue_redraw()
## Muted caption in the hole (already translated).
var center_text := "":
	set(value):
		center_text = value
		queue_redraw()
## Slot drawn in the hover state, -1 = none.
var hovered := -1:
	set(value):
		if value == hovered:
			return
		hovered = value
		mouse_default_cursor_shape = (
			Control.CURSOR_FORBIDDEN if value >= 0 and not _enabled(value) else Control.CURSOR_ARROW
		)
		queue_redraw()


func _init() -> void:
	name = "RadialRing"
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2.ONE * RadialRingGeometry.SIZE
	custom_minimum_size = size


## Puts the ring centre at `center` (viewport pixels).
func set_center(center: Vector2) -> void:
	position = (center - size * 0.5).round()


func _has_point(point: Vector2) -> bool:
	return (point - size * 0.5).length() <= RadialRingGeometry.OUTER_RADIUS + 2.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hovered != -1:
		hovered = -1
		slot_hovered.emit(-1)


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		var slot := _usable_slot_at(motion.position)
		if slot != hovered:
			hovered = slot
			slot_hovered.emit(slot)
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_LEFT:
		var slot := _usable_slot_at(button.position)
		if slot >= 0:
			slot_pressed.emit(slot)
		else:
			dismissed.emit()
		accept_event()
	elif button.button_index == MOUSE_BUTTON_RIGHT:
		dismissed.emit()
		accept_event()


## The non-empty slot under a local point, else -1.
func _usable_slot_at(point: Vector2) -> int:
	var slot := RadialRingGeometry.slot_at(point - size * 0.5)
	if slot < 0 or _is_empty(slot):
		return -1
	return slot


func _is_empty(slot: int) -> bool:
	return slot >= slots.size() or bool(slots[slot].get("empty", true))


func _enabled(slot: int) -> bool:
	return slot < slots.size() and bool(slots[slot].get("enabled", false))


func _draw() -> void:
	draw_set_transform(size * 0.5)
	for layer in SHADOW_LAYERS:
		for slot in RadialRingGeometry.SLOT_COUNT:
			if _is_empty(slot):
				continue
			var poly := RadialRingGeometry.segment(slot)
			for i in poly.size():
				poly[i] += Vector2(layer.x, layer.y)
			draw_colored_polygon(poly, Color(0, 0, 0, layer.z))
	draw_multiline(RadialRingGeometry.ticks(), UiPalette.LINE, 1.0)
	_draw_keys()
	_draw_dashed_hex()
	for slot in RadialRingGeometry.SLOT_COUNT:
		_draw_slot(slot)
	if center_text != "":
		_draw_centered(HudTheme.mono(500, 1), center_text, Vector2.ZERO, CENTER_SIZE, CENTER_TEXT)


func _draw_keys() -> void:
	var font := HudTheme.mono(600)
	for slot in RadialRingGeometry.SLOT_COUNT:
		var color := UiPalette.AMBER
		if _is_empty(slot):
			color = Color(UiPalette.AMBER, 0.35)
		_draw_centered(font, str(slot + 1), RadialRingGeometry.key_position(slot), KEY_SIZE, color)


func _draw_dashed_hex() -> void:
	var hex := RadialRingGeometry.inner_hex()
	for i in hex.size():
		var from := hex[i]
		var to := hex[(i + 1) % hex.size()]
		var length := from.distance_to(to)
		var direction := (to - from) / length
		var t := 0.0
		while t < length:
			var end := minf(t + DASH, length)
			draw_line(from + direction * t, from + direction * end, accent, 1.5, true)
			t += DASH + DASH_GAP


func _draw_slot(slot: int) -> void:
	var data: Dictionary = slots[slot] if slot < slots.size() else {"empty": true}
	var poly := RadialRingGeometry.segment(slot)
	var outline := poly.duplicate()
	outline.append(poly[0])
	if data.get("empty", true):
		draw_colored_polygon(poly, EMPTY_FILL)
		draw_polyline(outline, EMPTY_STROKE, 1.0)
		return
	var enabled: bool = data.get("enabled", false)
	var fill := NORMAL_FILL if enabled else DISABLED_FILL
	var stroke := NORMAL_STROKE
	var ink := UiPalette.HUD_TEXT if enabled else DISABLED_INK
	if slot == hovered and enabled:
		fill = accent
		stroke = accent
		ink = UiPalette.INK
	elif slot == hovered:
		fill = HOVER_DISABLED_FILL
		stroke = UiPalette.DISABLED
		ink = Color(UiPalette.DISABLED, 0.85)
	draw_colored_polygon(poly, fill)
	draw_polyline(outline, stroke, 1.0)
	var center := RadialRingGeometry.label_center(slot)
	_draw_icon(data.get("icon", &""), center + Vector2(0, -12), ink)
	var font := HudTheme.mono(600)
	var lines: Array = data.get("label", [])
	for i in lines.size():
		var text := tr(String(lines[i])).to_upper()
		var baseline := center + Vector2(0, 10.0 + LABEL_LINE * i)
		_draw_text_at_baseline(font, text, baseline, LABEL_SIZE, ink)


## A stroke icon of ICON_LINES / ICON_CIRCLES centred on `center`.
func _draw_icon(icon: StringName, center: Vector2, color: Color) -> void:
	var scale := ICON_BOX / 24.0
	var origin := center - Vector2(12, 12) * scale
	for line: Array in ICON_LINES.get(icon, []):
		var a := origin + Vector2(line[0], line[1]) * scale
		var b := origin + Vector2(line[2], line[3]) * scale
		draw_line(a, b, color, ICON_STROKE, true)
	for circle: Array in ICON_CIRCLES.get(icon, []):
		var c := origin + Vector2(circle[0], circle[1]) * scale
		var radius: float = circle[2] * scale
		if radius <= 1.5:
			draw_circle(c, radius, color, true, -1.0, true)
		else:
			draw_arc(c, radius, 0.0, TAU, 32, color, ICON_STROKE, true)


## Text horizontally centred on `center`, vertically centred on it too.
func _draw_centered(
	font: Font, text: String, center: Vector2, font_size: int, color: Color
) -> void:
	var baseline := (
		center + Vector2(0, (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
	)
	_draw_text_at_baseline(font, text, baseline, font_size, color)


func _draw_text_at_baseline(
	font: Font, text: String, baseline: Vector2, font_size: int, color: Color
) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(
		font,
		baseline - Vector2(width * 0.5, 0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		color
	)
