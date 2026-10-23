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
