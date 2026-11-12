class_name StaffMapStrikeLayer
extends Control
## What the strike mode draws over the staff map in screen space (TASK-097b), in one node (few
## draw calls): the glow / dim rings of the targets while the mode is open, and the strike trail:
## one trace per missile (flies for the weapon's duration with its arc, wobble and glyph head, then
## stays as a faint trace), an animated effect
## where each ends (StaffMapStrikeFx), interception marks on the air-defence sites and the
## launcher marker at each launch hex (TASK-147: silhouette, launch tick, side chip, label). The
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
var _labels := true
var _label_font: Font


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


## Launcher labels only at the zoom levels where counters are labelled (Z1 / Z2).
func set_labels(shown: bool) -> void:
	if shown != _labels:
		_labels = shown
		queue_redraw()


func labels_shown() -> bool:
	return _labels


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
	var markers := _trail.visible_launchers()
	for i in range(markers.size() - 1, -1, -1):  # the newest on top
		_draw_launcher(markers[i]["marker"], int(markers[i]["slot"]))
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


## One launcher marker (variant B): the launch tick on the launch hex centre with its single pulse,
## the silhouette 6 px above it (pop-in, map.void halo), the side chip at its top-left and the
## platform label under the tick; stacked markers sit up-right of the newest, fainter. An aircraft
## is not parked: it flies in from behind the launch point facing the target, launches and turns
## away (StaffMapLauncherFlyover); its tick and label stay at the launch point.
func _draw_launcher(marker: Dictionary, slot: int) -> void:
	var age := _trail.launcher_age(marker)
	var kind: Variant = marker["kind"]
	var aircraft := StaffMapLauncherFlyover.is_aircraft(kind)
	var alpha := _trail.launcher_alpha(marker)
	if not aircraft:
		alpha *= StaffMapLauncherMarker.stack_alpha(slot)
	var player := int(marker["player"])
	var colour := StaffMapFormations.side_colour(_palette, player)
	var tick: Vector2 = _screen_of_hex.call(marker["origin"])
	if slot == 0 and alpha > 0.0:
		var pulse_age := age - (StaffMapLauncherMarker.lead_in(kind) if aircraft else 0.0)
		_draw_tick(tick, StaffMapLauncherMarker.pulse(pulse_age), alpha)
	if aircraft:
		var flyover := StaffMapLauncherFlyover.variant(int(marker.get("strike", 0)))
		var target: Vector2 = _screen_of_hex.call(marker.get("to", marker["origin"]))
		var pose := StaffMapLauncherFlyover.pose(
			age, tick, target, flyover["side"], flyover["lateral"]
		)
		var plane_alpha := float(pose["alpha"])
		if plane_alpha > 0.0:
			var heading: Vector2 = pose["heading"]
			_draw_glyph(kind, pose["at"], heading.angle(), 1.0, colour, plane_alpha)
			var corner: Vector2 = pose["at"] - Vector2.ONE * StaffMapLauncherMarker.GLYPH_PX * 0.5
			_draw_side_chip(
				corner, player, Color(colour, plane_alpha), Color(_palette.map_void, plane_alpha)
			)
	elif alpha > 0.0:
		var box := StaffMapLauncherMarker.glyph_rect(StaffMapLauncherMarker.pop_scale(age))
		box.position += tick + StaffMapLauncherMarker.stack_offset(slot)
		var scale := box.size.x / StaffMapLauncherMarker.GLYPH_PX
		_draw_glyph(kind, box.get_center(), 0.0, scale, colour, alpha)
		_draw_side_chip(box.position, player, Color(colour, alpha), Color(_palette.map_void, alpha))
	if _labels and slot == 0 and alpha > 0.0 and str(marker["label"]) != "":
		_draw_launcher_label(tick, TranslationServer.translate(marker["label"]), alpha)


## The launch tick ring and its pulse ({radius, alpha} of StaffMapLauncherMarker.pulse).
func _draw_tick(tick: Vector2, ring: Dictionary, alpha: float) -> void:
	var width := StaffMapLauncherMarker.TICK_WIDTH
	var ink := Color(_palette.ui_text, alpha)
	draw_arc(tick, StaffMapLauncherMarker.TICK_RADIUS, 0.0, TAU, 20, ink, width, true)
	if float(ring["alpha"]) > 0.0:
		var pulse := Color(_palette.ui_text, float(ring["alpha"]) * alpha)
		draw_arc(tick, ring["radius"], 0.0, TAU, 24, pulse, width, true)


## A launcher silhouette of GLYPH_PX * `scale` centred on `centre`, its nose turned to `angle`
## (0 = the drawing's nose to the right), filled in `colour` over a map.void halo.
func _draw_glyph(
	kind: Variant, centre: Vector2, angle: float, scale: float, colour: Color, alpha: float
) -> void:
	var shape := StaffMapLauncherGlyphs.shape(kind)
	var halo := Color(_palette.map_void, alpha)
	var fill := Color(colour, alpha)
	var factor := StaffMapLauncherMarker.GLYPH_PX * scale / StaffMapLauncherGlyphs.BOX
	var fills: Array[PackedVector2Array] = []
	for polygon: PackedVector2Array in shape["fills"]:
		fills.append(_placed(polygon, centre, factor, angle))
	for polygon in fills:
		var ring := polygon.duplicate()
		ring.append(polygon[0])
		draw_polyline(ring, halo, StaffMapLauncherMarker.HALO_PX, true)
	for polygon in fills:
		draw_colored_polygon(polygon, fill)
	for polygon: PackedVector2Array in shape["cutouts"]:
		draw_colored_polygon(_placed(polygon, centre, factor, angle), halo)


## A polygon of the 24-unit glyph box scaled, turned about the box centre and centred on `centre`.
static func _placed(
	polygon: PackedVector2Array, centre: Vector2, scale: float, angle := 0.0
) -> PackedVector2Array:
	var middle := Vector2.ONE * StaffMapLauncherGlyphs.BOX * 0.5
	var points := PackedVector2Array()
	points.resize(polygon.size())
	for i in polygon.size():
		points[i] = centre + ((polygon[i] - middle) * scale).rotated(angle)
	return points


## The mini side chip at the glyph's top-left: own rectangle 9 x 6.5, enemy diamond 9 x 9 (as
## drawn in the mockup); the shape follows the side colour (StaffMapFormations.side_colour).
func _draw_side_chip(corner: Vector2, player: int, fill: Color, halo: Color) -> void:
	var points: PackedVector2Array
	if player == 0:
		var at := corner + Vector2(-3.0, -3.0)
		points = PackedVector2Array(
			[at, at + Vector2(9.0, 0.0), at + Vector2(9.0, 6.5), at + Vector2(0.0, 6.5)]
		)
	else:
		var c := corner + Vector2(1.5, 1.0)
		points = PackedVector2Array(
			[c + Vector2(0, -4.5), c + Vector2(4.5, 0), c + Vector2(0, 4.5), c + Vector2(-4.5, 0)]
		)
	draw_colored_polygon(points, fill)
	var ring := points.duplicate()
	ring.append(points[0])
	draw_polyline(ring, halo, 1.2, true)


## The platform label centred under the launch tick (IBM Plex Sans Condensed 500 11, 3 px halo).
func _draw_launcher_label(tick: Vector2, text: String, alpha: float) -> void:
	if _label_font == null:
		_label_font = HudTheme.font("IBMPlexSansCondensed-Medium")
	var size := StaffMapLauncherMarker.LABEL_SIZE
	var width := _label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var top := (
		StaffMapLauncherMarker.TICK_RADIUS
		+ StaffMapLauncherMarker.LABEL_GAP
		+ _label_font.get_ascent(size)
	)
	var origin := tick + Vector2(-width * 0.5, top)
	draw_string_outline(
		_label_font,
		origin,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size,
		StaffMapLauncherMarker.LABEL_HALO_PX,
		Color(StaffMapPlaceLayer.HALO, alpha)
	)
	draw_string(
		_label_font,
		origin,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size,
		Color(_palette.ui_text, alpha)
	)
