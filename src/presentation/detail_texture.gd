class_name DetailTexture
extends RefCounted
## Pure generators for the tileable ground detail: a value-noise height map, a grey albedo and a
## tangent-space normal map derived from it. Port of `tileH` / `canvasTex` / `normalTex` in
## docs/design/v2/game_screen.scene.js. Uses the design's hash (TerrainNoise.hash), no RNG.

## Seed of the per-pixel grain in the albedo (the design's `hash(x, y, 5)`).
const _GRAIN_SEED := 5.0


## Height map of `size`² values in [0, 1] (row-major). Octave `o` is value noise on a lattice
## of `periods[o]` cells that wraps around, so the map tiles seamlessly; amplitude 0.55^o.
static func height_map(size: int, periods: Array[int], seed_value: int) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	var total := 0.0
	for o in periods.size():
		var period := periods[o]
		var amplitude := pow(0.55, o)
		total += amplitude
		var lattice := PackedFloat32Array()
		lattice.resize(period * period)
		for j in period:
			for i in period:
				lattice[j * period + i] = TerrainNoise.hash(i, j, seed_value + o * 7)
		for y in size:
			var fy := float(y) / size * period
			var yi := int(fy)
			var yf := fy - yi
			var v := yf * yf * (3.0 - 2.0 * yf)
			var row0 := (yi % period) * period
			var row1 := ((yi + 1) % period) * period
			for x in size:
				var fx := float(x) / size * period
				var xi := int(fx)
				var xf := fx - xi
				var u := xf * xf * (3.0 - 2.0 * xf)
				var x1 := (xi + 1) % period
				var a := lattice[row0 + xi]
				var b := lattice[row0 + x1]
				var c := lattice[row1 + xi]
				var d := lattice[row1 + x1]
				heights[y * size + x] += (
					amplitude * (a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v)
				)
	for i in heights.size():
		heights[i] /= total
	return heights


## Grey albedo (slightly warm) with grain, mipmaps generated. Multiplied with vertex colours.
static func albedo_image(heights: PackedFloat32Array, size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var v := 0.76 + 0.34 * heights[y * size + x]
			v += (TerrainNoise.hash(x, y, _GRAIN_SEED) - 0.5) * 0.06
			img.set_pixel(x, y, Color(minf(v, 1.0), minf(v, 1.0), minf(v * 0.97, 1.0)))
	img.generate_mipmaps()
	return img


## Tangent-space normal map by central differences with wrap-around. OpenGL convention (what
## Godot expects): red = +x, green = towards row 0 (up the image), so a height rising along +x
## tilts the normal to -x (red < 0.5) and one rising towards higher rows tilts it up the image
## (green > 0.5). `strength` scales the slopes.
static func normal_image(heights: PackedFloat32Array, size: int, strength: float) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		var up := ((y + size - 1) % size) * size
		var down := ((y + 1) % size) * size
		for x in size:
			var left := (x + size - 1) % size
			var right := (x + 1) % size
			var dx := (heights[y * size + right] - heights[y * size + left]) * strength
			var dy := (heights[down + x] - heights[up + x]) * strength
			var n := Vector3(-dx, dy, 1.0).normalized()
			img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	img.generate_mipmaps()
	return img
