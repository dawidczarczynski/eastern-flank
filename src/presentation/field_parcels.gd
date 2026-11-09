class_name FieldParcels
extends RefCounted
## Procedural farmland of real-terrain maps (TASK-108f): the land is cut into rectangular
## parcels – 2.5 km regions, each with one orientation, split into parallel strips of 150-400 m and
## up to 2.5 km long (a few cut in two) – and each parcel is one crop.
## Everything is in metres (world position x MapScale.metres_per_unit) and deterministic from an
## integer hash, never
## GameState.rng, so the map looks the same on every run.
##
## A parcel is farmland when the majority of its area lies on FIELDS tiles (so it spills over
## neighbouring plains and hills, and a field hex partly under forest stays mostly field). bake()
## paints the farmland parcels into a ParcelMap, minus the tiles that can never carry a field
## (forest, water, urban, marsh); the terrain shader draws the crop rows from that image.
## Usage: var map := FieldParcels.bake(grid, hex_size, rect_units); map.kind_at(x, z)

## Parcel kinds, the values of the baked image's red channel. CROPS names them in this order.
enum Kind { NONE, WHEAT, MAIZE, POTATO, GREEN, STUBBLE, PLOUGHED, MEADOW, BALK }
## Names of the kinds (LookPreset.fields() "crops" keys; BALK has its own entry).
const CROPS: Array[StringName] = [
	&"", &"wheat", &"maize", &"potato", &"green", &"stubble", &"ploughed", &"meadow", &"balk"
]
## Kinds that are drawn from the "crops" look data (all but NONE and BALK).
const CROP_KINDS: Array[int] = [
	Kind.WHEAT, Kind.MAIZE, Kind.POTATO, Kind.GREEN, Kind.STUBBLE, Kind.PLOUGHED, Kind.MEADOW
]

const BLOCK_M := 2500.0
const STRIP_MIN_M := 150.0
const STRIP_MAX_M := 400.0
## A strip is cut in two along its length with this chance, at a distance in [CUT_MIN_M, CUT_MAX_M].
const CUT_CHANCE := 0.1
const CUT_MIN_M := 800.0
const CUT_MAX_M := 1700.0
## The unploughed balk (a hedgerow strip) along the first BALK_M of every strip's long side and at
## both of its ends (so a region border is a hedge, not a bare seam).
const BALK_M := 10.0
## Default size of one baked pixel.
const DEFAULT_METRES_PER_PIXEL := 5.0
## Farmland votes of a parcel are taken on a lattice of this spacing.
const SAMPLE_SPACING_M := 40.0
## Strips are judged for farmland in pieces of at most this length.
const SEGMENT_M := 150.0
## A gap of up to this many non-farmland pieces inside a strip is bridged (about one hex).
const GAP_PIECES := 2
## Parcels need at least this share of FIELDS samples to be farmland.
const FARMLAND_SHARE := 0.5

const _MASK := 0xFFFFFFFF


## The kind at (x_m, z_m) if the land there were farmland: a crop (by `shares`, {kind name:
## share}; empty = the active look's shares) or BALK on the edge strip of a parcel.
static func kind(x_m: float, z_m: float, shares: Dictionary = {}) -> int:
	var parcel := parcel_at(x_m, z_m)
	if parcel["balk"]:
		return Kind.BALK
	return crop_of(parcel["key"], shares)


## The parcel under (x_m, z_m): {key, along_x (rows run along x), balk (on the balk strip),
## id (0-127, for per-parcel variation)}.
static func parcel_at(x_m: float, z_m: float) -> Dictionary:
	var bx := floori(x_m / BLOCK_M)
	var bz := floori(z_m / BLOCK_M)
	var lx := x_m - bx * BLOCK_M
	var lz := z_m - bz * BLOCK_M
	var along_x := _along_x(bx, bz)
	var u := lz if along_x else lx
	var v := lx if along_x else lz
	var strip := _strip_at(bx, bz, u)
	var part := 0
	var cut := _cut(bx, bz, strip["index"])
	if cut > 0.0 and v >= cut:
		part = 1
	var key := _hash(bx, bz, 5 + strip["index"], part)
	var v0 := cut if part == 1 else 0.0
	var v1 := cut if part == 0 and cut > 0.0 else BLOCK_M
	return {
		"key": key,
		"along_x": along_x,
		"balk": u - float(strip["start"]) < BALK_M or v - v0 < BALK_M or v1 - v < BALK_M,
		"id": (key >> 8) & 127,
	}


## The crop kind of the parcel with `key`, by the cumulative `shares` in CROP_KINDS order.
static func crop_of(key: int, shares: Dictionary = {}) -> int:
	if shares.is_empty():
		shares = shares_of(LookPreset.fields())
	var roll := _unit(_hash(key, 7, 0, 0))
	var total := 0.0
	for k in CROP_KINDS:
		total += float(shares.get(CROPS[k], 0.0))
	var acc := 0.0
	for k in CROP_KINDS:
		acc += float(shares.get(CROPS[k], 0.0)) / total
		if roll < acc:
			return k
	return CROP_KINDS[CROP_KINDS.size() - 1]


## {kind name: share} from a LookPreset.fields() dictionary.
static func shares_of(look: Dictionary) -> Dictionary:
	var shares := {}
	for name: StringName in look["crops"] as Dictionary:
		shares[name] = look["crops"][name]["share"]
	return shares


## Every parcel of the BLOCK_M region (bx, bz): [{rect: Rect2 in metres, key, along_x}], one per
## strip
## and part (the balk is the first BALK_M of the rect across its length axis).
static func parcels_of_block(bx: int, bz: int) -> Array:
	var result: Array = []
	var along_x := _along_x(bx, bz)
	var edges := _edges(bx, bz)
	for k in edges.size() - 1:
		var cut := _cut(bx, bz, k)
		var spans: Array[Vector2] = [Vector2(0.0, BLOCK_M)]
		if cut > 0.0:
			spans = [Vector2(0.0, cut), Vector2(cut, BLOCK_M)]
		for part in spans.size():
			var u0 := edges[k]
			var u1 := edges[k + 1]
			var v0 := spans[part].x
			var v1 := spans[part].y
			var rect := Rect2(
				Vector2(v0, u0) if along_x else Vector2(u0, v0),
				Vector2(v1 - v0, u1 - u0) if along_x else Vector2(u1 - u0, v1 - v0)
			)
			rect.position += Vector2(bx, bz) * BLOCK_M
			result.append({"rect": rect, "key": _hash(bx, bz, 5 + k, part), "along_x": along_x})
	return result


## Bakes the farmland of `grid` (hex size `hex_size`) over `rect_units` (world units) into a
## ParcelMap, or returns null when the grid has no FIELDS tile (then the terrain shader stays
## off). `shares` as in kind().
static func bake(
	grid: HexGrid,
	hex_size: float,
	rect_units: Rect2,
	metres_per_pixel: float = DEFAULT_METRES_PER_PIXEL,
	shares: Dictionary = {}
) -> ParcelMap:
	var any_field := false
	for c in grid.coords():
		if grid.get_terrain(c) == Terrain.Type.FIELDS:
			any_field = true
			break
	if not any_field:
		return null
	if shares.is_empty():
		shares = shares_of(LookPreset.fields())
	var scale_m := MapScale.metres_per_unit
	var map := ParcelMap.new()
	map.metres_per_pixel = metres_per_pixel
	map.origin_m = rect_units.position * scale_m
	var width := ceili(rect_units.size.x * scale_m / metres_per_pixel)
	var height := ceili(rect_units.size.y * scale_m / metres_per_pixel)
	map.image = Image.create_empty(width, height, false, Image.FORMAT_RG8)
	var bounds := Rect2i(0, 0, width, height)
	var rect_m := Rect2(map.origin_m, Vector2(width, height) * metres_per_pixel)
	var first := Vector2i((rect_m.position / BLOCK_M).floor())
	var last := Vector2i((rect_m.end / BLOCK_M).floor())
	for bx in range(first.x, last.x + 1):
		for bz in range(first.y, last.y + 1):
			for parcel: Dictionary in parcels_of_block(bx, bz):
				var rect: Rect2 = parcel["rect"]
				if not rect.intersects(rect_m):
					continue
				var crop := crop_of(parcel["key"], shares)
				var along_x: bool = parcel["along_x"]
				var green := float(((parcel["key"] >> 8) & 127) * 2 + (1 if along_x else 0)) / 255.0
				# Long strips are judged per SEGMENT_M piece, so a strip runs as far as the farmland
				# does (bridging small gaps) and ends in a straight cut across it.
				var length := rect.size.x if along_x else rect.size.y
				var count := ceili(length / SEGMENT_M)
				var pieces: Array[Rect2] = []
				var flags: Array[bool] = []
				for n in count:
					var piece := Rect2(rect)
					if along_x:
						piece.position.x += n * length / count
						piece.size.x = length / count
					else:
						piece.position.y += n * length / count
						piece.size.y = length / count
					pieces.append(piece)
					flags.append(
						(
							piece.intersects(rect_m)
							and _field_share(grid, hex_size, piece, scale_m) >= FARMLAND_SHARE
						)
					)
				_bridge_gaps(flags)
				for n in count:
					if not flags[n]:
						continue
					var piece := pieces[n]
					map.image.fill_rect(
						_pixels(piece, map.origin_m, metres_per_pixel, bounds),
						Color(crop / 255.0, green, 0.0)
					)
					var balks: Array[Rect2] = [_edge_strip(piece, along_x, false, false)]
					if n == 0 or (not flags[n - 1] and pieces[n - 1].intersects(rect_m)):
						balks.append(_edge_strip(piece, along_x, true, true))
					if n == count - 1 or (not flags[n + 1] and pieces[n + 1].intersects(rect_m)):
						balks.append(_edge_strip(piece, along_x, true, false))
					for balk in balks:
						map.image.fill_rect(
							_pixels(balk, map.origin_m, metres_per_pixel, bounds),
							Color(Kind.BALK / 255.0, green, 0.0)
						)
	_clear_forbidden(map, grid, hex_size, scale_m)
	return map


## Sets false runs of at most GAP_PIECES entries that lie between two true entries.
static func _bridge_gaps(flags: Array[bool]) -> void:
	var i := 0
	while i < flags.size():
		if flags[i]:
			i += 1
			continue
		var j := i
		while j < flags.size() and not flags[j]:
			j += 1
		if i > 0 and j < flags.size() and j - i <= GAP_PIECES:
			for k in range(i, j):
				flags[k] = true
		i = j


## The BALK_M thick strip along a long side (`end` false) or across an end of `piece`; `first`
## picks the start side or end.
static func _edge_strip(piece: Rect2, along_x: bool, end: bool, first: bool) -> Rect2:
	var r := Rect2(piece)
	var across_x := along_x == end  # the strip's thin axis is x
	if across_x:
		if not first and end:
			r.position.x = piece.end.x - BALK_M
		r.size.x = BALK_M
	else:
		if not first and end:
			r.position.y = piece.end.y - BALK_M
		r.size.y = BALK_M
	return r


## Unit hash [0, 1) of four ints (the same hash as the parcels use).
static func unit_hash(a: int, b: int, c: int, d: int) -> float:
	return _unit(_hash(a, b, c, d))


## Whether a tile of `terrain` can never carry a field.
static func is_forbidden(terrain: int) -> bool:
	return (
		terrain == Terrain.Type.FOREST
		or terrain == Terrain.Type.WATER
		or terrain == Terrain.Type.URBAN
		or terrain == Terrain.Type.MARSH
	)


## Share of a parcel's lattice samples that lie on FIELDS tiles.
static func _field_share(grid: HexGrid, hex_size: float, rect: Rect2, scale_m: float) -> float:
	var nx := maxi(1, floori(rect.size.x / SAMPLE_SPACING_M))
	var nz := maxi(1, floori(rect.size.y / SAMPLE_SPACING_M))
	var hits := 0
	for j in nz:
		for i in nx:
			var x := (rect.position.x + (i + 0.5) * rect.size.x / nx) / scale_m
			var z := (rect.position.y + (j + 0.5) * rect.size.y / nz) / scale_m
			var c := Hex.from_world(Vector3(x, 0.0, z), hex_size)
			if grid.has_tile(c) and grid.get_terrain(c) == Terrain.Type.FIELDS:
				hits += 1
	return float(hits) / (nx * nz)


## Pixels whose centre lies inside `rect` (metres), clipped to `bounds`.
static func _pixels(rect: Rect2, origin_m: Vector2, mpp: float, bounds: Rect2i) -> Rect2i:
	var x0 := ceili((rect.position.x - origin_m.x) / mpp - 0.5)
	var x1 := ceili((rect.end.x - origin_m.x) / mpp - 0.5)
	var y0 := ceili((rect.position.y - origin_m.y) / mpp - 0.5)
	var y1 := ceili((rect.end.y - origin_m.y) / mpp - 0.5)
	return bounds.intersection(Rect2i(x0, y0, x1 - x0, y1 - y0))


## Erases the pixels whose centre is on a forbidden tile, one scanline span per hex row.
static func _clear_forbidden(map: ParcelMap, grid: HexGrid, size: float, scale_m: float) -> void:
	var mpp := map.metres_per_pixel
	var bounds := Rect2i(0, 0, map.image.get_width(), map.image.get_height())
	var s := size * scale_m
	var half_w := Hex.SQRT3 * 0.5 * s
	var clear := Color(0.0, 0.0, 0.0)
	for c in grid.coords():
		if not is_forbidden(grid.get_terrain(c)):
			continue
		var centre := Hex.to_world(c, size)
		var cx := centre.x * scale_m - map.origin_m.x
		var cz := centre.z * scale_m - map.origin_m.y
		var y0 := maxi(0, ceili((cz - s) / mpp - 0.5))
		var y1 := mini(bounds.size.y - 1, floori((cz + s) / mpp - 0.5))
		for py in range(y0, y1 + 1):
			var dz := absf((py + 0.5) * mpp - cz)
			var hw := half_w if dz <= s * 0.5 else Hex.SQRT3 * (s - dz)
			var x0 := maxi(0, ceili((cx - hw) / mpp - 0.5))
			var x1 := mini(bounds.size.x, ceili((cx + hw) / mpp - 0.5))
			if x1 > x0:
				map.image.fill_rect(Rect2i(x0, py, x1 - x0, 1), clear)


static func _along_x(bx: int, bz: int) -> bool:
	return (_hash(bx, bz, 1, 0) >> 9) & 1 == 0


## Strip boundaries (offsets across the block, 0 .. BLOCK_M): widths hashed in
## [STRIP_MIN_M, STRIP_MAX_M], the last strip takes the remainder (at least STRIP_MIN_M).
static func _edges(bx: int, bz: int) -> PackedFloat32Array:
	var edges := PackedFloat32Array([0.0])
	var pos := 0.0
	var k := 0
	while true:
		var width := lerpf(STRIP_MIN_M, STRIP_MAX_M, _unit(_hash(bx, bz, 2, k)))
		k += 1
		if pos + width > BLOCK_M - STRIP_MIN_M:
			edges.append(BLOCK_M)
			break
		pos += width
		edges.append(pos)
	return edges


## {index, start} of the strip containing the offset `u` across block (bx, bz).
static func _strip_at(bx: int, bz: int, u: float) -> Dictionary:
	var pos := 0.0
	var k := 0
	while true:
		var width := lerpf(STRIP_MIN_M, STRIP_MAX_M, _unit(_hash(bx, bz, 2, k)))
		if pos + width > BLOCK_M - STRIP_MIN_M or u < pos + width:
			return {"index": k, "start": pos}
		pos += width
		k += 1
	return {}


## Where strip `k` of the block is cut along its length, or -1 if it is not.
static func _cut(bx: int, bz: int, k: int) -> float:
	if _unit(_hash(bx, bz, 3, k)) >= CUT_CHANCE:
		return -1.0
	return lerpf(CUT_MIN_M, CUT_MAX_M, _unit(_hash(bx, bz, 4, k)))


static func _unit(h: int) -> float:
	return float(h & 0xFFFFFF) / 16777216.0


## Integer hash of four ints (32-bit result), the only source of "randomness" here.
static func _hash(a: int, b: int, c: int, d: int) -> int:
	var h := (a * 374761393 + b * 668265263 + c * 2246822519 + d * 3266489917 + 0x9E3779B9) & _MASK
	h = ((h ^ (h >> 15)) * 2246822519) & _MASK
	h = ((h ^ (h >> 13)) * 3266489917) & _MASK
	return (h ^ (h >> 16)) & _MASK
