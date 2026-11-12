class_name StaffMapStrikeTrail
extends RefCounted
## Pure helpers and the bookkeeping of the strike trail on the staff map (TASK-097b): where a strike
## came from, which air-defence sites tried to stop it, and the list of traces and burst markers
## kept until the start of the viewer's next turn (at most MAX_TRACES traces; the oldest go first).
## Built from `strike_launched` / `strike_resolved` events; the state is read only through
## CountryRules and the installations' coordinates. Nothing is drawn here.

## Kept strikes (all missiles of a strike are shown); the oldest strike goes first.
const MAX_STRIKES := 8
const MAX_TRACES := MAX_STRIKES
## Flight time of a trace without a weapon look (the weapon's look gives the real one).
const ARC_SECONDS := 0.6
const STAGGER_SECONDS := StaffMapStrikeFlight.STAGGER_SECONDS
const EFFECT_SECONDS := 1.2
const DESTROYED_SECONDS := 2.0
## Pixel distance range a missed missile lands beside the target.
const MISS_MIN_PX := 20.0
const MISS_MAX_PX := 34.0
const STOP_FRACTION := StaffMapStrikeFlight.STOP_FRACTION
## The launch point is searched at this share of the weapon's range from the target.
const STANDOFF_SHARE := StrikeLaunch.STANDOFF_SHARE
## Outcome of a strike for the burst marker colour.
const HIT := &"hit"
const INTERCEPTED := &"intercepted"
const MISSED := &"missed"

## Fog hook (TASK-100): `(coord: Vector2i, player: int) -> bool`; a strike the viewer cannot see
## leaves no trace. Always true until reconnaissance exists.
var is_visible: Callable = func(_coord: Vector2i, _player: int) -> bool: return true
## One trace per missile, oldest first: {strike, player, means, from, to, outcome, start, offset,
## bow, lateral, look (StrikeWeaponLook), duration (s), seed, stop (Vector2i, intercepted only,
## absent when no site), marks: [{coord, count}] and more (missiles of the salvo not drawn; both
## only on the first missile of a strike)}. `start` is the clock time the missile leaves.
var traces: Array[Dictionary] = []
## One impact / airburst / dust effect per missile: {strike, coord, outcome, player, class_id,
## start (clock time of the impact), seed, offset, destroyed, look, stop (as in traces)}.
var bursts: Array[Dictionary] = []
## One launcher marker per seen strike (TASK-147), oldest first: {strike, player, kind (String,
## the event's `launcher_kind`), origin (Vector2i), to (Vector2i, the target hex: an aircraft
## faces it), label (the means' `platform` text), start (clock time the marker appears), flight
## (s from then to the last impact), cap (s, the end of the strike card's lifetime)}. Gone
## markers are dropped on the next strike; at most StaffMapLauncherMarker.MAX_PER_HEX per hex and
## MAX_MARKERS overall.
var launchers: Array[Dictionary] = []
## Seconds since the first trace, advanced by the layer; arcs and effects are functions of it.
var clock := 0.0

var _launched := {}
var _strike_seq := 0
var _busy_until := 0.0
var _last_impact := 0.0


## The nearest own (border) hex to `target`: StrikeLaunch.origin (core, TASK-147).
static func origin(state: OperationalState, player: int, target: Vector2i) -> Vector2i:
	return StrikeLaunch.origin(state, player, target)


## The standoff launch point: StrikeLaunch.standoff_origin (core, TASK-147).
static func launch_origin(
	state: OperationalState, player: int, target: Vector2i, range_hexes: int
) -> Vector2i:
	return StrikeLaunch.standoff_origin(state, player, target, range_hexes)


## The air-defence sites that counted against the strike as they were BEFORE `strike_resolved`
## (the events arrive after the state changed): the sites named by the event's `interceptor_ids`
## (TASK-098a), [{id, coord, integrity}] in setup order; a target gets its `damage_dealt` back.
static func interceptors_before(
	state: OperationalState, event: Dictionary, _coord: Vector2i
) -> Array[Dictionary]:
	var sites: Array[Dictionary] = []
	var ids: Array = event.get("interceptor_ids", [])
	for installation in state.installations:
		if not ids.has(installation.id):
			continue
		var integrity := installation.integrity
		if installation.id == event["target"]:
			integrity += int(event.get("damage_dealt", 0))
		sites.append({"id": installation.id, "coord": installation.coord, "integrity": integrity})
	return sites


## "hit" when a missile hit, else "intercepted" when one was intercepted, else "missed".
static func outcome(event: Dictionary) -> StringName:
	if int(event["hits"]) > 0:
		return HIT
	return INTERCEPTED if int(event["intercepted"]) > 0 else MISSED


## The outcome of each of the `count` missiles: intercepted first, then hits, then misses.
static func missile_outcomes(event: Dictionary) -> Array[StringName]:
	var count: int = event["count"]
	var intercepted := clampi(int(event["intercepted"]), 0, count)
	var hits := clampi(int(event["hits"]), 0, count - intercepted)
	var list: Array[StringName] = []
	for i in count:
		if i < intercepted:
			list.append(INTERCEPTED)
		elif i < intercepted + hits:
			list.append(HIT)
		else:
			list.append(MISSED)
	return list


## A deterministic pseudo-random number in [0, 1) of an integer seed.
static func unit(seed_value: int) -> float:
	var x := (seed_value * 1103515245 + 12345) & 0x7fffffff
	x = (x * 1103515245 + 12345) & 0x7fffffff
	return float(x >> 8) / float(0x800000)


## The look of missile `index` of a salvo: `delay` (stagger, s), `bow` (arc height factor) and
## `lateral` (sideways bend of the arc, in fractions of its length). Pure and deterministic.
static func variation(seed_value: int, index: int) -> Dictionary:
	var s := seed_value * 31 + index * 7919
	return {
		"delay": StaffMapStrikeFlight.stagger(index),
		"bow": 0.8 + unit(s + 2) * 0.5,
		"lateral": (unit(s + 3) - 0.5) * 0.16,
	}


## Where a missed missile lands relative to the target hex centre, in pixels.
static func miss_offset(seed_value: int) -> Vector2:
	var angle := unit(seed_value + 11) * TAU
	return Vector2.from_angle(angle) * lerpf(MISS_MIN_PX, MISS_MAX_PX, unit(seed_value + 12))


## Feeds one event; returns true when the trace list or the bursts changed. `viewer` is the side
## whose screen it is: its own turn start clears everything.
func on_event(state: OperationalState, viewer: int, event: Dictionary) -> bool:
	match event.get("type"):
		&"strike_launched":
			_launched[event["target"]] = event
		&"strike_resolved":
			return _add(state, event, viewer)
		&"operational_turn_started":
			if (
				int(event.get("player", -1)) == viewer
				and (not traces.is_empty() or not bursts.is_empty())
			):
				clear()
				return true
	return false


func clear() -> void:
	traces.clear()
	bursts.clear()
	launchers.clear()
	_launched.clear()
	clock = 0.0
	_busy_until = 0.0
	_last_impact = 0.0


func trace_count() -> int:
	return traces.size()


func burst_count() -> int:
	return bursts.size()


## The number of strikes added so far (grows by one per drawn strike, never reset by clear()).
func strike_sequence() -> int:
	return _strike_seq


## Seconds from now to the last impact of the newest drawn strike (0 when it is past).
func seconds_to_last_impact() -> float:
	return maxf(_last_impact - clock, 0.0)


func strike_count() -> int:
	var ids := {}
	for trace in traces:
		ids[trace["strike"]] = true
	return ids.size()


## Arc progress 0..1 of a trace at the current clock.
func progress(trace: Dictionary) -> float:
	var duration: float = trace.get("duration", ARC_SECONDS)
	return clampf((clock - float(trace["start"])) / duration, 0.0, 1.0)


## Seconds since a burst's impact (negative before it), at the current clock.
func burst_age(burst: Dictionary) -> float:
	return clock - float(burst["start"])


## How long a burst's animated effect runs.
static func effect_seconds(burst: Dictionary) -> float:
	return DESTROYED_SECONDS if burst["destroyed"] else EFFECT_SECONDS


## True while an arc grows or an effect plays.
func animating() -> bool:
	return clock < _busy_until


func _add(state: OperationalState, event: Dictionary, viewer := 0) -> bool:
	var launched: Dictionary = _launched.get(event["target"], {})
	_launched.erase(event["target"])
	if launched.is_empty():
		return false
	var player: int = event["player"]
	var to: Vector2i = launched["coord"]
	if not is_visible.call(to, player):
		return false
	var all_outcomes := missile_outcomes(event)
	var outcomes: Array[StringName] = []
	for index in StaffMapStrikeFlight.drawn_indices(all_outcomes.size()):
		outcomes.append(all_outcomes[index])
	var look := StrikeWeaponLook.for_means(event["means"])
	var sites: Array[Dictionary] = []
	if int(event["intercepted"]) > 0:
		sites = interceptors_before(state, event, to)
	var assigned: Array[int] = []
	assigned.resize(sites.size())
	assigned.fill(0)
	var from := _from(state, player, launched, event["means"], to)
	_strike_seq += 1
	var base := to.x * 977 + to.y * 131 + _strike_seq * 53
	var first_trace := {}
	var last_hit := outcomes.rfind(HIT)
	if last_hit < 0:
		last_hit = outcomes.size() - 1
	var duration := look.duration(Hex.distance(from, to))
	var intercept_index := 0
	var flight_end := clock
	var lead_in := StaffMapLauncherMarker.lead_in(launched.get("launcher_kind", ""))
	for i in outcomes.size():
		var result: StringName = outcomes[i]
		var variance := variation(base, i)
		var start := clock + lead_in + float(variance["delay"])
		var trace := {
			"strike": _strike_seq,
			"player": player,
			"means": event["means"],
			"from": from,
			"to": to,
			"outcome": result,
			"class_id": launched.get("class_id", &""),
			"start": start,
			"offset": Vector2.ZERO,
			"bow": variance["bow"],
			"lateral": variance["lateral"],
			"look": look,
			"duration": duration,
			"seed": base + i * 17,
			"marks": [],
			"more": 0,
		}
		var burst := {
			"strike": _strike_seq,
			"coord": to,
			"outcome": result,
			"player": player,
			"class_id": launched.get("class_id", &""),
			"start": start + duration,
			"seed": base + i * 17,
			"look": look,
			"warhead": look.warhead,
			"burst_scale": look.burst_scale,
			"offset": Vector2.ZERO,
			"destroyed": bool(event.get("target_destroyed", false)) and i == last_hit,
		}
		match result:
			HIT:
				var jitter := (
					(Vector2(unit(base + i), unit(base + i + 5)) - Vector2(0.5, 0.5)) * 8.0
				)
				trace["offset"] = jitter
				burst["offset"] = jitter
			MISSED:
				trace["offset"] = miss_offset(base + i * 17)
				burst["offset"] = trace["offset"]
			INTERCEPTED:
				if not sites.is_empty():
					var k := intercept_index % sites.size()
					assigned[k] += 1
					trace["stop"] = sites[k]["coord"]
					burst["stop"] = sites[k]["coord"]
				var spread := Vector2(unit(base + i + 9), unit(base + i + 13)) - Vector2(0.5, 0.5)
				trace["offset"] = spread * 14.0
				burst["offset"] = trace["offset"]
				intercept_index += 1
		flight_end = maxf(flight_end, start + duration)
		if first_trace.is_empty():
			first_trace = trace
		traces.append(trace)
		bursts.append(burst)
		_busy_until = maxf(_busy_until, float(burst["start"]) + effect_seconds(burst))
	first_trace["marks"] = _marks(sites, assigned)
	first_trace["more"] = StaffMapStrikeFlight.hidden_count(all_outcomes.size())
	_last_impact = flight_end
	_add_launcher(state, launched, event["means"], from, flight_end - clock, player == viewer)
	_trim()
	return true


## The launcher marker of a strike at its launch hex (TASK-147).
func _add_launcher(
	state: OperationalState,
	launched: Dictionary,
	means_id: StringName,
	from: Vector2i,
	flight: float,
	own: bool
) -> void:
	launchers = launchers.filter(func(marker: Dictionary) -> bool: return launcher_alive(marker))
	var on_hex := launchers.filter(
		func(marker: Dictionary) -> bool: return marker["origin"] == from
	)
	if on_hex.size() >= StaffMapLauncherMarker.MAX_PER_HEX:
		launchers.erase(on_hex[0])
	if launchers.size() >= StaffMapLauncherMarker.MAX_MARKERS:
		launchers.pop_front()
	var means: StrikeMeansDefinition = state.strike_means.get(means_id)
	var marker := {
		"strike": _strike_seq,
		"player": int(launched.get("player", 0)),
		"kind": str(launched.get("launcher_kind", "")),
		"origin": from,
		"to": launched.get("coord", from),
		"label": means.platform if means != null else "",
		"start": clock,
		"flight": flight,
		"cap": StaffMapLauncherMarker.toast_cap(own, flight),
	}
	launchers.append(marker)
	_busy_until = maxf(_busy_until, clock + launcher_end(marker))


## Seconds a marker lives after its launch (an aircraft until its U-turn is flown).
static func launcher_end(marker: Dictionary) -> float:
	return StaffMapLauncherMarker.end_for(
		marker["kind"], float(marker["flight"]), float(marker["cap"])
	)


## Seconds since a marker's launch, at the current clock.
func launcher_age(marker: Dictionary) -> float:
	return clock - float(marker["start"])


## The marker's lifetime alpha at the current clock (stack fading not included).
func launcher_alpha(marker: Dictionary) -> float:
	return StaffMapLauncherMarker.alpha_at(
		launcher_age(marker), float(marker["flight"]), float(marker["cap"])
	)


func launcher_alive(marker: Dictionary) -> bool:
	return launcher_age(marker) < launcher_end(marker)


## The markers shown now, newest first, each with its `slot` in its hex's stack (0 = newest):
## [{marker, slot}].
func visible_launchers() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var slots := {}
	for i in range(launchers.size() - 1, -1, -1):
		var marker := launchers[i]
		if not launcher_alive(marker):
			continue
		var slot: int = slots.get(marker["origin"], 0)
		slots[marker["origin"]] = slot + 1
		list.append({"marker": marker, "slot": slot})
	return list


## The launch hex: the event's `origin` (TASK-147); older events without it get the standoff point
## of the means (the border hex for an unknown means).
static func _from(
	state: OperationalState, player: int, launched: Dictionary, means_id: StringName, to: Vector2i
) -> Vector2i:
	if launched.get("origin") is Vector2i:
		return launched["origin"]
	var means: StrikeMeansDefinition = state.strike_means.get(means_id)
	if means == null:
		return origin(state, player, to)
	return launch_origin(state, player, to, means.range_hexes)


## The interception marks: every contributing site, with the missiles it stopped.
func _marks(sites: Array[Dictionary], assigned: Array[int]) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	for i in sites.size():
		marks.append({"coord": sites[i]["coord"], "count": assigned[i]})
	return marks


## Keeps the newest MAX_STRIKES strikes (all their missiles).
func _trim() -> void:
	while strike_count() > MAX_STRIKES:
		var oldest: int = traces[0]["strike"]
		while not traces.is_empty() and traces[0]["strike"] == oldest:
			traces.pop_front()
		while not bursts.is_empty() and bursts[0]["strike"] == oldest:
			bursts.pop_front()
