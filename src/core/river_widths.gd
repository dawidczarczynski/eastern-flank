class_name RiverWidths
extends RefCounted
## Real river widths from the land-cover raster (TASK-216 follow-up): OSM draws a big river as one
## centre line (no `width`, class "river") plus a water polygon, so the line alone says "8 m". The
## raster already holds the polygon as WATER cells; the water width of a river hex is the shortest
## chord of the water body through its centre. The stored width stays when it is larger. Pure and
## deterministic; mutates only the grid's river widths.

## Widest water measured: wider bodies are lakes or estuaries, drawn by the water plane.
const MAX_WIDTH_M := 140.0
## Candidate probe points: the hex centre and six points at this distance (world units).
const PROBE_RING := 0.3
## Directions of the chord search (15 degrees apart over a half turn).
const DIRECTIONS := 12


## Raises the width of every river hex of `grid` to the water width `cover` shows there. A cover
## without a raster changes nothing. Returns the number of hexes widened.
static func apply(grid: HexGrid, cover: LandCover) -> int:
	if cover == null or not cover.has_raster() or not grid.has_links():
		return 0
	var widened := 0
	for c in grid.coords():
		if grid.river_links(c) == 0:
			continue
		var measured := measure_m(cover, Hex.to_world(c, TerrainField.HEX_SIZE))
		if measured > grid.river_width_m(c):
			grid.set_river_width_m(c, measured)
			widened += 1
	return widened


## Water width in metres of the river body near world point `centre` (0 when no water lies within
## PROBE_RING of it): the median over the probe points in water of their shortest chord.
static func measure_m(cover: LandCover, centre: Vector3) -> float:
	var probes: Array[Vector2] = [Vector2(centre.x, centre.z)]
	for k in 6:
		probes.append(Vector2(centre.x, centre.z) + Vector2.from_angle(k * TAU / 6.0) * PROBE_RING)
	var chords: Array[float] = []
	for p in probes:
		if cover.class_at(p.x, p.y) != LandCover.Kind.WATER:
			continue
		chords.append(_shortest_chord(cover, p))
	if chords.is_empty():
		return 0.0
	chords.sort()
	var units := chords[(chords.size() - 1) / 2]
	return minf(MapScale.metres_per_unit * units, MAX_WIDTH_M)


## Shortest water chord through `p` over DIRECTIONS directions, in world units (walking each way
## in raster cells until the water ends, at most the lake limit).
static func _shortest_chord(cover: LandCover, p: Vector2) -> float:
	var step := cover.cell_size
	var limit := int(ceil(MapScale.to_units(MAX_WIDTH_M * 1.5) / step))
	var best := INF
	for d in DIRECTIONS:
		var dir := Vector2.from_angle(d * PI / DIRECTIONS)
		var steps := 0
		for sign_dir in [1.0, -1.0]:
			var n := 0
			while n < limit:
				var q: Vector2 = p + dir * sign_dir * step * (n + 1)
				if cover.class_at(q.x, q.y) != LandCover.Kind.WATER:
					break
				n += 1
			steps += n
		best = minf(best, (steps + 1) * step)
	return best
