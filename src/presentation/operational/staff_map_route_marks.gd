class_name StaffMapRouteMarks
extends Control
## Screen-space markers of the route preview (TASK-092c, look: docs/design/operational_map
## "Orders"): a dot on every hex centre, a cross-bar with "+n" at every per-turn stop, the amber
## target, a red cross for an unreachable hex and the cursor label. Holds 3D anchor points on the
## relief and projects them through `project` (Vector3 -> Vector2 screen); StaffMap calls
## refresh() only when the preview or the camera changed, so an idle frame costs nothing.

const DOT_RADIUS := 2.6
const BAR_HALF := 8.0
const BAR_WIDTH := 2.0
const TARGET_RADIUS := 7.0
const CROSS_HALF := 8.0
const LABEL_SIZE := 12
const LABEL_PAD := Vector2(7, 4)
const LABEL_LIFT := 30.0
## Dots are skipped on a route whose projected hexes are closer than this (px).
const MIN_DOT_SPACING := 5.0

var colour := Color.WHITE
var ink := Color.BLACK
var amber := Color.ORANGE
var alert := Color.RED
var panel := Color(0.07, 0.08, 0.07, 0.92)
var text_colour := Color.WHITE

var _project := Callable()
var _dots := PackedVector3Array()
var _stops: Array[Dictionary] = []  # {at, before, after: Vector3, text}
var _target := Vector3.ZERO
var _kind := 0  # 0 nothing, 1 route, 2 unreachable
var _label := ""
var _font: Font
var _bar_font: Font


func _init() -> void:
	name = "RouteMarks"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = HudTheme.mono(600)
	_bar_font = HudTheme.mono(700)
	hide()


func set_projector(project: Callable) -> void:
	_project = project


## Shows a route: `dots` = hex centres on the relief (without the start), `stops` = Array of
## {at, before, after, text}, `target` = destination, `label` = the cursor label.
func show_route(
	dots: PackedVector3Array, stops: Array[Dictionary], target: Vector3, label: String
) -> void:
	_dots = dots
	_stops = stops
	_target = target
	_label = label
	_kind = 1
	show()
	queue_redraw()


## Shows the red cross and the reason on an unreachable hex.
func show_unreachable(at: Vector3, label: String) -> void:
	_dots = PackedVector3Array()
	_stops = []
	_target = at
	_label = label
	_kind = 2
	show()
	queue_redraw()


func clear() -> void:
	_kind = 0
	_dots = PackedVector3Array()
	_stops = []
	_label = ""
	hide()


func is_unreachable() -> bool:
	return _kind == 2


func label_text() -> String:
	return _label


func stop_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for stop in _stops:
		out.append(stop["text"])
	return out


func dot_count() -> int:
	return _dots.size()


## Camera moved: re-project.
func refresh() -> void:
	if _kind != 0:
		queue_redraw()


func _draw() -> void:
	if _kind == 0 or not _project.is_valid():
		return
	var target: Vector2 = _project.call(_target)
	if _kind == 2:
		_draw_cross(target)
		_draw_label(target, alert)
		return
	_draw_dots()
	for stop in _stops:
		_draw_stop(stop)
	draw_circle(target, TARGET_RADIUS + 2.0, Color(ink, 0.85))
	draw_arc(target, TARGET_RADIUS, 0.0, TAU, 24, amber, 2.0, true)
	draw_circle(target, 2.6, amber)
	_draw_label(target, amber)


func _draw_dots() -> void:
	var last := Vector2(-1e6, -1e6)
	for point in _dots:
		var p: Vector2 = _project.call(point)
		if p.distance_to(last) < MIN_DOT_SPACING:
			continue
		last = p
		draw_circle(p, DOT_RADIUS + 1.0, Color(ink, 0.85))
		draw_circle(p, DOT_RADIUS, colour)


## Cross-bar across the line and "+n" beside it.
func _draw_stop(stop: Dictionary) -> void:
	var at: Vector2 = _project.call(stop["at"])
	var before: Vector2 = _project.call(stop["before"])
	var after: Vector2 = _project.call(stop["after"])
	var along := after - before
	along = along.normalized() if along.length() > 0.001 else Vector2.RIGHT
	var across := Vector2(-along.y, along.x)
	draw_line(at - across * BAR_HALF, at + across * BAR_HALF, ink, BAR_WIDTH + 2.0)
	draw_line(at - across * BAR_HALF, at + across * BAR_HALF, colour, BAR_WIDTH)
	var text: String = stop["text"]
	var size := _bar_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
	var side := across if across.y <= 0.0 else -across  # the label goes upwards
	var anchor := at + side * (BAR_HALF + 4.0)
	var origin := anchor + Vector2(-size.x / 2.0, 0.0 if side.y < -0.3 else size.y * 0.6)
	if side.y >= -0.3:
		origin.x = anchor.x if side.x >= 0.0 else anchor.x - size.x
	_outlined(text, origin, _bar_font, colour)


func _draw_cross(at: Vector2) -> void:
	for d: Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
		draw_line(at - d * CROSS_HALF, at + d * CROSS_HALF, Color(ink, 0.9), 5.0)
		draw_line(at - d * CROSS_HALF, at + d * CROSS_HALF, alert, 2.4)


func _draw_label(at: Vector2, accent: Color) -> void:
	if _label == "":
		return
	var size := _font.get_string_size(_label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
	var box := Vector2(size.x, size.y) + LABEL_PAD * 2.0
	var top_left := at + Vector2(-box.x / 2.0, -LABEL_LIFT - box.y)
	var viewport := get_viewport_rect().size if is_inside_tree() else size_fallback()
	top_left.x = clampf(top_left.x, 4.0, maxf(4.0, viewport.x - box.x - 4.0))
	if top_left.y < 4.0:
		top_left.y = at.y + LABEL_LIFT  # no room above: below the target
	var rect := Rect2(top_left, box)
	draw_rect(rect, panel)
	draw_rect(rect, Color(accent, 0.7), false, 1.0)
	draw_string(
		_font,
		top_left + Vector2(LABEL_PAD.x, LABEL_PAD.y + _font.get_ascent(LABEL_SIZE)),
		_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		LABEL_SIZE,
		text_colour
	)


func size_fallback() -> Vector2:
	return Vector2(1280, 720)


## Text with a dark halo (readable over any ground).
func _outlined(text: String, origin: Vector2, font: Font, fill: Color) -> void:
	draw_string_outline(
		font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 4, Color(ink, 0.9)
	)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, fill)
