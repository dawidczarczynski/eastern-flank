class_name RadialRingGeometry
extends RefCounted
## Pure geometry of the HUD v3 radial ring (docs/design/hud_v3/README.md "04 Radial orders menu"):
## six trapezoid segments forming a pointy-top hex ring around the origin (screen pixels, y down),
## the dashed inner hex, the tick ring, the key numbers and the screen placement of the ring and
## its detail card. Shared by the target ring (TASK-089b) and the own-unit orders ring (TASK-082).
## Slots are 0-based, clockwise from north-east; the key shown for slot i is i + 1.

const SLOT_COUNT := 6
## Canvas of the ring (README: 400 x 400 SVG, origin in the centre).
const SIZE := 400.0
const INNER_RADIUS := 84.0
const OUTER_RADIUS := 160.0
const INNER_HEX_RADIUS := 75.0
const TICK_INNER := 168.0
const TICK_SHORT := 172.0
const TICK_LONG := 178.0
const TICK_STEP_DEG := 5
const TICK_LONG_EVERY_DEG := 30
const KEY_RADIUS := 190.0
## The detail card's left edge is this far right of the ring centre (or its right edge this far
## left when it flips).
const CARD_OFFSET := 206.0
## Minimum distance of the card from the viewport edge.
const EDGE := 8.0

## Segment polygons from the README, slot 0 (NE) to 5 (NW).
const _SEGMENTS := [
	[Vector2(3, -84), Vector2(3, -160), Vector2(137.1, -82.6), Vector2(71.2, -44.6)],
	[Vector2(74.2, -39.4), Vector2(140.1, -77.4), Vector2(140.1, 77.4), Vector2(74.2, 39.4)],
	[Vector2(71.2, 44.6), Vector2(137.1, 82.6), Vector2(3, 160), Vector2(3, 84)],
	[Vector2(-3, 84), Vector2(-3, 160), Vector2(-137.1, 82.6), Vector2(-71.2, 44.6)],
	[Vector2(-74.2, 39.4), Vector2(-140.1, 77.4), Vector2(-140.1, -77.4), Vector2(-74.2, -39.4)],
	[Vector2(-71.2, -44.6), Vector2(-137.1, -82.6), Vector2(-3, -160), Vector2(-3, -84)],
]
const _LABEL_CENTERS: Array[Vector2] = [
	Vector2(52.8, -91.5),
	Vector2(105.7, 0),
	Vector2(52.8, 91.5),
	Vector2(-52.8, 91.5),
	Vector2(-105.7, 0),
	Vector2(-52.8, -91.5),
]


## The polygon of `slot` (4 points, relative to the ring centre).
static func segment(slot: int) -> PackedVector2Array:
	return PackedVector2Array(_SEGMENTS[slot])


## Centre of the slot's icon + label block.
static func label_center(slot: int) -> Vector2:
	return _LABEL_CENTERS[slot]


## The slot under `point` (relative to the ring centre), or -1 in the gaps, the hole and outside.
static func slot_at(point: Vector2) -> int:
	for slot in SLOT_COUNT:
		if Geometry2D.is_point_in_polygon(point, segment(slot)):
			return slot
	return -1


## Vertices of the dashed inner hex (pointy top), clockwise from the top.
static func inner_hex(radius: float = INNER_HEX_RADIUS) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		points.append(Vector2.from_angle(deg_to_rad(-90.0 + 60.0 * i)) * radius)
	return points


## Tick ring as point pairs (inner, outer): every 5 degrees from east, clockwise; every 30 degrees
## a long one.
static func ticks() -> PackedVector2Array:
	var points := PackedVector2Array()
	for deg in range(0, 360, TICK_STEP_DEG):
		var direction := Vector2.from_angle(deg_to_rad(deg))
		var outer := TICK_LONG if deg % TICK_LONG_EVERY_DEG == 0 else TICK_SHORT
		points.append(direction * TICK_INNER)
		points.append(direction * outer)
	return points


## Centre of the key number of `slot`, on the slot's direction at KEY_RADIUS.
static func key_position(slot: int) -> Vector2:
	return _LABEL_CENTERS[slot].normalized() * KEY_RADIUS


## The ring centre for a unit projected to `projected`, kept fully inside `viewport`.
static func clamp_center(projected: Vector2, viewport: Vector2) -> Vector2:
	var half := SIZE * 0.5
	return Vector2(
		clampf(projected.x, half, maxf(half, viewport.x - half)),
		clampf(projected.y, half, maxf(half, viewport.y - half))
	)


## Top-left of a `card` sized detail card beside the ring at `center`: right of it, flipped to the
## left when it would leave the viewport; vertically centred on the ring and kept on screen.
static func card_position(center: Vector2, viewport: Vector2, card: Vector2) -> Vector2:
	var x := center.x + CARD_OFFSET
	if x + card.x > viewport.x - EDGE:
		x = center.x - CARD_OFFSET - card.x
	var y := clampf(center.y - card.y * 0.5, EDGE, maxf(EDGE, viewport.y - card.y - EDGE))
	return Vector2(x, y)
