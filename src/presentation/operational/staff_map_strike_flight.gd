class_name StaffMapStrikeFlight
extends RefCounted
## Pure geometry and timing of one missile's trace on the staff map (TASK-141b): the point of its
## arc at time t (apex height from the weapon's `arc_height`, drone wobble), the stagger of the
## missiles of a salvo, which missiles of a big salvo are drawn, and where an intercepted missile
## stops. Nothing is drawn here; StaffMapStrikeLayer draws what these return.

## Delay between two missiles of one salvo (s).
const STAGGER_SECONDS := 0.08
## Missiles drawn per strike; the rest is shown as a "+n" label.
const MAX_DRAWN := 6
## Where an intercepted missile stops when no air-defence site is known (share of the path).
const STOP_FRACTION := 0.72
## The apex of an arc never rises more than this many pixels above the chord.
const MAX_APEX_PX := 280.0
## Peak sideways wobble (px) at wobble = 1.
const WOBBLE_PX := 9.0
const WOBBLE_CYCLES := 3.0


## Launch delay of missile `index` of a salvo.
static func stagger(index: int) -> float:
	return index * STAGGER_SECONDS


## The indices (into the salvo) of the missiles that are drawn: all up to MAX_DRAWN, else evenly
## spread over the salvo so the outcomes stay represented.
static func drawn_indices(count: int) -> Array[int]:
	var list: Array[int] = []
	if count <= MAX_DRAWN:
		for i in maxi(count, 0):
			list.append(i)
		return list
	for i in MAX_DRAWN:
		list.append(i * count / MAX_DRAWN)
	return list


## Missiles of a salvo that are not drawn.
static func hidden_count(count: int) -> int:
	return maxi(count - MAX_DRAWN, 0)


## The apex height (px above the chord midpoint) of a flight of `length` px with `arc_height` (a
## fraction of the length), scaled by `bow` (the missile's own variation), capped.
static func apex(length: float, arc_height: float, bow := 1.0) -> float:
	return minf(length * arc_height * bow, MAX_APEX_PX)


## The point of the flight at `t` (0 .. 1): a quadratic curve from `from` to `to` bowed upward on
## screen so that its apex at t = 0.5 is `apex()`, bent sideways by `lateral` (fraction of the
## length) and, for a drone, wobbling sideways (`wobble` 0 .. 1, phase from `seed_value`).
static func point(
	from: Vector2,
	to: Vector2,
	t: float,
	arc_height: float,
	bow := 1.0,
	lateral := 0.0,
	wobble := 0.0,
	seed_value := 0
) -> Vector2:
	t = clampf(t, 0.0, 1.0)
	var length := from.distance_to(to)
	var chord := to - from
	var side := chord.orthogonal().normalized() * length * lateral if length > 0.0 else Vector2.ZERO
	# A quadratic Bezier peaks at half its control offset, hence the factor 2.
	var control := (from + to) * 0.5 + Vector2(0.0, -2.0 * apex(length, arc_height, bow)) + side
	var at := from.lerp(control, t).lerp(control.lerp(to, t), t)
	if wobble > 0.0 and length > 0.0:
		var phase := StaffMapStrikeTrail.unit(seed_value) * TAU
		var swing := sin(t * TAU * WOBBLE_CYCLES + phase) * sin(t * PI) * wobble * WOBBLE_PX
		at += chord.orthogonal().normalized() * swing
	return at


## The first `progress` of the flight as `segments` + 1 points at most.
static func points(
	from: Vector2,
	to: Vector2,
	segments: int,
	progress: float,
	arc_height: float,
	bow := 1.0,
	lateral := 0.0,
	wobble := 0.0,
	seed_value := 0
) -> PackedVector2Array:
	var result := PackedVector2Array()
	var last := clampi(roundi(segments * clampf(progress, 0.0, 1.0)), 0, segments)
	for i in last + 1:
		result.append(
			point(from, to, float(i) / segments, arc_height, bow, lateral, wobble, seed_value)
		)
	return result


## Where an intercepted missile ends: at the air-defence `site` (screen position, Vector2.INF when
## unknown) or STOP_FRACTION of the way from `from` to `to`.
static func stop_point(from: Vector2, to: Vector2, site := Vector2.INF) -> Vector2:
	if site.is_finite():
		return site
	return from.lerp(to, STOP_FRACTION)


## The direction (unit vector) of the flight at `t`, from two close points.
static func heading(
	from: Vector2,
	to: Vector2,
	t: float,
	arc_height: float,
	bow := 1.0,
	lateral := 0.0,
	wobble := 0.0,
	seed_value := 0
) -> Vector2:
	var before := point(from, to, t - 0.02, arc_height, bow, lateral, wobble, seed_value)
	var after := point(from, to, t + 0.02, arc_height, bow, lateral, wobble, seed_value)
	var direction := after - before
	return direction.normalized() if direction.length() > 0.001 else Vector2.RIGHT
