class_name StaffMapCounter
extends Control
## One formation counter of the staff map (TASK-092b, look: docs/design/operational_map
## "Counters", style A "HUD"): own = rectangle 40 x 26 px with a cut corner, enemy = diamond
## 38 x 38 px, filled with the side colour; ink APP-6 branch glyph (mechanised infantry, armour,
## rocket artillery), echelon mark II above, designation to the right, 5 slanted strength segments
## below. Fixed screen size: the control's origin is the hex centre on screen, everything is
## drawn around it. States: hover (brighter), selected (2 px amber corner brackets), low strength
## (< 50 %: darker fill, ui.alert outline and gauge), stack (count badge). Ignores the mouse –
## picking is a 2D hit test in StaffMapCounters.

const OWN_SIZE := Vector2(40, 26)
const ENEMY_SIZE := Vector2(38, 38)
const CUT := 6.0
const SEGMENT_SIZE := Vector2(6, 3)
const SEGMENT_GAP := 1.5
const SEGMENT_SLANT := 1.5
const SEGMENT_TOP := 3.0  # gap between frame and gauge
const GLYPH_WIDTH := 1.5
const LABEL_SIZE := 10
const BRACKET_PAD := 4.0
const BRACKET_ARM := 7.0
const BRACKET_STROKE := 2.0
const HOVER_LIGHTEN := 0.2
const LOW_DARKEN := 0.3

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
## Formations in the stack this counter stands for (1 = no badge).
var stack_count := 1:
	set(value):
		if stack_count != value:
			stack_count = value
			queue_redraw()

var _palette: StaffMapPalette


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


func is_low() -> bool:
	return StaffMapFormations.is_low(strength, max_strength)


## The side fill as drawn now (state included).
func fill_colour() -> Color:
	var colour := StaffMapFormations.side_colour(_palette, owner_id)
	if is_low():
		colour = colour.lerp(_palette.map_void, LOW_DARKEN)
	if hovered:
		colour = colour.lerp(Color.WHITE, HOVER_LIGHTEN)
	return colour


func ink_colour() -> Color:
	return StaffMapFormations.side_ink(_palette, owner_id)


## True when `local` (relative to the hex centre) hits the frame or the gauge.
func hits(local: Vector2) -> bool:
	if is_own():
		var frame := Rect2(-OWN_SIZE * 0.5, OWN_SIZE)
		if frame.grow(1.0).has_point(local):
			return true
	else:
		var half := ENEMY_SIZE * 0.5
		if absf(local.x) / half.x + absf(local.y) / half.y <= 1.05:
			return true
	return _gauge_rect().grow(1.0).has_point(local)


## Bounds of frame and gauge around the hex centre (the selection brackets frame it).
func body_rect() -> Rect2:
	return _frame_rect().merge(_gauge_rect())


func _frame_rect() -> Rect2:
	var frame_size := OWN_SIZE if is_own() else ENEMY_SIZE
	return Rect2(-frame_size * 0.5, frame_size)


func _gauge_rect() -> Rect2:
	var width := segments_width()
	var top := _frame_rect().end.y + SEGMENT_TOP
	return Rect2(Vector2(-width * 0.5, top), Vector2(width, SEGMENT_SIZE.y))


func _draw() -> void:
	if _palette == null:
		return
	var frame := _frame_rect()
	var outline := _palette.ui_alert if is_low() else _palette.label_halo
	if hovered:
		outline = _palette.ui_text
	var shape := _frame_polygon(frame)
	draw_colored_polygon(_frame_polygon(frame.grow(1.0)), outline)
	draw_colored_polygon(shape, fill_colour())
	_draw_glyph(_glyph_rect(frame))
	_draw_echelon(frame)
	_draw_designation(frame)
	_draw_gauge()
	if stack_count > 1:
		_draw_badge(frame)
	if selected:
		_draw_brackets(body_rect().grow(BRACKET_PAD))


func _frame_polygon(rect: Rect2) -> PackedVector2Array:
	if is_own():
		var cut := CUT * rect.size.y / OWN_SIZE.y
		return PackedVector2Array(
			[
				rect.position,
				Vector2(rect.end.x - cut, rect.position.y),
				Vector2(rect.end.x, rect.position.y + cut),
				rect.end,
				Vector2(rect.position.x, rect.end.y),
			]
		)
	var c := rect.get_center()
	var half := rect.size * 0.5
	return PackedVector2Array(
		[
			c + Vector2(0, -half.y),
			c + Vector2(half.x, 0),
			c + Vector2(0, half.y),
			c + Vector2(-half.x, 0),
		]
	)


## The APP-6 icon area: the frame interior (own) or the rectangle inscribed in the diamond.
func _glyph_rect(frame: Rect2) -> Rect2:
	if is_own():
		return frame.grow(-1.0)
	return Rect2(frame.get_center() - Vector2(11, 7.5), Vector2(22, 15))


func _draw_glyph(area: Rect2) -> void:
	var ink := ink_colour()
	match formation_class:
		&"mechanised":
			_draw_cross(area, ink)
			_draw_oval(area, ink, Vector2(0.5, 0.42))
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
	draw_circle(c + Vector2(0, h * 0.35), 2.6, ink)
	for dx in [-area.size.x * 0.22, area.size.x * 0.22]:
		var bottom := c + Vector2(dx, h)
		var tip := c + Vector2(dx, -h)
		draw_line(bottom, tip, ink, GLYPH_WIDTH, true)
		draw_polyline(
			PackedVector2Array([tip + Vector2(-2.5, 3), tip, tip + Vector2(2.5, 3)]),
			ink,
			GLYPH_WIDTH,
			true
		)


## Echelon mark (battalion = II) above the frame.
func _draw_echelon(frame: Rect2) -> void:
	var top := frame.position.y - 2.0
	for dx in [-1.75, 1.75]:
		var a := Vector2(dx, top - 6.0)
		var b := Vector2(dx, top)
		draw_line(a, b, _palette.label_halo, 3.5)
	for dx in [-1.75, 1.75]:
		draw_line(Vector2(dx, top - 5.5), Vector2(dx, top - 0.5), _palette.ui_text, 1.5)


func _draw_designation(frame: Rect2) -> void:
	if designation == "":
		return
	var font := HudTheme.mono(600)
	var x := frame.end.x + (4.0 if is_own() else 2.0)
	var baseline := (font.get_ascent(LABEL_SIZE) - font.get_descent(LABEL_SIZE)) * 0.5
	var at := Vector2(x, baseline)
	draw_string_outline(
		font, at, designation, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 3, _palette.label_halo
	)
	draw_string(font, at, designation, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, _palette.ui_text)


func _draw_gauge() -> void:
	var rect := _gauge_rect()
	draw_rect(rect.grow(1.5), Color(_palette.label_halo, 0.85))
	var colour := StaffMapFormations.strength_colour(strength, max_strength, _palette)
	var unlit := Color(_palette.ui_muted, 0.35)
	draw_segments(self, rect.position, lit_segments(), colour, unlit)


## Count badge at the frame's top-right corner.
func _draw_badge(frame: Rect2) -> void:
	var font := HudTheme.mono(700)
	var text := str(stack_count)
	var size_px := 9
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var box := Rect2(
		Vector2(frame.end.x - 6.0, frame.position.y - 7.0), Vector2(maxf(text_w + 6.0, 12.0), 12)
	)
	draw_rect(box, _palette.label_halo)
	draw_rect(box, _palette.ui_amber, false, 1.0)
	var baseline := box.position.y + (box.size.y + font.get_ascent(size_px)) * 0.5 - 1.5
	var at := Vector2(box.position.x + (box.size.x - text_w) * 0.5, baseline)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, _palette.ui_amber)


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
