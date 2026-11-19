extends RefCounted
## Orthographic silhouettes of triangle meshes and their comparison (TASK-181): rasterises a
## triangle list (metres) into a binary mask for the side / front / top view, computes the IoU of
## two masks, a diff image and the largest mismatch regions. Pure geometry, no rendering; used by
## tools/compare_silhouette.gd (tools/compare_silhouette.sh).
##
## A mask is a PackedByteArray (1 = covered), row-major: `size.x` columns along u, `size.y` rows
## along v, row 0 = the lowest v. Projection (u, v): side = (x, y), front = (z, y), top = (x, z).
## With the model facing +X: side shows the nose at the right, front is seen along the x axis,
## top has z growing downwards in the diff image.

const VIEWS: Array[String] = ["side", "front", "top"]
const COLOR_MATCH := Color("#6b6e66")
const COLOR_EXTRA := Color("#d9453b")  # only in the model
const COLOR_MISSING := Color("#3b82d9")  # only in the reference (the model lacks it)
const COLOR_EMPTY := Color("#2b2d29")
## A mismatch region smaller than this (m^2) is not worth reporting.
const MIN_REGION_AREA := 0.01


## The (u, v) of `point` in `view`.
static func project(point: Vector3, view: String) -> Vector2:
	match view:
		"side":
			return Vector2(point.x, point.y)
		"front":
			return Vector2(point.z, point.y)
	return Vector2(point.x, point.z)


## The frame (origin = lowest (u, v), size in pixels) that covers `bounds` plus `margin` metres.
static func frame(bounds: AABB, view: String, pixel: float, margin: float = 0.2) -> Dictionary:
	var low := project(bounds.position, view)
	var high := project(bounds.end, view)
	var origin := Vector2(minf(low.x, high.x), minf(low.y, high.y)) - Vector2.ONE * margin
	var extent := Vector2(absf(high.x - low.x), absf(high.y - low.y)) + Vector2.ONE * margin * 2.0
	return {
		"origin": origin,
		"pixel": pixel,
		"size": Vector2i(ceili(extent.x / pixel), ceili(extent.y / pixel)),
	}


## The silhouette of the triangle list in `view` inside `frame` (see frame()).
static func rasterize(
	positions: PackedVector3Array, indices: PackedInt32Array, view: String, frame_data: Dictionary
) -> PackedByteArray:
	var size: Vector2i = frame_data["size"]
	var origin: Vector2 = frame_data["origin"]
	var pixel: float = frame_data["pixel"]
	var mask := PackedByteArray()
	mask.resize(size.x * size.y)
	var inverse := 1.0 / pixel
	var projected := PackedVector2Array()
	projected.resize(positions.size())
	for i in positions.size():
		projected[i] = (project(positions[i], view) - origin) * inverse  # in pixels
	for t in range(0, indices.size() - 2, 3):
		_fill_triangle(
			mask, size, projected[indices[t]], projected[indices[t + 1]], projected[indices[t + 2]]
		)
	return mask


static func _fill_triangle(
	mask: PackedByteArray, size: Vector2i, a: Vector2, b: Vector2, c: Vector2
) -> void:
	var low_x := minf(a.x, minf(b.x, c.x))
	var high_x := maxf(a.x, maxf(b.x, c.x))
	var low_y := minf(a.y, minf(b.y, c.y))
	var high_y := maxf(a.y, maxf(b.y, c.y))
	var x0 := maxi(floori(low_x), 0)
	var x1 := mini(floori(high_x), size.x - 1)
	var y0 := maxi(floori(low_y), 0)
	var y1 := mini(floori(high_y), size.y - 1)
	if x1 < x0 or y1 < y0:
		return
	if x0 == x1 and y0 == y1:
		mask[y0 * size.x + x0] = 1
		return
	var cross := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	if absf(cross) < 1.0:
		# A sliver (or an edge-on triangle): walk its edges so that it still leaves a line.
		_draw_edge(mask, size, a, b)
		_draw_edge(mask, size, b, c)
		_draw_edge(mask, size, c, a)
		return
	var inverse := 1.0 / cross
	for y in range(y0, y1 + 1):
		var py := y + 0.5
		for x in range(x0, x1 + 1):
			var px := x + 0.5
			var w0 := ((b.x - px) * (c.y - py) - (b.y - py) * (c.x - px)) * inverse
			var w1 := ((c.x - px) * (a.y - py) - (c.y - py) * (a.x - px)) * inverse
			if w0 >= 0.0 and w1 >= 0.0 and w0 + w1 <= 1.0:
				mask[y * size.x + x] = 1
	# Pixels the centre test misses at the corners still belong to the silhouette.
	_mark(mask, size, a)
	_mark(mask, size, b)
	_mark(mask, size, c)


static func _draw_edge(mask: PackedByteArray, size: Vector2i, a: Vector2, b: Vector2) -> void:
	var steps := maxi(ceili(a.distance_to(b) * 2.0), 1)
	for i in steps + 1:
		_mark(mask, size, a.lerp(b, float(i) / steps))


static func _mark(mask: PackedByteArray, size: Vector2i, point: Vector2) -> void:
	var x := floori(point.x)
	var y := floori(point.y)
	if x >= 0 and y >= 0 and x < size.x and y < size.y:
		mask[y * size.x + x] = 1


static func area_pixels(mask: PackedByteArray) -> int:
	var count := 0
	for value in mask:
		count += value
	return count


## Intersection over union of two masks of the same size (two empty masks: 1.0).
static func iou(a: PackedByteArray, b: PackedByteArray) -> float:
	var inter := 0
	var union := 0
	for i in a.size():
		inter += a[i] & b[i]
		union += a[i] | b[i]
	return 1.0 if union == 0 else float(inter) / union


## The diff image: grey = both, red = only in `model`, blue = only in `reference`. The side and
## front views are flipped so that up is up; each pixel is drawn `zoom` x `zoom` big.
static func diff_image(
	model: PackedByteArray, reference: PackedByteArray, size: Vector2i, view: String, zoom: int = 1
) -> Image:
	var image := Image.create(size.x * zoom, size.y * zoom, false, Image.FORMAT_RGB8)
	var flip := view != "top"
	for y in size.y:
		var row := size.y - 1 - y if flip else y
		for x in size.x:
			var m := model[y * size.x + x]
			var r := reference[y * size.x + x]
			var color := COLOR_EMPTY
			if m == 1 and r == 1:
				color = COLOR_MATCH
			elif m == 1:
				color = COLOR_EXTRA
			elif r == 1:
				color = COLOR_MISSING
			for dy in zoom:
				for dx in zoom:
					image.set_pixel(x * zoom + dx, row * zoom + dy, color)
	return image


## The `count` largest connected regions where the masks differ, largest first: [{"kind":
## "extra" (model only) | "missing" (reference only), "area_m2", "u0", "u1", "v0", "v1" (metres,
## frame coordinates), "thickness_m" (area / longer side of the region's box), "thin_axis":
## "u" | "v"
## (the shorter side of the box)}].
static func mismatch_regions(
	model: PackedByteArray, reference: PackedByteArray, frame_data: Dictionary, count: int = 3
) -> Array[Dictionary]:
	var size: Vector2i = frame_data["size"]
	var origin: Vector2 = frame_data["origin"]
	var pixel: float = frame_data["pixel"]
	var seen := PackedByteArray()
	seen.resize(model.size())
	var found: Array[Dictionary] = []
	for start in model.size():
		if seen[start] == 1 or model[start] == reference[start]:
			continue
		var kind := 1 if model[start] == 1 else 2  # 1 = extra, 2 = missing
		var stack := PackedInt32Array([start])
		seen[start] = 1
		var cells := 0
		var low := Vector2i(size.x, size.y)
		var high := Vector2i(-1, -1)
		while not stack.is_empty():
			var index := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			cells += 1
			var x := index % size.x
			var y := index / size.x
			low = Vector2i(mini(low.x, x), mini(low.y, y))
			high = Vector2i(maxi(high.x, x), maxi(high.y, y))
			for step: Vector2i in [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
			]:
				var nx := x + step.x
				var ny := y + step.y
				if nx < 0 or ny < 0 or nx >= size.x or ny >= size.y:
					continue
				var next := ny * size.x + nx
				if seen[next] == 0 and model[next] != reference[next]:
					var next_kind := 1 if model[next] == 1 else 2
					if next_kind == kind:
						seen[next] = 1
						stack.append(next)
		var area := cells * pixel * pixel
		if area < MIN_REGION_AREA:
			continue
		var width := (high.x - low.x + 1) * pixel
		var height := (high.y - low.y + 1) * pixel
		(
			found
			. append(
				{
					"kind": "extra" if kind == 1 else "missing",
					"area_m2": area,
					"u0": origin.x + low.x * pixel,
					"u1": origin.x + (high.x + 1) * pixel,
					"v0": origin.y + low.y * pixel,
					"v1": origin.y + (high.y + 1) * pixel,
					"thickness_m": area / maxf(width, height),
					"thin_axis": "u" if width < height else "v",
				}
			)
		)
	found.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["area_m2"] > b["area_m2"]
	)
	return found.slice(0, count)


## One line for a region, e.g. "side extra 0.31 m2: x 2.10..3.40 m, h 2.30..2.60 m, model +0.12 m
## high". `mirror_u` (the nose-relative x) is not applied here: coordinates are the frame's.
static func describe_region(region: Dictionary, view: String) -> String:
	var axes := {"side": ["x", "h"], "front": ["z", "h"], "top": ["x", "z"]}[view] as Array
	var words := (
		{"side": ["long", "high"], "front": ["wide", "high"], "top": ["long", "wide"]}[view]
		as Array
	)
	var thin_index := 0 if region["thin_axis"] == "u" else 1
	var sign := 1.0 if region["kind"] == "extra" else -1.0
	return (
		"%s %s %.2f m2: %s %.2f..%.2f m, %s %.2f..%.2f m, model %+.2f m %s"
		% [
			view,
			region["kind"],
			region["area_m2"],
			axes[0],
			region["u0"],
			region["u1"],
			axes[1],
			region["v0"],
			region["v1"],
			sign * region["thickness_m"],
			words[thin_index],
		]
	)
