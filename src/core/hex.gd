class_name Hex
extends RefCounted
## Hex grid utilities: axial coordinates (q, r) as Vector2i, "pointy-top" layout.
## Reference: https://www.redblobgames.com/grids/hexagons/

const SQRT3 := 1.7320508075688772
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]

## Offset of Hex.line's points (q, r; s = -q - r gets the rest) that breaks ties between hexes.
const LINE_NUDGE := Vector2(1e-6, 2e-6)


static func neighbors(c: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in DIRECTIONS:
		result.append(c + d)
	return result


@warning_ignore("integer_division")
static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


## Hexes on the straight line from `a` to `b`, both included, in order (cube lerp at
## distance + 1 evenly spaced points). Points exactly between two hexes are nudged by a fixed
## LINE_NUDGE, so the result is deterministic; line(b, a) may differ from line(a, b) reversed
## at such ties (LineOfSight orders its endpoints).
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var n := distance(a, b)
	var result: Array[Vector2i] = [a]
	if n == 0:
		return result
	var aq := a.x + LINE_NUDGE.x
	var ar := a.y + LINE_NUDGE.y
	var bq := b.x + LINE_NUDGE.x
	var br := b.y + LINE_NUDGE.y
	for i in range(1, n):
		var t := float(i) / n
		result.append(_round(lerpf(aq, bq, t), lerpf(ar, br, t)))
	result.append(b)
	return result


## Tile center in world space (XZ plane). `size` = distance from center to a corner.
static func to_world(c: Vector2i, size: float) -> Vector3:
	var x := size * SQRT3 * (c.x + c.y / 2.0)
	var z := size * 1.5 * c.y
	return Vector3(x, 0.0, z)


static func from_world(p: Vector3, size: float) -> Vector2i:
	var q := (SQRT3 / 3.0 * p.x - p.z / 3.0) / size
	var r := (2.0 / 3.0 * p.z) / size
	return _round(q, r)


static func _round(qf: float, rf: float) -> Vector2i:
	var sf := -qf - rf
	var q := roundf(qf)
	var r := roundf(rf)
	var s := roundf(sf)
	var dq := absf(q - qf)
	var dr := absf(r - rf)
	var ds := absf(s - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(int(q), int(r))
