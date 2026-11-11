class_name StaffMapInstallationMarker
extends Control
## One installation marker of the staff map (TASK-097a, TASK-142): the same hexagonal game tile as
## the formation counters (base R 18, docs/design/operational_map "Counter and marker tokens") with
## a chamfered square plate in the side colour carrying the engraved class glyph (airfield, depot,
## command post, air defence) and 4 integrity studs under it. A destroyed installation is a grey
## plate with an ui.alert cross and unlit studs. Fixed screen size, the control's origin is the hex
## centre. `depth` comes from StaffMapCounter.depth_for_pitch (0 = flat hexagon, no wall / shadow).
## Ignores the mouse - picking is a 2D hit test in StaffMapInstallations.

const RADIUS := 18.0
const PLATE := 18.0
const CUT := 4.0
const PLATE_Y := -2.0
const STUDS := 4
const STUD_RADIUS := 2.1
const STUD_PITCH := 6.2
const STUD_Y := 11.2
const GLYPH_WIDTH := 1.0
const HOVER_LIGHTEN := 0.15
const DESTROYED_FILL := Color("#6d7076")
const DESTROYED_INK := Color("#2a2c30")
const SHADOW_SIZE := Vector2(64, 26)

var installation_id: StringName
var class_id: StringName
var owner_id := 0
var integrity := Installation.MAX_INTEGRITY
var destroyed := false
var hovered := false:
	set(value):
		if hovered != value:
			hovered = value
			queue_redraw()

var depth := 1.0:
	set(value):
		if not is_equal_approx(depth, value):
			depth = value
			queue_redraw()

var _palette: StaffMapPalette


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(installation: Installation, palette: StaffMapPalette) -> void:
	_palette = palette
	installation_id = installation.id
	name = String(installation.id)
	class_id = installation.class_id
	owner_id = installation.owner
	set_integrity(installation.integrity)


func set_integrity(value: int) -> void:
	integrity = value
	destroyed = value <= 0
	queue_redraw()


## Fraction of the bar that is lit, 0..1.
func bar_fraction() -> float:
	return clampf(float(integrity) / float(Installation.MAX_INTEGRITY), 0.0, 1.0)


func fill_colour() -> Color:
	var colour := DESTROYED_FILL
	if not destroyed:
		colour = StaffMapFormations.side_colour(_palette, owner_id)
	if hovered:
		colour = colour.lerp(Color.WHITE, HOVER_LIGHTEN)
	return colour


func ink_colour() -> Color:
	return DESTROYED_INK if destroyed else StaffMapFormations.side_ink(_palette, owner_id)


## True when `local` (relative to the hex centre) is on the tile or its wall.
func hits(local: Vector2) -> bool:
	var scale_y := StaffMapCounter.squash(depth) * StaffMapCounter.TILE_SCALE
	for shift in [StaffMapCounter.WALL_DEPTH * depth, 0.0]:
		var p := Vector2(local.x / StaffMapCounter.TILE_SCALE, (local.y - shift) / scale_y)
		if StaffMapCounter.in_hex(p, RADIUS + 1.0):
			return true
	return false


## Tile and wall around the centre.
func body_rect() -> Rect2:
	var k := StaffMapCounter.TILE_SCALE
	var h := RADIUS * sqrt(3.0) * 0.5 * StaffMapCounter.squash(depth) * k
	return Rect2(-RADIUS * k, -h, RADIUS * k * 2.0, h * 2.0 + StaffMapCounter.WALL_DEPTH * depth)


## Number of lit integrity studs.
func lit_studs() -> int:
	return 0 if destroyed else ceili(bar_fraction() * STUDS)


func _plate(c: Vector2) -> PackedVector2Array:
	var half := PLATE * 0.5
	return PackedVector2Array(
		[
			c + Vector2(-half + CUT, -half),
			c + Vector2(half - CUT, -half),
			c + Vector2(half, -half + CUT),
			c + Vector2(half, half - CUT),
			c + Vector2(half - CUT, half),
			c + Vector2(-half + CUT, half),
			c + Vector2(-half, half - CUT),
			c + Vector2(-half, -half + CUT),
		]
	)


func _draw() -> void:
	if _palette == null:
		return
	StaffMapCounter.draw_shadow(self, SHADOW_SIZE, depth)
	var sy := StaffMapCounter.squash(depth)
	var k := StaffMapCounter.TILE_SCALE
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k * sy))
	var side := DESTROYED_FILL if destroyed else StaffMapFormations.side_colour(_palette, owner_id)
	var base := StaffMapCounter.base_colour(_palette, side)
	StaffMapCounter.draw_base(self, _palette, RADIUS, base, depth, hovered)
	var plate_colour := fill_colour().lerp(Color(0.5, 0.5, 0.5), StaffMapCounter.PLATE_GREY)
	var rise := StaffMapCounter.PLATE_RISE * depth / (sy * k)
	if rise > 0.05:
		draw_colored_polygon(
			_plate(Vector2(0, PLATE_Y)), plate_colour.lerp(Color.BLACK, StaffMapCounter.WALL_DARKEN)
		)
	var c := Vector2(0, PLATE_Y - rise)
	var top := _plate(c)
	draw_colored_polygon(top, plate_colour)
	var edge := top.slice(6, 8)
	edge.append_array(top.slice(0, 3))
	draw_polyline(edge, Color(1, 1, 1, StaffMapCounter.EDGE_ALPHA), 0.8)
	var area := Rect2(c - Vector2.ONE * (PLATE * 0.5 - 3.0), Vector2.ONE * (PLATE - 6.0))
	_draw_glyph(area, plate_colour.lerp(Color.BLACK, StaffMapCounter.ENGRAVE_DARKEN))
	if destroyed:
		var x := area.grow(1.5)
		draw_line(x.position, x.end, _palette.ui_alert, 1.6, true)
		draw_line(
			Vector2(x.position.x, x.end.y),
			Vector2(x.end.x, x.position.y),
			_palette.ui_alert,
			1.6,
			true
		)
	_draw_studs(base)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_studs(base: Color) -> void:
	var colour := (
		_palette.ui_alert
		if bar_fraction() < 0.5
		else StaffMapFormations.side_colour(_palette, owner_id)
	)
	var recess := base.lerp(Color.BLACK, 0.55)
	for i in STUDS:
		var at := Vector2((i - (STUDS - 1) * 0.5) * STUD_PITCH, STUD_Y)
		draw_circle(at, STUD_RADIUS + 0.4, base.lerp(Color.BLACK, 0.3))
		draw_circle(at, STUD_RADIUS, colour if i < lit_studs() else recess)


func _draw_glyph(a: Rect2, ink: Color) -> void:
	var c := a.get_center()
	match class_id:
		&"airfield":  # a plane seen from above
			draw_line(Vector2(c.x, a.position.y), Vector2(c.x, a.end.y), ink, GLYPH_WIDTH)
			draw_line(Vector2(a.position.x, c.y), Vector2(a.end.x, c.y), ink, GLYPH_WIDTH)
			draw_line(
				Vector2(c.x - a.size.x * 0.25, a.end.y),
				Vector2(c.x + a.size.x * 0.25, a.end.y),
				ink,
				GLYPH_WIDTH
			)
		&"depot":  # a crate with a lid line
			draw_rect(a.grow(-1.0), ink, false, GLYPH_WIDTH)
			draw_line(
				Vector2(a.position.x, c.y - 1.5), Vector2(a.end.x, c.y - 1.5), ink, GLYPH_WIDTH
			)
		&"c2":  # a pole with a pennant
			draw_line(
				Vector2(a.position.x + 1, a.position.y),
				Vector2(a.position.x + 1, a.end.y),
				ink,
				GLYPH_WIDTH
			)
			draw_colored_polygon(
				PackedVector2Array(
					[
						Vector2(a.position.x + 1, a.position.y),
						Vector2(a.end.x, a.position.y + a.size.y * 0.3),
						Vector2(a.position.x + 1, a.position.y + a.size.y * 0.6),
					]
				),
				ink
			)
		&"air_defence":  # a dome on a base line
			draw_arc(Vector2(c.x, a.end.y), a.size.x * 0.5, PI, TAU, 12, ink, GLYPH_WIDTH)
			draw_line(Vector2(a.position.x, a.end.y), Vector2(a.end.x, a.end.y), ink, GLYPH_WIDTH)
		_:
			draw_circle(c, 2.0, ink)
