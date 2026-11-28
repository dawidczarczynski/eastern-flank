class_name WaterValidator
extends RefCounted
## The water ruleset of ADR 0034 decision 5 (TASK-223a): lists every error of the rivers, lakes and
## bridges of a WaterSample with its world position, so the rewrite starts from a measured list and
## later tasks are accepted by "zero violations". Pure and deterministic; distances and heights are
## metres (positions converted with MapScale).
##
## A violation is {rule: StringName, position: Vector2 (world XZ), value: float, limit: float}.
## Results come grouped by rule in RULES order, then along the reaches.

const RULES: Array[StringName] = [
	&"surface_rises",
	&"junction_step",
	&"lake_step",
	&"dry_bed",
	&"flooded_bank",
	&"shallow",
	&"width_jump",
	&"bridge_short",
	&"steep_water",
]

## The surface may rise at most this much from one vertex to the next downstream, metres.
const RISE_TOLERANCE_M := 0.05
## A tributary's level at a confluence may differ from the main river's by this much, metres.
const JUNCTION_STEP_M := 0.1
## Same for a river's end against the lake it flows into.
const LAKE_STEP_M := 0.1
## Ground above the surface inside the water, and below it just outside, tolerated, metres.
const LEVEL_TOLERANCE_M := 0.05
## Rivers at least this wide (metres) must be at least SHALLOW_M deep (metres) at their centre.
const SHALLOW_WIDTH_M := 6.0
const SHALLOW_M := 0.5
## Width may change by at most this factor within WIDTH_WINDOW_M along a reach.
const WIDTH_RATIO := 1.5
const WIDTH_WINDOW_M := 50.0
## Surface gradient limit (rise over run).
const MAX_GRADIENT := 0.02
## The bank is sampled this far beyond the water edge, metres.
const BANK_PROBE_M := 1.5
## A reach end this close to another reach is a junction; width is not checked within
## WIDTH_WINDOW_M of one. Metres.
const JOIN_M := 15.0
## A lake is looked for at a reach end and this far ahead of it, metres.
const LAKE_PROBE_M := 60.0


static func check(sample: WaterSample) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var junctions := _junctions(sample)
	for reach in sample.reaches:
		_surface(reach, out)
	for reach in sample.reaches:
		_ends(sample, reach, out)
	for reach in sample.reaches:
		_section(sample, reach, out)
	for reach in sample.reaches:
		_widths(reach, junctions, out)
	_bridges(sample, out)
	# Group by rule (stable: the order within a rule stays the order of discovery).
	var grouped: Array[Dictionary] = []
	for rule in RULES:
		for v in out:
			if v["rule"] == rule:
				grouped.append(v)
	return grouped


static func _add(
	out: Array[Dictionary], rule: StringName, at: Vector2, value: float, limit: float
) -> void:
	out.append({"rule": rule, "position": at, "value": value, "limit": limit})


static func _metres(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b) * MapScale.metres_per_unit


## surface_rises and steep_water along a reach.
static func _surface(reach: WaterSample.Reach, out: Array[Dictionary]) -> void:
	for i in range(1, reach.points.size()):
		var drop := reach.level[i - 1] - reach.level[i]
		if -drop > RISE_TOLERANCE_M:
			_add(out, &"surface_rises", reach.points[i], -drop, RISE_TOLERANCE_M)
		var run := _metres(reach.points[i - 1], reach.points[i])
		if run > 1e-6 and absf(drop) / run > MAX_GRADIENT:
			_add(out, &"steep_water", reach.points[i], absf(drop) / run, MAX_GRADIENT)


## junction_step (the end meets another reach) and lake_step (the end meets a lake).
static func _ends(sample: WaterSample, reach: WaterSample.Reach, out: Array[Dictionary]) -> void:
	var count := reach.points.size()
	if count < 2:
		return
	var end := reach.points[count - 1]
	var level := reach.level[count - 1]
	# A reach ending on another reach is a confluence even when a lake lies just ahead.
	var main := _nearest_other(sample, reach, end)
	if not main.is_empty() and main["distance_m"] <= JOIN_M:
		var step := absf(level - float(main["level"]))
		if step > JUNCTION_STEP_M:
			_add(out, &"junction_step", end, step, JUNCTION_STEP_M)
		return
	var lake := _lake_near(sample, end, (end - reach.points[count - 2]).normalized())
	if not is_nan(lake) and absf(level - lake) > LAKE_STEP_M:
		_add(out, &"lake_step", end, absf(level - lake), LAKE_STEP_M)


static func _lake_near(sample: WaterSample, end: Vector2, direction: Vector2) -> float:
	if not sample.lake_at.is_valid():
		return NAN
	var here: float = sample.lake_at.call(end)
	if not is_nan(here):
		return here
	return sample.lake_at.call(end + direction * MapScale.to_units(LAKE_PROBE_M))


## The point of any reach other than `own` nearest to `p`: {distance_m, level, width_m}, empty
## without one.
static func _nearest_other(sample: WaterSample, own: WaterSample.Reach, p: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for reach in sample.reaches:
		if reach == own:
			continue
		var near := _nearest_on(reach, p)
		if not near.is_empty() and near["distance_m"] < best_d:
			best_d = near["distance_m"]
			best = near
	return best


static func _nearest_on(reach: WaterSample.Reach, p: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for i in reach.points.size() - 1:
		var a := reach.points[i]
		var b := reach.points[i + 1]
		var ab := b - a
		var len2 := ab.length_squared()
		var t := 0.0 if len2 < 1e-12 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		var d := (a + ab * t).distance_to(p) * MapScale.metres_per_unit
		if d < best_d:
			best_d = d
			best = {
				"distance_m": d,
				"level": lerpf(reach.level[i], reach.level[i + 1], t),
				"width_m": lerpf(reach.width_m[i], reach.width_m[i + 1], t),
			}
	return best


## dry_bed, shallow and flooded_bank at every vertex of a reach.
static func _section(sample: WaterSample, reach: WaterSample.Reach, out: Array[Dictionary]) -> void:
	if not sample.ground.is_valid():
		return
	var count := reach.points.size()
	for i in count:
		var p := reach.points[i]
		var level := reach.level[i]
		var depth := level - float(sample.ground.call(p.x, p.y))
		if depth < -LEVEL_TOLERANCE_M:
			_add(out, &"dry_bed", p, -depth, LEVEL_TOLERANCE_M)
		elif reach.width_m[i] >= SHALLOW_WIDTH_M and depth < SHALLOW_M:
			_add(out, &"shallow", p, depth, SHALLOW_M)
		var before := reach.points[maxi(i - 1, 0)]
		var after := reach.points[mini(i + 1, count - 1)]
		var along := (after - before).normalized()
		if along == Vector2.ZERO:
			continue
		var side := Vector2(-along.y, along.x)
		var reach_units := MapScale.to_units(reach.width_m[i] * 0.5 + BANK_PROBE_M)
		for direction in [-1.0, 1.0]:
			var q: Vector2 = p + side * (reach_units * direction)
			if _in_other_water(sample, reach, q):
				continue  # the bank of a confluence or a lake shore: other water, not a bank
			var bank_depth := level - float(sample.ground.call(q.x, q.y))
			if bank_depth > LEVEL_TOLERANCE_M:
				_add(out, &"flooded_bank", q, bank_depth, LEVEL_TOLERANCE_M)


## Whether `q` lies in the water of a reach other than `own` or on a lake.
static func _in_other_water(sample: WaterSample, own: WaterSample.Reach, q: Vector2) -> bool:
	if sample.lake_at.is_valid() and not is_nan(float(sample.lake_at.call(q))):
		return true
	var near := _nearest_other(sample, own, q)
	return not near.is_empty() and near["distance_m"] <= float(near["width_m"]) * 0.5


## Reach ends that lie on another reach: confluences.
static func _junctions(sample: WaterSample) -> PackedVector2Array:
	var result := PackedVector2Array()
	for reach in sample.reaches:
		if reach.points.size() < 2:
			continue
		for end in [reach.points[0], reach.points[reach.points.size() - 1]]:
			var near := _nearest_other(sample, reach, end)
			if not near.is_empty() and near["distance_m"] <= JOIN_M:
				result.append(end)
	return result


## width_jump: a vertex whose width differs by more than WIDTH_RATIO from one within the
## WIDTH_WINDOW_M before it, away from junctions; one report per jump (the vertices within the
## window after a report are skipped).
static func _widths(
	reach: WaterSample.Reach, junctions: PackedVector2Array, out: Array[Dictionary]
) -> void:
	var count := reach.points.size()
	var along := PackedFloat32Array()
	along.resize(count)
	for i in range(1, count):
		along[i] = along[i - 1] + _metres(reach.points[i - 1], reach.points[i])
	var quiet_until := -INF
	for i in count:
		if along[i] <= quiet_until or _near_junction(reach.points[i], junctions):
			continue
		var j := i - 1
		while j >= 0 and along[i] - along[j] <= WIDTH_WINDOW_M:
			var hi := maxf(reach.width_m[i], reach.width_m[j])
			var lo := maxf(minf(reach.width_m[i], reach.width_m[j]), 1e-3)
			if hi / lo > WIDTH_RATIO:
				_add(out, &"width_jump", reach.points[i], hi / lo, WIDTH_RATIO)
				quiet_until = along[i] + WIDTH_WINDOW_M
				break
			j -= 1


static func _near_junction(p: Vector2, junctions: PackedVector2Array) -> bool:
	for j in junctions:
		if _metres(p, j) <= WIDTH_WINDOW_M:
			return true
	return false


## bridge_short: the deck is shorter than the water under it.
static func _bridges(sample: WaterSample, out: Array[Dictionary]) -> void:
	for bridge in sample.bridges:
		var at: Vector2 = bridge["position"]
		var best := {}
		var best_d := INF
		for reach in sample.reaches:
			var near := _nearest_on(reach, at)
			if not near.is_empty() and near["distance_m"] < best_d:
				best_d = near["distance_m"]
				best = near
		if best.is_empty() or best_d > float(best["width_m"]) * 0.5:
			continue  # no water under it
		var span := float(bridge["span_m"])
		if span < float(best["width_m"]):
			_add(out, &"bridge_short", at, span, float(best["width_m"]))
