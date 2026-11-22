class_name HudShapes
extends RefCounted
## Pure geometry of the HUD v3 look (docs/design/hud_v3/README.md "Shapes"): chamfered
## rectangles, hex badge, skewed segment, trapezoid, header tab, hatch stripes and tick ruler.
## All polygons are in local pixels with the origin at the top-left of their box and are
## wound clockwise (screen coordinates). No drawing here, so everything is unit-testable.

const BADGE_SIZE := Vector2(40, 36)
const HATCH_THIN_STRIPE := 2.0
const HATCH_THIN_PERIOD := 6.0
const HATCH_WIDE_STRIPE := 6.0
const HATCH_WIDE_PERIOD := 9.0
const TAB_SLANT := 10.0
const SEGMENT_SKEW := 3.0


## Rectangle `size` with the corners cut by c_tl / c_tr / c_br / c_bl pixels (0 = square
## corner). A chamfered corner contributes two vertices, a square one a single vertex, so the
## polygon has 4..8 vertices. Cuts are limited to half of the shorter side.
static func chamfer(
	size: Vector2, c_tl: float = 0.0, c_tr: float = 0.0, c_br: float = 0.0, c_bl: float = 0.0
) -> PackedVector2Array:
	var limit := minf(size.x, size.y) * 0.5
	var tl := clampf(c_tl, 0.0, limit)
	var tr := clampf(c_tr, 0.0, limit)
	var br := clampf(c_br, 0.0, limit)
	var bl := clampf(c_bl, 0.0, limit)
	var w := size.x
	var h := size.y
	var pts := PackedVector2Array()
	if tl > 0.0:
		pts.append(Vector2(0, tl))
		pts.append(Vector2(tl, 0))
	else:
		pts.append(Vector2(0, 0))
	if tr > 0.0:
		pts.append(Vector2(w - tr, 0))
		pts.append(Vector2(w, tr))
	else:
		pts.append(Vector2(w, 0))
	if br > 0.0:
		pts.append(Vector2(w, h - br))
		pts.append(Vector2(w - br, h))
	else:
		pts.append(Vector2(w, h))
	if bl > 0.0:
		pts.append(Vector2(bl, h))
		pts.append(Vector2(0, h - bl))
	else:
		pts.append(Vector2(0, h))
	return pts


## The same chamfered shape shrunk by `d` on every side (the inner fill of a framed panel):
## the box is inset and the cuts keep their size, as in the CSS two-element frame.
static func chamfer_inset(
	size: Vector2,
	d: float,
	c_tl: float = 0.0,
	c_tr: float = 0.0,
	c_br: float = 0.0,
	c_bl: float = 0.0
) -> PackedVector2Array:
	var inner := chamfer(size - Vector2(d, d) * 2.0, c_tl, c_tr, c_br, c_bl)
	for i in inner.size():
		inner[i] += Vector2(d, d)
	return inner


## Pointy hexagon "25% 0, 75% 0, 100% 50%, ..." filling `size` (the badge is 40 x 36).
static func hex_badge(size: Vector2 = BADGE_SIZE) -> PackedVector2Array:
	var w := size.x
	var h := size.y
	return PackedVector2Array(
		[
			Vector2(w * 0.25, 0),
			Vector2(w * 0.75, 0),
			Vector2(w, h * 0.5),
			Vector2(w * 0.75, h),
			Vector2(w * 0.25, h),
			Vector2(0, h * 0.5),
		]
	)


## HP bar segment leaning right: "3px 0, 100% 0, calc(100% - 3px) 100%, 0 100%".
static func skewed_segment(size: Vector2, skew: float = SEGMENT_SKEW) -> PackedVector2Array:
	return PackedVector2Array(
		[Vector2(skew, 0), Vector2(size.x, 0), Vector2(size.x - skew, size.y), Vector2(0, size.y)]
	)


## Trapezoid hanging from the top edge (turn bar): the bottom edge is `inset` narrower per side.
static func trapezoid(size: Vector2, inset: float = 26.0) -> PackedVector2Array:
	return PackedVector2Array(
		[Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x - inset, size.y), Vector2(inset, size.y)]
	)


## Header tab: "0 0, calc(100% - 10px) 0, 100% 100%, 0 100%" (slanted right edge).
static func header_tab(size: Vector2, slant: float = TAB_SLANT) -> PackedVector2Array:
	return PackedVector2Array(
		[Vector2(0, 0), Vector2(size.x - slant, 0), Vector2(size.x, size.y), Vector2(0, size.y)]
	)


## Stripes of `repeating-linear-gradient(135deg, C 0 stripe, transparent stripe period)` inside
## a `size` rectangle, as polygons already clipped to it. At 135 degrees the stripes run along
## (1, -1) and the gradient starts at the top-left corner; `stripe` and `period` are measured
## perpendicular to the stripes.
static func hatch(size: Vector2, stripe: float, period: float) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if size.x <= 0.0 or size.y <= 0.0 or stripe <= 0.0 or period <= 0.0:
		return result
	var rect := PackedVector2Array(
		[Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)]
	)
	var step := period * sqrt(2.0)  # distance between stripe starts along x + y
	var width := minf(stripe, period) * sqrt(2.0)
	var reach := maxf(size.x, size.y) + 1.0
	var s := 0.0
	while s < size.x + size.y:
		var band := PackedVector2Array(
			[
				Vector2(s + reach, -reach),
				Vector2(s + width + reach, -reach),
				Vector2(s + width - reach, reach),
				Vector2(s - reach, reach),
			]
		)
		for piece in Geometry2D.intersect_polygons(rect, band):
			if piece.size() >= 3:
				result.append(piece)
		s += step
	return result


## Hatch with thin stripes (2 px every 6 px).
static func hatch_thin(size: Vector2) -> Array[PackedVector2Array]:
	return hatch(size, HATCH_THIN_STRIPE, HATCH_THIN_PERIOD)


## Hatch with wide stripes (6 px every 9 px, active bars).
static func hatch_wide(size: Vector2) -> Array[PackedVector2Array]:
	return hatch(size, HATCH_WIDE_STRIPE, HATCH_WIDE_PERIOD)


## Vertical tick segments of a ruler as point pairs (top, bottom): `count` ticks `step` px apart
## starting at x = 0.5; every 10th is `tall`, every 5th `mid`, the others `short` px high.
static func ruler_ticks(
	count: int = 61, step: float = 5.0, tall: float = 8.0, mid: float = 5.0, short: float = 3.0
) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in count:
		var x := i * step + 0.5
		var height := short
		if i % 10 == 0:
			height = tall
		elif i % 5 == 0:
			height = mid
		pts.append(Vector2(x, 0))
		pts.append(Vector2(x, height))
	return pts


## Corner bracket L-shapes as a polyline (3 points) for corner `corner` (0 tl, 1 tr, 2 br, 3 bl)
## of a box `size`, arms `arm` long, drawn `outset` px outside the box.
static func corner_bracket(
	corner: int, size: Vector2, arm: float, outset: float = 0.0
) -> PackedVector2Array:
	var o := outset
	match corner:
		0:
			return PackedVector2Array(
				[Vector2(-o, -o + arm), Vector2(-o, -o), Vector2(-o + arm, -o)]
			)
		1:
			return PackedVector2Array(
				[
					Vector2(size.x + o - arm, -o),
					Vector2(size.x + o, -o),
					Vector2(size.x + o, -o + arm)
				]
			)
		2:
			return PackedVector2Array(
				[
					Vector2(size.x + o, size.y + o - arm),
					Vector2(size.x + o, size.y + o),
					Vector2(size.x + o - arm, size.y + o)
				]
			)
		_:
			return PackedVector2Array(
				[
					Vector2(-o + arm, size.y + o),
					Vector2(-o, size.y + o),
					Vector2(-o, size.y + o - arm)
				]
			)


## The "return" arrow (U+21B5) that no HUD font contains, as two open polylines in a `size` box:
## the shaft (down from the top right, then left) and the arrowhead at its left end.
static func enter_glyph(size: Vector2 = Vector2(9, 8)) -> Array[PackedVector2Array]:
	var x_left := 0.5
	var x_right := size.x - 0.5
	var y_mid := size.y * 0.62
	var head := minf(size.y * 0.3, x_right - x_left)
	var shaft := PackedVector2Array(
		[Vector2(x_right, 0.5), Vector2(x_right, y_mid), Vector2(x_left, y_mid)]
	)
	var arrow := PackedVector2Array(
		[
			Vector2(x_left + head, y_mid - head),
			Vector2(x_left, y_mid),
			Vector2(x_left + head, y_mid + head)
		]
	)
	return [shaft, arrow]


## APP-6-like unit class symbol (TASK-111 unit marker icon) as open polylines inside a `size` box
## (the icon frame, 15 x 11 px): infantry = cross, tank = oval, mechanised infantry / IFV = cross
## and oval, APC = cross and wheels (class_glyph_dots), recon = one slash, self-propelled artillery
## = oval and dot, MLRS = dot and two rockets, air defence = dome, ATGM = inverted V, engineer =
## bridge mark. Unknown classes draw nothing (the frame alone).
static func class_glyph(unit_class: StringName, size: Vector2) -> Array[PackedVector2Array]:
	var a := Rect2(Vector2.ONE * 1.5, size - Vector2.ONE * 3.0)  # inner area, off the frame
	var lines: Array[PackedVector2Array] = []
	match unit_class:
		&"infantry":
			lines.append_array(_cross(a))
		&"mech_infantry", &"ifv":
			lines.append_array(_cross(a))
			lines.append(_oval(a, Vector2(0.62, 0.56)))
		&"apc":
			var top := Rect2(a.position, Vector2(a.size.x, a.size.y * 0.72))
			lines.append_array(_cross(top))
		&"tank":
			lines.append(_oval(a, Vector2(0.8, 0.72)))
		&"recon":
			lines.append(
				PackedVector2Array([Vector2(a.position.x, a.end.y), Vector2(a.end.x, a.position.y)])
			)
		&"sp_artillery":
			lines.append(_oval(a, Vector2(0.8, 0.72)))
		&"mlrs":
			for dx: float in [-a.size.x * 0.3, a.size.x * 0.3]:
				var x := a.get_center().x + dx
				var tip := Vector2(x, a.position.y)
				lines.append(PackedVector2Array([Vector2(x, a.end.y), tip]))
				lines.append(
					PackedVector2Array([tip + Vector2(-1.5, 1.8), tip, tip + Vector2(1.5, 1.8)])
				)
		&"air_defense":
			var dome := PackedVector2Array()
			var c := Vector2(a.get_center().x, a.end.y)
			for i in 13:
				var t := PI + PI * i / 12.0
				dome.append(c + Vector2(cos(t) * a.size.x * 0.5, sin(t) * a.size.y * 0.75))
			lines.append(dome)
		&"atgm":
			lines.append(
				PackedVector2Array(
					[
						Vector2(a.position.x, a.end.y),
						Vector2(a.get_center().x, a.position.y),
						Vector2(a.end.x, a.end.y)
					]
				)
			)
		&"engineer":
			var y0 := a.position.y + a.size.y * 0.25
			var y1 := a.end.y - a.size.y * 0.15
			var x0 := a.position.x + a.size.x * 0.12
			var x1 := a.end.x - a.size.x * 0.12
			var xm := a.get_center().x
			lines.append(
				PackedVector2Array(
					[Vector2(x0, y1), Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1)]
				)
			)
			lines.append(PackedVector2Array([Vector2(xm, y0), Vector2(xm, y1)]))
	return lines


## Filled dots of class_glyph (centres, radius ~1.3 px): the artillery dot of sp_artillery and
## mlrs, the two wheels of apc.
static func class_glyph_dots(unit_class: StringName, size: Vector2) -> PackedVector2Array:
	var a := Rect2(Vector2.ONE * 1.5, size - Vector2.ONE * 3.0)
	match unit_class:
		&"sp_artillery":
			return PackedVector2Array([a.get_center()])
		&"mlrs":
			return PackedVector2Array([a.get_center() + Vector2(0, a.size.y * 0.15)])
		&"apc":
			var y := a.end.y - 1.0
			var c := a.get_center().x
			return PackedVector2Array([Vector2(c - 2.5, y), Vector2(c + 2.5, y)])
	return PackedVector2Array()


static func _cross(a: Rect2) -> Array[PackedVector2Array]:
	return [
		PackedVector2Array([a.position, a.end]),
		PackedVector2Array([Vector2(a.position.x, a.end.y), Vector2(a.end.x, a.position.y)])
	]


static func _oval(a: Rect2, fraction: Vector2) -> PackedVector2Array:
	var c := a.get_center()
	var radius := a.size * fraction * 0.5
	var points := PackedVector2Array()
	for i in 21:
		var t := TAU * i / 20.0
		points.append(c + Vector2(cos(t) * radius.x, sin(t) * radius.y))
	return points
