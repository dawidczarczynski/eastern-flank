class_name StaffMapCountries
extends RefCounted
## Pure helpers of the staff map's country layer (TASK-113): the dash-dot pattern cut into a
## border polyline and the place of each country's name. The view bakes the result once.

## Pattern along a border in hex units, alternating drawn / gap: dash, gap, dot, gap.
const PATTERN := [0.5, 0.22, 0.05, 0.22]
## Untranslated country names by ISO code (the translation keys of the strings table).
const NAMES := {"PL": "Poland", "LT": "Lithuania", "BY": "Belarus", "RU": "Russia"}


## The drawn pieces of `line` for the alternating drawn / gap lengths in `pattern` (even
## index = drawn). The pattern runs on across corners; a closed ring ends mid-pattern.
static func dashes(
	line: PackedVector2Array, pattern: Array = PATTERN
) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if line.size() < 2 or pattern.is_empty():
		return out
	var index := 0
	var remaining: float = pattern[0]
	var piece := PackedVector2Array()
	for i in line.size() - 1:
		var a := line[i]
		var length := a.distance_to(line[i + 1])
		if length < 0.000001:
			continue
		var direction := (line[i + 1] - a) / length
		var at := 0.0
		while at < length - 0.000001:
			var step := minf(remaining, length - at)
			if index % 2 == 0:
				if piece.is_empty():
					piece.append(a + direction * at)
				piece.append(a + direction * (at + step))
			at += step
			remaining -= step
			if remaining <= 0.000001:
				if not piece.is_empty():
					out.append(piece)
					piece = PackedVector2Array()
				index += 1
				remaining = pattern[index % pattern.size()]
	if piece.size() >= 2:
		out.append(piece)
	return out


## Where each country's name goes: ISO code -> world XZ centre (hex size `size`) of the country's
## hex nearest to the mean of all its hexes (so the name sits on the country, also for curved
## ones). Countries without a hex are left out. Deterministic.
static func name_anchors(map: ImportedMap, size: float = 1.0) -> Dictionary:
	var sums := {}
	var counts := {}
	var centres := {}
	for row in map.height:
		for col in map.width:
			var coord := MapGenerator.offset_to_axial(col, row)
			var iso := map.country_at(coord)
			if iso == "":
				continue
			var world := Hex.to_world(coord, size)
			var point := Vector2(world.x, world.z)
			sums[iso] = sums.get(iso, Vector2.ZERO) + point
			counts[iso] = counts.get(iso, 0) + 1
			if not centres.has(iso):
				centres[iso] = []
			(centres[iso] as Array).append(point)
	var anchors := {}
	for iso: String in sums:
		var mean: Vector2 = sums[iso] / float(counts[iso])
		var best := Vector2.ZERO
		var best_distance := INF
		for point: Vector2 in centres[iso]:
			var distance := point.distance_squared_to(mean)
			if distance < best_distance:
				best_distance = distance
				best = point
		anchors[iso] = best
	return anchors
