class_name DecalTextures
extends RefCounted
## Procedural albedo+alpha images for the ground decals of TASK-058 (GroundMarksView), cached per
## kind and size. Every image has alpha 0 on its outermost pixels so a decal never shows a hard
## box edge. Track marks and tyre marks run along u (the decal's local X); round marks are
## centred. Deterministic: the noise comes from TerrainNoise with fixed seeds.

const TREAD_COLOR := Color("#2e251b")
const TYRE_COLOR := Color("#33291f")
const CRATER_CENTER_COLOR := Color("#2b2219")
const CRATER_RIM_COLOR := Color("#74634a")
const SCORCH_COLOR := Color("#1d1812")

## Soft edge of a revealed texture, as a fraction of its length.
const REVEAL_EDGE := 0.02

static var _cache := {}


## Two parallel tread strips with a chevron grouser pattern, dark brown, soft edges.
static func tread(size: int) -> Image:
	return _cached(&"tread", size, _paint_tread)


## Two narrower, smoother strips with fine transverse lines.
static func tyre(size: int) -> Image:
	return _cached(&"tyre", size, _paint_tyre)


## Dark centre, lighter raised rim ring and soil splatter around it.
static func crater(size: int) -> Image:
	return _cached(&"crater", size, _paint_crater)


## Black-brown blob with a noisy edge.
static func scorch(size: int) -> Image:
	return _cached(&"scorch", size, _paint_scorch)


## Copy of `image` revealed only for u < `cut` (0..1 along the decal's long axis, the travel
## direction of a track mark): the alpha is cut with a short soft edge. The pattern itself is
## unchanged, so a growing track never stretches its treads.
static func revealed(image: Image, cut: float) -> Image:
	var result := image.duplicate() as Image
	if result.has_mipmaps():
		result.clear_mipmaps()
	var width := result.get_width()
	for x in width:
		var factor := clampf((cut - (x + 0.5) / width) / REVEAL_EDGE + 0.5, 0.0, 1.0)
		if factor >= 1.0:
			continue
		for y in result.get_height():
			var c := result.get_pixel(x, y)
			c.a *= factor
			result.set_pixel(x, y, c)
	result.generate_mipmaps()
	return result


static func _cached(kind: StringName, size: int, painter: Callable) -> Image:
	var key := "%s_%d" % [kind, size]
	if not _cache.has(key):
		var image := Image.create(size, size, true, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		painter.call(image, size)
		_clear_border(image, size)
		image.generate_mipmaps()
		_cache[key] = image
	return _cache[key]


static func _clear_border(image: Image, size: int) -> void:
	for i in size:
		for edge in [0, size - 1]:
			image.set_pixel(i, edge, Color(0, 0, 0, 0))
			image.set_pixel(edge, i, Color(0, 0, 0, 0))


static func _noise(u: float, v: float, frequency: float, seed_value: float) -> float:
	return TerrainNoise.value_noise(u * frequency, v * frequency, seed_value)


## 1 inside a strip centred at `centre` (v) of half width `half`, fading to 0 at its edges.
static func _strip(v: float, centre: float, half: float) -> float:
	return 1.0 - smoothstep(half * 0.55, half, absf(v - centre))


## Fade towards the u ends of a strip texture.
static func _ends(u: float) -> float:
	return smoothstep(0.0, 0.07, minf(u, 1.0 - u))


static func _paint_tread(image: Image, size: int) -> void:
	for y in size:
		for x in size:
			var u := (x + 0.5) / size
			var v := (y + 0.5) / size
			var best := 0.0
			var band := 0.0
			for centre in [0.25, 0.75]:
				var strip := _strip(v, centre, 0.23)
				if strip > best:
					best = strip
					# Chevrons: the grouser line bends with the distance from the strip middle.
					var phase := u * 14.0 + absf(v - centre) * 9.0
					band = 1.0 if fposmod(phase, 1.0) < 0.5 else 0.0
			var wear := 0.8 + 0.2 * _noise(u, v, 24.0, 5.0)
			var alpha := best * (0.78 + 0.22 * band) * wear * _ends(u)
			image.set_pixel(x, y, Color(TREAD_COLOR, clampf(alpha, 0.0, 1.0)))


static func _paint_tyre(image: Image, size: int) -> void:
	for y in size:
		for x in size:
			var u := (x + 0.5) / size
			var v := (y + 0.5) / size
			var strip := maxf(_strip(v, 0.25, 0.17), _strip(v, 0.75, 0.17))
			var line := 0.5 + 0.5 * sin(u * TAU * 22.0)
			var wear := 0.85 + 0.15 * _noise(u, v, 30.0, 9.0)
			var alpha := strip * (0.78 + 0.22 * line) * wear * _ends(u)
			image.set_pixel(x, y, Color(TYRE_COLOR, clampf(alpha, 0.0, 1.0)))


static func _paint_crater(image: Image, size: int) -> void:
	for y in size:
		for x in size:
			var u := (x + 0.5) / size
			var v := (y + 0.5) / size
			var dx := u - 0.5
			var dy := v - 0.5
			var angle := atan2(dy, dx)
			# Distance as a fraction of the 0.5 radius, with a ragged outline.
			var r := sqrt(dx * dx + dy * dy) * 2.0
			r *= 0.9 + 0.2 * _noise(cos(angle) * 2.0 + 3.0, sin(angle) * 2.0 + 3.0, 1.0, 11.0)
			var hole := 1.0 - smoothstep(0.35, 0.62, r)
			var rim := exp(-pow((r - 0.72) / 0.12, 2.0))
			var splatter := _noise(u, v, 18.0, 13.0)
			splatter = smoothstep(0.55, 0.8, splatter) * (1.0 - smoothstep(0.7, 1.0, r)) * 0.5
			var color := CRATER_RIM_COLOR.lerp(CRATER_CENTER_COLOR, hole)
			var alpha := maxf(hole * 0.9, maxf(rim * 0.6, splatter))
			alpha *= 1.0 - smoothstep(0.88, 1.0, r)
			image.set_pixel(x, y, Color(color, clampf(alpha, 0.0, 1.0)))


static func _paint_scorch(image: Image, size: int) -> void:
	for y in size:
		for x in size:
			var u := (x + 0.5) / size
			var v := (y + 0.5) / size
			var dx := u - 0.5
			var dy := v - 0.5
			var r := sqrt(dx * dx + dy * dy) * 2.0
			var ragged := _noise(u, v, 9.0, 21.0) * 0.5 + _noise(u, v, 22.0, 23.0) * 0.25
			var edge := 0.62 + ragged * 0.55
			var alpha := (1.0 - smoothstep(edge * 0.45, edge, r)) * 0.85
			alpha *= 1.0 - smoothstep(0.9, 1.0, r)
			var shade := 0.8 + 0.4 * _noise(u, v, 14.0, 25.0)
			image.set_pixel(
				x,
				y,
				Color(SCORCH_COLOR.r * shade, SCORCH_COLOR.g * shade, SCORCH_COLOR.b * shade, alpha)
			)
