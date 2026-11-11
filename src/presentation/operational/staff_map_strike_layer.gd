class_name StaffMapStrikeLayer
extends Control
## What the strike mode draws over the staff map in screen space (TASK-097b), in one node (few
## draw calls): the glow / dim rings of the targets while the mode is open, and the strike trail:
## one trace per missile (flies for the weapon's duration with its arc, wobble and glyph head, then
## stays as a faint trace), an animated effect
## where each ends (StaffMapStrikeFx) and interception marks on the air-defence sites. The
## data comes from StaffMapStrikeHud (targets) and StaffMapStrikeTrail (traces, bursts); the layer
## only reads them and re-draws when the camera moved (`layout`) or an arc grows.

const ARC_SEGMENTS := 24
const DOT_SEGMENTS := 48
const HEAD_SIZE := 16.0
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
	for head in heads():
		_draw_head(head)


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
	var look := _look(trace)
	var colour := look.shade(StaffMapFormations.side_colour(_palette, trace["player"]))
	var progress := _trail.progress(trace)
	if progress <= 0.0:
		return
	var points := _points(trace, progress)
	if points.size() >= 2:
		if progress >= 1.0:
			_polyline(points, Color(colour, FAINT_ALPHA), 2.0, look.dotted)
		else:
			_polyline(points, Color(colour, 0.35), 1.5, look.dotted)
			var keep := maxi(2, ceili(points.size() * look.trail_length))
			_polyline(points.slice(points.size() - keep), Color(colour, 0.95), 2.5, look.dotted)
	var defender := StaffMapFormations.side_colour(_palette, 1 - int(trace["player"]))
	for mark: Dictionary in trace["marks"]:
		_draw_mark(_screen_of_hex.call(mark["coord"]), int(mark["count"]), defender)
	if int(trace.get("more", 0)) > 0:
		var font := HudTheme.mono(700, 0)
		var label := "+%d" % int(trace.get("more", 0))
		draw_string(
			font,
			_end_point(trace) + Vector2(12.0, -12.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			11,
			_palette.ui_text
		)


## One solid or dotted (every other segment) polyline.
func _polyline(points: PackedVector2Array, colour: Color, width: float, dotted: bool) -> void:
	if not dotted:
		draw_polyline(points, colour, width, true)
		return
	for i in range(0, points.size() - 1, 2):
		draw_line(points[i], points[i + 1], colour, width, true)


## The first `progress` of a trace's flight, in screen pixels.
func _points(trace: Dictionary, progress: float) -> PackedVector2Array:
	var look := _look(trace)
	var from: Vector2 = _screen_of_hex.call(trace["from"])
	return StaffMapStrikeFlight.points(
		from,
		_end_point(trace),
		DOT_SEGMENTS if look.dotted else ARC_SEGMENTS,
		progress,
		look.arc_height,
		_bow(trace),
		float(trace["lateral"]),
		look.wobble,
		int(trace.get("seed", 0))
	)


## The weapon's look of a trace (the default look for a hand-made trace without one).
func _look(trace: Dictionary) -> StrikeWeaponLook:
	var look: Variant = trace.get("look")
	if look is StrikeWeaponLook:
		return look
	return StrikeWeaponLook.for_means(trace.get("means", &""))


## The per-missile variation of the arc, damped so the weapon's own arc height stays readable.
func _bow(trace: Dictionary) -> float:
	return 1.0 + (float(trace["bow"]) - 1.0) * 0.25


## The missiles in flight now: [{at, angle, look, colour}] (one head per missile, drawn in
## `_draw`); empty before launch and after impact.
func heads() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if _palette == null or not _screen_of_hex.is_valid() or _trail == null:
		return list
	for trace in _trail.traces:
		var progress := _trail.progress(trace)
		if progress <= 0.0 or progress >= 1.0:
			continue
		var look := _look(trace)
		var from: Vector2 = _screen_of_hex.call(trace["from"])
		var to := _end_point(trace)
		var bow := _bow(trace)
		var lateral := float(trace["lateral"])
		var seed_value := int(trace.get("seed", 0))
		var direction := StaffMapStrikeFlight.heading(
			from, to, progress, look.arc_height, bow, lateral, look.wobble, seed_value
		)
		(
			list
			. append(
				{
					"at":
					StaffMapStrikeFlight.point(
						from, to, progress, look.arc_height, bow, lateral, look.wobble, seed_value
					),
					"angle": direction.angle(),
					"look": look,
					"colour": look.shade(StaffMapFormations.side_colour(_palette, trace["player"])),
				}
			)
		)
	return list


func _draw_head(head: Dictionary) -> void:
	var look: StrikeWeaponLook = head["look"]
	var colour: Color = head["colour"]
	draw_circle(head["at"], HEAD_SIZE * 0.45, Color(_palette.map_void, 0.6))
	StaffMapWeaponGlyph.draw_glyph(
		self, look.glyph, head["at"], HEAD_SIZE, colour.lightened(0.35), float(head["angle"]), 1.6
	)


## Where a trace or burst ends on screen: the target (plus its offset), or short of it at the
## interceptor site for an intercepted missile.
func _end_point(item: Dictionary) -> Vector2:
	var offset: Vector2 = item["offset"]
	var coord: Vector2i = item["coord"] if item.has("coord") else item["to"]
	if item["outcome"] == StaffMapStrikeTrail.INTERCEPTED:
		var site := Vector2.INF
		if item.has("stop"):
			site = _screen_of_hex.call(item["stop"]) + StaffMapInstallations.OFFSET
		return (
			StaffMapStrikeFlight.stop_point(
				_screen_of_hex.call(_origin_of(item)), _screen_of_hex.call(coord), site
			)
			+ offset
		)
	var at: Vector2 = _screen_of_hex.call(coord)
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
