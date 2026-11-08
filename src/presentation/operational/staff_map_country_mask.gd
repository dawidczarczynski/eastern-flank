class_name StaffMapCountryMask
extends RefCounted
## Country coverage raster of the staff map (TASK-114): which country each point of the ground
## belongs to, as an RGBA8 image (channel i = country i of ImportedMap.countries, 255 inside),
## drawn by the terrain shader as the political tint. The rule hexes only decide the interior;
## near a real border line the side of that line decides, so the tint follows the drawn border
## and not the hex edges (visuals are realistic, hexes are mechanics). Built once at load.

## World size (hex units) of one raster pixel and the reach of a border line's influence.
const PIXEL := 0.25
const BAND := 0.8
## Most countries one raster carries (one per channel).
const MAX_COUNTRIES := 4

var rect := Rect2()
var image: Image
var _by_coord := {}  # hex -> index into map.countries


## Null when the map has no countries or border lines. `water` is the terrain's water mask
## (StaffMapTerrain) used to fill coast pixels that lie on land but in a hex of no country.
static func build(map: ImportedMap, world_rect: Rect2, water: Image) -> StaffMapCountryMask:
	if map == null or map.countries.is_empty() or map.country_rows.is_empty():
		return null
	var mask := StaffMapCountryMask.new()
	mask.rect = world_rect
	var columns := maxi(ceili(world_rect.size.x / PIXEL), 1)
	var rows := maxi(ceili(world_rect.size.y / PIXEL), 1)
	var by_coord := {}
	for row in map.height:
		for col in map.width:
			var coord := MapGenerator.offset_to_axial(col, row)
			var k := map.countries.find(map.country_at(coord))
			if k >= 0:
				by_coord[coord] = k
	mask._by_coord = by_coord
	var index := PackedInt32Array()
	index.resize(columns * rows)
	for j in rows:
		for i in columns:
			index[j * columns + i] = mask._hex_index(mask._world(i, j))
	mask._follow_borders(map, index, columns, rows)
	mask._fill_coast(index, columns, water)
	var bytes := PackedByteArray()
	bytes.resize(columns * rows * 4)
	for k in index.size():
		if index[k] >= 0 and index[k] < MAX_COUNTRIES:
			bytes[k * 4 + index[k]] = 255
	mask.image = Image.create_from_data(columns, rows, false, Image.FORMAT_RGBA8, bytes)
	return mask


## Country index (into map.countries) at a world point, -1 for none; by the hex it lies in.
func _hex_index(world: Vector2) -> int:
	return _by_coord.get(Hex.from_world(Vector3(world.x, 0.0, world.y), 1.0), -1)


func _world(i: int, j: int) -> Vector2:
	return rect.position + Vector2(i + 0.5, j + 0.5) * PIXEL


## Pixels within BAND of a border segment take the country on their side of the nearest one.
func _follow_borders(map: ImportedMap, index: PackedInt32Array, columns: int, rows: int) -> void:
	var best := PackedFloat32Array()
	best.resize(columns * rows)
	best.fill(BAND)
	for line in map.border_lines:
		for s in line.size() - 1:
			var a := line[s]
			var b := line[s + 1]
			var along := b - a
			var length := along.length()
			if length < 0.000001:
				continue
			var normal := Vector2(-along.y, along.x) / length
			var middle := (a + b) * 0.5
			var left := _hex_index(middle + normal * BAND * 0.75)
			var right := _hex_index(middle - normal * BAND * 0.75)
			if left == right:
				continue  # not a border between two countries here
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(BAND, BAND) - rect.position
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(BAND, BAND) - rect.position
			var i0 := maxi(floori(lo.x / PIXEL), 0)
			var i1 := mini(ceili(hi.x / PIXEL), columns - 1)
			var j0 := maxi(floori(lo.y / PIXEL), 0)
			var j1 := mini(ceili(hi.y / PIXEL), rows - 1)
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var p := _world(i, j)
					var t := clampf((p - a).dot(along) / (length * length), 0.0, 1.0)
					var distance := p.distance_to(a + along * t)
					var k := j * columns + i
					if distance >= best[k]:
						continue
					best[k] = distance
					var side := left if (p - a).dot(normal) >= 0.0 else right
					if side >= 0:
						index[k] = side


## Land pixels in a hex of no country (coast strips) take the nearest country's index.
func _fill_coast(index: PackedInt32Array, columns: int, water: Image) -> void:
	var open: Array[int] = []
	for k in index.size():
		if index[k] >= 0:
			continue
		var world := _world(k % columns, k / columns)
		if water == null or StaffMapTerrain.mask_at(water, rect, world) <= 0.5:
			open.append(k)
	for _pass in 4:
		var found := {}
		for k in open:
			var i := k % columns
			var j := k / columns
			for step in [1, -1, columns, -columns]:
				var n: int = k + step
				if (step == 1 and i == columns - 1) or (step == -1 and i == 0):
					continue
				if n >= 0 and n < index.size() and index[n] >= 0:
					found[k] = index[n]
					break
		for k: int in found:
			index[k] = found[k]
		open = open.filter(func(k: int) -> bool: return index[k] < 0)
