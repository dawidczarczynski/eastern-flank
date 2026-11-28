class_name DevTunables
extends RefCounted
## Live effect tunables of the dev arena (TASK-186a, devtools only): a static store of look values
## (barrage, rocket salvo, impact effects, camera shake) that the arena panel's sliders override
## for the session (no disk saving). The effect code reads it at use (get_value / get_int), so a
## change affects the next attack. Overrides only count while `active` (the arena sets it on enter
## and clears it on leave), so the normal battle and the unit catalog keep the constants.

enum QualityChoice { AUTO, LOW, HIGH }

const BARRAGE_ELEV_MIN := &"barrage_elev_min"
const BARRAGE_ELEV_MAX := &"barrage_elev_max"
const BARRAGE_FULL_DISTANCE := &"barrage_full_distance"
const BARRAGE_COUNT := &"barrage_count"
const BARRAGE_INTERVAL := &"barrage_interval"
const BARRAGE_FLIGHT_BASE := &"barrage_flight_base"
const BARRAGE_FLIGHT_PER_UNIT := &"barrage_flight_per_unit"
const TRACER_SIZE := &"tracer_size"
const LANDING_RADIUS := &"landing_radius"
const SALVO_COUNT := &"salvo_count"
const SALVO_INTERVAL := &"salvo_interval"
const SALVO_FLIGHT_BASE := &"salvo_flight_base"
const SALVO_APEX_BASE := &"salvo_apex_base"
const FIREBALL := &"impact_fireball"
const SMOKE := &"impact_smoke"
const DEBRIS := &"impact_debris"
const DUST_RING := &"impact_dust_ring"
const MUZZLE_FLASH_SIZE := &"muzzle_flash_size"
const CAMERA_SHAKE := &"camera_shake"
const TRACER_INTERVAL := &"tracer_interval"

## Slow motion (Engine.time_scale) while active; 1.0 = normal.
const SLOW_MOTION_MIN := 0.1
const SLOW_MOTION_MAX := 1.0

## Per key: label, default (= the constant it replaces), min, max, step. Order = slider order.
const SPECS := {
	&"barrage_elev_min":
	{"label": "Barrel elevation min", "def": 15.0, "min": 0.0, "max": 85.0, "step": 1.0},
	&"barrage_elev_max":
	{"label": "Barrel elevation max", "def": 65.0, "min": 0.0, "max": 85.0, "step": 1.0},
	&"barrage_full_distance":
	{"label": "Elevation full at (tiles)", "def": 8.0, "min": 1.0, "max": 30.0, "step": 0.5},
	&"barrage_count": {"label": "Barrage shells", "def": 3.0, "min": 1.0, "max": 12.0, "step": 1.0},
	&"barrage_interval":
	{"label": "Barrage interval", "def": 0.5, "min": 0.05, "max": 2.0, "step": 0.05},
	&"barrage_flight_base":
	{"label": "Shell flight base", "def": 0.4, "min": 0.2, "max": 4.0, "step": 0.05},
	&"barrage_flight_per_unit":
	{"label": "Shell flight / distance", "def": 0.04, "min": 0.0, "max": 0.5, "step": 0.01},
	&"tracer_size": {"label": "Tracer size", "def": 0.04, "min": 0.01, "max": 1.0, "step": 0.01},
	&"landing_radius":
	{"label": "Landing disc radius", "def": 0.45, "min": 0.0, "max": 2.0, "step": 0.05},
	&"salvo_count": {"label": "Rocket count", "def": 6.0, "min": 1.0, "max": 12.0, "step": 1.0},
	&"salvo_interval":
	{"label": "Rocket interval", "def": 0.35, "min": 0.05, "max": 2.0, "step": 0.05},
	&"salvo_flight_base":
	{"label": "Rocket flight base", "def": 1.0, "min": 0.2, "max": 4.0, "step": 0.05},
	&"salvo_apex_base":
	{"label": "Rocket apex base", "def": 0.7, "min": 0.0, "max": 4.0, "step": 0.1},
	&"impact_fireball":
	{"label": "Fireball particles", "def": 8.0, "min": 0.0, "max": 30.0, "step": 1.0},
	&"impact_smoke": {"label": "Smoke particles", "def": 5.0, "min": 0.0, "max": 30.0, "step": 1.0},
	&"impact_debris":
	{"label": "Debris particles", "def": 7.0, "min": 0.0, "max": 30.0, "step": 1.0},
	&"impact_dust_ring":
	{"label": "Dust ring particles", "def": 8.0, "min": 0.0, "max": 30.0, "step": 1.0},
	&"muzzle_flash_size":
	{"label": "Muzzle flash size", "def": 0.16, "min": 0.01, "max": 1.0, "step": 0.01},
	&"camera_shake": {"label": "Camera shake", "def": 0.03, "min": 0.0, "max": 0.3, "step": 0.005},
	&"tracer_interval":
	{"label": "Infantry tracer every", "def": 2.0, "min": 1.0, "max": 12.0, "step": 1.0},
}

## Look / performance switches (TASK-186b). Stored for the session like the tunables; the readers
## below honour them only while `active`.
const CAMERA_MIN_FACTOR := 0.5  # unlock camera distance: the minimum distance is halved ...
const CAMERA_MAX_FACTOR := 2.0  # ... and the maximum doubled

## Overrides count only while this is true (set by the arena).
static var active := false

static var quality_choice := QualityChoice.AUTO
## True size is the normal look of the game (rivers, forests, units at real scale); the devtools
## page can switch it off.
static var true_size := true
## Debug run: the devtools page's scale / look switches also apply to normal battles.
static var battle_overrides := false
static var look_name: StringName = LookPreset.DEFAULT_PRESET
static var grid_on := true
static var fps_overlay := false
## Markers at every water error of the battle map (WaterErrorOverlay, TASK-223a).
static var water_errors := false
static var unlock_camera := false

static var _overrides := {}
static var _slow_motion := 1.0


## GraphicsQuality.Level forced by the switch while active, -1 = Auto (command line or detection).
static func quality_override() -> int:
	if not active:
		return -1
	match quality_choice:
		QualityChoice.LOW:
			return GraphicsQuality.Level.LOW
		QualityChoice.HIGH:
			return GraphicsQuality.Level.HIGH
	return -1


## VisualScale preset to show: true size unless the devtools switch is off.
static func scale_preset() -> StringName:
	if true_size:
		return VisualScale.TRUE_PRESET
	return VisualScale.DEFAULT_PRESET


## LookPreset the arena should show (the default one outside the arena).
static func look_preset() -> StringName:
	return look_name if (active or battle_overrides) else LookPreset.DEFAULT_PRESET


static func grid_enabled() -> bool:
	return grid_on or not active


static func camera_min_distance() -> float:
	if active and unlock_camera:
		return CameraMath.MIN_DISTANCE * CAMERA_MIN_FACTOR
	return CameraMath.MIN_DISTANCE


static func camera_max_distance() -> float:
	if active and unlock_camera:
		return CameraMath.MAX_DISTANCE * CAMERA_MAX_FACTOR
	return CameraMath.MAX_DISTANCE


## Puts the stored scale and look into the global presets (arena enter and every live change).
static func apply_look() -> void:
	VisualScale.apply(scale_preset())
	LookPreset.apply(look_preset())


## Keys in slider order.
static func keys() -> Array:
	return SPECS.keys()


static func default_of(key: StringName) -> float:
	return float(SPECS[key]["def"])


## Override of `key` (clamped when set) while active, else the default.
static func get_value(key: StringName) -> float:
	if active and _overrides.has(key):
		return float(_overrides[key])
	return default_of(key)


static func get_int(key: StringName) -> int:
	return roundi(get_value(key))


## True while active and `key` has an override (even one equal to the default).
static func is_overridden(key: StringName) -> bool:
	return active and _overrides.has(key)


## Stores `value` clamped to the key's range; returns the stored value.
static func set_value(key: StringName, value: float) -> float:
	var spec: Dictionary = SPECS[key]
	var clamped := clampf(value, float(spec["min"]), float(spec["max"]))
	_overrides[key] = clamped
	return clamped


static func reset(key: StringName) -> void:
	_overrides.erase(key)


static func reset_all() -> void:
	_overrides.clear()


## Slow motion factor (clamped 0.1..1.0); applied to Engine.time_scale while active.
static func set_slow_motion(factor: float) -> void:
	_slow_motion = clampf(factor, SLOW_MOTION_MIN, SLOW_MOTION_MAX)
	if active:
		Engine.time_scale = _slow_motion


static func slow_motion() -> float:
	return _slow_motion


## The arena enters: overrides count, slow motion applies.
static func activate() -> void:
	active = true
	Engine.time_scale = _slow_motion
	if true_size or look_name != LookPreset.DEFAULT_PRESET:
		apply_look()


## The arena leaves: overrides are ignored again and time runs at normal speed (the values
## themselves are remembered for the session).
static func deactivate() -> void:
	var changed := true_size or look_name != LookPreset.DEFAULT_PRESET
	active = false
	Engine.time_scale = 1.0
	if changed:
		apply_look()  # inactive: back to the defaults
