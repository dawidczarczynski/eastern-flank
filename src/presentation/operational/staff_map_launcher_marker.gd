class_name StaffMapLauncherMarker
extends RefCounted
## Pure timing and layout of a strike launcher marker (TASK-147, variant B of
## docs/design/operational_map/strike_launcher_marker.html): pops in (120 ms, scale .8 -> 1),
## shows alone for LEAD_IN_SECONDS before the first missile leaves (so the eye finds it), stays for
## the flight of the salvo, fades out in 0.6 s and never outlives the strike's report card; the
## launch tick pulses once; markers on one hex stack up-right, older ones fainter.
## Nothing is drawn here: StaffMapStrikeLayer draws what these return.

## The marker shows this long before the first missile of its salvo leaves (s).
const LEAD_IN_SECONDS := 1.2
const POP_SECONDS := 0.25
const POP_FROM := 0.8
const FADE_SECONDS := 0.6
const PULSE_SECONDS := 0.8
const PULSE_FROM := 4.5
const PULSE_TO := 9.0
const PULSE_ALPHA := 0.6
## Glyph size (px), its lift above the launch tick and the tick ring.
const GLYPH_PX := 28.0
const LIFT_PX := 6.0
const TICK_RADIUS := 4.5
const TICK_WIDTH := 1.4
const HALO_PX := 2.6
## Label: IBM Plex Sans Condensed 500, 11 px, 3 px halo, under the launch tick.
const LABEL_SIZE := 11
const LABEL_HALO_PX := 3
const LABEL_GAP := 3.0
## Same-hex stack: each further marker this far up-right; alpha by age (newest first).
const STACK_STEP := Vector2(14.0, -14.0)
const STACK_ALPHA: Array[float] = [1.0, 0.7, 0.45]
const MAX_PER_HEX := 3
const MAX_MARKERS := 8


## The marker's alpha `t` seconds after the launch: 1 until the flight ends (`flight` s from the
## marker's appearance: the lead-in plus the longest trace), then a linear fade over
## FADE_SECONDS; `cap` (s) is the strike card's lifetime, the marker is gone by then at the latest.
static func alpha_at(t: float, flight: float, cap := INF) -> float:
	var fade_start := _fade_start(flight, cap)
	if t < 0.0 or t >= end_time(flight, cap):
		return 0.0
	if t <= fade_start:
		return 1.0
	return clampf(1.0 - (t - fade_start) / FADE_SECONDS, 0.0, 1.0)


## When the marker is gone (s after the launch).
static func end_time(flight: float, cap := INF) -> float:
	return minf(_fade_start(flight, cap) + FADE_SECONDS, cap)


static func _fade_start(flight: float, cap: float) -> float:
	return clampf(flight, 0.0, maxf(cap - FADE_SECONDS, 0.0))


## Seconds between the marker's appearance and the first missile leaving: the aircraft's approach
## (StaffMapLauncherFlyover) for an aircraft, else LEAD_IN_SECONDS.
static func lead_in(kind: Variant) -> float:
	if StaffMapLauncherFlyover.is_aircraft(kind):
		return StaffMapLauncherFlyover.APPROACH_SECONDS
	return LEAD_IN_SECONDS


## When a marker of `kind` is gone (s after it appeared): its tick and label after the flight and
## fade, an aircraft after its U-turn too, never after the card's end `cap`.
static func end_for(kind: Variant, flight: float, cap := INF) -> float:
	var end := end_time(flight, cap)
	if StaffMapLauncherFlyover.is_aircraft(kind):
		end = minf(maxf(end, StaffMapLauncherFlyover.end_time()), cap)
	return end


## The pop-in scale `t` s after the launch (.8 -> 1 in POP_SECONDS, ease-out).
static func pop_scale(t: float) -> float:
	var k := clampf(t / POP_SECONDS, 0.0, 1.0)
	return lerpf(POP_FROM, 1.0, 1.0 - (1.0 - k) * (1.0 - k))


## The launch tick's single pulse ring `t` s after the launch: {radius, alpha}; alpha 0 after.
static func pulse(t: float) -> Dictionary:
	if t < 0.0 or t >= PULSE_SECONDS:
		return {"radius": PULSE_TO, "alpha": 0.0}
	var k := t / PULSE_SECONDS
	return {"radius": lerpf(PULSE_FROM, PULSE_TO, k), "alpha": PULSE_ALPHA * (1.0 - k)}


## The screen offset of the `slot`-th marker on one hex (0 = the newest, on the tick).
static func stack_offset(slot: int) -> Vector2:
	return STACK_STEP * clampi(slot, 0, MAX_PER_HEX - 1)


## The alpha factor of the `slot`-th marker on one hex (older = fainter).
static func stack_alpha(slot: int) -> float:
	return STACK_ALPHA[clampi(slot, 0, STACK_ALPHA.size() - 1)]


## The strike card's lifetime from the marker's appearance (s): the card is revealed
## IMPACT_REVEAL_SECONDS after the last impact (`flight` s from the appearance) and stays the
## card's time (own 9 s, enemy 3.5 s), so a marker never outlives its report.
static func toast_cap(own: bool, flight: float) -> float:
	return (
		maxf(flight, 0.0)
		+ StaffMapStrikeReports.IMPACT_REVEAL_SECONDS
		+ (StaffMapStrikeReports.OWN_SECONDS if own else StaffMapStrikeReports.ENEMY_SECONDS)
	)


## The glyph's top-left corner relative to the launch tick, at `scale` (the pop-in): the glyph
## stands LIFT_PX above the tick, centred over it, growing from its foot.
static func glyph_rect(scale := 1.0) -> Rect2:
	var size := GLYPH_PX * scale
	return Rect2(Vector2(-size * 0.5, -LIFT_PX - size), Vector2(size, size))
