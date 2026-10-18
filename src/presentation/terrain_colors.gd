class_name TerrainColors
extends RefCounted
## Pure per-vertex terrain colour, a port of the design's terrain mesh colouring
## (docs/design/game_screen.scene.js, "terrain mesh"). Colours are mixed in linear space
## like three.js; use with vertex_color_is_srgb = false.

## Water/shore threshold, forest mix, off-map darkening and jitter amplitude from the design.
const _WATER_BELOW := 0.03
const _FOREST_MIX := 0.85
const _OFF_MAP_FACTOR := 0.6
const _JITTER := 0.55
## Noise seeds from the design: colour noise k and the jitter offsets in x and z.
const _K_SEED := 61.0
const _JITTER_X_SEED := 71.0
const _JITTER_Z_SEED := 72.0
## Macro (dry/moist patch) noise seed and strengths from the design.
const _MACRO_SEED := 91.0
const _DRY_STRENGTH := 0.45
const _MOIST_STRENGTH := 0.4

## Palette, converted from the design's sRGB hex values to linear once.
static var _deep := Color("#17323b").srgb_to_linear()
static var _shoal := Color("#5d8778").srgb_to_linear()
static var _sand := Color("#c6b78a").srgb_to_linear()
static var _grass1 := Color("#627c33").srgb_to_linear()
static var _grass2 := Color("#87974b").srgb_to_linear()
static var _forest1 := Color("#46672f").srgb_to_linear()
static var _forest2 := Color("#587a38").srgb_to_linear()
static var _dry := Color("#9c9558").srgb_to_linear()
static var _moist := Color("#4c6a2c").srgb_to_linear()
static var _hill := Color("#837b50").srgb_to_linear()
static var _rock1 := Color("#756e5e").srgb_to_linear()
static var _rock2 := Color("#a29c8f").srgb_to_linear()
static var _snow := Color("#eef0ef").srgb_to_linear()


## Linear colour of a terrain vertex at height `y` with normal Y `normal_y`.
## `k` is the colour noise (see noise_k), `jittered_type` the Terrain.Type of the tile at
## the jittered position (see jitter) or -1 off the map, `on_map` whether the vertex
## itself is on a map tile (off-map vertices are darkened). `mac` is the macro noise (see
## macro_k): high values tint non-forest land dry, low values moist; 0.5 is neutral.
static func color_at(
	y: float, normal_y: float, k: float, jittered_type: int, on_map: bool, mac := 0.5
) -> Color:
	var c: Color
	if y < _WATER_BELOW:
		c = _deep.lerp(_shoal, TerrainNoise.smooth(-0.7, -0.05, y))
		c = c.lerp(_sand, TerrainNoise.smooth(-0.06, 0.03, y))
	else:
		c = _grass1.lerp(_grass2, TerrainNoise.smooth(0.35, 0.7, k))
		if jittered_type == Terrain.Type.FOREST:
			c = c.lerp(_forest1.lerp(_forest2, k), _FOREST_MIX)
		else:
			c = c.lerp(_dry, TerrainNoise.smooth(0.55, 0.75, mac) * _DRY_STRENGTH)
			c = c.lerp(_moist, TerrainNoise.smooth(0.42, 0.28, mac) * _MOIST_STRENGTH)
		c = c.lerp(_sand, TerrainNoise.smooth(0.16, 0.04, y))
		c = c.lerp(_hill, TerrainNoise.smooth(0.6, 1.1, y) * 0.6)
		var rock_weight := minf(
			1.0,
			(
				TerrainNoise.smooth(0.18, 0.42, 1.0 - normal_y)
				+ TerrainNoise.smooth(1.3, 1.8, y) * 0.85
			)
		)
		c = c.lerp(_rock1.lerp(_rock2, k), rock_weight)
		var snow_weight := (
			TerrainNoise.smooth(1.85, 2.15, y + (k - 0.5) * 0.35)
			* TerrainNoise.smooth(0.55, 0.8, normal_y)
		)
		c = c.lerp(_snow, snow_weight)
	var factor := 0.88 + k * 0.24
	if not on_map:
		factor *= _OFF_MAP_FACTOR
	return Color(c.r * factor, c.g * factor, c.b * factor)


## Colour noise `k` in [0, 1] at world (x, z).
static func noise_k(x: float, z: float) -> float:
	return TerrainNoise.fbm(x * 0.35, z * 0.35, _K_SEED, 3)


## Macro noise in [0, 1] at world (x, z): large dry and moist patches on the plains.
static func macro_k(x: float, z: float) -> float:
	return TerrainNoise.fbm(x * 0.12 + 5.0, z * 0.12, _MACRO_SEED, 3)


## Jittered world position (x, z) whose tile type decides forest colouring, so forest
## edges don't follow the hex outline exactly.
static func jitter(x: float, z: float) -> Vector2:
	return Vector2(
		x + (TerrainNoise.fbm(x * 0.8, z * 0.8, _JITTER_X_SEED, 2) - 0.5) * _JITTER,
		z + (TerrainNoise.fbm(x * 0.8 + 9.0, z * 0.8, _JITTER_Z_SEED, 2) - 0.5) * _JITTER
	)
