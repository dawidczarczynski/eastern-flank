class_name StaffMapCounter
extends Control
## One formation counter of the staff map (TASK-092b, TASK-142; look: docs/design/operational_map
## "Counter and marker tokens", variant D): a thin hexagonal game tile in matte resin. The hexagon
## base is the same for both sides; on it stands a raised plate that carries the side by shape and
## colour (own = rectangle with a cut corner, enemy = diamond) with the engraved APP-6 glyph; the
## echelon mark is engraved above the plate, five strength studs sit under it, the designation
## to the right. Fixed screen size: the control's origin is the hex centre. `depth` (from the
## camera pitch, see depth_for_pitch) fades in the wall, the shadow and the vertical squash: 0 is a
## flat hexagon on a flat map. States: hover (lighter plate + rim), selected (amber brackets),
## low strength (darker plate, alert studs), moved (darker plate), in contact (ground ring),
## stack (up to 3 tiles + count badge). Ignores the mouse - picking is a 2D hit test in
## StaffMapCounters.

const TILE_SCALE := 1.35  # on-screen size of the whole tile
const RADIUS := 21.0  # hexagon base, flat-top; the same for both sides
const RECESS_RADIUS := 17.8
const WALL_DEPTH := 5.0
const SQUASH_TILTED := 0.8
const OWN_SIZE := Vector2(24, 16)
const ENEMY_SIZE := Vector2(23, 23)
const CUT := 3.6
const PLATE_Y := -2.5
const PLATE_RISE := 1.6
const SEGMENT_SIZE := Vector2(6, 3)
const SEGMENT_GAP := 1.5
const SEGMENT_SLANT := 1.5
const STUD_RADIUS := 2.3
const STUD_PITCH := 6.2
const STUD_Y := 12.5
const ECHELON_Y := -15.8
const GLYPH_WIDTH := 1.0
const LABEL_SIZE := 12
const BRACKET_PAD := 4.0
const BRACKET_ARM := 7.0
const BRACKET_STROKE := 2.0
const HOVER_LIGHTEN := 0.15
const LOW_DARKEN := 0.3
const MOVED_DARKEN := 0.4
const BASE_MUTED := 0.78
const BASE_VOID := 0.3
const PLATE_GREY := 0.2
const WALL_DARKEN := 0.5
const RECESS_DARKEN := 0.14
const BEVEL_ALPHA := 0.45
const ENGRAVE_DARKEN := 0.8
const EDGE_ALPHA := 0.35
const RING_RADIUS_X := 27.0
const RING_RADIUS_Y := 13.0
const RING_SEGMENTS := 28
const RING_FLAT_PAD := 5.0
const RING_WIDTH := 1.5
const SHADOW_SIZE := Vector2(76, 30)
const SHADOW_OFFSET := Vector2(6, 3)
const SHADOW_ALPHA := 0.45
const STACK_TILES := 3
const STACK_STEP := 8.0
const STACK_DARKEN := 0.25
const PULSE_SECONDS := 1.6
const PULSE_GROW := 26.0

static var _shadow_texture: GradientTexture2D

var formation_id: StringName
var formation_class: StringName
var relation := StaffMapFormations.OWN
var owner_id := 0
var designation := ""
var strength := 0
var max_strength := 0
var hovered := false:
	set(value):
		if hovered != value:
			hovered = value
			queue_redraw()
var selected := false:
	set(value):
		if selected != value:
			selected = value
			queue_redraw()
## The formation has an order (TASK-092d): a small order mark on the tile, own side only.
var has_order := false:
	set(value):
		if has_order != value:
			has_order = value
			queue_redraw()
## The formation moved this turn (TASK-092e): darker plate, own side only.
var moved := false:
	set(value):
		if moved != value:
			moved = value
			queue_redraw()
## The formation is in contact (TASK-092e): a dashed ui.alert ring on the ground.
var in_contact := false:
	set(value):
		if in_contact != value:
			in_contact = value
			queue_redraw()
## Country of origin of a joined ally (TASK-118): its ISO code shows as a small tag on the tile.
var country_tag := "":
	set(value):
		if country_tag != value:
			country_tag = value
			queue_redraw()
## Remaining seconds of the "just joined" pulse ring (0 = none).
var pulse_left := 0.0
## Formations in the stack this counter stands for (1 = no badge).
var stack_count := 1:
	set(value):
		if stack_count != value:
			stack_count = value
			queue_redraw()
## 0 = flat map (flat hexagon, no wall / shadow), 1 = tilted map; see depth_for_pitch.
var depth := 1.0:
	set(value):
		if not is_equal_approx(depth, value):
			depth = value
			queue_redraw()

var _palette: StaffMapPalette


## The tile depth for a camera pitch (degrees): 0 when flat, full from the default tilt up, in
## between while the camera tilts.
static func depth_for_pitch(pitch: float) -> float:
	return clampf(pitch / StaffMapCameraMath.PITCH_DEFAULT, 0.0, 1.0)


## Vertical squash of the tile for a depth (the tilted map foreshortens the hexagon).
static func squash(depth_factor: float) -> float:
	return lerpf(1.0, SQUASH_TILTED, depth_factor)


## Corners of a flat-top hexagon of `radius` around the origin (y down).
static func hex_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var a := TAU * i / 6.0
		points.append(Vector2(cos(a), sin(a)) * radius)
	return points


## Neutral base colour of a tile (the side colour, muted and darkened).
static func base_colour(palette: StaffMapPalette, side: Color) -> Color:
	return side.lerp(palette.ui_muted, BASE_MUTED).lerp(palette.map_void, BASE_VOID)


## Wall of a tile: the hull of its top and base outlines.
static func wall_hull(top: PackedVector2Array, base: PackedVector2Array) -> PackedVector2Array:
	var points := top.duplicate()
	points.append_array(base)
	return Geometry2D.convex_hull(points)


## True when `point` is inside the flat-top hexagon of `radius` (no vertical squash).
static func in_hex(point: Vector2, radius: float) -> bool:
	var h := radius * sqrt(3.0) * 0.5
	return absf(point.y) <= h and absf(point.x) <= radius - absf(point.y) / sqrt(3.0)


## Draws the hexagonal base (wall, top face, recessed field, bevel, hover rim) around the origin
## of the canvas' current transform, which must already carry the vertical squash.
static func draw_base(
	canvas: CanvasItem,
	palette: StaffMapPalette,
	radius: float,
	base: Color,
	depth_factor: float,
	rim: bool
) -> void:
	var hex := hex_points(radius)
	var wall := WALL_DEPTH * depth_factor / (squash(depth_factor) * TILE_SCALE)
	if wall > 0.05:
		var lowered := PackedVector2Array()
		for p in hex:
			lowered.append(p + Vector2(0, wall))
		canvas.draw_colored_polygon(wall_hull(hex, lowered), base.lerp(Color.BLACK, WALL_DARKEN))
	canvas.draw_colored_polygon(hex, base)
	canvas.draw_colored_polygon(
		hex_points(radius * RECESS_RADIUS / RADIUS), base.lerp(Color.BLACK, RECESS_DARKEN)
	)
	var inner := hex_points(radius - 1.0)
	for i in 6:
		var colour := Color(1, 1, 1, BEVEL_ALPHA) if i >= 3 else Color(0, 0, 0, BEVEL_ALPHA)
		canvas.draw_line(inner[i], inner[(i + 1) % 6], colour, 1.0)
	if rim:
		var closed := hex.duplicate()
		closed.append(hex[0])
		canvas.draw_polyline(closed, palette.ui_text, 1.2)


## The soft ground shadow of a tile (light from the upper left), scaled by `depth_factor`.
static func draw_shadow(canvas: CanvasItem, size: Vector2, depth_factor: float) -> void:
	if depth_factor <= 0.01:
		return
	if _shadow_texture == null:
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color(0, 0, 0, SHADOW_ALPHA), Color(0, 0, 0, 0)])
		_shadow_texture = GradientTexture2D.new()
		_shadow_texture.gradient = gradient
		_shadow_texture.fill = GradientTexture2D.FILL_RADIAL
		_shadow_texture.fill_from = Vector2(0.5, 0.5)
		_shadow_texture.fill_to = Vector2(1.0, 0.5)
		_shadow_texture.width = 64
		_shadow_texture.height = 32
	canvas.draw_texture_rect(
		_shadow_texture,
		Rect2(SHADOW_OFFSET - size * 0.5, size),
		false,
		Color(1, 1, 1, depth_factor)
	)


## Draws a 5-segment gauge with its top-left corner at `origin` (also used by the panel).
static func draw_segments(
	canvas: CanvasItem, origin: Vector2, lit: int, colour: Color, unlit: Color, scale := 1.0
) -> void:
	var w := SEGMENT_SIZE.x * scale
	var h := SEGMENT_SIZE.y * scale
	var slant := SEGMENT_SLANT * scale
	for i in StaffMapFormations.SEGMENTS:
		var x := origin.x + i * (w + SEGMENT_GAP * scale)
		var quad := PackedVector2Array(
			[
				Vector2(x + slant, origin.y),
				Vector2(x + w + slant, origin.y),
				Vector2(x + w, origin.y + h),
				Vector2(x, origin.y + h),
			]
		)
		canvas.draw_colored_polygon(quad, colour if i < lit else unlit)


## Width of the gauge drawn by draw_segments.
static func segments_width(scale := 1.0) -> float:
	var n := StaffMapFormations.SEGMENTS
	return (n * SEGMENT_SIZE.x + (n - 1) * SEGMENT_GAP + SEGMENT_SLANT) * scale


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	set_process(false)


## A short expanding amber ring: the formation has just appeared (TASK-118).
func start_pulse() -> void:
	pulse_left = PULSE_SECONDS
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	pulse_left = maxf(pulse_left - delta, 0.0)
	if pulse_left <= 0.0:
		set_process(false)
	queue_redraw()


func setup(formation: Formation, viewer_player: int, palette: StaffMapPalette) -> void:
	_palette = palette
	formation_id = formation.id
	name = String(formation.id)
	formation_class = formation.definition.formation_class
	designation = StaffMapFormations.designation(formation.display_name, formation.parent)
	set_viewer(formation.owner_id, viewer_player)
	set_strength(formation.strength(), formation.max_strength())


func set_viewer(p_owner_id: int, viewer_player: int) -> void:
	owner_id = p_owner_id
	relation = StaffMapFormations.viewer_relation(p_owner_id, viewer_player)
	queue_redraw()


func set_strength(value: int, maximum: int) -> void:
	strength = value
	max_strength = maximum
	queue_redraw()


func is_own() -> bool:
	return relation == StaffMapFormations.OWN


func lit_segments() -> int:
	return StaffMapFormations.lit_segments(strength, max_strength)


## Drawn as moved (own counters only: the other side's moves are not shown).
func is_moved() -> bool:
	return moved and is_own()


func is_low() -> bool:
	return StaffMapFormations.is_low(strength, max_strength)


## The side fill as drawn now (state included).
func fill_colour() -> Color:
	var colour := StaffMapFormations.side_colour(_palette, owner_id)
	if is_low():
		colour = colour.lerp(_palette.map_void, LOW_DARKEN)
	if is_moved():
		colour = colour.lerp(_palette.map_void, MOVED_DARKEN)
	if hovered:
		colour = colour.lerp(Color.WHITE, HOVER_LIGHTEN)
	return colour


func ink_colour() -> Color:
	return StaffMapFormations.side_ink(_palette, owner_id)


## Height the front tile is lifted by the tiles stacked under it.
func lift() -> float:
	return STACK_STEP * (mini(stack_count, STACK_TILES) - 1) * lerpf(0.5, 1.0, depth)


## True when `local` (relative to the hex centre) is on the tile, its wall or the stack under it.
func hits(local: Vector2) -> bool:
	var scale_y := squash(depth) * TILE_SCALE
	var wall := WALL_DEPTH * depth
	for shift in [wall, 0.0, -lift() * 0.5, -lift()]:
		if in_hex(Vector2(local.x / TILE_SCALE, (local.y - shift) / scale_y), RADIUS + 1.0):
			return true
	return false


## Bounds of tile, wall and studs around the hex centre (the selection brackets frame it).
func body_rect() -> Rect2:
	var h := RADIUS * sqrt(3.0) * 0.5 * squash(depth) * TILE_SCALE
	var top := -h - lift()
	return Rect2(
		-RADIUS * TILE_SCALE, top, RADIUS * TILE_SCALE * 2.0, h * 2.0 + WALL_DEPTH * depth + lift()
	)


## The top face of the front tile: bounding box of the squashed hexagon.
func _tile_rect() -> Rect2:
	var h := RADIUS * sqrt(3.0) * 0.5 * squash(depth) * TILE_SCALE
	return Rect2(-RADIUS * TILE_SCALE, -h - lift(), RADIUS * TILE_SCALE * 2.0, h * 2.0)


## The plate colour as drawn now: the side colour with the states, a little greyed.
func _plate_colour() -> Color:
	return fill_colour().lerp(Color(0.5, 0.5, 0.5), PLATE_GREY)


func _base_colour() -> Color:
	return base_colour(_palette, StaffMapFormations.side_colour(_palette, owner_id))


func _draw() -> void:
	if _palette == null:
		return
	draw_shadow(self, SHADOW_SIZE, depth)
	if in_contact:
		_draw_ring()
	var tiles := mini(stack_count, STACK_TILES)
	var step := STACK_STEP * lerpf(0.5, 1.0, depth)
	for i in tiles:
		var front := i == tiles - 1
		draw_set_transform(
			Vector2(0, -step * i), 0.0, Vector2(TILE_SCALE, TILE_SCALE * squash(depth))
		)
		_draw_tile(front)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tile := _tile_rect()
	_draw_designation(tile)
	if stack_count > 1:
		_draw_badge(tile)
	if country_tag != "":
		_draw_country_tag(tile)
	if pulse_left > 0.0:
		_draw_pulse(tile)
	if has_order and is_own():
		_draw_order_mark(tile)
	if selected:
		_draw_brackets(body_rect().grow(BRACKET_PAD))


## One tile in the squashed space (origin = hex centre). Back tiles of a stack show base and plate.
func _draw_tile(front: bool) -> void:
	var base := _base_colour()
	var plate_colour := _plate_colour()
	if not front:
		plate_colour = plate_colour.lerp(_palette.map_void, STACK_DARKEN)
	draw_base(self, _palette, RADIUS, base, depth, front and hovered)
	var rise := PLATE_RISE * depth / (squash(depth) * TILE_SCALE)
	var plate := _plate_polygon(Vector2(0, PLATE_Y))
	if rise > 0.05:
		draw_colored_polygon(plate, plate_colour.lerp(Color.BLACK, WALL_DARKEN))
	var top := _plate_polygon(Vector2(0, PLATE_Y - rise))
	draw_colored_polygon(top, plate_colour)
	var edge := _plate_top_edge(top)
	draw_polyline(edge, Color(1, 1, 1, EDGE_ALPHA), 0.8)
	if not front:
		return
	_draw_glyph(_glyph_rect(Vector2(0, PLATE_Y - rise)), plate_colour)
	_draw_echelon(base)
	_draw_studs(base)


func _plate_polygon(c: Vector2) -> PackedVector2Array:
	if is_own():
		var half := OWN_SIZE * 0.5
		return PackedVector2Array(
			[
				c + Vector2(-half.x, -half.y),
				c + Vector2(half.x - CUT, -half.y),
				c + Vector2(half.x, -half.y + CUT),
				c + Vector2(half.x, half.y),
				c + Vector2(-half.x, half.y),
			]
		)
	var half := ENEMY_SIZE * 0.5
	return PackedVector2Array(
		[
			c + Vector2(0, -half.y),
			c + Vector2(half.x, 0),
			c + Vector2(0, half.y),
			c + Vector2(-half.x, 0)
		]
	)


## The upper edges of a plate polygon (highlighted by the light from the upper left).
func _plate_top_edge(plate: PackedVector2Array) -> PackedVector2Array:
	if is_own():
		return PackedVector2Array([plate[4], plate[0], plate[1], plate[2]])
	return PackedVector2Array([plate[3], plate[0], plate[1]])


## The APP-6 icon area on the plate: its interior (own) or the rectangle inscribed in the diamond.
func _glyph_rect(c: Vector2) -> Rect2:
	if is_own():
		return Rect2(c - OWN_SIZE * 0.5, OWN_SIZE).grow(-1.0)
	return Rect2(c - Vector2(8.0, 5.6), Vector2(16.0, 11.2))


func _engraved_ink(plate_colour: Color) -> Color:
	return plate_colour.lerp(Color.BLACK, ENGRAVE_DARKEN)


func _draw_glyph(area: Rect2, plate_colour: Color) -> void:
	_draw_glyph_ink(area, _engraved_ink(plate_colour))


func _draw_glyph_ink(area: Rect2, ink: Color) -> void:
	match formation_class:
		&"mechanised":
			_draw_cross(area, ink)
			_draw_oval(area, ink, Vector2(0.44, 0.36))
		&"armoured":
			_draw_oval(area, ink, Vector2(0.62, 0.5))
		&"artillery":
			_draw_rockets(area, ink)
		_:
			_draw_cross(area, ink)


func _draw_cross(area: Rect2, ink: Color) -> void:
	var top_right := Vector2(area.end.x, area.position.y)
	var bottom_left := Vector2(area.position.x, area.end.y)
	if is_own():  # the cut corner: end the stroke on the chamfer
		top_right += Vector2(-CUT * 0.5, CUT * 0.5)
	draw_line(area.position, area.end, ink, GLYPH_WIDTH, true)
	draw_line(bottom_left, top_right, ink, GLYPH_WIDTH, true)


func _draw_oval(area: Rect2, ink: Color, fraction: Vector2) -> void:
	var c := area.get_center()
	var radius := area.size * fraction * 0.5
	var points := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		points.append(c + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_polyline(points, ink, GLYPH_WIDTH, true)


## Rocket artillery: the artillery dot with two rockets (arrows) beside it.
func _draw_rockets(area: Rect2, ink: Color) -> void:
	var c := area.get_center()
	var h := area.size.y * 0.32
	draw_circle(c + Vector2(0, h * 0.35), 1.6, ink)
	for dx in [-area.size.x * 0.22, area.size.x * 0.22]:
		var bottom := c + Vector2(dx, h)
		var tip := c + Vector2(dx, -h)
		draw_line(bottom, tip, ink, GLYPH_WIDTH, true)
		draw_polyline(
			PackedVector2Array([tip + Vector2(-1.5, 1.8), tip, tip + Vector2(1.5, 1.8)]),
			ink,
			GLYPH_WIDTH,
			true
		)


## Echelon mark (battalion = II) engraved on the base above the plate.
func _draw_echelon(base: Color) -> void:
	for dx in [-1.75, 1.75]:
		var a := Vector2(dx, ECHELON_Y - 1.5)
		var b := Vector2(dx, ECHELON_Y + 1.5)
		draw_line(a + Vector2(0, 0.7), b + Vector2(0, 0.7), Color(1, 1, 1, EDGE_ALPHA), 1.3)
		draw_line(a, b, base.lerp(Color.BLACK, 0.6), 1.3)


## Five strength studs on the base under the plate.
func _draw_studs(base: Color) -> void:
	var colour := StaffMapFormations.strength_colour(strength, max_strength, _palette)
	if is_low():
		colour = _palette.ui_alert
	var recess := base.lerp(Color.BLACK, 0.55)
	for i in StaffMapFormations.SEGMENTS:
		var at := Vector2((i - 2) * STUD_PITCH, STUD_Y)
		draw_circle(at, STUD_RADIUS + 0.4, base.lerp(Color.BLACK, 0.3))
		draw_circle(at, STUD_RADIUS, colour if i < lit_segments() else recess)


func _draw_designation(tile: Rect2) -> void:
	if designation == "":
		return
	var font := HudTheme.mono(600)
	var x := tile.end.x + 3.0
	var baseline := (font.get_ascent(LABEL_SIZE) - font.get_descent(LABEL_SIZE)) * 0.5
	var at := Vector2(x, baseline + tile.get_center().y)
	draw_string_outline(
		font, at, designation, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 5, _palette.label_halo
	)
	draw_string(font, at, designation, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, _palette.ui_text)


## Small country-of-origin tag at the tile's lower-left corner (TASK-118).
func _draw_country_tag(tile: Rect2) -> void:
	var font := HudTheme.mono(700)
	var size_px := 8
	var text_w := font.get_string_size(country_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var box := Rect2(Vector2(tile.position.x + 2.0, tile.end.y - 6.0), Vector2(text_w + 6.0, 11))
	draw_rect(box, _palette.label_halo)
	draw_rect(box, Color(_palette.ui_text, 0.7), false, 1.0)
	var baseline := box.position.y + (box.size.y + font.get_ascent(size_px)) * 0.5 - 1.5
	var at := Vector2(box.position.x + 3.0, baseline)
	draw_string(font, at, country_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, _palette.ui_text)


## An amber ring that grows and fades while the formation has just joined.
func _draw_pulse(tile: Rect2) -> void:
	var t := 1.0 - pulse_left / PULSE_SECONDS
	var ring := tile.grow(PULSE_GROW * t)
	draw_polyline(
		PackedVector2Array(
			[
				ring.position,
				Vector2(ring.end.x, ring.position.y),
				ring.end,
				Vector2(ring.position.x, ring.end.y),
				ring.position
			]
		),
		Color(_palette.ui_amber, 1.0 - t),
		2.0
	)


## Count badge at the tile's upper-right corner.
func _draw_badge(tile: Rect2) -> void:
	var font := HudTheme.mono(700)
	var text := str(stack_count)
	var size_px := 9
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var box := Rect2(
		Vector2(tile.end.x - 10.0, tile.position.y - 7.0), Vector2(maxf(text_w + 6.0, 12.0), 12)
	)
	draw_rect(box, _palette.label_halo)
	draw_rect(box, _palette.ui_amber, false, 1.0)
	var baseline := box.position.y + (box.size.y + font.get_ascent(size_px)) * 0.5 - 1.5
	var at := Vector2(box.position.x + (box.size.x - text_w) * 0.5, baseline)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, _palette.ui_amber)


## A small amber tab with an arrow at the tile's upper-left corner.
func _draw_order_mark(tile: Rect2) -> void:
	var box := Rect2(tile.position + Vector2(2.0, -6.0), Vector2(11, 11))
	draw_rect(box.grow(1.0), _palette.label_halo)
	draw_rect(box, _palette.ui_amber)
	var c := box.get_center()
	var ink := Color(0.05, 0.06, 0.05)
	draw_line(c + Vector2(-3.5, 0.0), c + Vector2(3.0, 0.0), ink, 1.5)
	draw_polyline(
		PackedVector2Array([c + Vector2(0.5, -3.0), c + Vector2(3.5, 0.0), c + Vector2(0.5, 3.0)]),
		ink,
		1.5
	)


## The dashed ui.alert ring of a counter in contact, an ellipse on the ground under the tile.
func _draw_ring() -> void:
	var radius := Vector2(RING_RADIUS_X, RING_RADIUS_Y) * TILE_SCALE
	var flat_y := RADIUS * 0.866 * TILE_SCALE + RING_FLAT_PAD
	radius.y = lerpf(flat_y, radius.y, depth)  # round when the map is flat
	for i in range(0, RING_SEGMENTS, 2):  # every other segment: a dashed ellipse
		var a0 := TAU * i / RING_SEGMENTS
		var a1 := TAU * (i + 1) / RING_SEGMENTS
		draw_line(
			Vector2(cos(a0), sin(a0)) * radius,
			Vector2(cos(a1), sin(a1)) * radius,
			_palette.ui_alert,
			RING_WIDTH
		)


func _draw_brackets(rect: Rect2) -> void:
	var corners := [
		[rect.position, Vector2(1, 0), Vector2(0, 1)],
		[Vector2(rect.end.x, rect.position.y), Vector2(-1, 0), Vector2(0, 1)],
		[rect.end, Vector2(-1, 0), Vector2(0, -1)],
		[Vector2(rect.position.x, rect.end.y), Vector2(1, 0), Vector2(0, -1)],
	]
	for corner in corners:
		var p: Vector2 = corner[0]
		var points := PackedVector2Array(
			[p + (corner[1] as Vector2) * BRACKET_ARM, p, p + (corner[2] as Vector2) * BRACKET_ARM]
		)
		draw_polyline(points, _palette.ui_amber, BRACKET_STROKE)
