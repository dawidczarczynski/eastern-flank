extends RefCounted
## Measurements of a normalised reference GLB (TASK-180): section profiles along the length and
## the constants a procedural model starts with (DECK_H, ROOF_H, TURRET_X, TURRET_RING_R,
## TRUNNION, UPPER_HW, LOWER_HW, road wheels, ...), each with a confidence 0..1. Pure geometry on
## a triangle mesh (positions in metres after tools/glb_reference.gd normalised it: front = +X,
## ground y = 0, centred), no nodes: tools/render_glb.gd feeds it and writes measurements.json.
##
## Output frame = the model files' frame (src/presentation/models/*.gd): `x` in metres from the
## hull nose (0) rearwards, `h` above the ground, half widths from the centre line.
## Heuristics, not truth: low-confidence values and values that conflict with the catalog go to
## "warnings" so that nobody uses them silently.

## Profile step along the length (metres).
const STEP := 0.1
## Triangles larger than this get interior sample points, so big flat faces show in profiles.
const SAMPLE_SPACING := 0.05
## Up-facing triangle area is binned by height in bins of this size to find the deck and roof.
const HEIGHT_BIN := 0.02
## A triangle counts as up-facing (deck, roof) above this normal.y.
const UP_NORMAL := 0.9
## The deck is searched in this band of the robust height; the roof above the deck + ROOF_GAP.
const DECK_BAND := Vector2(0.3, 0.85)
const ROOF_GAP := 0.25
## Turret base layer above the deck (metres) and the share of its widest slab that still counts.
const TURRET_LAYER := Vector2(0.05, 0.25)
const TURRET_MIN_SHARE := 0.35
## A gun barrel slab is thinner than this in height and width (metres); at least GUN_MIN_LENGTH.
const BARREL_MAX := 0.7
const GUN_MIN_LENGTH := 0.5
## Band below the deck for UPPER_HW and band above the ground (tracks / tyres only) for LOWER_HW.
const UPPER_BAND := 0.45
const TRACK_BAND := Vector2(0.05, 0.3)
## Wheel components: radius range, roundness tolerance in the side view.
const WHEEL_RADIUS := Vector2(0.15, 0.7)
const WHEEL_ROUND := 0.15
## Side depth map for fused wheels: cell size (x, h); a wheel is a run of cells deeper than the
## row's 90th percentile minus WHEEL_GAP_DROP; wheel centres lie below HUB_MAX_H of the deck.
const DEPTH_CELL := Vector2(0.03, 0.03)
const DEPTH_SPACING := 0.012
const WHEEL_GAP_DROP := 0.2
const HUB_MAX_H := 0.4
## Values below this confidence are listed under warnings.
const LOW_CONFIDENCE := 0.5
## Deviation from the catalog that is reported as a conflict.
const CATALOG_TOLERANCE := 0.05
## Weld positions on this grid (metres) to join split vertices (UV seams) into components.
const WELD := 0.001


## Measures a normalised mesh. `positions` in metres, `indices` a triangle list. `catalog`: the
## unit's catalog dimensions ({"hull_length", "overall_length", "width", "height"}, any subset);
## `foot` = a soldier (height and proportions only).
static func measure(
	positions: PackedVector3Array, indices: PackedInt32Array, catalog: Dictionary, foot: bool
) -> Dictionary:
	var points := sample_points(positions, indices, SAMPLE_SPACING)
	if points.is_empty():
		return {"kind": "empty", "constants": {}, "warnings": ["the mesh has no triangles"]}
	if foot:
		return _measure_foot(points, catalog)
	return _measure_vehicle(positions, indices, points, catalog)


## Vertices plus interior points of triangles larger than `spacing` (a barycentric grid).
static func sample_points(
	positions: PackedVector3Array, indices: PackedInt32Array, spacing: float
) -> PackedVector3Array:
	var points := positions.duplicate()
	for t in range(0, indices.size() - 2, 3):
		var a := positions[indices[t]]
		var b := positions[indices[t + 1]]
		var c := positions[indices[t + 2]]
		var longest := maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a)))
		if longest <= spacing:
			continue
		var n := mini(ceili(longest / spacing), 200)
		for i in n + 1:
			for j in n + 1 - i:
				var u := float(i) / n
				var v := float(j) / n
				points.append(a + (b - a) * u + (c - a) * v)
	return points


static func _measure_vehicle(
	positions: PackedVector3Array,
	indices: PackedInt32Array,
	points: PackedVector3Array,
	catalog: Dictionary
) -> Dictionary:
	var constants := {}
	var warnings: Array[String] = []
	var box := _bounds(points)
	var robust_h := _percentile(_axis(points, 1), 0.98)
	var levels := deck_and_roof(positions, indices, robust_h)
	var deck: float = levels["deck"]
	constants["DECK_H"] = _value(deck, levels["deck_confidence"], "largest up-facing area")
	if levels.has("roof"):
		constants["ROOF_H"] = _value(
			levels["roof"], levels["roof_confidence"], "largest up-facing area above the deck"
		)
	var hull := _hull_extent(points, deck)
	var nose: float = hull["nose"]
	constants["HULL_LENGTH"] = _value(hull["length"], 0.8, "extent of everything below the deck")
	if box.end.x - nose > STEP:
		constants["GUN_OVERHANG"] = _value(box.end.x - nose, 0.8, "front tip beyond the hull nose")
	if hull["rear"] - box.position.x > STEP:
		constants["REAR_OVERHANG"] = _value(
			hull["rear"] - box.position.x, 0.7, "rear tip beyond the hull rear"
		)
	var profiles := section_profiles(points, nose, deck)
	_add_hull_widths(constants, points, nose, hull["length"], deck)
	var turret := turret_footprint(points, nose, hull["length"], deck)
	var components := components_bounds(positions, indices)
	if not turret.is_empty():
		var separate := _has_turret_component(components, nose, deck, turret)
		_add_turret(constants, turret, separate)
		var gun := gun_axis(points, nose, deck, turret["front"])
		if not gun.is_empty():
			_add_gun(constants, gun, warnings)
		else:
			warnings.append("no gun barrel detected ahead of the turret")
	else:
		warnings.append("no turret detected above the deck")
	var wheels := road_wheels(components, nose, deck)
	if wheels.is_empty():
		wheels = road_wheels_from_side(positions, indices, nose, hull["length"], deck)
	if wheels.is_empty():
		warnings.append(
			"wheels not detected: no separate round components (fused mesh?); measure by hand"
		)
	else:
		constants["ROAD_WHEELS"] = wheels
	warnings.append_array(low_confidence_warnings(constants))
	warnings.append_array(catalog_warnings(constants, box, catalog))
	return {
		"kind": "vehicle",
		"frame": "metres; x from the hull nose rearwards, h above the ground, hw from the centre",
		"hull_nose_glb_x": snappedf(nose, 0.001),
		"size_m": _size(box),
		"profile_step_m": STEP,
		"profiles": profiles,
		"constants": constants,
		"warnings": warnings,
	}


## Deck and roof heights from the up-facing triangle area binned by height: the deck is the
## largest bin in DECK_BAND of the robust height, the roof the largest bin above deck + ROOF_GAP.
static func deck_and_roof(
	positions: PackedVector3Array, indices: PackedInt32Array, robust_h: float
) -> Dictionary:
	var bins := {}
	var heights := {}
	for t in range(0, indices.size() - 2, 3):
		var a := positions[indices[t]]
		var b := positions[indices[t + 1]]
		var c := positions[indices[t + 2]]
		var normal := (c - a).cross(b - a)  # Godot's front faces wind clockwise
		var double_area := normal.length()
		if double_area <= 0.0 or normal.y / double_area < UP_NORMAL:
			continue
		var y := (a.y + b.y + c.y) / 3.0
		var key := floori(y / HEIGHT_BIN)
		bins[key] = float(bins.get(key, 0.0)) + double_area * 0.5
		heights[key] = float(heights.get(key, 0.0)) + double_area * 0.5 * y
	var deck := _peak(bins, heights, robust_h * DECK_BAND.x, robust_h * DECK_BAND.y)
	var result := {"deck": robust_h * 0.6, "deck_confidence": 0.1}
	if deck.is_empty():
		return result
	result["deck"] = deck["h"]
	result["deck_confidence"] = deck["confidence"]
	var roof := _peak(bins, heights, float(deck["h"]) + ROOF_GAP, INF)
	if not roof.is_empty():
		result["roof"] = roof["h"]
		result["roof_confidence"] = roof["confidence"]
	return result


## The bin with the most area in [low, high): its area-weighted height and a confidence = the
## share of the band's area in it and its two neighbours (scaled: half the band = 1.0).
static func _peak(bins: Dictionary, heights: Dictionary, low: float, high: float) -> Dictionary:
	var best_key := 0
	var best := 0.0
	var total := 0.0
	for key: int in bins:
		var y := key * HEIGHT_BIN
		if y < low or y >= high:
			continue
		total += bins[key]
		if bins[key] > best:
			best = bins[key]
			best_key = key
	if best <= 0.0:
		return {}
	var area := 0.0
	var moment := 0.0
	for key in [best_key - 1, best_key, best_key + 1]:
		area += float(bins.get(key, 0.0))
		moment += float(heights.get(key, 0.0))
	return {"h": moment / area, "confidence": clampf(area / total * 2.0, 0.0, 1.0)}


## Nose (GLB x of the front end), rear and length of everything below the deck (hull, tracks,
## wheels; the gun is above the deck).
static func _hull_extent(points: PackedVector3Array, deck: float) -> Dictionary:
	var xs := PackedFloat32Array()
	for point in points:
		if point.y < deck - STEP:
			xs.append(point.x)
	if xs.is_empty():
		var box := _bounds(points)
		return {"nose": box.end.x, "rear": box.position.x, "length": box.size.x}
	var nose := _percentile(xs, 0.999)
	var rear := _percentile(xs, 0.001)
	return {"nose": nose, "rear": rear, "length": nose - rear}


## Height and half-width profiles every STEP along the model x: "hull" = geometry up to the
## deck, "above_deck" = everything above it ("h0" = its lowest point). Empty slabs are left out.
static func section_profiles(points: PackedVector3Array, nose: float, deck: float) -> Dictionary:
	var hull := {}
	var above := {}
	for point in points:
		var slab := floori((nose - point.x) / STEP)
		var target := hull if point.y <= deck + 0.02 else above
		var entry: Dictionary = target.get(slab, {"h": point.y, "hw": 0.0, "h0": point.y})
		entry["h"] = maxf(entry["h"], point.y)
		entry["h0"] = minf(entry["h0"], point.y)
		entry["hw"] = maxf(entry["hw"], absf(point.z))
		target[slab] = entry
	return {"hull": _profile_rows(hull, false), "above_deck": _profile_rows(above, true)}


static func _profile_rows(slabs: Dictionary, with_bottom: bool) -> Array[Dictionary]:
	var keys := slabs.keys()
	keys.sort()
	var rows: Array[Dictionary] = []
	for slab: int in keys:
		var entry: Dictionary = slabs[slab]
		var row := {
			"x": snappedf((slab + 0.5) * STEP, 0.001),
			"h": snappedf(entry["h"], 0.001),
			"hw": snappedf(entry["hw"], 0.001),
		}
		if with_bottom:
			row["h0"] = snappedf(entry["h0"], 0.001)
		rows.append(row)
	return rows


## UPPER_HW: the hull's half width in the band just below the deck (fenders, sponsons);
## LOWER_HW: the inner edge of the tracks / tyres near the ground (the lower hull runs between
## them), with TRACK_Z / TRACK_WIDTH. Only the middle 70 % of the hull length is used.
static func _add_hull_widths(
	constants: Dictionary, points: PackedVector3Array, nose: float, length: float, deck: float
) -> void:
	var upper := PackedFloat32Array()
	var low := PackedFloat32Array()
	for point in points:
		var x := nose - point.x
		if x < length * 0.15 or x > length * 0.85:
			continue
		if point.y >= deck - UPPER_BAND and point.y <= deck:
			upper.append(absf(point.z))
		elif point.y >= TRACK_BAND.x and point.y <= TRACK_BAND.y:
			low.append(absf(point.z))
	if not upper.is_empty():
		constants["UPPER_HW"] = _value(
			_percentile(upper, 0.99), 0.75, "half width in the %.2f m below the deck" % UPPER_BAND
		)
	if low.is_empty():
		return
	var inner := _percentile(low, 0.02)
	var outer := _percentile(low, 0.98)
	# Geometry near the centre line this low (a belly plate, a ground slab) hides the gap.
	var confidence := 0.6 if inner > 0.3 else 0.2
	constants["LOWER_HW"] = _value(
		inner, confidence, "inner edge of the tracks / tyres near the ground"
	)
	constants["TRACK_Z"] = _value((inner + outer) * 0.5, confidence, "track centre line")
	constants["TRACK_WIDTH"] = _value(outer - inner, confidence, "track / tyre width")


## The turret's footprint in its base layer (TURRET_LAYER above the deck): the contiguous run of
## slabs around the widest one. {"x" (area centroid), "ring_r" (radius of a disc of equal area,
## at most the half width), "front", "rear", "hw", "circularity"} or {} without one.
static func turret_footprint(
	points: PackedVector3Array, nose: float, length: float, deck: float
) -> Dictionary:
	var low := {}
	var high := {}
	for point in points:
		var x := nose - point.x
		if point.y < deck + TURRET_LAYER.x or point.y > deck + TURRET_LAYER.y:
			continue
		if x < 0.0 or x > length + 1.0:
			continue
		var slab := floori(x / STEP)
		low[slab] = minf(float(low.get(slab, INF)), point.z)
		high[slab] = maxf(float(high.get(slab, -INF)), point.z)
	if low.is_empty():
		return {}
	var widest := 0
	var widest_hw := 0.0
	for slab: int in low:
		var hw := (float(high[slab]) - float(low[slab])) * 0.5
		if hw > widest_hw:
			widest_hw = hw
			widest = slab
	var first := widest
	var last := widest
	while _slab_hw(low, high, first - 1) >= widest_hw * TURRET_MIN_SHARE:
		first -= 1
	while _slab_hw(low, high, last + 1) >= widest_hw * TURRET_MIN_SHARE:
		last += 1
	var area := 0.0
	var moment := 0.0
	for slab in range(first, last + 1):
		var hw := _slab_hw(low, high, slab)
		area += 2.0 * hw * STEP
		moment += 2.0 * hw * STEP * (slab + 0.5) * STEP
	var half_length := (last - first + 1) * STEP * 0.5
	return {
		"x": moment / area,
		"ring_r": minf(sqrt(area / PI), widest_hw),
		"front": first * STEP,
		"rear": (last + 1) * STEP,
		"hw": widest_hw,
		"circularity": minf(half_length, widest_hw) / maxf(half_length, widest_hw),
	}


static func _slab_hw(low: Dictionary, high: Dictionary, slab: int) -> float:
	if not low.has(slab):
		return 0.0
	return (float(high[slab]) - float(low[slab])) * 0.5


static func _add_turret(constants: Dictionary, turret: Dictionary, separate: bool) -> void:
	var round_confidence := 0.35 + 0.5 * float(turret["circularity"])
	var bonus := 0.1 if separate else 0.0
	var source := "separate component; " if separate else ""
	constants["TURRET_X"] = _value(
		turret["x"], 0.6 + bonus, source + "area centroid of the turret base layer"
	)
	constants["TURRET_RING_R"] = _value(
		turret["ring_r"],
		round_confidence + bonus,
		source + "radius of a disc with the base layer's area (exact for a round turret)"
	)
	constants["TURRET_FRONT"] = _value(turret["front"], 0.6 + bonus, "front of the base layer")
	constants["TURRET_REAR"] = _value(turret["rear"], 0.6 + bonus, "rear of the base layer")
	constants["TURRET_HW"] = _value(turret["hw"], 0.6 + bonus, "half width of the base layer")


## The barrel: thin slabs above the deck ahead of the turret front. {"tip" (model x), "face"
## (model x where the barrel meets the mantlet / turret), "h" (axis height at the face),
## "elevation_deg", "length"} or {} without a barrel.
static func gun_axis(
	points: PackedVector3Array, nose: float, deck: float, turret_front: float
) -> Dictionary:
	var slabs := {}
	for point in points:
		var x := nose - point.x
		if point.y <= deck + STEP:
			continue
		var slab := floori(x / STEP)
		var entry: Dictionary = slabs.get(slab, {"y0": INF, "y1": -INF, "z0": INF, "z1": -INF})
		entry["y0"] = minf(entry["y0"], point.y)
		entry["y1"] = maxf(entry["y1"], point.y)
		entry["z0"] = minf(entry["z0"], point.z)
		entry["z1"] = maxf(entry["z1"], point.z)
		slabs[slab] = entry
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var tip := INF
	for slab: int in slabs:
		var entry: Dictionary = slabs[slab]
		if (slab + 1) * STEP > turret_front:
			continue
		tip = minf(tip, slab * STEP)
		if entry["y1"] - entry["y0"] < BARREL_MAX and entry["z1"] - entry["z0"] < BARREL_MAX:
			xs.append((slab + 0.5) * STEP)
			ys.append((float(entry["y0"]) + float(entry["y1"])) * 0.5)
	if xs.size() * STEP < GUN_MIN_LENGTH:
		return {}
	var line := _fit_line(xs, ys)
	var face := _mantlet_face(points, nose, deck, xs, line)
	return {
		"tip": tip,
		"face": face,
		"h": line.x + line.y * face,
		"elevation_deg": rad_to_deg(atan(-line.y)),
		"length": face - tip,
	}


## Rearwards from the barrel root: the first slab where the geometry around the axis height is
## wider than a barrel.
static func _mantlet_face(
	points: PackedVector3Array, nose: float, deck: float, xs: PackedFloat32Array, line: Vector2
) -> float:
	var root := xs[0]
	for x in xs:
		root = maxf(root, x)
	var widths := {}
	for point in points:
		var x := nose - point.x
		if x < root or point.y <= deck + STEP:
			continue
		if absf(point.y - (line.x + line.y * x)) > 0.2:
			continue
		var slab := floori(x / STEP)
		var range_z: Vector2 = widths.get(slab, Vector2(INF, -INF))
		widths[slab] = Vector2(minf(range_z.x, point.z), maxf(range_z.y, point.z))
	var keys := widths.keys()
	keys.sort()
	for slab: int in keys:
		var range_z: Vector2 = widths[slab]
		if range_z.y - range_z.x >= BARREL_MAX:
			return slab * STEP
	return root + STEP * 0.5


## Least squares y = a + b x as Vector2(a, b).
static func _fit_line(xs: PackedFloat32Array, ys: PackedFloat32Array) -> Vector2:
	var n := xs.size()
	var mean_x := 0.0
	var mean_y := 0.0
	for i in n:
		mean_x += xs[i] / n
		mean_y += ys[i] / n
	var sxx := 0.0
	var sxy := 0.0
	for i in n:
		sxx += (xs[i] - mean_x) * (xs[i] - mean_x)
		sxy += (xs[i] - mean_x) * (ys[i] - mean_y)
	var slope := sxy / sxx if sxx > 0.0 else 0.0
	return Vector2(mean_y - slope * mean_x, slope)


static func _add_gun(constants: Dictionary, gun: Dictionary, warnings: Array[String]) -> void:
	constants["TRUNNION"] = _value(
		[snappedf(gun["face"], 0.001), snappedf(gun["h"], 0.001)],
		0.55,
		"(x, h) where the barrel meets the mantlet; the real trunnion lies somewhat behind it"
	)
	constants["GUN_LENGTH"] = _value(gun["length"], 0.7, "barrel from the mantlet to the muzzle")
	constants["GUN_ELEVATION_DEG"] = _value(gun["elevation_deg"], 0.7, "barrel axis slope")
	if absf(gun["elevation_deg"]) > 3.0:
		warnings.append(
			(
				"the gun is elevated %.1f deg in the GLB: GUN_OVERHANG / TRUNNION h are not level"
				% gun["elevation_deg"]
			)
		)


## Connected components (vertices welded on a WELD grid): Array of AABB, largest first.
static func components_bounds(
	positions: PackedVector3Array, indices: PackedInt32Array
) -> Array[AABB]:
	var welded := PackedInt32Array()
	welded.resize(positions.size())
	var ids := {}
	for i in positions.size():
		var key := Vector3i((positions[i] / WELD).round())
		if not ids.has(key):
			ids[key] = ids.size()
		welded[i] = ids[key]
	var parent := PackedInt32Array()
	parent.resize(ids.size())
	for i in parent.size():
		parent[i] = i
	for t in range(0, indices.size() - 2, 3):
		var a := _find(parent, welded[indices[t]])
		for k in [1, 2]:
			var b := _find(parent, welded[indices[t + k]])
			if a != b:
				parent[b] = a
	var boxes := {}
	for i in positions.size():
		var root := _find(parent, welded[i])
		if boxes.has(root):
			boxes[root] = (boxes[root] as AABB).expand(positions[i])
		else:
			boxes[root] = AABB(positions[i], Vector3.ZERO)
	var result: Array[AABB] = []
	for root: int in boxes:
		result.append(boxes[root])
	result.sort_custom(func(a: AABB, b: AABB) -> bool: return a.get_volume() > b.get_volume())
	return result


static func _find(parent: PackedInt32Array, i: int) -> int:
	var root := i
	while parent[root] != root:
		root = parent[root]
	while parent[i] != root:
		var next := parent[i]
		parent[i] = root
		i = next
	return root


## A component standing on the deck that covers the turret footprint's centre.
static func _has_turret_component(
	components: Array[AABB], nose: float, deck: float, turret: Dictionary
) -> bool:
	var centre_x := nose - float(turret["x"])
	for box in components:
		if box.position.y < deck - 0.05 or box.end.y < deck + TURRET_LAYER.y:
			continue
		if box.position.x <= centre_x and box.end.x >= centre_x and box.size.z > turret["hw"]:
			return true
	return false


## Road wheels from round components below the deck: the most common radius per side. A
## constant {"value": {"count_per_side", "radius", "h", "x": [model x...]}, "confidence"} or {}.
static func road_wheels(components: Array[AABB], nose: float, deck: float) -> Dictionary:
	var wheels: Array[Vector4] = []  # model x, h, radius, side
	for box in components:
		var radius := box.size.y * 0.5
		if radius < WHEEL_RADIUS.x or radius > WHEEL_RADIUS.y:
			continue
		if absf(box.size.x - box.size.y) > box.size.y * WHEEL_ROUND:
			continue
		var centre := box.get_center()
		if centre.y > deck * 0.6 or absf(centre.z) < 0.5 or box.size.z > box.size.y:
			continue
		var x := nose - centre.x
		var side := signf(centre.z)
		var merged := false
		for i in wheels.size():
			var other := wheels[i]
			if other.w == side and absf(other.x - x) < 0.15 and absf(other.y - centre.y) < 0.15:
				if radius > other.z:
					wheels[i] = Vector4(x, centre.y, radius, side)
				merged = true
		if not merged:
			wheels.append(Vector4(x, centre.y, radius, side))
	if wheels.is_empty():
		return {}
	var best: Array[Vector4] = []
	for wheel in wheels:
		var group: Array[Vector4] = []
		for other in wheels:
			if absf(other.z - wheel.z) <= wheel.z * 0.12 and absf(other.y - wheel.y) < 0.1:
				group.append(other)
		if group.size() > best.size():
			best = group
	var right: Array[float] = []
	var left: Array[float] = []
	var radii := PackedFloat32Array()
	var hs := PackedFloat32Array()
	for wheel in best:
		(right if wheel.w > 0.0 else left).append(snappedf(wheel.x, 0.001))
		radii.append(wheel.z)
		hs.append(wheel.y)
	var side_xs := right if right.size() >= left.size() else left
	side_xs.sort()
	var confidence := 0.85 if right.size() == left.size() and right.size() >= 3 else 0.45
	return {
		"value":
		{
			"count_per_side": side_xs.size(),
			"radius": snappedf(_percentile(radii, 0.5), 0.001),
			"h": snappedf(_percentile(hs, 0.5), 0.001),
			"x": side_xs,
		},
		"confidence": confidence,
		"note":
		(
			"round components below the deck, the most common radius (%d right, %d left)"
			% [right.size(), left.size()]
		),
	}


## Fallback for a fused mesh (Meshy: one shell): the side depth map (outermost |z| per cell of
## x and h) shows each road wheel as a run of deep cells, separated from the next by a gap where
## the view reaches the hull side. The row (below HUB_MAX_H of the deck) with the most runs of a
## similar width is the wheels' diameter line: run centres = wheel x, half the median run width
## = radius, row height = wheel centre h. Low confidence.
static func road_wheels_from_side(
	positions: PackedVector3Array,
	indices: PackedInt32Array,
	nose: float,
	length: float,
	deck: float
) -> Dictionary:
	var columns := ceili(length / DEPTH_CELL.x) + 1
	var rows := ceili(deck * HUB_MAX_H / DEPTH_CELL.y) + 1
	var low := PackedInt32Array()
	for t in range(0, indices.size() - 2, 3):
		var bottom := minf(positions[indices[t]].y, positions[indices[t + 1]].y)
		if minf(bottom, positions[indices[t + 2]].y) < rows * DEPTH_CELL.y:
			low.append_array(indices.slice(t, t + 3))
	# Denser than the profiles: an empty cell would show the hull side behind a wheel.
	var points := sample_points(positions, low, DEPTH_SPACING)
	var best: Dictionary = {}
	for side in [1.0, -1.0]:
		var depth := PackedFloat32Array()
		depth.resize(columns * rows)
		depth.fill(-1.0)
		for point in points:
			var column := floori((nose - point.x) / DEPTH_CELL.x)
			var row := floori(point.y / DEPTH_CELL.y)
			if column < 0 or column >= columns or row < 0 or row >= rows:
				continue
			var cell := row * columns + column
			depth[cell] = maxf(depth[cell], point.z * side)
		var found: Array[Dictionary] = []
		for row in rows:
			found.append(_wheel_runs(depth.slice(row * columns, (row + 1) * columns)))
		var candidate := _wheel_row(found)
		if _better_wheel_row(candidate, best):
			best = candidate
	if best.get("count_per_side", 0) < 3:
		return {}
	return {
		"value": best,
		"confidence": 0.45,
		"note": "fallback: wheel runs in the side depth map of a fused mesh (may count a sprocket)",
	}


## A cell at least `threshold` deep; an empty cell (sparse samples) takes the nearest known cells
## within twice DEPTH_SPACING on both sides, so the sampling does not cut runs into pieces.
static func _deep(row: PackedFloat32Array, column: int, threshold: float) -> bool:
	if row[column] >= 0.0:
		return row[column] >= threshold
	var reach := ceili(DEPTH_SPACING * 2.0 / DEPTH_CELL.x)
	var left := false
	var right := false
	for step in range(1, reach + 1):
		if not left and column - step >= 0 and row[column - step] >= 0.0:
			if row[column - step] < threshold:
				return false
			left = true
		if not right and column + step < row.size() and row[column + step] >= 0.0:
			if row[column + step] < threshold:
				return false
			right = true
	return left and right


## More wheels wins; with as many, the wider runs (closer to the diameter).
static func _better_wheel_row(row: Dictionary, best: Dictionary) -> bool:
	var count: int = row.get("count_per_side", 0)
	var best_count: int = best.get("count_per_side", 0)
	if count != best_count:
		return count > best_count
	return float(row.get("radius", 0.0)) > float(best.get("radius", 0.0))


## The best row of one side; its "h" is the middle of the band of neighbouring rows with as many
## runs at least 95 % as wide (the polygonal wheels and the cells make the widest row arbitrary).
static func _wheel_row(rows: Array[Dictionary]) -> Dictionary:
	var best_row := -1
	for row in rows.size():
		if best_row < 0 or _better_wheel_row(rows[row], rows[best_row]):
			best_row = row
	if best_row < 0 or rows[best_row].is_empty():
		return {}
	var best := rows[best_row].duplicate()
	var first := best_row
	var last := best_row
	while first > 0 and _same_wheel_row(rows[first - 1], best):
		first -= 1
	while last < rows.size() - 1 and _same_wheel_row(rows[last + 1], best):
		last += 1
	best["h"] = snappedf((first + last + 1) * 0.5 * DEPTH_CELL.y, 0.001)
	return best


static func _same_wheel_row(row: Dictionary, best: Dictionary) -> bool:
	if row.get("count_per_side", 0) != best["count_per_side"]:
		return false
	return float(row["radius"]) >= float(best["radius"]) * 0.95


## Runs of deep cells in one row of the depth map: those of the most common width (within
## WHEEL_ROUND) and of a wheel's size. {"count_per_side", "radius", "x": [...]} or {}.
static func _wheel_runs(row: PackedFloat32Array) -> Dictionary:
	var values := PackedFloat32Array()
	for value in row:
		if value > 0.0:
			values.append(value)
	if values.size() < 4:
		return {}
	var threshold := _percentile(values, 0.9) - WHEEL_GAP_DROP
	var runs: Array[Vector2] = []  # centre x, half width
	var first := -1
	for column in row.size() + 1:
		var deep := column < row.size() and _deep(row, column, threshold)
		if deep and first < 0:
			first = column
		elif not deep and first >= 0:
			var half := (column - first) * DEPTH_CELL.x * 0.5
			if half >= WHEEL_RADIUS.x and half <= WHEEL_RADIUS.y:
				runs.append(Vector2((first + column) * DEPTH_CELL.x * 0.5, half))
			first = -1
	var best: Array[Vector2] = []
	for run in runs:
		var group: Array[Vector2] = []
		for other in runs:
			if absf(other.y - run.y) <= run.y * WHEEL_ROUND:
				group.append(other)
		if group.size() > best.size():
			best = group
	if best.is_empty():
		return {}
	var halves := PackedFloat32Array()
	var xs: Array[float] = []
	for run in best:
		halves.append(run.y)
		xs.append(snappedf(run.x, 0.001))
	return {
		"count_per_side": best.size(),
		"radius": snappedf(_percentile(halves, 0.5), 0.001),
		"x": xs,
	}


## Foot unit: height and proportions only.
static func _measure_foot(points: PackedVector3Array, catalog: Dictionary) -> Dictionary:
	var box := _bounds(points)
	var zs := _axis(points, 2)
	var xs := _axis(points, 0)
	var width := _percentile(zs, 0.99) - _percentile(zs, 0.01)
	var depth := _percentile(xs, 0.99) - _percentile(xs, 0.01)
	var height := box.size.y
	var constants := {
		"HEIGHT": _value(height, 0.9, "bounding box height"),
		"WIDTH": _value(width, 0.7, "1st..99th percentile across"),
		"DEPTH": _value(depth, 0.7, "1st..99th percentile along x"),
		"WIDTH_TO_HEIGHT": _value(width / height, 0.7, "proportion"),
		"DEPTH_TO_HEIGHT": _value(depth / height, 0.7, "proportion"),
	}
	var warnings := low_confidence_warnings(constants)
	warnings.append_array(catalog_warnings(constants, box, catalog))
	return {
		"kind": "foot",
		"frame": "metres; height above the ground",
		"size_m": _size(box),
		"constants": constants,
		"warnings": warnings,
	}


## Every constant below LOW_CONFIDENCE.
static func low_confidence_warnings(constants: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var names := constants.keys()
	names.sort()
	for name: String in names:
		var entry: Dictionary = constants[name]
		if float(entry["confidence"]) < LOW_CONFIDENCE:
			found.append(
				(
					"%s low confidence (%.2f): %s - check by hand"
					% [name, entry["confidence"], entry["note"]]
				)
			)
	return found


## Measured values that conflict with the catalog dimensions by more than CATALOG_TOLERANCE.
static func catalog_warnings(
	constants: Dictionary, box: AABB, catalog: Dictionary
) -> Array[String]:
	var found: Array[String] = []
	var checks := []
	if constants.has("HULL_LENGTH") and catalog.has("hull_length"):
		checks.append(["HULL_LENGTH", constants["HULL_LENGTH"]["value"], catalog["hull_length"]])
	if constants.has("HEIGHT") and catalog.has("height"):
		checks.append(["HEIGHT", constants["HEIGHT"]["value"], catalog["height"]])
	if constants.has("UPPER_HW") and catalog.has("width"):
		checks.append(
			["2 x UPPER_HW", 2.0 * float(constants["UPPER_HW"]["value"]), catalog["width"]]
		)
	if constants.has("ROOF_H") and catalog.has("height"):
		var roof: float = constants["ROOF_H"]["value"]
		if roof > float(catalog["height"]) * (1.0 + CATALOG_TOLERANCE):
			found.append(
				"ROOF_H %.2f m is above the catalog height %.2f m" % [roof, catalog["height"]]
			)
	if catalog.has("width") and not constants.has("HEIGHT"):
		checks.append(["width", box.size.z, catalog["width"]])
	for check: Array in checks:
		var measured := float(check[1])
		var expected := float(check[2])
		if expected <= 0.0:
			continue
		var deviation := (measured - expected) / expected
		if absf(deviation) > CATALOG_TOLERANCE:
			found.append(
				(
					"%s %.2f m vs. catalog %.2f m (%+.0f%%)"
					% [check[0], measured, expected, deviation * 100.0]
				)
			)
	return found


static func _value(value: Variant, confidence: float, note: String) -> Dictionary:
	var rounded: Variant = snappedf(value, 0.001) if value is float else value
	return {
		"value": rounded, "confidence": snappedf(clampf(confidence, 0.0, 1.0), 0.01), "note": note
	}


static func _size(box: AABB) -> Dictionary:
	return {
		"length": snappedf(box.size.x, 0.001),
		"height": snappedf(box.size.y, 0.001),
		"width": snappedf(box.size.z, 0.001),
	}


static func _bounds(points: PackedVector3Array) -> AABB:
	var low := points[0]
	var high := points[0]
	for point in points:
		low = low.min(point)
		high = high.max(point)
	return AABB(low, high - low)


static func _axis(points: PackedVector3Array, axis: int) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(points.size())
	for i in points.size():
		values[i] = points[i][axis]
	return values


static func _percentile(values: PackedFloat32Array, share: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[int((sorted.size() - 1) * share)]
