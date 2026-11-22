class_name HexForestMaskSource
extends ForestMaskSource
## The transitional ForestMaskSource (TASK-189): forest where the hex tile is FOREST (so forests
## are hex-edged until TASK-108g's land-cover raster replaces this source), the tile-centre
## clearing (`clearing`, world units; where a unit stands) and the road and river ribbons widened
## by FeatureRibbonPlanner's clearance kept off. Hexes are filled row by row (Image.fill_rect),
## ribbons rasterised segment by segment near forest only: Suwałki takes ~0.1 s.

var clearing := 0.0


func _init(clearing_units: float = 0.0) -> void:
	clearing = clearing_units


func build(grid: HexGrid, area: Rect2, per_unit: float) -> Dictionary:
	var size := ForestMaskSource.mask_size(area, per_unit)
	var forest := Image.create(size.x, size.y, false, Image.FORMAT_L8)
	var keep_off := PackedByteArray()
	keep_off.resize(size.x * size.y)
	var r := TerrainField.HEX_SIZE
	for c in grid.coords():
		if grid.get_terrain(c) != Terrain.Type.FOREST:
			continue
		var w := Hex.to_world(c, r)
		_fill_hex(forest, Vector2(w.x, w.z), r, area, per_unit)
		if clearing > 0.0:
			_disc(keep_off, size, Vector2(w.x, w.z), clearing, area, per_unit)
	if grid.has_links():
		for kind: FeatureRibbonPlanner.Kind in [
			FeatureRibbonPlanner.Kind.ROAD, FeatureRibbonPlanner.Kind.RIVER
		]:
			var lines := FeatureRibbonPlanner.lines(grid, kind)
			var halves := FeatureRibbonPlanner.half_widths(grid, kind)
			var reach_extra := FeatureRibbonPlanner.clearance(kind)
			for n in lines.size():
				var line: PackedVector2Array = lines[n]
				var widths: PackedFloat32Array = halves[n]
				for k in line.size() - 1:
					if not _near_forest(grid, (line[k] + line[k + 1]) * 0.5):
						continue
					var reach := maxf(widths[k], widths[k + 1]) + reach_extra
					_segment(keep_off, size, line[k], line[k + 1], reach, area, per_unit)
	return {
		"forest": forest,
		"keep_off": Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, keep_off),
	}


## Marks the texels whose centre lies in the pointy-top hex at `centre` (size `r`).
static func _fill_hex(
	image: Image, centre: Vector2, r: float, area: Rect2, per_unit: float
) -> void:
	var size := image.get_size()
	var z0 := maxi(0, ceili((centre.y - r - area.position.y) * per_unit - 0.5))
	var z1 := mini(size.y - 1, floori((centre.y + r - area.position.y) * per_unit - 0.5))
	for pz in range(z0, z1 + 1):
		var dz := absf(area.position.y + (pz + 0.5) / per_unit - centre.y)
		var half := Hex.SQRT3 * 0.5 * r if dz <= r * 0.5 else Hex.SQRT3 * (r - dz)
		var x0 := maxi(0, ceili((centre.x - half - area.position.x) * per_unit - 0.5))
		var x1 := mini(size.x - 1, floori((centre.x + half - area.position.x) * per_unit - 0.5))
		if x1 >= x0:
			image.fill_rect(Rect2i(x0, pz, x1 - x0 + 1, 1), Color.WHITE)


static func _disc(
	bytes: PackedByteArray,
	size: Vector2i,
	centre: Vector2,
	radius: float,
	area: Rect2,
	per_unit: float
) -> void:
	_segment(bytes, size, centre, centre, radius, area, per_unit)


## Marks the texels whose centre lies within `reach` of segment a-b.
static func _segment(
	bytes: PackedByteArray,
	size: Vector2i,
	a: Vector2,
	b: Vector2,
	reach: float,
	area: Rect2,
	per_unit: float
) -> void:
	var lo := ((a.min(b) - Vector2.ONE * reach - area.position) * per_unit).floor()
	var hi := ((a.max(b) + Vector2.ONE * reach - area.position) * per_unit).ceil()
	var x0 := maxi(int(lo.x), 0)
	var z0 := maxi(int(lo.y), 0)
	var x1 := mini(int(hi.x), size.x - 1)
	var z1 := mini(int(hi.y), size.y - 1)
	var ab := b - a
	var length_squared := ab.length_squared()
	var reach_squared := reach * reach
	for pz in range(z0, z1 + 1):
		var cz := area.position.y + (pz + 0.5) / per_unit
		for px in range(x0, x1 + 1):
			var c := Vector2(area.position.x + (px + 0.5) / per_unit, cz)
			var t := 0.0
			if length_squared > 0.0:
				t = clampf((c - a).dot(ab) / length_squared, 0.0, 1.0)
			if c.distance_squared_to(a + ab * t) < reach_squared:
				bytes[pz * size.x + px] = 255


## Whether the tile at `p` or a neighbour is forest (only there the ribbons matter).
static func _near_forest(grid: HexGrid, p: Vector2) -> bool:
	var coord := Hex.from_world(Vector3(p.x, 0.0, p.y), TerrainField.HEX_SIZE)
	if grid.has_tile(coord) and grid.get_terrain(coord) == Terrain.Type.FOREST:
		return true
	for n in Hex.neighbors(coord):
		if grid.has_tile(n) and grid.get_terrain(n) == Terrain.Type.FOREST:
			return true
	return false
