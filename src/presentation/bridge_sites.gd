class_name BridgeSites
extends RefCounted
## Where bridges stand (TASK-108c), split out of FeatureRibbonPlanner: every crossing of a drawn
## road centreline with a drawn river centreline, then greedily the steepest first, dropping any
## whose deck would overlap one already kept. Pure and static.


## Bridge sites (TASK-108c): one per place where a drawn road centreline crosses a drawn river
## centreline (segment tests per tile on the clearance index; decks that would overlap keep the
## steepest crossing). Entry: {position: Vector2 (world XZ), direction: Vector2 (unit, along the
## road), span_m: water width / |sin angle| + 2 abutments (capped), water_m: local water width,
## width_m}. Empty when either kind has no links. A road link into a river hex whose drawn line
## misses the drawn river gets none.
static func find(grid: HexGrid) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not grid.has_links():
		return result
	var index := FeatureRibbonPlanner.clearance_index(grid)
	var roads: Dictionary = index[FeatureRibbonPlanner.Kind.ROAD]
	var rivers: Dictionary = index[FeatureRibbonPlanner.Kind.RIVER]
	var tiles: Array = []
	for coord: Vector2i in roads:
		if rivers.has(coord):
			tiles.append(coord)
	tiles.sort()
	var candidates: Array[Dictionary] = []
	for coord: Vector2i in tiles:
		var road_entry: Array = roads[coord]
		var river_entry: Array = rivers[coord]
		var road_pairs: PackedVector2Array = road_entry[0]
		var river_pairs: PackedVector2Array = river_entry[0]
		var river_halves: PackedFloat32Array = river_entry[1]
		var river_waters: PackedFloat32Array = river_entry[2]
		for i in road_pairs.size() / 2:
			var ra := road_pairs[2 * i]
			var rb := road_pairs[2 * i + 1]
			if ra == rb:
				continue
			for j in river_halves.size():
				var wa := river_pairs[2 * j]
				var wb := river_pairs[2 * j + 1]
				if wa == wb:
					continue
				var hit: Variant = Geometry2D.segment_intersects_segment(ra, rb, wa, wb)
				if hit == null:
					continue
				var at: Vector2 = hit
				# A crossing belongs to the tile it lies in (neighbours list the same segments).
				var tile := Hex.from_world(Vector3(at.x, 0.0, at.y), TerrainField.HEX_SIZE)
				if tile != coord:
					continue
				var direction := (rb - ra).normalized()
				var sin_angle := absf(direction.cross((wb - wa).normalized()))
				var water_m := river_waters[j] * MapScale.metres_per_unit
				(
					candidates
					. append(
						{
							"position": at,
							"direction": direction,
							"span_m": span_m(water_m, sin_angle),
							"water_m": water_m,
							"width_m": FeatureRibbonPlanner.BRIDGE_WIDTH_M,
							"sin": sin_angle,
						}
					)
				)
	# Steepest crossings first (a river that weaves across a road gives several shallow ones
	# near a clean one); a candidate whose deck would overlap one already kept is dropped.
	candidates.sort_custom(_steeper_first)
	for site in candidates:
		if not overlaps(result, site):
			site.erase("sin")
			result.append(site)
	return result


## Span of a bridge over `water_m` of water crossed at an angle whose sine is `sin_angle`: the
## water along the road plus an abutment at each end, at most BRIDGE_MAX_SPAN_M.
static func span_m(water_m: float, sin_angle: float) -> float:
	if sin_angle < 1e-3:
		return FeatureRibbonPlanner.BRIDGE_MAX_SPAN_M
	return minf(
		water_m / sin_angle + 2.0 * FeatureRibbonPlanner.BRIDGE_ABUTMENT_M,
		FeatureRibbonPlanner.BRIDGE_MAX_SPAN_M
	)


static func _steeper_first(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(a["sin"], b["sin"]):
		return a["sin"] > b["sin"]
	var pa: Vector2 = a["position"]
	var pb: Vector2 = b["position"]
	return pa.x < pb.x or (pa.x == pb.x and pa.y < pb.y)


## Whether `site`'s deck would overlap a kept one: the centres are closer than half the two spans
## (and never closer than FeatureRibbonPlanner.BRIDGE_MERGE_M).
static func overlaps(sites: Array[Dictionary], site: Dictionary) -> bool:
	var at: Vector2 = site["position"]
	for kept in sites:
		var reach_m := maxf(
			FeatureRibbonPlanner.BRIDGE_MERGE_M,
			0.5 * (float(kept["span_m"]) + float(site["span_m"]))
		)
		if (kept["position"] as Vector2).distance_to(at) * MapScale.metres_per_unit < reach_m:
			return true
	return false
