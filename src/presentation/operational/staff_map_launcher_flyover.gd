class_name StaffMapLauncherFlyover
extends RefCounted
## Pure path of an aircraft launcher marker (TASK-147 follow-up): the aircraft appears
## APPROACH_PX behind the launch point (away from the target), flies straight to it facing the
## target in APPROACH_SECONDS (the missiles leave when it arrives), then banks away in a half-circle
## U-turn to one side in TURN_SECONDS, fading out over its last FADE_SECONDS. Screen pixels, fixed
## size; nothing is drawn here (StaffMapStrikeLayer draws it).

const KINDS: Array[StringName] = [&"fighter", &"bomber", &"aircraft"]
const APPROACH_SECONDS := 1.8
const TURN_SECONDS := 1.2
const FADE_SECONDS := 0.6
const FADE_IN_SECONDS := 0.25
const APPROACH_PX := 230.0
## The turn radius keeps the approach speed: pi * R = speed * TURN_SECONDS.
const TURN_RADIUS_PX := APPROACH_PX / APPROACH_SECONDS * TURN_SECONDS / PI
## Sideways offset of the approach line per variant (stacked launches from one hex differ).
const LATERAL_PX := 12.0


## True for the launcher kinds drawn as a flying aircraft.
static func is_aircraft(kind: Variant) -> bool:
	return KINDS.has(StringName(str(kind)) if kind != null else &"")


## When the flyover is over (s after the aircraft appears).
static func end_time() -> float:
	return APPROACH_SECONDS + TURN_SECONDS


## The turn side (+1 / -1) and the lateral offset (px) of a launch, from a stable per-launch
## number (the strike sequence), so stacked launches from one hex fly apart.
static func variant(seed_value: int) -> Dictionary:
	return {
		"side": 1.0 if seed_value % 2 == 0 else -1.0,
		"lateral": float(posmod(seed_value, 3) - 1) * LATERAL_PX,
	}


## {at (screen point), heading (unit vector the nose points along), alpha} of the aircraft `t` s
## after it appeared, launching at `origin` towards `target` (screen points). `side` +1 / -1 picks
## the turn side, `lateral` shifts the approach line sideways (px).
static func pose(
	t: float, origin: Vector2, target: Vector2, side := 1.0, lateral := 0.0
) -> Dictionary:
	var forward := target - origin
	forward = forward.normalized() if forward.length() > 0.001 else Vector2.RIGHT
	var across := forward.orthogonal() * signf(side if side != 0.0 else 1.0)
	var start := origin - forward * APPROACH_PX + across * lateral
	var alpha := alpha_at(t)
	if t <= APPROACH_SECONDS:
		var k := clampf(t / APPROACH_SECONDS, 0.0, 1.0)
		return {
			"at": start.lerp(origin, k), "heading": (origin - start).normalized(), "alpha": alpha
		}
	# Half circle from the origin around a centre beside it: starts along `forward`, ends facing
	# back (away from the target), TURN_RADIUS_PX * 2 to the side.
	var k := clampf((t - APPROACH_SECONDS) / TURN_SECONDS, 0.0, 1.0)
	var eased := k * k * (3.0 - 2.0 * k) * 0.35 + k * 0.65  # a softer bank in and out
	var centre := origin + across * TURN_RADIUS_PX
	var radial := origin - centre
	var spin := _spin(radial, forward)
	var angle := spin * PI * eased
	var heading := radial.rotated(angle).rotated(PI / 2.0 * spin).normalized()
	return {"at": centre + radial.rotated(angle), "heading": heading, "alpha": alpha}


## The aircraft's alpha `t` s after it appeared: fades in, then out over the last FADE_SECONDS.
static func alpha_at(t: float) -> float:
	if t < 0.0 or t >= end_time():
		return 0.0
	var fade_in := clampf(t / FADE_IN_SECONDS, 0.0, 1.0)
	var fade_out := clampf((end_time() - t) / FADE_SECONDS, 0.0, 1.0)
	return minf(fade_in, fade_out)


## The rotation direction (+1 / -1) of the radial vector that moves the aircraft along `forward`
## at the start of the turn.
static func _spin(radial: Vector2, forward: Vector2) -> float:
	return 1.0 if radial.rotated(PI / 2.0).dot(forward) >= 0.0 else -1.0
