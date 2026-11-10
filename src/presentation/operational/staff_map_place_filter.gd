class_name StaffMapPlaceFilter
extends RefCounted
## Which place-name labels the staff map shows (TASK-112): pure maths, no nodes. Ranks open with
## the zoom level (0 cities, 1 + towns, 2 + villages); labels whose anchor is off-screen are
## dropped; overlapping label rects are resolved greedily, higher rank first, then list order
## (the importer's tie-break order), so the same input always gives the same output.

## Font sizes in px per rank (city, town, village); fixed at every zoom and tilt.
const FONT_SIZES: Array[int] = [17, 12, 10]
## At the widest zoom level the largest towns (first in list order) are labelled too.
const WIDE_TOWNS := 30
## Empty space kept between two labels, px.
const GAP := 3.0


## Indices (ascending) of the labels to draw. `ranks`, `screen_positions` (label anchors) and
## `sizes` (label rect sizes, px; the rect is centred on its anchor) are parallel; `bounds` is the
## screen rectangle an anchor must lie in; labels touching an `obstacles` rect are
## dropped, except cities and towns, which try a few nearby spots first (the chosen offset lands in
## `shifts`, index -> Vector2).
static func visible_places(
	ranks: PackedInt32Array,
	screen_positions: PackedVector2Array,
	sizes: PackedVector2Array,
	zoom_level: int,
	bounds: Rect2,
	obstacles: Array[Rect2] = [],
	shifts: Dictionary = {}
) -> PackedInt32Array:
	var max_rank := clampi(zoom_level, 0, 2)
	var candidates: Array[int] = []
	var towns := 0
	for i in ranks.size():
		var allowed := ranks[i] <= max_rank
		if ranks[i] == 1:
			towns += 1
			allowed = allowed or towns <= WIDE_TOWNS
		if allowed and bounds.has_point(screen_positions[i]):
			candidates.append(i)
	# Stable by construction: rank, then list order.
	candidates.sort_custom(func(a: int, b: int) -> bool: return _before(ranks, a, b))
	var taken: Array[Rect2] = []
	var shown: Array[int] = []
	for i in candidates:
		var base := Rect2(screen_positions[i] - sizes[i] * 0.5, sizes[i]).grow(GAP * 0.5)
		var spots: Array[Vector2] = [Vector2.ZERO]
		if ranks[i] <= 1:  # cities and towns slide off a counter instead of vanishing
			var reach := sizes[i].x * 0.5 + 40.0
			spots.append_array(
				[Vector2(0, 46), Vector2(0, -46), Vector2(reach, 0), Vector2(-reach, 0)]
			)
			spots.append_array([Vector2(0, 78), Vector2(0, -78)])
		for shift in spots:
			var rect := Rect2(base.position + shift, base.size)
			if _free(rect, obstacles) and _free(rect, taken):
				taken.append(rect)
				shown.append(i)
				shifts[i] = shift
				break
	shown.sort()
	return PackedInt32Array(shown)


static func _before(ranks: PackedInt32Array, a: int, b: int) -> bool:
	if ranks[a] != ranks[b]:
		return ranks[a] < ranks[b]
	return a < b


static func _free(rect: Rect2, others: Array[Rect2]) -> bool:
	for other in others:
		if rect.intersects(other):
			return false
	return true
