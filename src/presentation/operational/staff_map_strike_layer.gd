class_name StaffMapStrikeLayer
extends Control
## What the strike mode draws over the staff map in screen space (TASK-097b), in one node (few
## draw calls): the glow / dim rings of the targets while the mode is open, and the strike trail:
## one arc per missile (grows for ARC_SECONDS, then stays as a faint trace), an animated effect
## where each ends (StaffMapStrikeFx) and interception marks on the air-defence sites. The
## data comes from StaffMapStrikeHud (targets) and StaffMapStrikeTrail (traces, bursts); the layer
## only reads them and re-draws when the camera moved (`layout`) or an arc grows.

const ARC_SECONDS := StaffMapStrikeTrail.ARC_SECONDS
const ARC_SEGMENTS := 24
const FAINT_ALPHA := 0.5
const FORMATION_RADIUS := 22.0
const INSTALLATION_RADIUS := 16.0
const MARK_RADIUS := 8.0

var _palette: StaffMapPalette
var _screen_of_hex: Callable  # (Vector2i) -> Vector2
var _trail: StaffMapStrikeTrail
var _targets: Array[Dictionary] = []  # {coord, installation: bool, status, hovered}
var _viewer := 0


func _init() -> void:
	name = "StrikeLayer"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(false)


func setup(palette: StaffMapPalette, screen_of_hex: Callable, trail: StaffMapStrikeTrail) -> void:
	_palette = palette
	_screen_of_hex = screen_of_hex
	_trail = trail


## `targets`: [{coord, installation (bool), status (&"legal" / &"conditional" / &"illegal"),
## hovered (bool)}]; empty hides the glows.
func set_targets(targets: Array[Dictionary], viewer: int) -> void:
	_targets = targets
	_viewer = viewer
	queue_redraw()


func target_count() -> int:
	return _targets.size()


## The status of the first target on `coord` (&"" when none), for tests.
func status_at(coord: Vector2i) -> StringName:
	for target in _targets:
		if target["coord"] == coord:
			return target["status"]
	return &""


## The camera moved or the trail changed: redraw, and animate while an arc grows.
func layout() -> void:
	set_process(_trail != null and _trail.animating())
	queue_redraw()


func _process(delta: float) -> void:
	_trail.clock += delta
	if not _trail.animating():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _palette == null or not _screen_of_hex.is_valid():
		return
	for target in _targets:
		_draw_target(target)
	for trace in _trail.traces:
		_draw_trace(trace)
	for burst in _trail.bursts:
		_draw_burst(burst)


func _draw_target(target: Dictionary) -> void:
	var at: Vector2 = _screen_of_hex.call(target["coord"])
	var radius := FORMATION_RADIUS
	if target["installation"]:
		at += StaffMapInstallations.OFFSET
		radius = INSTALLATION_RADIUS
	match target["status"]:
		&"legal":
			var colour := StaffMapFormations.side_colour(_palette, _viewer)
			draw_circle(at, radius, Color(colour, 0.16))
			draw_arc(at, radius + 4.0, 0.0, TAU, 28, Color(colour, 0.4), 2.0, true)
			draw_arc(at, radius, 0.0, TAU, 28, colour, 2.5, true)
		&"conditional":
			var colour := _palette.ui_amber
			draw_circle(at, radius, Color(colour, 0.14))
			draw_arc(at, radius, 0.0, TAU, 28, colour, 2.0, true)
		_:
			draw_circle(at, radius, Color(_palette.map_void, 0.55))
			draw_arc(at, radius, 0.0, TAU, 28, Color(_palette.ui_text, 0.22), 1.0, true)
	if target["hovered"]:
		draw_arc(at, radius + 7.0, 0.0, TAU, 28, _palette.ui_text, 1.5, true)


func _draw_trace(trace: Dictionary) -> void:
	var colour := StaffMapFormations.side_colour(_palette, trace["player"])
	var progress := _trail.progress(trace)
	if progress <= 0.0:
		return
	var from: Vector2 = _screen_of_hex.call(trace["from"])
	var to := _end_point(trace)
	var points := arc_points(
		from, to, ARC_SEGMENTS, progress, float(trace["bow"]), float(trace["lateral"])
	)
	if points.size() >= 2:
		var alpha := 0.9 if progress < 1.0 else FAINT_ALPHA
		draw_polyline(points, Color(colour, alpha), 2.0, true)
	if progress < 1.0 and not points.is_empty():
		draw_circle(points[points.size() - 1], 3.5, colour)
	var defender := StaffMapFormations.side_colour(_palette, 1 - int(trace["player"]))
	for mark: Dictionary in trace["marks"]:
		_draw_mark(_screen_of_hex.call(mark["coord"]), int(mark["count"]), defender)


## Where a trace or burst ends on screen: the target (plus its offset), or short of it at the
## interceptor site for an intercepted missile.
func _end_point(item: Dictionary) -> Vector2:
	var offset: Vector2 = item["offset"]
	if item["outcome"] == StaffMapStrikeTrail.INTERCEPTED:
		if item.has("stop"):
			return _screen_of_hex.call(item["stop"]) + StaffMapInstallations.OFFSET + offset
		var from: Vector2 = _screen_of_hex.call(_origin_of(item))
		var to: Vector2 = _screen_of_hex.call(item["coord"] if item.has("coord") else item["to"])
		return from.lerp(to, StaffMapStrikeTrail.STOP_FRACTION) + offset
	var at: Vector2 = _screen_of_hex.call(item["coord"] if item.has("coord") else item["to"])
	if item["class_id"] != &"formation":
		at += StaffMapInstallations.OFFSET  # installations sit beside the hex centre
	return at + offset


## The launching hex of a burst's strike (its trace's `from`).
func _origin_of(item: Dictionary) -> Vector2i:
	if item.has("from"):
		return item["from"]
	for trace in _trail.traces:
		if trace["strike"] == item["strike"]:
			return trace["from"]
	return item["coord"]


func _draw_mark(at: Vector2, count: int, colour: Color) -> void:
	draw_arc(at, MARK_RADIUS, 0.0, TAU, 16, colour, 1.5, true)
	var d := MARK_RADIUS * 0.55
	draw_line(at + Vector2(-d, -d), at + Vector2(d, d), colour, 1.5, true)
	draw_line(at + Vector2(-d, d), at + Vector2(d, -d), colour, 1.5, true)
	if count > 0:
		var font := HudTheme.mono(700, 0)
		draw_string(
			font,
			at + Vector2(MARK_RADIUS + 3.0, 4.0),
			"×%d" % count,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			11,
			_palette.ui_text
		)


func _draw_burst(burst: Dictionary) -> void:
	StaffMapStrikeFx.draw(
		self, burst, _trail.burst_age(burst), _end_point(burst), burst_colour(burst["outcome"])
	)


## The burst colour of an outcome: hit red, intercepted amber, missed grey.
func burst_colour(outcome: StringName) -> Color:
	match outcome:
		StaffMapStrikeTrail.HIT:
			return _palette.ui_alert
		StaffMapStrikeTrail.INTERCEPTED:
			return _palette.ui_amber
	return UiPalette.HUD_MUTED


## The first `progress` (0..1) of a quadratic arc from `from` to `to`, bowed upward on screen by a
## third of its length (at most 160 px) times `bow`, bent sideways by `lateral` of its length. Pure.
static func arc_points(
	from: Vector2, to: Vector2, segments: int, progress: float, bow := 1.0, lateral := 0.0
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var length := from.distance_to(to)
	var side := (
		(to - from).orthogonal().normalized() * length * lateral if length > 0.0 else Vector2.ZERO
	)
	var control := (from + to) * 0.5 + Vector2(0.0, -minf(length * 0.33, 160.0) * bow) + side
	var last := clampi(roundi(segments * clampf(progress, 0.0, 1.0)), 0, segments)
	for i in last + 1:
		var t := float(i) / segments
		points.append(from.lerp(control, t).lerp(control.lerp(to, t), t))
	return points
