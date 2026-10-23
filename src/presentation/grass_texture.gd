class_name GrassTexture
extends RefCounted
## Procedural grass-blade alpha card for the grass clumps (TASK-057): a fan of tapered, slightly
## bent blades rooted along the bottom edge. Alpha is 0/1 (alpha scissor). The colour is a neutral
## grey luminance with only a mild root-to-tip ramp: the hue comes from the per-instance colour
## and the root darkening from grass.gdshader. The top row is the blade tip (UV.y = 0), the
## bottom row the root.

const BLADES := 14
const ROOT_COLOR := Color(0.85, 0.85, 0.85)
const TIP_COLOR := Color(1.0, 1.0, 1.0)
const FLOWER_STEMS_MIN := 5
const FLOWER_STEMS_MAX := 7


## An RGBA8 card of `size` x `size` pixels with mipmaps; `seed_value` varies the blade layout.
static func card(size: int, seed_value: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var image := Image.create(size, size, true, Image.FORMAT_RGBA8)
	image.fill(Color(TIP_COLOR, 0.0))
	for b in BLADES:
		var root_x := (0.06 + 0.88 * (float(b) + rng.randf() * 0.8) / BLADES) * size
		var height := (0.45 + 0.55 * rng.randf()) * size
		var half_width := (0.025 + 0.02 * rng.randf()) * size
		var lean := (rng.randf() * 2.0 - 1.0) * 0.14 * size
		var shade := 0.92 + 0.08 * rng.randf()
		var rows := int(height)
		for row in rows:
			var t := float(row) / rows  # 0 root .. 1 tip
			var y := size - 1 - row
			var x_center := root_x + lean * t * t
			var half := maxf(half_width * (1.0 - t), 0.0) + 0.3
			var color := ROOT_COLOR.lerp(TIP_COLOR, clampf(float(row) / size * 1.6, 0.0, 1.0))
			color = Color(color.r * shade, color.g * shade, color.b * shade, 1.0)
			for x in range(
				maxi(int(floor(x_center - half)), 0), mini(int(ceil(x_center + half)), size - 1) + 1
			):
				if absf(x + 0.5 - x_center) <= half:
					image.set_pixel(x, y, color)
	image.generate_mipmaps()
	return image


## A flower card (TASK-070) of `size` x `size` pixels with mipmaps: 5-7 thin stems with a blossom
## disc at each tip in the top 35 % of the card. R = shade (0.6-1.0), G = blossom mask (1 on
## blossoms, 0 on stems), B = 0, A = coverage (0 or 1). grass.gdshader (flower_mode) colours it.
static func flower_card(size: int, seed_value: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var image := Image.create(size, size, true, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var unit := size / 128.0
	var stems := rng.randi_range(FLOWER_STEMS_MIN, FLOWER_STEMS_MAX)
	for b in stems:
		var root_x := (0.1 + 0.8 * (float(b) + rng.randf() * 0.8) / stems) * size
		var radius := (3.0 + 3.0 * rng.randf()) * unit
		var tip_y := radius + 0.29 * rng.randf() * size
		var lean := (rng.randf() * 2.0 - 1.0) * 0.1 * size
		var shade := 0.6 + 0.4 * rng.randf()
		var rows := int(size - 1 - tip_y)
		for row in rows:
			var t := float(row) / rows
			var y := size - 1 - row
			var x_center := root_x + lean * t * t
			for x in range(
				maxi(int(floor(x_center - 1.0)), 0), mini(int(ceil(x_center + 1.0)), size - 1) + 1
			):
				if absf(x + 0.5 - x_center) <= 0.9 * unit + 0.2:
					image.set_pixel(x, y, Color(shade * 0.8, 0.0, 0.0, 1.0))
		var tip_x := root_x + lean
		for y in range(
			maxi(int(floor(tip_y - radius)), 0), mini(int(ceil(tip_y + radius)), size - 1) + 1
		):
			for x in range(
				maxi(int(floor(tip_x - radius)), 0), mini(int(ceil(tip_x + radius)), size - 1) + 1
			):
				if Vector2(x + 0.5 - tip_x, y + 0.5 - tip_y).length() <= radius:
					image.set_pixel(x, y, Color(shade, 1.0, 0.0, 1.0))
	image.generate_mipmaps()
	return image
