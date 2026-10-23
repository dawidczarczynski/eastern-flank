class_name GroundNoise
extends RefCounted
## Pure low-frequency noises the terrain view derives its ground look from (ported from the
## design's terrain colouring, docs/design/game_screen.scene.js): the dry/moist macro patches
## (TerrainSplat dry grass) and the jitter that keeps forest ground from following hex outlines.

## Seeds from the design: macro patches and the jitter offsets in x and z; jitter amplitude.
const _MACRO_SEED := 91.0
const _JITTER_X_SEED := 71.0
const _JITTER_Z_SEED := 72.0
const _JITTER := 0.55
## Fine moisture noise for the plains dirt patches (TerrainSplat): frequency per unit and seed.
const MOISTURE_FREQUENCY := 0.9
const MOISTURE_SEED := 97.0


## Macro noise in [0, 1] at world (x, z): large dry (high) and moist (low) patches.
static func macro_k(x: float, z: float) -> float:
	return TerrainNoise.fbm(x * 0.12 + 5.0, z * 0.12, _MACRO_SEED, 3)


## Jittered world position (x, z) whose tile type decides the forest floor, so forest edges
## don't follow the hex outline exactly.
static func jitter(x: float, z: float) -> Vector2:
	return Vector2(
		x + (TerrainNoise.fbm(x * 0.8, z * 0.8, _JITTER_X_SEED, 2) - 0.5) * _JITTER,
		z + (TerrainNoise.fbm(x * 0.8 + 9.0, z * 0.8, _JITTER_Z_SEED, 2) - 0.5) * _JITTER
	)


## Fine moisture noise in [0, 1] (TerrainSplat dirt patches above DIRT_PATCH_FROM).
static func moisture_k(x: float, z: float) -> float:
	return TerrainNoise.value_noise(x * MOISTURE_FREQUENCY, z * MOISTURE_FREQUENCY, MOISTURE_SEED)


## Tall-grass patch noise in [0, 1] (TASK-070); `meadow` is LookPreset.meadow().
static func patch_k(x: float, z: float, meadow: Dictionary) -> float:
	var f: float = meadow["patch_frequency"]
	return TerrainNoise.fbm(x * f + 13.0, z * f, meadow["patch_seed"], 2)


## Flower cluster noise in [0, 1] (TASK-070).
static func flower_k(x: float, z: float, meadow: Dictionary) -> float:
	var f: float = meadow["flower_frequency"]
	return TerrainNoise.fbm(x * f, z * f + 7.0, meadow["flower_seed"], 2)
