class_name MotionEffects
extends RefCounted
## Pure parameters of the movement effects (TASK-064): track / wheel dust and engine exhaust of
## a driving vehicle. The engine works hardest when it pulls away and when the tracks pivot the
## hull in place, then settles to a thin stream; the cloud it leaves hangs behind for a while.
## Feel constants, not balance; UnitView feeds the numbers to MotionFx.

## Ground speed (world units per second) of a unit moving one tile per EventQueue.SECONDS_PER_TILE.
const FULL_SPEED := 1.73 / EventQueue.SECONDS_PER_TILE
## Dust particles per second at full speed, per unit class (others raise none).
const DUST_BASE := {&"tank": 24.0, &"mlrs": 14.0}
## Exhaust particles per second with the engine at cruise (load 0) and at full load.
const EXHAUST_CRUISE := {&"tank": 3.0, &"mlrs": 2.0}
const EXHAUST_PEAK := {&"tank": 45.0, &"mlrs": 14.0}
## The pull-away puff fades with this time constant (seconds).
## Size of the dust and exhaust puffs relative to a tank's (wheeled trucks raise less).
const CLOUD_SIZE := {&"tank": 1.0, &"mlrs": 0.55}
const START_DECAY := 1.8
## Heading error (radians) from which the hull counts as pivoting at full load.
const PIVOT_ERROR := 0.8
## How much speed takes away from the turning load: a bend at speed is cheaper than a pivot.
const PIVOT_SPEED_RELIEF := 0.7
const DUST_PLAINS := Color("a39477")
const DUST_FOREST := Color("7d6f58")
const DUST_MUD := Color("5a4a38")
const MUD_FROM := 0.4
const MUD_RATE_FACTOR := 0.4
const NO_DUST := Color(0.0, 0.0, 0.0, 0.0)


## Whether a unit class raises dust and exhaust at all.
static func emits(unit_class: StringName) -> bool:
	return DUST_BASE.has(unit_class)


static func cloud_size(unit_class: StringName) -> float:
	return CLOUD_SIZE.get(unit_class, 1.0)


## Dust particles per second at ground `speed`: proportional up to FULL_SPEED.
static func dust_rate(unit_class: StringName, speed: float) -> float:
	return clampf(speed / FULL_SPEED, 0.0, 1.0) * float(DUST_BASE.get(unit_class, 0.0))


## Dust colour over `terrain` (Terrain.Type); `weights` are the ground layer weights (TerrainSplat)
## under the unit, if known. Water raises none (alpha 0).
static func dust_color(terrain: int, weights := PackedFloat32Array()) -> Color:
	if terrain == Terrain.Type.WATER:
		return NO_DUST
	if terrain == Terrain.Type.MARSH or _is_muddy(weights):
		return DUST_MUD
	return DUST_FOREST if terrain == Terrain.Type.FOREST else DUST_PLAINS


## Multiplier of the dust rate on mud and marsh (spatter, not a cloud).
static func dust_rate_factor(terrain: int, weights := PackedFloat32Array()) -> float:
	return MUD_RATE_FACTOR if terrain == Terrain.Type.MARSH or _is_muddy(weights) else 1.0


## Engine load 0..1: the pull-away puff (`since_start` seconds into the move) or the hull pivoting
## (`heading_error` radians off the way it must go while `speed` is low), whichever is larger.
static func exhaust_load(since_start: float, heading_error: float, speed: float) -> float:
	var start := exp(-maxf(0.0, since_start) / START_DECAY)
	var relief := 1.0 - PIVOT_SPEED_RELIEF * clampf(speed / FULL_SPEED, 0.0, 1.0)
	var pivot := clampf(absf(heading_error) / PIVOT_ERROR, 0.0, 1.0) * relief
	return maxf(start, pivot)


## Exhaust particles per second at engine `load` (0..1).
static func exhaust_rate(unit_class: StringName, load: float) -> float:
	var cruise: float = EXHAUST_CRUISE.get(unit_class, 0.0)
	var peak: float = EXHAUST_PEAK.get(unit_class, 0.0)
	return lerpf(cruise, peak, clampf(load, 0.0, 1.0))


static func _is_muddy(weights: PackedFloat32Array) -> bool:
	return weights.size() > TerrainSplat.MUD and weights[TerrainSplat.MUD] > MUD_FROM
