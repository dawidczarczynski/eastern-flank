class_name ParcelFill
extends RefCounted
## Procedural field parcels for the open land the OSM polygons leave out (TASK-215b): on
## Suwałki 71 % of the open land has no land-use polygon. The land is cut into field systems –
## the convex cells of a jittered grid (RealParcelLook.fill_cell_m) – each with one direction (the
## long axis of the nearest OSM parcel, so the fill follows the real field pattern, else hashed),
## recursively split across its longer side into straight-edged parcels of about fill_target_ha.
## A parcel is kept only where some of it lies on land a field can be on (CoverLook.allows_parcel);
## the renderer masks the rest and the OSM parcels are painted over the fill. Some system borders
## and splits are hedges. Pure, deterministic from the seed and the cell index (integer hashes,
## never GameState.rng). Metres in the view's frame (world x MapScale.metres_per_unit).

## Offset of the fill parcels' ids (keys): far above any OSM polygon index.
const ID_BASE := 1000000
const MAX_DEPTH := 14
const SALT := 0x215F


## {polygons: [{rings, landuse, id, axis}], hedges, edges (Array[PackedVector2Array]: every parcel
## edge once – the splits and the field system borders of the systems with a parcel)} over
## `rect_m`.
## `axes` = [[centroid (Vector2), axis angle (radians)], ...] of the OSM parcels (direction
## hints); `look` (or null) decides where a parcel may show.
static func make(
	rect_m: Rect2, axes: Array, look: CoverLook, settings: RealParcelLook, seed_value: int
) -> Dictionary:
	var polygons: Array[Dictionary] = []
	var hedges: Array[PackedVector2Array] = []
	var edges: Array[PackedVector2Array] = []
	var seen := {}
	var s := settings.fill_cell_m
	var first := Vector2i((rect_m.position / s).floor()) - Vector2i.ONE
	var last := Vector2i((rect_m.end / s).floor()) + Vector2i.ONE
	var m := MapScale.metres_per_unit
	for cz in range(first.y, last.y + 1):
		for cx in range(first.x, last.x + 1):
			var cell := Vector2i(cx, cz)
			var site := _site(cell, s, settings.fill_jitter, seed_value)
			if not rect_m.grow(s).has_point(site):
				continue
			var ring := _cell_ring(cell, s, settings.fill_jitter, seed_value)
			if ring.size() < 3:
				continue
			var key := FieldParcels.hash4(seed_value, cx, cz, SALT)
			var angle := _direction(site, axes, 1.5 * s, key)
			var u := Vector2(cos(angle), sin(angle))
			var v := Vector2(-u.y, u.x)
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for p in ring:
				lo = lo.min(Vector2(p.dot(u), p.dot(v)))
				hi = hi.max(Vector2(p.dot(u), p.dot(v)))
			var leaves: Array[Rect2] = []
			var cuts: Array = []
			_split(Rect2(lo, hi - lo), key, 0, settings, leaves, cuts)
			var index := 0
			var kept := polygons.size()
			for leaf in leaves:
				index += 1
				var poly := PackedVector2Array(
					[
						u * leaf.position.x + v * leaf.position.y,
						u * leaf.end.x + v * leaf.position.y,
						u * leaf.end.x + v * leaf.end.y,
						u * leaf.position.x + v * leaf.end.y,
					]
				)
				poly = clip_convex(poly, ring)
				if poly.size() < 3:
					continue
				var rings: Array[PackedVector2Array] = [poly]
				if RealParcels.area(rings) < settings.min_parcel_ha * 10000.0:
					continue
				if look != null and not _shows(poly, look, m):
					continue
				var id := ID_BASE + ((cz - first.y) * (last.x - first.x + 1) + cx - first.x) * 256
				polygons.append(
					{"rings": rings, "landuse": &"farmland", "id": id + index, "axis": angle}
				)
			if polygons.size() == kept:
				continue  # nothing of this field system shows
			for cut: Array in cuts:
				var a: Vector2 = cut[0]
				var b: Vector2 = cut[1]
				var line := clip_segment(u * a.x + v * a.y, u * b.x + v * b.y, ring)
				if line.size() != 2:
					continue
				edges.append(line)
				if FieldParcels.unit_hash(cut[2], 17, 0, 0) < settings.split_hedge_share:
					hedges.append(line)
			for i in ring.size():
				var a := ring[i]
				var b := ring[(i + 1) % ring.size()]
				var ka := (a * 10.0).round()
				var kb := (b * 10.0).round()
				var key4 := (
					Vector4(ka.x, ka.y, kb.x, kb.y) if ka < kb else Vector4(kb.x, kb.y, ka.x, ka.y)
				)
				if not seen.has(key4):
					seen[key4] = true
					edges.append(PackedVector2Array([a, b]))
			hedges.append_array(_system_hedges(cell, ring, s, settings, seed_value))
	return {"polygons": polygons, "hedges": hedges, "edges": edges}


## The jittered site of grid cell `cell`.
static func _site(cell: Vector2i, s: float, jitter: float, seed_value: int) -> Vector2:
	var jx := FieldParcels.unit_hash(seed_value, cell.x, cell.y, SALT + 1) * 2.0 - 1.0
	var jz := FieldParcels.unit_hash(seed_value, cell.x, cell.y, SALT + 2) * 2.0 - 1.0
	return (Vector2(cell) + Vector2(0.5, 0.5) + Vector2(jx, jz) * jitter) * s


## The Voronoi cell of `cell`'s site among its 8 neighbours (convex, counter-clockwise).
static func _cell_ring(
	cell: Vector2i, s: float, jitter: float, seed_value: int
) -> PackedVector2Array:
	var site := _site(cell, s, jitter, seed_value)
	var ring := PackedVector2Array(
		[
			site + Vector2(-2.0, -2.0) * s,
			site + Vector2(2.0, -2.0) * s,
			site + Vector2(2.0, 2.0) * s,
			site + Vector2(-2.0, 2.0) * s
		]
	)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var other := _site(cell + Vector2i(dx, dz), s, jitter, seed_value)
			var axis := (other - site).normalized()
			ring = RealParcels.clip_half_plane(ring, axis, (0.5 * (site + other)).dot(axis), true)
	return ring


## The row direction of a field system at `site`: the axis of the nearest OSM parcel within
## `reach`, else hashed.
static func _direction(site: Vector2, axes: Array, reach: float, key: int) -> float:
	var best := reach * reach
	var angle := FieldParcels.unit_hash(key, 3, 0, 0) * PI
	for entry: Array in axes:
		var d := site.distance_squared_to(entry[0])
		if d < best:
			best = d
			angle = entry[1]
	return angle


## Splits `rect` (u, v frame) across its longer side until it is about the target size; the leaves
## go to `leaves`, every cut as [from (u, v), to (u, v), key] to `cuts`.
static func _split(
	rect: Rect2, key: int, depth: int, settings: RealParcelLook, leaves: Array[Rect2], cuts: Array
) -> void:
	var spread := settings.fill_size_spread * (2.0 * FieldParcels.unit_hash(key, 5, 0, 0) - 1.0)
	var target := settings.fill_target_ha * 10000.0 * (1.0 + spread)
	if rect.get_area() <= target * 1.4 or depth >= MAX_DEPTH:
		leaves.append(rect)
		return
	var f := lerpf(0.3, 0.7, FieldParcels.unit_hash(key, 6, 0, 0))
	var a := Rect2(rect)
	var b := Rect2(rect)
	var cut: Array
	if rect.size.x >= rect.size.y:
		a.size.x = rect.size.x * f
		b.position.x = rect.position.x + a.size.x
		b.size.x = rect.size.x - a.size.x
		cut = [Vector2(b.position.x, rect.position.y), Vector2(b.position.x, rect.end.y), key]
	else:
		a.size.y = rect.size.y * f
		b.position.y = rect.position.y + a.size.y
		b.size.y = rect.size.y - a.size.y
		cut = [Vector2(rect.position.x, b.position.y), Vector2(rect.end.x, b.position.y), key]
	cuts.append(cut)
	_split(a, FieldParcels.hash4(key, depth, 0, SALT), depth + 1, settings, leaves, cuts)
	_split(b, FieldParcels.hash4(key, depth, 1, SALT), depth + 1, settings, leaves, cuts)


## Whether some of `poly` lies on land a field can be on: its centroid or a point halfway to one
## of its corners.
static func _shows(poly: PackedVector2Array, look: CoverLook, m: float) -> bool:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	if look.allows_parcel(c.x / m, c.y / m):
		return true
	for p in poly:
		var q := 0.5 * (c + p)
		if look.allows_parcel(q.x / m, q.y / m):
			return true
	return false


## The hedges on the borders of `cell` shared with a neighbour of a higher index (so each border is
## decided once), with RealParcelLook.system_hedge_share by hash of the pair.
static func _system_hedges(
	cell: Vector2i, ring: PackedVector2Array, s: float, settings: RealParcelLook, seed_value: int
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var site := _site(cell, s, settings.fill_jitter, seed_value)
	var n := ring.size()
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var other_cell := cell + Vector2i(dx, dz)
			if dz < 0 or (dz == 0 and dx <= 0):
				continue  # the neighbour decides
			var key := FieldParcels.hash4(
				seed_value, other_cell.x * 7919 + cell.x, other_cell.y * 7919 + cell.y, SALT + 3
			)
			if FieldParcels.unit_hash(key, 1, 0, 0) >= settings.system_hedge_share:
				continue
			var other := _site(other_cell, s, settings.fill_jitter, seed_value)
			var axis := (other - site).normalized()
			var t := (0.5 * (site + other)).dot(axis)
			for i in n:
				var a := ring[i]
				var b := ring[(i + 1) % n]
				if absf(a.dot(axis) - t) < 0.01 and absf(b.dot(axis) - t) < 0.01:
					result.append(PackedVector2Array([a, b]))
	return result


## `poly` clipped to the convex counter-clockwise or clockwise `hull`.
static func clip_convex(poly: PackedVector2Array, hull: PackedVector2Array) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in hull:
		c += p
	c /= hull.size()
	var result := poly
	var n := hull.size()
	for i in n:
		var a := hull[i]
		var b := hull[(i + 1) % n]
		var normal := Vector2(b.y - a.y, a.x - b.x).normalized()
		if normal.dot(c - a) > 0.0:
			normal = -normal  # outward
		result = RealParcels.clip_half_plane(result, normal, a.dot(normal), true)
		if result.size() < 3:
			return PackedVector2Array()
	return result


## The part of segment a-b inside the convex `hull` ([from, to]), or empty.
static func clip_segment(a: Vector2, b: Vector2, hull: PackedVector2Array) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in hull:
		c += p
	c /= hull.size()
	var t0 := 0.0
	var t1 := 1.0
	var n := hull.size()
	var d := b - a
	for i in n:
		var p := hull[i]
		var q := hull[(i + 1) % n]
		var normal := Vector2(q.y - p.y, p.x - q.x)
		if normal.dot(c - p) > 0.0:
			normal = -normal
		var num := normal.dot(p - a)
		var den := normal.dot(d)
		if absf(den) < 1e-9:
			if num < 0.0:
				return PackedVector2Array()
			continue
		var t := num / den
		if den > 0.0:
			t1 = minf(t1, t)
		else:
			t0 = maxf(t0, t)
		if t0 >= t1:
			return PackedVector2Array()
	return PackedVector2Array([a + d * t0, a + d * t1])
