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
## Defence arc: radius (px) and half span (rad).
const ARC_RADIUS := 15.0
const ARC_SPAN := 1.1

var colour := Color.WHITE
var ink := Color.BLACK
var amber := Color.ORANGE
var alert := Color.RED
var panel := Color(0.07, 0.08, 0.07, 0.92)
var text_colour := Color.WHITE

var _project := Callable()
## One entry per route: {dots: PackedVector3Array, stops: Array[Dictionary] {at, before, after,
## text}, target: Vector3, before: Vector3 (the hex before the target), label, colour: Color,
## style: StaffMapRoute.style()}. The planning preview is a single entry.
var _routes: Array[Dictionary] = []
var _unreachable := Vector3.ZERO
var _kind := 0  # 0 nothing, 1 routes, 2 unreachable
var _label := ""
var _alpha := 1.0  # the opacity of the entry being drawn
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


## Shows the planning preview: `dots` = hex centres on the relief (without the start), `stops` =
## Array of {at, before, after, text}, `target` = destination, `before` = the point before it,
## `label` = the cursor label, `style` = StaffMapRoute.style(posture, false).
func show_route(
	dots: PackedVector3Array,
	stops: Array[Dictionary],
	target: Vector3,
	label: String,
	before := Vector3.ZERO,
	style := {}
) -> void:
	_label = label
	show_routes(
		[
			{
				"dots": dots,
				"stops": stops,
				"target": target,
				"before": before,
				"label": label,
				"colour": colour,
				"style": style if not style.is_empty() else StaffMapRoute.style(&"advance", false),
			}
		]
	)


## Shows many routes at once (the issued orders); see `_routes` for an entry.
func show_routes(entries: Array[Dictionary]) -> void:
	_routes = entries
	_unreachable = Vector3.ZERO
	_kind = 1 if not entries.is_empty() else 0
	visible = _kind != 0
	queue_redraw()


## Shows the red cross and the reason on an unreachable hex.
func show_unreachable(at: Vector3, label: String) -> void:
	_routes = []
	_unreachable = at
	_label = label
	_kind = 2
	show()
	queue_redraw()


func clear() -> void:
	_kind = 0
	_routes = []
	_label = ""
	hide()


func is_unreachable() -> bool:
	return _kind == 2


func label_text() -> String:
	return _label


func route_count() -> int:
	return _routes.size()


## Texts of the stop marks of route `index`.
func stop_texts(index := 0) -> PackedStringArray:
	var out := PackedStringArray()
	if index < _routes.size():
		for stop: Dictionary in _routes[index]["stops"]:
			out.append(stop["text"])
	return out


func dot_count(index := 0) -> int:
	if index >= _routes.size():
		return 0
	return (
		(_routes[index]["dots"] as PackedVector3Array).size()
		if _routes[index]["style"]["dots"]
		else 0
	)


func style_of(index := 0) -> Dictionary:
	return _routes[index]["style"] if index < _routes.size() else {}


## Camera moved: re-project.
func refresh() -> void:
	if _kind != 0:
		queue_redraw()


func _draw() -> void:
	if _kind == 0 or not _project.is_valid():
		return
	if _kind == 2:
		var cross: Vector2 = _project.call(_unreachable)
		_alpha = 1.0
		_draw_cross(cross)
		_draw_label(cross, alert)
		return
	for route in _routes:
		_draw_route(route)


func _draw_route(route: Dictionary) -> void:
	var style: Dictionary = route["style"]
	_alpha = style["alpha"]
	var line_colour: Color = route["colour"]
	if style["dots"]:
		_draw_dots(route["dots"], line_colour)
	for stop: Dictionary in route["stops"]:
		_draw_stop(stop, line_colour)
	var target: Vector2 = _project.call(route["target"])
	var accent: Color = amber if style["amber_target"] else line_colour
	draw_circle(target, TARGET_RADIUS + 2.0, _c(ink, 0.85))
	draw_arc(target, TARGET_RADIUS, 0.0, TAU, 24, _c(accent), 2.0, true)
	draw_circle(target, 2.6, _c(accent))
	if style["defend_arc"]:
		_draw_defence_arc(target, _project.call(route["before"]), line_colour)
	if route["label"] != "":
		_label = route["label"]
		_draw_label(target, accent)


## The defence arc of a "defend" order: a crescent across the direction of travel in front of the
## target.
func _draw_defence_arc(target: Vector2, before: Vector2, line_colour: Color) -> void:
	var along := target - before
	var heading := along.angle() if along.length() > 0.5 else -PI / 2.0
	draw_arc(
		target, ARC_RADIUS, heading - ARC_SPAN, heading + ARC_SPAN, 16, _c(ink, 0.9), 5.0, true
	)
	draw_arc(
		target, ARC_RADIUS, heading - ARC_SPAN, heading + ARC_SPAN, 16, _c(line_colour), 2.4, true
	)


## Colour `c` with its alpha scaled by the opacity of the route being drawn.
func _c(c: Color, alpha := 1.0) -> Color:
	return Color(c, c.a * alpha * _alpha)


func _draw_dots(dots: PackedVector3Array, line_colour: Color) -> void:
	var last := Vector2(-1e6, -1e6)
	for point in dots:
		var p: Vector2 = _project.call(point)
		if p.distance_to(last) < MIN_DOT_SPACING:
			continue
		last = p
		draw_circle(p, DOT_RADIUS + 1.0, _c(ink, 0.85))
		draw_circle(p, DOT_RADIUS, _c(line_colour))


## Cross-bar across the line and "+n" beside it.
func _draw_stop(stop: Dictionary, line_colour: Color) -> void:
	var at: Vector2 = _project.call(stop["at"])
	var before: Vector2 = _project.call(stop["before"])
	var after: Vector2 = _project.call(stop["after"])
	var along := after - before
	along = along.normalized() if along.length() > 0.001 else Vector2.RIGHT
	var across := Vector2(-along.y, along.x)
	draw_line(at - across * BAR_HALF, at + across * BAR_HALF, _c(ink), BAR_WIDTH + 2.0)
	draw_line(at - across * BAR_HALF, at + across * BAR_HALF, _c(line_colour), BAR_WIDTH)
	var text: String = stop["text"]
	var size := _bar_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
	var side := across if across.y <= 0.0 else -across  # the label goes upwards
	var anchor := at + side * (BAR_HALF + 4.0)
	var origin := anchor + Vector2(-size.x / 2.0, 0.0 if side.y < -0.3 else size.y * 0.6)
	if side.y >= -0.3:
		origin.x = anchor.x if side.x >= 0.0 else anchor.x - size.x
	_outlined(text, origin, _bar_font, line_colour)


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
		font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 4, _c(ink, 0.9)
	)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, _c(fill))
