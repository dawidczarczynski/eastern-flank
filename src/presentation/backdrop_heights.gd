class_name BackdropHeights
extends RefCounted
## Ground height of the non-playable scenery ring around the map (TASK-052). Pure and
## map-independent (no MapGenerator / TerrainField): it continues the height at the nearest
## border point outward, adds low-amplitude deterministic noise that fades in with the distance
## from the edge and eases towards a gentle mean level, so it works for any map, hand-made or not.

## Gentle land level the backdrop settles on far from the map.
const MEAN_LEVEL := 0.35
## How much of the way to MEAN_LEVEL the ground has eased at EASE_DISTANCE and beyond.
const EASE_STRENGTH := 0.6
const EASE_DISTANCE := 12.0
## Noise: peak deviation (world units), the distance over which it fades in, spatial frequency.
const NOISE_AMPLITUDE := 1.1
const NOISE_FADE_DISTANCE := 5.0
const NOISE_FREQUENCY := 0.09
const NOISE_SEED := 137.0


## Height at (x, z) outside (or on the border of) `inner`; the border height comes from
## `surface.height_at` at the nearest point of `inner`. Inside `inner` this is just that height.
static func height_at(surface: TerrainSurface, inner: Rect2, x: float, z: float) -> float:
	var nearest := nearest_border_point(inner, x, z)
	var border := surface.height_at(nearest.x, nearest.y)
	return height(border, distance_outside(inner, x, z), x, z)


## Height from an already known border height and the distance outside the rectangle.
static func height(border_height: float, distance: float, x: float, z: float) -> float:
	if distance <= 0.0:
		return border_height
	var ease_weight := TerrainNoise.smooth(0.0, EASE_DISTANCE, distance) * EASE_STRENGTH
	var base := lerpf(border_height, MEAN_LEVEL, ease_weight)
	var noise := (
		(TerrainNoise.fbm(x * NOISE_FREQUENCY, z * NOISE_FREQUENCY, NOISE_SEED, 3) - 0.5) * 2.0
	)
	return base + noise * NOISE_AMPLITUDE * TerrainNoise.smooth(0.0, NOISE_FADE_DISTANCE, distance)


## The point of `inner` closest to (x, z) (the point itself when inside).
static func nearest_border_point(inner: Rect2, x: float, z: float) -> Vector2:
	return Vector2(
		clampf(x, inner.position.x, inner.end.x), clampf(z, inner.position.y, inner.end.y)
	)


static func distance_outside(inner: Rect2, x: float, z: float) -> float:
	return Vector2(x, z).distance_to(nearest_border_point(inner, x, z))
