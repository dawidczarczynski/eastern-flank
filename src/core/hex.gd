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


static func neighbors(c: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in DIRECTIONS:
		result.append(c + d)
	return result


@warning_ignore("integer_division")
static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


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
