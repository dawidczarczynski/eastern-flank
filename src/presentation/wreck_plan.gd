class_name WreckPlan
extends RefCounted
## Pure numbers of a destroyed vehicle's death playback and wreck (TASK-065): which units leave a
## wreck, the timeline of the burn / turret / flash over EventQueue.DEATH_DURATION, and the
## deterministic turret offsets (a view-local hash of the unit id, never GameState.rng).

## Seconds into the death: the hull is fully burnt, the turret has finished moving.
const BURN_END := 0.4
const TURRET_START := 0.1
const TURRET_END := 0.4
const FLASH_DURATION := 0.25
const FLASH_ENERGY := 6.0
const FLASH_RANGE := 2.5
const FLASH_COLOR := Color("ffb060")
## Particles of the death burst (fire and smoke).
const BURST_PARTICLES := 20
## Turret knocked askew: yaw and tilt ranges in degrees, lift in model units.
const TURRET_YAW_MIN := 20.0
const TURRET_YAW_MAX := 35.0
const TURRET_TILT_MIN := 6.0
const TURRET_TILT_MAX := 10.0
const TURRET_LIFT := 0.01


## Whether a unit of this definition leaves a wreck: vehicles do, infantry does not.
static func leaves_wreck(definition: UnitDefinition) -> bool:
	return UnitModels.is_vehicle(definition)


## Burnt amount (0..1) `t` seconds into the death.
static func burnt_at(t: float) -> float:
	return clampf(t / BURN_END, 0.0, 1.0)


## Share (0..1) of the turret's final displacement reached `t` seconds into the death.
static func turret_progress(t: float) -> float:
	return smoothstep(TURRET_START, TURRET_END, t)


## Energy of the muzzle-flash-like death flash `t` seconds into the death (linear to 0).
static func flash_energy(t: float) -> float:
	return FLASH_ENERGY * clampf(1.0 - t / FLASH_DURATION, 0.0, 1.0)


## Final turret yaw in radians (+20..35 degrees), deterministic per unit id.
static func turret_yaw(unit_id: int) -> float:
	return deg_to_rad(lerpf(TURRET_YAW_MIN, TURRET_YAW_MAX, _unit_random(unit_id, "yaw")))


## Final turret tilt in radians (6..10 degrees), deterministic per unit id.
static func turret_tilt(unit_id: int) -> float:
	return deg_to_rad(lerpf(TURRET_TILT_MIN, TURRET_TILT_MAX, _unit_random(unit_id, "tilt")))


## Stable pseudo-random value in [0, 1] from the unit id and a salt.
static func _unit_random(unit_id: int, salt: String) -> float:
	return float(("%s:%d" % [salt, unit_id]).hash() % 1000) / 999.0
