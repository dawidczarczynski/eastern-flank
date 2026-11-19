class_name SalvoTiming
extends RefCounted
## Pure timing of a rocket launcher's ripple salvo (TASK-074): how many rockets, how far apart,
## how long each flies, which launches / impacts fall into a time window, the flight profile, the
## HP shown after each impact and the landing points. Visual tunables, not balance data. All times
## in seconds at speed 1.

## One rocket per tube; the interval is a look choice (~3-4x faster than the real ripple, so the
## pauses stay visible without the attack dragging).
const PROFILES := {
	&"homar_k": {"count": 12, "interval": 0.50},
	&"bm27_uragan": {"count": 16, "interval": 0.38},
}
const DEFAULT_PROFILE := {"count": 6, "interval": 0.35}
## A barrel-artillery barrage: shells in a row from the one gun, a look choice like the profiles.
const BARRAGE_COUNT := 3
const BARRAGE_INTERVAL := 0.5
## Shells are fast: flight time of a barrage = BASE + PER_UNIT x distance, within MIN..MAX.
const BARRAGE_FLIGHT_BASE := 0.4
const BARRAGE_FLIGHT_PER_UNIT := 0.04
const BARRAGE_FLIGHT_MIN := 0.6
const BARRAGE_FLIGHT_MAX := 1.0
const FLIGHT_BASE := 1.0
const FLIGHT_PER_UNIT := 0.09
const FLIGHT_MIN := 1.1
const FLIGHT_MAX := 2.2
## Time the event keeps playing after the last impact (its flash).
const SETTLE := 0.5
## Fraction of the flight with the motor burning (tail glow); the rocket coasts dark afterwards.
const MOTOR_BURN := 0.4
## Landing disc radius as a fraction of the hex size (inside the target tile).
const LANDING_RADIUS := 0.45


static func _profile(unit_id: StringName) -> Dictionary:
	return PROFILES.get(unit_id, DEFAULT_PROFILE)


## Rockets in one salvo: one per tube (`mouth_count`) when the model has tubes, else the profile's.
static func rocket_count(unit_id: StringName, mouth_count: int) -> int:
	if DevTunables.is_overridden(DevTunables.SALVO_COUNT):
		return DevTunables.get_int(DevTunables.SALVO_COUNT)
	return mouth_count if mouth_count > 0 else int(_profile(unit_id)["count"])


## Seconds between two launches.
static func interval(unit_id: StringName) -> float:
	if DevTunables.is_overridden(DevTunables.SALVO_INTERVAL):
		return DevTunables.get_value(DevTunables.SALVO_INTERVAL)
	return float(_profile(unit_id)["interval"])


## Shells in one barrage and the seconds between two of them (DevTunables-aware).
static func barrage_count() -> int:
	return DevTunables.get_int(DevTunables.BARRAGE_COUNT)


static func barrage_interval() -> float:
	return DevTunables.get_value(DevTunables.BARRAGE_INTERVAL)


## Landing disc radius as a fraction of the hex size.
static func landing_radius() -> float:
	return DevTunables.get_value(DevTunables.LANDING_RADIUS)


## Flight time of every shell of a barrage over the horizontal world `distance`.
static func barrage_flight_time(distance: float) -> float:
	var base := DevTunables.get_value(DevTunables.BARRAGE_FLIGHT_BASE)
	var per_unit := DevTunables.get_value(DevTunables.BARRAGE_FLIGHT_PER_UNIT)
	var t := base + per_unit * distance
	if (
		DevTunables.is_overridden(DevTunables.BARRAGE_FLIGHT_BASE)
		or DevTunables.is_overridden(DevTunables.BARRAGE_FLIGHT_PER_UNIT)
	):
		return clampf(t, 0.2, 6.0)  # a tuned flight is not squeezed into the default range
	return clampf(t, BARRAGE_FLIGHT_MIN, BARRAGE_FLIGHT_MAX)


## Flight time of every rocket of a salvo over the horizontal world `distance`.
static func flight_time(distance: float) -> float:
	var t := DevTunables.get_value(DevTunables.SALVO_FLIGHT_BASE) + FLIGHT_PER_UNIT * distance
	if DevTunables.is_overridden(DevTunables.SALVO_FLIGHT_BASE):
		return clampf(t, 0.2, 6.0)
	return clampf(t, FLIGHT_MIN, FLIGHT_MAX)


static func launch_time(index: int, launch_interval: float) -> float:
	return index * launch_interval


static func impact_time(index: int, launch_interval: float, flight: float) -> float:
	return launch_time(index, launch_interval) + flight


## Salvo phase of the event: first launch to SETTLE after the last impact.
static func salvo_duration(count: int, launch_interval: float, flight: float) -> float:
	return (count - 1) * launch_interval + flight + SETTLE


## Indices whose launch / impact time lies in (t0, t1], ascending: {"launches", "impacts"}
## (Array[int] each). A negative t0 includes time 0. Consecutive windows never skip or repeat one.
static func crossings(
	t0: float, t1: float, count: int, launch_interval: float, flight: float
) -> Dictionary:
	var launches: Array[int] = []
	var impacts: Array[int] = []
	for i in count:
		var launch := launch_time(i, launch_interval)
		if t0 < launch and launch <= t1:
			launches.append(i)
		var impact := launch + flight
		if t0 < impact and impact <= t1:
			impacts.append(i)
	return {"launches": launches, "impacts": impacts}


## Path parameter for the flight-time fraction `s` (clamped to 0..1): an accelerating start while
## the motor burns, then linear. Monotonic, 0 -> 0, 1 -> 1.
static func flight_progress(s: float) -> float:
	var x := clampf(s, 0.0, 1.0)
	return lerpf(x * x, x, smoothstep(0.0, MOTOR_BURN, x))


## HP the target shows after impact `k` (0-based) of `count`: steps from `hp_before` down to exactly
## `target_hp` at the last impact, never increasing.
static func hp_after_impact(hp_before: int, target_hp: int, k: int, count: int) -> int:
	var n := maxi(1, count)
	var step := clampi(k, 0, n - 1) + 1
	return hp_before - roundi(float(hp_before - target_hp) * step / n)


## `count` points uniform in a horizontal disc of `radius` around `centre` (y = centre.y; the
## caller sets the ground height). Uses only `rng` – a view-local generator, never GameState.rng.
static func landing_points(
	rng: RandomNumberGenerator, centre: Vector3, count: int, radius: float
) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in count:
		var r := radius * sqrt(rng.randf())
		var angle := rng.randf() * TAU
		points.append(centre + Vector3(cos(angle) * r, 0.0, sin(angle) * r))
	return points
