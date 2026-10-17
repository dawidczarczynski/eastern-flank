class_name TerrainNoise
extends RefCounted
## Deterministic 2D noise, an exact port of the visual design's helpers
## (docs/design/game_screen.scene.js: hash/vnoise/fbm/ridged/smooth).
## Ported instead of FastNoiseLite so the output can't change between Godot versions.


## Pseudo-random value in [0, 1) for a lattice point and a seed.
## Inside this class call it as `TerrainNoise.hash` – a bare `hash` resolves to the global built-in.
static func hash(x: float, y: float, s: float) -> float:
	var h := sin(x * 127.1 + y * 311.7 + s * 74.7) * 43758.5453
	return h - floorf(h)


## Value noise: smoothstep-interpolated lattice of `hash`.
static func value_noise(x: float, y: float, s: float) -> float:
	var xi := floorf(x)
	var yi := floorf(y)
	var xf := x - xi
	var yf := y - yi
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := yf * yf * (3.0 - 2.0 * yf)
	var a := TerrainNoise.hash(xi, yi, s)
	var b := TerrainNoise.hash(xi + 1.0, yi, s)
	var c := TerrainNoise.hash(xi, yi + 1.0, s)
	var d := TerrainNoise.hash(xi + 1.0, yi + 1.0, s)
	return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v


## Fractal sum of `value_noise`, normalised to [0, 1].
static func fbm(x: float, y: float, s: float = 0.0, octaves: int = 5) -> float:
	var total := 0.0
	var amplitude := 0.5
	var frequency := 1.0
	var norm := 0.0
	for i in octaves:
		total += amplitude * value_noise(x * frequency, y * frequency, s + i * 13)
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2.03
	return total / norm


## Ridged fractal noise (4 octaves), normalised to [0, 1].
static func ridged(x: float, y: float, s: float) -> float:
	var total := 0.0
	var amplitude := 0.5
	var frequency := 1.0
	var norm := 0.0
	for i in 4:
		var n := value_noise(x * frequency, y * frequency, s + i * 7)
		total += amplitude * (1.0 - absf(n * 2.0 - 1.0))
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2.1
	return total / norm


## Clamped smoothstep from `a` to `b`; works with `a > b` (falling edge).
static func smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
