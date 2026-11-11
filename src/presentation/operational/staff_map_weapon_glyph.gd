class_name StaffMapWeaponGlyph
extends Control
## The silhouette glyph of a strike weapon class (TASK-141b): drawn polylines (no assets), nose
## along +x in a unit box of -1 .. 1. Used three ways: as the tile of a weapon row (26 px), as the
## 96 px stand-in of the detail card while a weapon has no 3D model, and (the static `draw`) as the
## head of a flying missile on the strike layer.

const GLYPH_SIZE := 26.0
const STROKE := 1.6

var glyph: StringName = &"missile":
	set(value):
		glyph = value
		queue_redraw()
var colour: Color = UiPalette.HUD_TEXT:
	set(value):
		colour = value
		queue_redraw()
var glyph_size := GLYPH_SIZE
var stroke := STROKE


func _init(glyph_id: StringName = &"missile", px := GLYPH_SIZE) -> void:
	glyph = glyph_id
	glyph_size = px
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_glyph(self, glyph, size / 2.0, glyph_size, colour, 0.0, stroke)


## The outlines of a glyph (unit box, nose +x); an unknown glyph is drawn as `missile`.
static func shapes(glyph_id: StringName) -> Array[PackedVector2Array]:
	var list: Array[PackedVector2Array] = []
	match glyph_id:
		&"ballistic":
			list.append(_mirrored([[1.0, 0.0], [0.55, 0.13], [-0.75, 0.13], [-1.0, 0.42]]))
			list.append(PackedVector2Array([Vector2(-1.0, 0.42), Vector2(-1.0, -0.42)]))
			list.append(PackedVector2Array([Vector2(0.15, 0.13), Vector2(0.15, -0.13)]))
		&"drone":
			list.append(_mirrored([[1.0, 0.0], [-0.75, 0.85], [-0.55, 0.0]]))
			list.append(PackedVector2Array([Vector2(-0.8, 0.3), Vector2(-0.8, -0.3)]))
		&"loitering":
			list.append(_mirrored([[0.9, 0.0], [0.6, 0.09], [-0.8, 0.09]]))
			list.append(_mirrored([[0.1, 0.09], [0.1, 0.8], [-0.2, 0.8], [-0.2, 0.09]], false))
			list.append(_mirrored([[-0.7, 0.09], [-0.9, 0.4], [-0.9, 0.09]], false))
		&"rocket":
			list.append(_mirrored([[1.0, 0.0], [0.55, 0.2], [-0.7, 0.2], [-1.0, 0.5]]))
			list.append(PackedVector2Array([Vector2(-1.0, 0.5), Vector2(-1.0, -0.5)]))
			list.append(PackedVector2Array([Vector2(-0.1, 0.2), Vector2(-0.1, -0.2)]))
		_:
			list.append(_mirrored([[1.0, 0.0], [0.45, 0.13], [-0.95, 0.13]]))
			list.append(
				_mirrored([[0.15, 0.13], [-0.35, 0.75], [-0.6, 0.75], [-0.45, 0.13]], false)
			)
			list.append(_mirrored([[-0.8, 0.13], [-1.0, 0.4], [-1.0, 0.13]], false))
	return list


## Draws `glyph_id` centred on `at`, `px` tall/wide, turned by `angle` (radians, 0 = nose right).
## The canvas transform is reset afterwards.
static func draw_glyph(
	canvas: CanvasItem,
	glyph_id: StringName,
	at: Vector2,
	px: float,
	colour: Color,
	angle := 0.0,
	width := STROKE
) -> void:
	var scale := px / 2.0
	canvas.draw_set_transform(at, angle, Vector2(scale, scale))
	for line in shapes(glyph_id):
		canvas.draw_polyline(line, colour, width / scale, true)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Upper outline `half` ([[x, y], ...] with y >= 0) mirrored to the lower side: one closed outline
## (or, with `closed` false, the same shape as two strokes joined at the first and last point).
static func _mirrored(half: Array, closed := true) -> PackedVector2Array:
	var line := PackedVector2Array()
	for pair: Array in half:
		line.append(Vector2(pair[0], -pair[1]))
	for i in range(half.size() - 1, -1, -1):
		line.append(Vector2(half[i][0], half[i][1]))
	if closed:
		line.append(line[0])
	return line
