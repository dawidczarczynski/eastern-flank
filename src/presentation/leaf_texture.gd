class_name LeafTexture
extends RefCounted
## Procedural alpha cards for the tree crowns (TASK-060): `cluster` is a bunch of broad leaves
## radiating from the card centre (birch, oak, alder), `needles` a needle spray along a twig from
## the bottom edge (v = 1) to the top (v = 0) (pine, spruce). Alpha is 0 or 1 (alpha scissor).
## The colour is a neutral grey luminance: the hue comes from the species colour and the
## per-instance variation in foliage.gdshader. Transparent pixels carry the mean leaf grey so
## filtering and mipmaps do not darken or lighten the cut edges.

const CLUSTER_LEAVES := 30
const NEEDLE_SHOOTS := 5
const BACKGROUND := 0.8


## An RGBA8 leaf-cluster card of `size` x `size` pixels with mipmaps.
static func cluster(size: int, seed_value: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var image := _blank(size)
	var n := float(size)
	for i in CLUSTER_LEAVES:
		# Leaf base somewhere around the centre, pointing outwards with some jitter.
		var angle := TAU * (float(i) + rng.randf() * 0.7) / CLUSTER_LEAVES
		var base_r := (0.01 + 0.22 * rng.randf()) * n
		var base := Vector2(n * 0.5, n * 0.5) + Vector2(cos(angle), sin(angle)) * base_r
		var direction := angle + (rng.randf() * 2.0 - 1.0) * 0.9
		var length := (0.22 + 0.1 * rng.randf()) * n
		var width := length * (0.42 + 0.12 * rng.randf())
		var shade := 0.72 + 0.28 * rng.randf()
		_leaf(image, base, Vector2(cos(direction), sin(direction)), length, width, shade)
	image.generate_mipmaps()
	return image


## An RGBA8 needle-spray card of `size` x `size` pixels with mipmaps.
static func needles(size: int, seed_value: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var image := _blank(size)
	var n := float(size)
	for s in NEEDLE_SHOOTS:
		# The main twig, then two side shoots branching off it.
		var start := Vector2(n * 0.5, n * 0.98)
		var bend := (rng.randf() * 2.0 - 1.0) * 0.25
		var side_sign := 1.0 if s % 2 == 1 else -1.0
		var heading := -PI * 0.5 + (0.0 if s == 0 else side_sign * (0.45 + 0.2 * rng.randf()))
		var length := n * (0.9 if s == 0 else 0.42 + 0.12 * rng.randf())
		if s > 0:
			start = Vector2(n * 0.5, n * (0.88 - 0.16 * s + 0.06 * rng.randf()))
		var p := start
		var steps := int(length / 2.0)
		for step in steps:
			var t := float(step) / steps
			var dir := Vector2(cos(heading + bend * t), sin(heading + bend * t))
			p += dir * 2.0
			var needle := (0.14 + 0.08 * rng.randf()) * n * (1.0 - 0.45 * t)
			for side: float in [-1.0, 1.0]:
				var a := heading + bend * t + side * (0.75 + 0.35 * rng.randf())
				var shade := 0.72 + 0.28 * rng.randf()
				_stroke(image, p, Vector2(cos(a), sin(a)), needle, maxf(2.2, n * 0.026), shade)
			_stroke(image, p, dir, 2.5, 2.4, 0.55)
	image.generate_mipmaps()
	return image


## Share of opaque pixels of the top mip level.
static func coverage(image: Image) -> float:
	var opaque := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
	return float(opaque) / (image.get_width() * image.get_height())


static func _blank(size: int) -> Image:
	var image := Image.create(size, size, true, Image.FORMAT_RGBA8)
	image.fill(Color(BACKGROUND, BACKGROUND, BACKGROUND, 0.0))
	return image


## A pointed leaf from `base` along `dir`: half width follows sin(pi t)^0.7, a darker midrib.
static func _leaf(
	image: Image, base: Vector2, dir: Vector2, length: float, width: float, shade: float
) -> void:
	var side := Vector2(-dir.y, dir.x)
	var tip := base + dir * length
	var lo := base.min(tip) - Vector2(width, width)
	var hi := base.max(tip) + Vector2(width, width)
	var size := image.get_width()
	for y in range(maxi(int(lo.y), 0), mini(int(hi.y) + 1, size)):
		for x in range(maxi(int(lo.x), 0), mini(int(hi.x) + 1, size)):
			var d := Vector2(x + 0.5, y + 0.5) - base
			var t := d.dot(dir) / length
			if t < 0.0 or t > 1.0:
				continue
			var across := absf(d.dot(side))
			var half := width * 0.5 * pow(sin(PI * t), 0.7)
			if across > half:
				continue
			var v := shade * (0.88 + 0.12 * t)
			if across < 0.6:
				v *= 0.82
			image.set_pixel(x, y, Color(v, v, v, 1.0))


## A straight stroke of `width` pixels from `from` along `dir` for `length` pixels.
static func _stroke(
	image: Image, from: Vector2, dir: Vector2, length: float, width: float, shade: float
) -> void:
	var to := from + dir * length
	var lo := from.min(to) - Vector2(width, width)
	var hi := from.max(to) + Vector2(width, width)
	var size := image.get_width()
	for y in range(maxi(int(lo.y), 0), mini(int(hi.y) + 1, size)):
		for x in range(maxi(int(lo.x), 0), mini(int(hi.x) + 1, size)):
			var d := Vector2(x + 0.5, y + 0.5) - from
			var t := clampf(d.dot(dir) / length, 0.0, 1.0)
			if d.distance_to(dir * length * t) > width * 0.5 * (1.0 - 0.5 * t):
				continue
			var v := shade * (0.85 + 0.15 * t)
			image.set_pixel(x, y, Color(v, v, v, 1.0))
