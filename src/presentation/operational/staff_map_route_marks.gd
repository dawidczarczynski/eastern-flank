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
## Border incident markers: gate bar half length / width, casus belli triangle, plate metrics.
const GATE_HALF := 11.0
const GATE_WIDTH := 4.0
const CB_SIZE := Vector2(26, 23)
const TAG_SIZE := 12
const PLATE_SIZE := 12
const PLATE_PAD := Vector2(10, 5)
const PLATE_TEXT_WIDTH := 190.0
## Closed country: cross size / stroke, plate above the hex, flips below the hex when it would
## reach above this y (px) – the turn bar and the escalation chip occupy the top ~150 px.
const CLOSED_CROSS := 22.0
const CLOSED_STROKE := 3.0
const CLOSED_FLIP := 160.0

var colour := Color.WHITE
var ink := Color.BLACK
var amber := Color.ORANGE
var alert := Color.RED
var panel := Color(0.07, 0.08, 0.07, 0.92)
var text_colour := Color.WHITE
var muted := Color.GRAY

var _project := Callable()
## One entry per route: {dots: PackedVector3Array, stops: Array[Dictionary] {at, before, after,
## text}, target: Vector3, before: Vector3 (the hex before the target), label, colour: Color,
## style: StaffMapRoute.style(), warnings: Array of {at: Vector3, text, ends} border incidents
## (TASK-116)}. The planning preview is a single entry.
var _routes: Array[Dictionary] = []
var _unreachable := Vector3.ZERO
var _kind := 0  # 0 nothing, 1 routes, 2 unreachable, 3 closed country
var _label := ""
var _alpha := 1.0  # the opacity of the entry being drawn
var _font: Font
var _bar_font: Font
var _plate_font: Font
var _closed := {}  # {at, corners, title, reason} of the kind-3 closed-country mark


func _init() -> void:
	name = "RouteMarks"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = HudTheme.mono(600)
	_bar_font = HudTheme.mono(700)
	_plate_font = HudTheme.display(700)
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
	style := {},
	warnings: Array[Dictionary] = []
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
				"warnings": warnings,
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


## Shows the closed-country mark on the hovered hex: `corners` = the hex outline (6 points on the
## relief), `title` "RUSSIA · CLOSED" and the `reason` line.
func show_closed(at: Vector3, corners: PackedVector3Array, title: String, reason: String) -> void:
	_routes = []
	_closed = {"at": at, "corners": corners, "title": title, "reason": reason}
	_label = title
	_kind = 3
	show()
	queue_redraw()


func is_closed_country() -> bool:
	return _kind == 3


func closed_texts() -> PackedStringArray:
	return (
		PackedStringArray([_closed["title"], _closed["reason"]])
		if _kind == 3
		else PackedStringArray()
	)


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


## Texts of the border warnings of route `index` (the planning preview has index 0).
func warning_texts(index := 0) -> PackedStringArray:
	var out := PackedStringArray()
	if index < _routes.size():
		for warning: Dictionary in _routes[index].get("warnings", []):
			out.append(warning["text"])
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
	if _kind == 3:
		_alpha = 1.0
		_draw_closed()
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
	_draw_warnings(route.get("warnings", []), style["amber_target"])


## Border incidents (design border_warnings.html): a sanctuary breach is a 4 px gate bar across the
## route at the border hex (+ the tag and the sentence in the planning preview); a casus belli is
## a 26 x 23 px triangle "CB" (+ a plate with the sentence in the preview). ui.alert when the
## incident ends the operation. An issued order keeps the bars and triangles only.
func _draw_warnings(warnings: Array, labelled: bool) -> void:
	for warning: Dictionary in warnings:
		var at: Vector2 = _project.call(warning["at"])
		var colour := alert if warning["ends"] else amber
		if warning.get("kind", &"") == StaffMapBorders.BREACH:
			_draw_gate(warning, at, colour, labelled)
		else:
			_draw_casus_belli(warning, at, colour, labelled)


func _draw_gate(warning: Dictionary, at: Vector2, colour: Color, labelled: bool) -> void:
	var before: Vector2 = _project.call(warning["before"])
	var after: Vector2 = _project.call(warning["after"])
	var along := after - before
	along = along.normalized() if along.length() > 0.001 else Vector2.RIGHT
	var across := Vector2(-along.y, along.x)
	draw_line(at - across * GATE_HALF, at + across * GATE_HALF, _c(ink, 0.9), GATE_WIDTH + 2.0)
	draw_line(at - across * GATE_HALF, at + across * GATE_HALF, _c(colour), GATE_WIDTH)
	if not labelled:
		return
	var tag_size := _plate_font.get_string_size(
		warning["tag"], HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE
	)
	var box := Vector2(tag_size.x + 16.0 + PLATE_PAD.x * 2.0, tag_size.y + PLATE_PAD.y * 2.0)
	# Beside the bar (right), not above it: the route's cost label sits above the target hex.
	var top_left := _clamped(at + Vector2(GATE_HALF + 8.0, -box.y / 2.0), box)
	_draw_plate_frame(Rect2(top_left, box), colour, 6.0)
	var base := top_left + Vector2(PLATE_PAD.x, PLATE_PAD.y + _plate_font.get_ascent(TAG_SIZE))
	var mid_y := top_left.y + box.y / 2.0
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(base.x + 5.0, mid_y - 4.0),
				Vector2(base.x + 10.0, mid_y + 4.0),
				Vector2(base.x, mid_y + 4.0)
			]
		),
		_c(colour)
	)
	draw_string(
		_plate_font,
		base + Vector2(16.0, 0.0),
		warning["tag"],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		TAG_SIZE,
		_c(colour)
	)
	var sentence: String = warning["sentence"]
	var s_size := _font.get_string_size(sentence, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var s_origin := _clamped(at + Vector2(-s_size.x / 2.0, GATE_HALF + 8.0), s_size)
	s_origin.y += _font.get_ascent(11)
	draw_string_outline(
		_font, s_origin, sentence, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, _c(ink, 0.9)
	)
	draw_string(_font, s_origin, sentence, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _c(text_colour, 0.85))


func _draw_casus_belli(warning: Dictionary, at: Vector2, colour: Color, labelled: bool) -> void:
	var points := PackedVector2Array(
		[
			at + Vector2(0, -CB_SIZE.y / 2.0),
			at + Vector2(CB_SIZE.x / 2.0, CB_SIZE.y / 2.0),
			at + Vector2(-CB_SIZE.x / 2.0, CB_SIZE.y / 2.0)
		]
	)
	draw_colored_polygon(points, _c(colour))
	draw_polyline(
		PackedVector2Array([points[0], points[1], points[2], points[0]]), _c(ink, 0.9), 1.0, true
	)
	var glyph: String = warning["chip"]
	var g_size := _bar_font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	draw_string(
		_bar_font,
		at + Vector2(-g_size.x / 2.0, CB_SIZE.y / 2.0 - 3.5),
		glyph,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		_c(ink)
	)
	if labelled:
		_draw_chip_plate(
			at + Vector2(CB_SIZE.x / 2.0 + 8.0, 0.0),
			CB_SIZE.x + 16.0,
			glyph,
			warning["text"],
			colour
		)


## Plate with a chip ("CB") and a wrapped sentence, vertically centred on `anchor`; flips to the
## left of `flip_width` px before `anchor` when it would leave the screen.
func _draw_chip_plate(
	anchor: Vector2, flip_width: float, chip: String, text: String, colour: Color
) -> void:
	var text_box := _plate_font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, PLATE_TEXT_WIDTH, PLATE_SIZE
	)
	var chip_size := _bar_font.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	var chip_w := chip_size.x + 8.0
	var box := Vector2(
		PLATE_PAD.x * 2.0 + chip_w + 7.0 + text_box.x, PLATE_PAD.y * 2.0 + maxf(text_box.y, 16.0)
	)
	var left := anchor.x
	if left + box.x > _viewport().x - 4.0:
		left = anchor.x - flip_width - box.x
	var rect := Rect2(_clamped(Vector2(left, anchor.y - box.y / 2.0), box), box)
	_draw_plate_frame(rect, colour, 9.0)
	var chip_rect := Rect2(
		rect.position + Vector2(PLATE_PAD.x, PLATE_PAD.y + 1.0), Vector2(chip_w, 15.0)
	)
	draw_rect(chip_rect, _c(colour))
	draw_string(
		_bar_font,
		chip_rect.position + Vector2(4.0, 11.5),
		chip,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		_c(ink)
	)
	draw_multiline_string(
		_plate_font,
		(
			rect.position
			+ Vector2(PLATE_PAD.x + chip_w + 7.0, PLATE_PAD.y + _plate_font.get_ascent(PLATE_SIZE))
		),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		PLATE_TEXT_WIDTH,
		PLATE_SIZE,
		-1,
		_c(text_colour)
	)


## The chamfered plate of the design: map.void 90 %, 1 px edge in `colour` at 45 %; the outline
## runs along the chamfers too.
func _draw_plate_frame(rect: Rect2, colour: Color, cut: float) -> void:
	var shape := HudShapes.chamfer(rect.size, 0.0, cut, 0.0, cut)
	for i in shape.size():
		shape[i] += rect.position
	draw_colored_polygon(shape, _c(panel, 0.9))
	shape.append(shape[0])
	draw_polyline(shape, _c(colour, 0.45), 1.0, true)


func _viewport() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else size_fallback()


func _clamped(top_left: Vector2, box: Vector2) -> Vector2:
	var view := _viewport()
	return Vector2(
		clampf(top_left.x, 4.0, maxf(4.0, view.x - box.x - 4.0)),
		clampf(top_left.y, 4.0, maxf(4.0, view.y - box.y - 4.0))
	)


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


## Closed country (variant A): ui.alert cross in the hex outline (1.6 px, 10 % fill) and the plate
## above (below the hex when it would reach above CLOSED_FLIP): title with "· CLOSED" in
## ui.alert, reason in mono 11 ui.muted.
func _draw_closed() -> void:
	var at: Vector2 = _project.call(_closed["at"])
	var ring := PackedVector2Array()
	for corner: Vector3 in _closed["corners"]:
		ring.append(_project.call(corner))
	draw_colored_polygon(ring, Color(alert, 0.10))
	ring.append(ring[0])
	draw_polyline(ring, alert, 1.6, true)
	var half := CLOSED_CROSS / 2.0
	for d: Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
		draw_line(at - d * half, at + d * half, Color(ink, 0.9), CLOSED_STROKE + 2.0)
	for d: Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
		draw_line(at - d * half, at + d * half, alert, CLOSED_STROKE)
	var title: String = _closed["title"]
	var reason: String = _closed["reason"]
	var dot := title.find("·")
	var head := title.substr(0, dot) if dot >= 0 else title
	var tail := title.substr(dot) if dot >= 0 else ""
	var head_w := _plate_font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, PLATE_SIZE).x
	var title_size := _plate_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, PLATE_SIZE)
	var reason_size := _font.get_multiline_string_size(
		reason, HORIZONTAL_ALIGNMENT_LEFT, PLATE_TEXT_WIDTH, 11
	)
	var box := Vector2(
		PLATE_PAD.x * 2.0 + maxf(title_size.x, reason_size.x),
		PLATE_PAD.y * 2.0 + title_size.y + 3.0 + reason_size.y
	)
	var hex_top := ring[0].y
	for p in ring:
		hex_top = minf(hex_top, p.y)
	var y := hex_top - 8.0 - box.y
	if y < CLOSED_FLIP:
		var hex_bottom := ring[0].y
		for p in ring:
			hex_bottom = maxf(hex_bottom, p.y)
		y = hex_bottom + 8.0
	var rect := Rect2(_clamped(Vector2(at.x - box.x / 2.0, y), box), box)
	_draw_plate_frame(rect, alert, 9.0)
	var origin := (
		rect.position + Vector2(PLATE_PAD.x, PLATE_PAD.y + _plate_font.get_ascent(PLATE_SIZE))
	)
	draw_string(_plate_font, origin, head, HORIZONTAL_ALIGNMENT_LEFT, -1, PLATE_SIZE, text_colour)
	draw_string(
		_plate_font,
		origin + Vector2(head_w, 0),
		tail,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		PLATE_SIZE,
		alert
	)
	draw_multiline_string(
		_font,
		(
			rect.position
			+ Vector2(PLATE_PAD.x, PLATE_PAD.y + title_size.y + 3.0 + _font.get_ascent(11))
		),
		reason,
		HORIZONTAL_ALIGNMENT_LEFT,
		PLATE_TEXT_WIDTH,
		11,
		-1,
		muted
	)


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
