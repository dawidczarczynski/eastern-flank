class_name RealParcels
extends RefCounted
## The real field parcels of an imported map (TASK-215b, ADR 0032) as the view draws them: the
## OSM polygons of ImportedMap (outer ring, then holes; metres east / south of tile (0, 0)'s
## centre), polygons over RealParcelLook.large_parcel_ha cut perpendicular to their long axis into
## parcels of equal area, each parcel with a hashed key (from the map seed and the polygon id,
## never GameState.rng), a row direction along its long side and, once painted (FieldParcels.bake),
## one crop that no neighbour shares. The open land without a polygon is filled with procedural
## parcels when painted (ParcelFill, `fill_on`). Hedge and track edges become polylines drawn as
## balks (BALK_M / RealParcelLook.track_m wide) that TASK-199 can follow (hedge_lines).
## Pure and deterministic; read-only after construction, so the bake may run on a worker thread.
## Usage: var real := RealParcels.from_imported(map); FieldParcels.bake(..., look, real)

## Share of the parcels whose rows run across their long side instead of along it.
const ROW_ACROSS_CHANCE := 0.2
## Two parcels are neighbours when they touch (or leave a gap of at most NEIGHBOUR_GAP_PX pixels,
## a balk or a narrow track) along at least NEIGHBOUR_CONTACT_PX pixels.
const NEIGHBOUR_GAP_PX := 1
## The edge image (edge_image) has texels of EDGE_TEXEL x the parcel map's; a texel within
## EDGE_RANGE_M of a parcel edge stores the edge line (wide enough for a hedge balk's half width
## and the headland beyond it, plus half a texel's diagonal).
const EDGE_TEXEL := 2
const EDGE_RANGE_M := 15.0
## Row bands the edge image is stamped in on the worker threads.
const EDGE_BANDS := 8
const NEIGHBOUR_CONTACT_PX := 2
## The crops a meadow or orchard polygon chooses from (the ground look, or a lush green when a
## neighbouring meadow already has it); farmland takes the look's crop shares.
const MEADOW_SHARES := {&"meadow": 0.7, &"green": 0.3}
## Salt of the parcel keys (FieldParcels.hash4).
const KEY_SALT := 0x215B

## One dictionary per drawn parcel: {rings: Array[PackedVector2Array] (metres, outer ring first),
## landuse: StringName, id: int (polygon), part: int (0.. after subdivision), key: int,
## angle: float (row direction, radians in [0, PI) from +x towards +z), axis: float (long axis,
## same range), area_m2: float, osm: bool}. The OSM parcels come first (osm_count), then the fill
## parcels paint() adds.
var pieces: Array[Dictionary] = []
var osm_count := 0
## Whether paint() fills the open land without a polygon (ParcelFill): on for an imported map,
## off for from_polygons (tests of given polygons).
var fill_on := false
var settings: RealParcelLook
var seed := 0
## Polylines (metres) along the hedge edges, one per run of consecutive hedge edges of a ring;
## a closed run repeats its first point at the end. Shared edges are listed once.
var hedge_lines: Array[PackedVector2Array] = []
## The same for the track edges.
var track_lines: Array[PackedVector2Array] = []
## Every edge of the fill parcels once (ParcelFill), stamped instead of their rings.
var fill_edges: Array[PackedVector2Array] = []
## The hedges of the OSM edges (the fill's are appended to hedge_lines by paint()).
var _osm_hedge_count := 0


## The parcels of `map` (null when it has none). `seed_value` defaults to a hash of the map id.
## Metres are converted to the view's metres (MapScale.metres_per_unit per world unit).
static func from_imported(map: ImportedMap, seed_value: int = -1) -> RealParcels:
	if map == null or not map.has_parcels():
		return null
	var k := MapScale.metres_per_unit / map.metres_per_world_unit()
	var polygons: Array[Dictionary] = []
	for i in map.parcel_count():
		var rings: Array[PackedVector2Array] = []
		for ring in map.parcel_polygon(i):
			rings.append(Transform2D.IDENTITY.scaled(Vector2(k, k)) * ring)
		(
			polygons
			. append(
				{
					"rings": rings,
					"edges": map.parcel_edge_kinds(i),
					"landuse": map.parcel_landuse(i),
					"id": i,
				}
			)
		)
	var s := seed_value if seed_value >= 0 else String(map.id).hash() & 0x7FFFFFFF
	var result := from_polygons(polygons, s, k)
	result.fill_on = true
	return result


## Parcels from `polygons` ([{rings, edges (optional, PARCEL_EDGE_* per vertex and ring),
## landuse (optional, &"farmland"), id (optional, the index)}]); `metres_scale` = view metres per
## real metre (the subdivision threshold is in real hectares).
static func from_polygons(
	polygons: Array,
	seed_value: int = 0,
	metres_scale: float = 1.0,
	look_settings: RealParcelLook = null
) -> RealParcels:
	var result := RealParcels.new()
	result.settings = look_settings if look_settings != null else RealParcelLook.load_default()
	result.seed = seed_value
	var seen := {}
	var max_m2 := result.settings.large_parcel_ha * 10000.0 * metres_scale * metres_scale
	for index in polygons.size():
		var polygon: Dictionary = polygons[index]
		var rings: Array[PackedVector2Array] = []
		rings.assign(polygon["rings"])
		var id: int = polygon.get("id", index)
		var landuse: StringName = polygon.get("landuse", &"farmland")
		var parts := subdivide(rings, max_m2)
		for part in parts.size():
			var piece_rings: Array[PackedVector2Array] = parts[part]
			var key := FieldParcels.hash4(seed_value, id, part, KEY_SALT)
			(
				result
				. pieces
				. append(
					{
						"rings": piece_rings,
						"landuse": landuse,
						"id": id,
						"part": part,
						"key": key,
						"angle": row_angle(piece_rings[0], key),
						"axis": _axis_angle(long_axis(piece_rings[0])),
						"area_m2": area(piece_rings),
						"osm": true,
					}
				)
			)
		var edges: Array = polygon.get("edges", [])
		for r in mini(rings.size(), edges.size()):
			result.hedge_lines.append_array(
				_runs(rings[r], edges[r], ImportedMap.PARCEL_EDGE_HEDGE, seen)
			)
			result.track_lines.append_array(
				_runs(rings[r], edges[r], ImportedMap.PARCEL_EDGE_TRACK, seen)
			)
	result.osm_count = result.pieces.size()
	result._osm_hedge_count = result.hedge_lines.size()
	return result


static func _axis_angle(axis: Vector2) -> float:
	return fposmod(atan2(axis.y, axis.x), PI)


## The row direction of a parcel with outer ring `outer`: its long side (min-area rectangle),
## turned by 90 degrees for ROW_ACROSS_CHANCE of the keys; radians in [0, PI).
static func row_angle(outer: PackedVector2Array, key: int) -> float:
	var axis := long_axis(outer)
	if FieldParcels.unit_hash(key, 13, 0, 0) < ROW_ACROSS_CHANCE:
		axis = Vector2(-axis.y, axis.x)
	return _axis_angle(axis)


## Area (m²) of a polygon: the outer ring minus its holes.
static func area(rings: Array[PackedVector2Array]) -> float:
	if rings.is_empty():
		return 0.0
	var total := absf(_signed_area(rings[0]))
	for i in range(1, rings.size()):
		total -= absf(_signed_area(rings[i]))
	return maxf(total, 0.0)


## Unit vector of the long side of the minimum-area rectangle around `ring` (+x for a degenerate
## ring); for a square the first hull edge decides.
static func long_axis(ring: PackedVector2Array) -> Vector2:
	var hull := Geometry2D.convex_hull(ring)
	var best_area := INF
	var best := Vector2.RIGHT
	for i in hull.size() - 1:
		var d := hull[i + 1] - hull[i]
		if d.length_squared() < 1e-6:
			continue
		var u := d.normalized()
		var v := Vector2(-u.y, u.x)
		var u0 := INF
		var u1 := -INF
		var v0 := INF
		var v1 := -INF
		for p in hull:
			u0 = minf(u0, p.dot(u))
			u1 = maxf(u1, p.dot(u))
			v0 = minf(v0, p.dot(v))
			v1 = maxf(v1, p.dot(v))
		var a := (u1 - u0) * (v1 - v0)
		if a < best_area - 1e-3:
			best_area = a
			best = u if u1 - u0 >= v1 - v0 - 1e-6 else v
	return best


## `rings` cut perpendicular to the long axis of its outer ring into ceil(area / max_m2) pieces of
## equal area (each an Array[PackedVector2Array], outer ring first); the polygon itself when it is
## not larger than max_m2.
static func subdivide(rings: Array[PackedVector2Array], max_m2: float) -> Array:
	var total := area(rings)
	if total <= max_m2 or rings.is_empty():
		return [rings]
	var count := ceili(total / max_m2)
	var axis := long_axis(rings[0])
	var t0 := INF
	var t1 := -INF
	for p in rings[0]:
		t0 = minf(t0, p.dot(axis))
		t1 = maxf(t1, p.dot(axis))
	var cuts := PackedFloat64Array([t0])
	for n in range(1, count):
		var target := total * n / count
		var lo := cuts[cuts.size() - 1]
		var hi := t1
		for _i in 48:
			var mid := 0.5 * (lo + hi)
			if _area_below(rings, axis, mid) < target:
				lo = mid
			else:
				hi = mid
		cuts.append(0.5 * (lo + hi))
	cuts.append(t1)
	var result: Array = []
	for n in count:
		var piece: Array[PackedVector2Array] = []
		for r in rings.size():
			var clipped := clip_half_plane(
				clip_half_plane(rings[r], axis, cuts[n], false), axis, cuts[n + 1], true
			)
			if clipped.size() >= 3 and absf(_signed_area(clipped)) > 1e-3:
				piece.append(clipped)
			elif r == 0:
				break
		if not piece.is_empty():
			result.append(piece)
	return result


## Kind of a neighbour graph colouring: the crop (FieldParcels.Kind) of every piece, so that no
## two neighbours (`neighbours`, piece indices per piece) share one when the shares allow it.
## Farmland chooses by `shares` ({kind name: share}), meadows and orchards by MEADOW_SHARES (then
## by `shares` when both are taken). Smallest-last order: a planar neighbour graph needs at most
## six crops. Deterministic (piece keys, index ties).
func assign_crops(neighbours: Array[PackedInt32Array], shares: Dictionary) -> PackedInt32Array:
	var count := pieces.size()
	var crops := PackedInt32Array()
	crops.resize(count)
	crops.fill(-1)
	for i in _smallest_last(neighbours):
		var banned: Array[int] = []
		for n in neighbours[i]:
			if crops[n] >= 0 and not banned.has(crops[n]):
				banned.append(crops[n])
		var key: int = pieces[i]["key"]
		var own := shares if pieces[i]["landuse"] == &"farmland" else MEADOW_SHARES
		var crop := FieldParcels.pick(key, own, banned)
		if banned.has(crop):
			crop = FieldParcels.pick(key, shares, banned)
		crops[i] = crop
	return crops


## Rasterises the pieces into `map` (ParcelMap of FieldParcels.bake, any strips already painted):
## first the open land is filled (ParcelFill, when `fill_on`; `look` = the land cover or null),
## then the image becomes RGB8 with blue = 1 + row angle (FieldParcels.angle_code) and green =
## variation id * 2 + 1 for an OSM parcel (0 for a fill parcel); the OSM parcels are painted over
## the fill. The exact edges (and the hedge / track balks on them) go to map.edges (edge_image).
## Fills map.real / real_crops / real_neighbours.
func paint(map: ParcelMap, shares: Dictionary, look: CoverLook = null) -> void:
	var image := map.image
	if image.get_format() != Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGB8)
	var width := image.get_width()
	var height := image.get_height()
	if fill_on and pieces.size() == osm_count:
		_add_fill(Rect2(map.origin_m, Vector2(width, height) * map.metres_per_pixel), look)
	var rows: Array[PackedInt32Array] = []
	rows.resize(height)
	# The pixel spans of every piece on the worker threads, in chunks.
	var spans: Array[PackedInt32Array] = []
	spans.resize(pieces.size())
	var chunk := 64
	var origin := map.origin_m
	var mpp := map.metres_per_pixel
	var task := func(c: int) -> void:
		for i in range(c * chunk, mini(pieces.size(), (c + 1) * chunk)):
			spans[i] = _spans(pieces[i]["rings"], origin, mpp, width, height)
	var chunks := ceili(float(pieces.size()) / chunk)
	var group := WorkerThreadPool.add_group_task(task, chunks, -1, true, "Parcel spans")
	WorkerThreadPool.wait_for_group_task_completion(group)
	for i in pieces.size():
		var own := spans[i]
		for s in range(0, own.size(), 3):
			var row := rows[own[s]]
			row.append(own[s + 1])
			row.append(own[s + 2])
			row.append(i)
			rows[own[s]] = row
	var neighbours := neighbours_of(rows, pieces.size())
	var crops := assign_crops(neighbours, shares)
	# The fill first, the OSM parcels over it.
	var order := range(osm_count, pieces.size()) + range(osm_count)
	for i: int in order:
		var key: int = pieces[i]["key"]
		var colour := Color(
			crops[i] / 255.0,
			(((key >> 8) & 127) * 2 + (1 if i < osm_count else 0)) / 255.0,
			FieldParcels.angle_code(pieces[i]["angle"]) / 255.0
		)
		var own := spans[i]
		for s in range(0, own.size(), 3):
			image.fill_rect(Rect2i(own[s + 1], own[s], own[s + 2] - own[s + 1], 1), colour)
	map.edges = edge_image(map.origin_m, map.metres_per_pixel, width, height, image.get_data())
	map.real = self
	map.real_crops = crops
	map.real_neighbours = neighbours


## Appends the fill parcels (ParcelFill) over `rect_m` and their hedges.
func _add_fill(rect_m: Rect2, look: CoverLook) -> void:
	var axes: Array = []
	for i in osm_count:
		var ring: PackedVector2Array = pieces[i]["rings"][0]
		var c := Vector2.ZERO
		for p in ring:
			c += p
		axes.append([c / maxi(ring.size(), 1), pieces[i]["axis"]])
	var fill := ParcelFill.make(rect_m, axes, look, settings, seed)
	for polygon: Dictionary in fill["polygons"]:
		var rings: Array[PackedVector2Array] = polygon["rings"]
		var key := FieldParcels.hash4(seed, polygon["id"], 0, KEY_SALT)
		var axis := Vector2(cos(polygon["axis"]), sin(polygon["axis"]))
		if FieldParcels.unit_hash(key, 13, 0, 0) < ROW_ACROSS_CHANCE:
			axis = Vector2(-axis.y, axis.x)
		(
			pieces
			. append(
				{
					"rings": rings,
					"landuse": polygon["landuse"],
					"id": polygon["id"],
					"part": 0,
					"key": key,
					"angle": _axis_angle(axis),
					"axis": polygon["axis"],
					"area_m2": area(rings),
					"osm": false,
				}
			)
		)
	hedge_lines.append_array(fill["hedges"])
	fill_edges = fill["edges"]


## Neighbour lists from the parcel spans per pixel row (`rows[y]` = [x0, x1, piece, ...], x1
## exclusive): pieces whose spans touch or lie at most NEIGHBOUR_GAP_PX apart, along x within a
## row or along z between rows up to NEIGHBOUR_GAP_PX + 1 apart, on NEIGHBOUR_CONTACT_PX pixels.
static func neighbours_of(rows: Array[PackedInt32Array], count: int) -> Array[PackedInt32Array]:
	var contacts := {}
	var sorted_rows: Array[Array] = []
	for row in rows:
		# Sorted by x0 through packed keys (x0, then the span's place): no sort callback.
		var keys := PackedInt64Array()
		for s in range(0, row.size(), 3):
			keys.append(row[s] * 1048576 + s)
		keys.sort()
		var spans: Array = []
		for key in keys:
			var s := key % 1048576
			spans.append(Vector3i(row[s], row[s + 1], row[s + 2]))
		sorted_rows.append(spans)
	for y in sorted_rows.size():
		var spans: Array = sorted_rows[y]
		for s in range(1, spans.size()):
			var a: Vector3i = spans[s - 1]
			var b: Vector3i = spans[s]
			if a.z != b.z and b.x - a.y <= NEIGHBOUR_GAP_PX:
				_touch(contacts, a.z, b.z, 1)
		for dy in range(1, NEIGHBOUR_GAP_PX + 2):
			if y + dy >= sorted_rows.size():
				break
			var below: Array = sorted_rows[y + dy]
			var j := 0
			for a: Vector3i in spans:
				while j < below.size() and (below[j] as Vector3i).y <= a.x:
					j += 1
				var k := j
				while k < below.size() and (below[k] as Vector3i).x < a.y:
					var b: Vector3i = below[k]
					if a.z != b.z:
						_touch(contacts, a.z, b.z, mini(a.y, b.y) - maxi(a.x, b.x))
					k += 1
	var result: Array[PackedInt32Array] = []
	result.resize(count)
	for pair: Vector2i in contacts:
		if contacts[pair] >= NEIGHBOUR_CONTACT_PX:
			var first := result[pair.x]
			first.append(pair.y)
			result[pair.x] = first
			var second := result[pair.y]
			second.append(pair.x)
			result[pair.y] = second
	for i in count:
		var sorted := result[i]
		sorted.sort()
		result[i] = sorted
	return result


static func _touch(contacts: Dictionary, a: int, b: int, amount: int) -> void:
	var pair := Vector2i(mini(a, b), maxi(a, b))
	contacts[pair] = int(contacts.get(pair, 0)) + amount


## Piece indices in smallest-last order (reversed: the piece removed last comes first): bucket
## queue by degree, deterministic (each bucket is a stack in index order).
static func _smallest_last(neighbours: Array[PackedInt32Array]) -> PackedInt32Array:
	var count := neighbours.size()
	var degree := PackedInt32Array()
	degree.resize(count)
	var buckets: Array[PackedInt32Array] = []
	var max_degree := 0
	for i in count:
		degree[i] = neighbours[i].size()
		max_degree = maxi(max_degree, degree[i])
	buckets.resize(max_degree + 1)
	for i in range(count - 1, -1, -1):
		var bucket := buckets[degree[i]]
		bucket.append(i)
		buckets[degree[i]] = bucket
	var removed := PackedByteArray()
	removed.resize(count)
	var order := PackedInt32Array()
	var d := 0
	while order.size() < count:
		d = maxi(d - 1, 0)
		while buckets[d].is_empty():
			d += 1
		var bucket := buckets[d]
		var best := bucket[bucket.size() - 1]
		bucket.resize(bucket.size() - 1)
		buckets[d] = bucket
		if removed[best] == 1 or degree[best] != d:
			continue  # a stale entry
		removed[best] = 1
		order.append(best)
		for n in neighbours[best]:
			if removed[n] == 0:
				degree[n] -= 1
				var lower := buckets[degree[n]]
				lower.append(n)
				buckets[degree[n]] = lower
	order.reverse()
	return order


## Pixel spans [y, x0, x1 (exclusive), ...] of the pixels whose centre lies inside `rings`
## (even-odd rule, so holes and the zero-width seams of a clipped ring drop out).
static func _spans(
	rings: Array[PackedVector2Array], origin_m: Vector2, mpp: float, width: int, height: int
) -> PackedInt32Array:
	var px_rings: Array[PackedVector2Array] = []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for ring in rings:
		var pts := PackedVector2Array()
		for p in ring:
			var q := (p - origin_m) / mpp
			pts.append(q)
			lo = lo.min(q)
			hi = hi.max(q)
		px_rings.append(pts)
	var result := PackedInt32Array()
	var y0 := maxi(0, ceili(lo.y - 0.5))
	var y1 := mini(height - 1, floori(hi.y - 0.5))
	var xs := PackedFloat64Array()
	for y in range(y0, y1 + 1):
		var yc := y + 0.5
		xs.clear()
		for pts in px_rings:
			var n := pts.size()
			for i in n:
				var a := pts[i]
				var b := pts[(i + 1) % n]
				if (a.y <= yc) != (b.y <= yc):
					xs.append(a.x + (yc - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for s in range(0, xs.size() - 1, 2):
			var x0 := maxi(0, ceili(xs[s] - 0.5))
			var x1 := mini(width, ceili(xs[s + 1] - 0.5))
			if x1 > x0:
				result.append(y)
				result.append(x0)
				result.append(x1)
	return result


## The exact parcel edges as an RGB8 image of EDGE_TEXEL x coarser texels than the parcel map
## (ParcelMap.edges, read by
## ParcelMap.label_at_metres and the shader's parcel_label): every texel whose centre lies within
## EDGE_RANGE_M of a parcel edge holds the nearest edge as a line – red = 1 + its direction
## (angle code, FieldParcels.angle_code), green = the texel centre's signed distance to it
## (-EDGE_RANGE_M .. EDGE_RANGE_M over 0..255, along the normal (-sin, cos)), blue = 1 + its
## PARCEL_EDGE_* kind (tracks and hedges win over a plain edge lying on them). 0 = no edge near.
## So the drawn edge is the straight polygon edge, not the 5 m texel steps. The edges of the fill
## (and its hedges) are left out on texels of an OSM parcel (`label`: the painted RGB8 bytes,
## green bit 0), which is painted over them.
func edge_image(
	origin_m: Vector2, mpp: float, label_width: int, label_height: int, label := PackedByteArray()
) -> Image:
	var width := ceili(float(label_width) / EDGE_TEXEL)
	var height := ceili(float(label_height) / EDGE_TEXEL)
	# Every segment once, in stamping order (plain edges, then tracks, then hedges win ties).
	var segments := PackedVector2Array()
	var codes := PackedByteArray()
	var filtered := PackedByteArray()  # 1: left out under an OSM parcel (fill lines)
	for i in osm_count:
		for ring: PackedVector2Array in pieces[i]["rings"]:
			var n := ring.size()
			for k in n:
				_add_segment(segments, codes, filtered, ring[k], ring[(k + 1) % n], 1, 0)
	for line in fill_edges:
		_add_segment(segments, codes, filtered, line[0], line[1], 1, 1)
	for line in track_lines:
		for k in line.size() - 1:
			_add_segment(segments, codes, filtered, line[k], line[k + 1], 2, 0)
	for j in hedge_lines.size():
		var line := hedge_lines[j]
		for k in line.size() - 1:
			_add_segment(
				segments,
				codes,
				filtered,
				line[k],
				line[k + 1],
				3,
				1 if j >= _osm_hedge_count else 0
			)
	# Row bands on the worker threads, each with its own buffers (same result as one pass).
	var edge_mpp := mpp * EDGE_TEXEL
	var bands := EDGE_BANDS
	var band_rows := ceili(float(height) / bands)
	var results: Array = []
	results.resize(bands)
	var task := func(band: int) -> void:
		var row0 := band * band_rows
		var row1 := mini(height, row0 + band_rows)
		var data := PackedByteArray()
		data.resize(width * maxi(row1 - row0, 0) * 3)
		var best := PackedFloat32Array()
		best.resize(width * maxi(row1 - row0, 0))
		best.fill(INF)
		var empty := PackedByteArray()
		for k in codes.size():
			_stamp(
				data,
				label if filtered[k] == 1 else empty,
				label_width,
				width,
				row0,
				row1,
				best,
				segments[2 * k],
				segments[2 * k + 1],
				codes[k],
				origin_m,
				edge_mpp
			)
		results[band] = data
	var group := WorkerThreadPool.add_group_task(task, bands, -1, true, "Parcel edges")
	WorkerThreadPool.wait_for_group_task_completion(group)
	var data := PackedByteArray()
	for band in bands:
		data.append_array(results[band])
	return Image.create_from_data(width, height, false, Image.FORMAT_RGB8, data)


static func _add_segment(
	segments: PackedVector2Array,
	codes: PackedByteArray,
	filtered: PackedByteArray,
	a: Vector2,
	b: Vector2,
	code: int,
	filter: int
) -> void:
	segments.append(a)
	segments.append(b)
	codes.append(code)
	filtered.append(filter)


## Half width (metres) of the balk an edge of image kind `code` (1 + PARCEL_EDGE_*) carries.
static func balk_half_m(code: int) -> float:
	if code == 1 + ImportedMap.PARCEL_EDGE_HEDGE:
		return 0.5 * FieldParcels.BALK_M
	if code == 1 + ImportedMap.PARCEL_EDGE_TRACK:
		return 0.5 * RealParcelLook.load_default().track_m
	return 0.0


## Writes segment a-b (metres) into the edge image where it is the nearest edge so far; a kind
## line (code > 1) also takes texels where it ties with the plain edge it lies on.
static func _stamp(
	data: PackedByteArray,
	label: PackedByteArray,
	label_w: int,
	w: int,
	row0: int,
	row1: int,
	best: PackedFloat32Array,
	a_m: Vector2,
	b_m: Vector2,
	code: int,
	origin_m: Vector2,
	mpp: float
) -> void:
	var a := (a_m - origin_m) / mpp
	var b := (b_m - origin_m) / mpp
	var seg := b - a
	var len2 := seg.length_squared()
	if len2 < 1e-8:
		return
	var angle_code := FieldParcels.angle_code(atan2(seg.y, seg.x))
	# The quantised direction through the segment's midpoint (the shader decodes the same line).
	var theta := FieldParcels.code_angle(angle_code)
	var normal := Vector2(-sin(theta), cos(theta))
	var mid := 0.5 * (a + b)
	var r := EDGE_RANGE_M / mpp
	var x0 := maxi(0, floori(minf(a.x, b.x) - r))
	var x1 := mini(w - 1, ceili(maxf(a.x, b.x) + r))
	var y0 := maxi(row0, floori(minf(a.y, b.y) - r))
	var y1 := mini(row1 - 1, ceili(maxf(a.y, b.y) + r))
	if y1 < y0:
		return
	var slack := 0.05 if code > 1 else -1e-4
	for y in range(y0, y1 + 1):
		var cy := y + 0.5
		var xa := x0
		var xb := x1
		if absf(normal.x) > 1e-3:
			# Only the texels whose centre is within r of the line on this row.
			var base := (cy - mid.y) * normal.y
			var u0 := (-r - base) / normal.x + mid.x - 0.5
			var u1 := (r - base) / normal.x + mid.x - 0.5
			xa = maxi(x0, floori(minf(u0, u1)))
			xb = mini(x1, ceili(maxf(u0, u1)))
		for x in range(xa, xb + 1):
			var cx := x + 0.5
			var t := clampf(((cx - a.x) * seg.x + (cy - a.y) * seg.y) / len2, 0.0, 1.0)
			var dx := cx - (a.x + t * seg.x)
			var dy := cy - (a.y + t * seg.y)
			var dist := sqrt(dx * dx + dy * dy)
			var idx := (y - row0) * w + x
			if dist >= r or dist > best[idx] + slack:
				continue
			if not label.is_empty():
				# The label texel under this texel's centre.
				var lx := mini(x * EDGE_TEXEL + EDGE_TEXEL / 2, label_w - 1)
				var li := ((y * EDGE_TEXEL + EDGE_TEXEL / 2) * label_w + lx) * 3
				if li + 2 < label.size() and label[li + 2] > 0 and (label[li + 1] & 1) == 1:
					continue  # under an OSM parcel
			best[idx] = minf(dist, best[idx])
			var signed := (cx - mid.x) * normal.x + (cy - mid.y) * normal.y
			data[idx * 3] = angle_code
			data[idx * 3 + 1] = clampi(roundi((signed / r * 0.5 + 0.5) * 255.0), 0, 255)
			data[idx * 3 + 2] = code


## Runs of consecutive edges of `kind` around `ring` as polylines; edges already in `seen`
## (undirected, by their end points) are skipped and break a run.
static func _runs(
	ring: PackedVector2Array, kinds: PackedByteArray, kind: int, seen: Dictionary
) -> Array[PackedVector2Array]:
	var n := mini(ring.size(), kinds.size())
	var result: Array[PackedVector2Array] = []
	var take := PackedByteArray()
	take.resize(n)
	for i in n:
		if kinds[i] == kind:
			var a := ring[i]
			var b := ring[(i + 1) % n]
			var key := Vector4(a.x, a.y, b.x, b.y) if a < b else Vector4(b.x, b.y, a.x, a.y)
			if not seen.has(key):
				seen[key] = true
				take[i] = 1
	# Start after an edge that is not taken, so a run is never split at index 0.
	var start := -1
	for i in n:
		if take[i] == 0:
			start = i
			break
	if start < 0:
		var closed := ring.duplicate()
		if n > 0:
			closed.append(ring[0])
			result.append(closed)
		return result
	var current := PackedVector2Array()
	for step in range(1, n + 1):
		var i := (start + step) % n
		if take[i] == 1:
			if current.is_empty():
				current.append(ring[i])
			current.append(ring[(i + 1) % n])
		elif not current.is_empty():
			result.append(current)
			current = PackedVector2Array()
	if not current.is_empty():
		result.append(current)
	return result


## Area of `rings` on the side t = p . axis < `t`.
static func _area_below(rings: Array[PackedVector2Array], axis: Vector2, t: float) -> float:
	var total := 0.0
	for r in rings.size():
		var a := absf(_signed_area(clip_half_plane(rings[r], axis, t, true)))
		total += a if r == 0 else -a
	return total


## Sutherland-Hodgman clip of `ring` to the half plane p . axis <= t (`below`) or >= t.
static func clip_half_plane(
	ring: PackedVector2Array, axis: Vector2, t: float, below: bool
) -> PackedVector2Array:
	var result := PackedVector2Array()
	var n := ring.size()
	if n == 0:
		return result
	var sign := 1.0 if below else -1.0
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var da := sign * (a.dot(axis) - t)
		var db := sign * (b.dot(axis) - t)
		if da <= 0.0:
			if db <= 0.0:
				result.append(b)
			else:
				result.append(a.lerp(b, da / (da - db)))
		elif db <= 0.0:
			result.append(a.lerp(b, da / (da - db)))
			result.append(b)
	return result


static func _signed_area(ring: PackedVector2Array) -> float:
	var n := ring.size()
	var total := 0.0
	for i in n:
		total += ring[i].cross(ring[(i + 1) % n])
	return 0.5 * total
