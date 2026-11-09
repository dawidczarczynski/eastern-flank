class_name StaffMapInstallationMarker
extends Control
## One installation marker of the staff map (TASK-097a): a small chamfered plate in the side
## colour like the counters, an ink glyph by class (airfield, depot, command post, air defence)
## and a thin integrity bar below. A destroyed installation is a grey plate with a cross over the
## glyph and no bar. Fixed screen size, the control's origin is the plate centre. Ignores the
## mouse - picking is a 2D hit test in StaffMapInstallations.

const SIZE := Vector2(22, 22)
const CUT := 5.0
const BAR_SIZE := Vector2(22, 3)
const BAR_GAP := 2.0
const GLYPH_WIDTH := 1.5
const HOVER_LIGHTEN := 0.2
const DESTROYED_FILL := Color("#6d7076")
const DESTROYED_INK := Color("#2a2c30")

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


## True when `local` (relative to the plate centre) is on the plate or its bar.
func hits(local: Vector2) -> bool:
	return body_rect().grow(1.0).has_point(local)


## Plate and bar around the centre.
func body_rect() -> Rect2:
	var plate := Rect2(-SIZE * 0.5, SIZE)
	return plate.merge(Rect2(Vector2(-BAR_SIZE.x * 0.5, SIZE.y * 0.5 + BAR_GAP), BAR_SIZE))


func _plate(rect: Rect2) -> PackedVector2Array:
	var cut := CUT * rect.size.y / SIZE.y
	return PackedVector2Array(
		[
			rect.position + Vector2(cut, 0),
			Vector2(rect.end.x, rect.position.y),
			Vector2(rect.end.x, rect.end.y - cut),
			rect.end - Vector2(cut, 0),
			Vector2(rect.position.x, rect.end.y),
			Vector2(rect.position.x, rect.position.y + cut),
		]
	)


func _draw() -> void:
	if _palette == null:
		return
	var plate := Rect2(-SIZE * 0.5, SIZE)
	var outline := _palette.ui_text if hovered else _palette.label_halo
	draw_colored_polygon(_plate(plate.grow(1.0)), outline)
	draw_colored_polygon(_plate(plate), fill_colour())
	_draw_glyph(plate.grow(-5.0))
	if destroyed:
		var area := plate.grow(-3.0)
		draw_line(area.position, area.end, _palette.ui_alert, 2.0, true)
		draw_line(
			Vector2(area.position.x, area.end.y),
			Vector2(area.end.x, area.position.y),
			_palette.ui_alert,
			2.0,
			true
		)
	else:
		_draw_bar()


func _draw_bar() -> void:
	var rect := Rect2(Vector2(-BAR_SIZE.x * 0.5, SIZE.y * 0.5 + BAR_GAP), BAR_SIZE)
	draw_rect(rect.grow(1.0), _palette.label_halo)
	draw_rect(rect, _palette.map_void)
	var colour := _palette.ui_alert if bar_fraction() < 0.5 else ink_colour()
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * bar_fraction(), rect.size.y)), colour)


func _draw_glyph(a: Rect2) -> void:
	var ink := ink_colour()
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
