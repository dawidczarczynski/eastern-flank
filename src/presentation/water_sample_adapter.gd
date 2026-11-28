class_name WaterSampleAdapter
extends RefCounted
## Fills a WaterSample (TASK-223a) from today's water data: the river lines of FeatureRibbonPlanner,
## the surface levels of RiverChannel, the drawn ground of TerrainSurface, the water tiles of the
## grid (lakes lie on the water plane) and the bridge sites. The one place that knows these
## sources; TASK-223c replaces it with a reader of `WaterNetwork`.
##
## Heights are converted to metres with MapScale and RiverChannel.VERTICAL (the relief is drawn
## that much exaggerated against the metres, like the channel depth). Rivers too narrow for a
## channel (RiverChannel.build's `min_water_m`) are left out: they are not dug, so there is no
## surface to check.


## The sample of `grid` as drawn over `surface` (null `surface` channel = ground without channels).
static func build(grid: HexGrid, surface: TerrainSurface) -> WaterSample:
	var sample := WaterSample.new()
	if not grid.has_links():
		return sample
	var lines := FeatureRibbonPlanner.lines(grid, FeatureRibbonPlanner.Kind.RIVER)
	var waters := FeatureRibbonPlanner.water_widths(grid)
	for li in lines.size():
		var reach := _reach(lines[li], waters[li], surface)
		if reach != null:
			sample.reaches.append(reach)
	sample.ground = func(x: float, z: float) -> float: return to_metres(surface.height_at(x, z))
	sample.lake_at = func(p: Vector2) -> float: return _lake_level(grid, p)
	for site in BridgeSites.find(grid):
		sample.bridges.append({"position": site["position"], "span_m": site["span_m"]})
	return sample


## Height in metres of a world height.
static func to_metres(height: float) -> float:
	return height * MapScale.metres_per_unit / RiverChannel.VERTICAL


static func _reach(
	line: PackedVector2Array, water: PackedFloat32Array, surface: TerrainSurface
) -> WaterSample.Reach:
	var widest := 0.0
	for w in water:
		widest = maxf(widest, w * MapScale.metres_per_unit)
	if line.size() < 2 or widest < 6.0:
		return null
	var heights := PackedFloat32Array()
	var frees := PackedFloat32Array()
	for i in line.size():
		heights.append(surface.base_height_at(line[i].x, line[i].y))
		frees.append(
			RiverChannel.depth_units(water[i] * MapScale.metres_per_unit) * RiverChannel.FREEBOARD
		)
	var level := RiverChannel.levels(heights, frees)
	var reach := WaterSample.Reach.new()
	# Downstream is the lower end of the line (RiverChannel digs it that way).
	var reversed := level[0] < level[level.size() - 1]
	for step in line.size():
		var i := line.size() - 1 - step if reversed else step
		reach.points.append(line[i])
		reach.width_m.append(water[i] * MapScale.metres_per_unit)
		reach.level.append(to_metres(level[i]))
	return reach


static func _lake_level(grid: HexGrid, p: Vector2) -> float:
	var c := Hex.from_world(Vector3(p.x, 0.0, p.y), TerrainField.HEX_SIZE)
	if grid.has_tile(c) and grid.get_terrain(c) == Terrain.Type.WATER:
		return to_metres(TerrainSurface.WATER_SURFACE)
	return NAN
