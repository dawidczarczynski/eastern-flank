class_name WeaponBlueprint
extends RefCounted
## Blueprint-style side drawing of a strike weapon (TASK-146, docs/design/operational_map/
## weapon_blueprint.html variant A): faint grid, dashed centre line, outline + inner detail in one
## colour, dimension lines with the real length, diameter and (winged weapons) wingspan. Pure
## drawing helper: no nodes, the caller redraws only when the weapon or the size changes.
##
## Dimensions in metres (length, body diameter, wingspan; span 0 = no wings). Sources: manufacturer
## and public references. [ASSUMPTION] = approximate, to be confirmed: Kinzhal (Iskander-derived
## airframe), Kh-101 span, JASSM-ER span (some sources 2.7), PrSM, Homar-K rocket, Warmate.

enum Kind { BALLISTIC, CRUISE, DELTA, TUBE, ROCKET }

const TABLE := {
	&"iskander_m": {"kind": Kind.BALLISTIC, "length": 7.2, "diameter": 0.92, "span": 0.0},
	# [ASSUMPTION]
	&"kinzhal": {"kind": Kind.BALLISTIC, "length": 8.0, "diameter": 1.0, "span": 0.0},
	&"kalibr": {"kind": Kind.CRUISE, "length": 6.2, "diameter": 0.53, "span": 3.3},
	# [ASSUMPTION span]
	&"kh101": {"kind": Kind.CRUISE, "length": 7.45, "diameter": 0.74, "span": 3.0},
	&"geran_2": {"kind": Kind.DELTA, "length": 3.5, "diameter": 0.5, "span": 2.5},
	# [ASSUMPTION]
	&"jassm_er": {"kind": Kind.CRUISE, "length": 4.27, "diameter": 0.55, "span": 2.4},
	&"atacms": {"kind": Kind.BALLISTIC, "length": 3.96, "diameter": 0.61, "span": 0.0},
	# [ASSUMPTION]
	&"prsm": {"kind": Kind.BALLISTIC, "length": 4.0, "diameter": 0.43, "span": 0.0},
	# [ASSUMPTION]
	&"homar_k": {"kind": Kind.ROCKET, "length": 4.0, "diameter": 0.24, "span": 0.0},
	# [ASSUMPTION]
	&"warmate": {"kind": Kind.TUBE, "length": 1.1, "diameter": 0.09, "span": 1.6},
	&"storm_shadow": {"kind": Kind.CRUISE, "length": 5.1, "diameter": 0.48, "span": 3.0},
	&"tomahawk": {"kind": Kind.CRUISE, "length": 5.56, "diameter": 0.52, "span": 2.67},
}

const PAD := 12.0
const GRID := 12.0
const LABEL_SIZE := 10
const RIGHT_LABEL_W := 72.0
const BELOW_H := 22.0
const ABOVE_H := 34.0
const DETAIL_ALPHA := 0.6
const FILL_ALPHA := 0.1


static func has_blueprint(id: StringName) -> bool:
	return TABLE.has(id)


## {length_m, diameter_m, span_m}; empty for an unknown id.
static func dimensions(id: StringName) -> Dictionary:
	if not TABLE.has(id):
		return {}
	var row: Dictionary = TABLE[id]
	return {
		"length_m": row["length"],
		"diameter_m": row["diameter"],
		"span_m": row["span"],
	}


## ["7.2 m", "Ø 0.92 m"] (+ "span 3.3 m" for a winged weapon); empty for an unknown id.
static func labels(id: StringName) -> Array[String]:
	var result: Array[String] = []
	if not TABLE.has(id):
		return result
	var dims := dimensions(id)
	result.append("%s m" % _num(dims["length_m"]))
	result.append("Ø %s m" % _num(dims["diameter_m"]))
	if (dims["span_m"] as float) > 0.0:
		result.append("span %s m" % _num(dims["span_m"]))
	return result


static func _num(value: float) -> String:
	var text := "%.2f" % value
	while text.ends_with("0"):
		text = text.left(-1)
	return text.trim_suffix(".")


## Draws the blueprint of `means_id` filling `rect` (canvas coordinates): `color` is the outline,
## detail and fill colour, the grid and dimensions use the muted / text HUD colours.
static func draw(canvas: CanvasItem, means_id: StringName, rect: Rect2, color: Color) -> void:
	if not TABLE.has(means_id):
		return
	_draw_grid(canvas, rect)
	var row: Dictionary = TABLE[means_id]
	var length: float = row["length"]
	var diameter: float = row["diameter"]
	var span: float = row["span"]
	var kind: int = row["kind"]
	var half := maxf(maxf(span / 2.0, diameter / 2.0), _fin_half(kind, diameter))
	var top := rect.position.y + PAD + (ABOVE_H if span > 0.0 else 0.0)
	var bottom := rect.end.y - PAD - BELOW_H
	var area_w := rect.size.x - 2.0 * PAD - RIGHT_LABEL_W
	var area_h := bottom - top
	var px := minf(area_w / length, area_h / (2.0 * half))
	var origin := Vector2(rect.position.x + PAD + (area_w - length * px) / 2.0, top + area_h / 2.0)
	var muted := UiPalette.HUD_MUTED
	var cy := origin.y
	_dashed(
		canvas,
		Vector2(origin.x - 14.0, cy),
		Vector2(origin.x + length * px + 14.0, cy),
		Color(muted, 0.45)
	)
	var shapes := _shapes(kind, length, diameter, span)
	var fill := Color(color, FILL_ALPHA)
	for poly: PackedVector2Array in shapes["solid"]:
		var pts := _to_px(poly, origin, px)
		canvas.draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		canvas.draw_polyline(pts, color, 1.4, true)
	for line: PackedVector2Array in shapes["detail"]:
		canvas.draw_polyline(_to_px(line, origin, px), Color(color, DETAIL_ALPHA), 1.0, true)
	_draw_dimensions(canvas, means_id, origin, px, length, diameter, span)


static func _fin_half(kind: int, diameter: float) -> float:
	match kind:
		Kind.BALLISTIC:
			return diameter * 1.0
		Kind.CRUISE:
			return diameter * 1.3
		_:
			return 0.0


static func _to_px(poly: PackedVector2Array, origin: Vector2, px: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in poly:
		result.append(origin + p * px)
	return result


static func _draw_grid(canvas: CanvasItem, rect: Rect2) -> void:
	var muted := UiPalette.HUD_MUTED
	var index := 0
	var x := rect.position.x
	while x <= rect.end.x:
		var a := 0.18 if index % 5 == 0 else 0.09
		canvas.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(muted, a), 1.0)
		x += GRID
		index += 1
	index = 0
	var y := rect.position.y
	while y <= rect.end.y:
		var a := 0.18 if index % 5 == 0 else 0.09
		canvas.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(muted, a), 1.0)
		y += GRID
		index += 1


static func _dashed(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color) -> void:
	var x := from.x
	while x < to.x:
		canvas.draw_line(Vector2(x, from.y), Vector2(minf(x + 6.0, to.x), to.y), color, 1.0)
		x += 10.0


static func _draw_dimensions(
	canvas: CanvasItem,
	means_id: StringName,
	origin: Vector2,
	px: float,
	length: float,
	diameter: float,
	span: float
) -> void:
	var line := Color(UiPalette.HUD_TEXT, 0.7)
	var text := UiPalette.HUD_TEXT
	var font := HudTheme.mono(500, 0)
	var texts := labels(means_id)
	var half := maxf(maxf(span / 2.0, diameter / 2.0), 0.0)
	# Length, below the lowest part of the drawing.
	var by := origin.y + half * px + 12.0
	if _fin_half(int(TABLE[means_id]["kind"]), diameter) > half:
		by = origin.y + _fin_half(int(TABLE[means_id]["kind"]), diameter) * px + 12.0
	var x0 := origin.x
	var x1 := origin.x + length * px
	canvas.draw_line(Vector2(x0, by), Vector2(x1, by), line, 1.0)
	for x in [x0, x1]:
		canvas.draw_line(Vector2(x, by - 4.0), Vector2(x, by + 4.0), Color(text, 1.0), 1.0)
	canvas.draw_string(
		font,
		Vector2(x0, by + 14.0),
		texts[0],
		HORIZONTAL_ALIGNMENT_CENTER,
		x1 - x0,
		LABEL_SIZE,
		text
	)
	# Diameter, right of the nose.
	var dx := x1 + 24.0
	var r := diameter / 2.0 * px
	canvas.draw_line(
		Vector2(x1 - 0.1 * px, origin.y - r), Vector2(dx - 4.0, origin.y - r), Color(line, 0.3), 1.0
	)
	canvas.draw_line(
		Vector2(x1 - 0.1 * px, origin.y + r), Vector2(dx - 4.0, origin.y + r), Color(line, 0.3), 1.0
	)
	canvas.draw_line(Vector2(dx, origin.y - r), Vector2(dx, origin.y + r), line, 1.0)
	for yy in [origin.y - r, origin.y + r]:
		canvas.draw_line(Vector2(dx - 4.0, yy), Vector2(dx + 4.0, yy), Color(text, 1.0), 1.0)
	canvas.draw_string(
		font,
		Vector2(dx + 8.0, origin.y + 3.5),
		texts[1],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		LABEL_SIZE,
		text
	)
	# Wingspan, above the wings.
	if span > 0.0:
		var sy := origin.y - span / 2.0 * px - 8.0
		canvas.draw_string(
			font,
			Vector2(x0, sy - 2.0),
			texts[2],
			HORIZONTAL_ALIGNMENT_CENTER,
			x1 - x0,
			LABEL_SIZE,
			text
		)


## Silhouette parts in metres, nose to the right, centred on y = 0, y down:
## {"solid": [polygons], "detail": [polylines]}.
static func _shapes(kind: int, length: float, diameter: float, span: float) -> Dictionary:
	var r := diameter / 2.0
	var solid: Array[PackedVector2Array] = []
	var detail: Array[PackedVector2Array] = []
	match kind:
		Kind.BALLISTIC:
			var shoulder := length * 0.72
			solid.append(_body(length, r, shoulder))
			solid.append_array(_pair([[0.0, -r], [-r * 0.5, -r * 2.0], [length * 0.13, -r]]))
			detail.append(PackedVector2Array([Vector2(shoulder, -r), Vector2(shoulder, r)]))
			detail.append(
				PackedVector2Array([Vector2(length * 0.08, -r), Vector2(length * 0.08, r)])
			)
		Kind.CRUISE:
			solid.append(_body(length, r, length * 0.82))
			var wing_x := length * 0.4
			var half_span := span / 2.0
			(
				solid
				. append_array(
					_pair(
						[
							[wing_x - length * 0.1, -r],
							[wing_x + length * 0.04, -half_span],
							[wing_x + length * 0.1, -half_span],
							[wing_x + length * 0.1, -r],
						]
					)
				)
			)
			(
				solid
				. append_array(
					_pair(
						[
							[0.0, -r],
							[0.0, -r * 2.2],
							[length * 0.1, -r * 2.2],
							[length * 0.17, -r],
						]
					)
				)
			)
			(
				detail
				. append(
					PackedVector2Array(
						[
							Vector2(length * 0.5, r),
							Vector2(length * 0.57, r * 1.45),
							Vector2(length * 0.66, r),
						]
					)
				)
			)
		Kind.DELTA:
			solid.append(_body(length, r, length * 0.8))
			(
				solid
				. append_array(
					_pair(
						[
							[length * 0.06, -r * 0.4],
							[length * 0.66, -r * 0.4],
							[length * 0.06, -span / 2.0],
						]
					)
				)
			)
			solid.append_array(
				_pair([[0.0, -r * 0.4], [-length * 0.07, -r * 1.0], [length * 0.1, -r * 0.4]])
			)
			detail.append(PackedVector2Array([Vector2(0.0, 0.0), Vector2(-length * 0.1, 0.0)]))
		Kind.TUBE:
			solid.append(_body(length, r, length * 0.85))
			var wing_x := length * 0.4
			solid.append_array(
				_pair(
					[
						[wing_x, -r],
						[wing_x, -span / 2.0],
						[wing_x + length * 0.12, -span / 2.0],
						[wing_x + length * 0.12, -r]
					]
				)
			)
			solid.append_array(
				_pair([[0.0, -r], [0.0, -r * 3.0], [length * 0.1, -r * 3.0], [length * 0.1, -r]])
			)
			detail.append(PackedVector2Array([Vector2(length * 0.2, -r), Vector2(length * 0.2, r)]))
		Kind.ROCKET:
			solid.append(_body(length, r, length * 0.9))
			solid.append_array(_pair([[0.0, -r], [-length * 0.04, -r * 2.2], [length * 0.11, -r]]))
			detail.append(
				PackedVector2Array([Vector2(length * 0.65, -r), Vector2(length * 0.65, r)])
			)
	return {"solid": solid, "detail": detail}


## Cylinder from the tail (x = 0) to `shoulder`, then a curved nose to x = `length`.
static func _body(length: float, r: float, shoulder: float) -> PackedVector2Array:
	var upper: Array[Vector2] = [Vector2(0.0, -r), Vector2(shoulder, -r)]
	var steps := 6
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var x := shoulder + (length - shoulder) * t
		var y := -r * sqrt(maxf(0.0, 1.0 - t * t))
		upper.append(Vector2(x, y))
	var poly := PackedVector2Array(upper)
	for i in range(upper.size() - 2, -1, -1):
		poly.append(Vector2(upper[i].x, -upper[i].y))
	return poly


## The upper half-points [[x, y], ...] (y <= 0) as one polygon, plus its mirror image below.
static func _pair(points: Array) -> Array[PackedVector2Array]:
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	for p: Array in points:
		upper.append(Vector2(p[0], p[1]))
		lower.append(Vector2(p[0], -p[1]))
	return [upper, lower]
