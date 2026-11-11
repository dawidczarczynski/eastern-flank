class_name StaffMapAirDefence
extends RefCounted
## Pure models and texts of the air defence on the staff map (TASK-098b, docs/design/
## operational_map/air_defence_overlay.html variant A "Glass zones"): the coverage zones of both
## sides, the "Interception ~X% per missile" line of a planned strike, the lines of an air-defence
## marker's hover card, the suppressed badge and the geometry helpers of the zone layer (ring,
## dashes, hatch). Reads the state through StrikeRules (`coverage`, `interception_chance`,
## `interceptors`); holds no rules.

## Kinds of the odds line (the row colour follows it).
const ODDS_SOME := &"some"
const ODDS_SUPPRESSED := &"suppressed"
const ODDS_NONE := &"none"
const RING_SEGMENTS := 64
## Hexes are `StaffMapStrike.KM_PER_HEX` km apart; in hex units (centre-to-corner 1) the distance
## between neighbouring centres is sqrt(3).
const HEX_STEP := Hex.SQRT3


## One zone per non-destroyed air-defence site of both sides, setup order of each side:
## {id, coord, owner, radius_hexes, radius_km, suppressed, rounds}.
static func zones(state: OperationalState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for player in state.player_sides.size():
		for site in StrikeRules.coverage(state, player):
			(
				result
				. append(
					{
						"id": site["id"],
						"coord": site["coord"],
						"owner": player,
						"radius_hexes": site["radius_hexes"],
						"radius_km": int(site["radius_hexes"]) * StaffMapStrike.KM_PER_HEX,
						"suppressed": site["suppressed"],
						"rounds": site["suppressed_rounds"],
					}
				)
			)
	return result


## The odds line of `weapon_id` fired by `striker` at `coord`: {kind, percent, text}. Interception
## above 0 -> "Interception ~X% per missile" (X is StrikeRules.interception_chance); 0 with a
## suppressed enemy site covering the hex -> "Air defence suppressed"; otherwise "No air defence
## cover".
static func odds(
	state: OperationalState, striker: int, weapon_id: StringName, coord: Vector2i
) -> Dictionary:
	var percent := StrikeRules.interception_chance(state, striker, weapon_id, coord)
	if percent > 0:
		return {
			"kind": ODDS_SOME,
			"percent": percent,
			"text": _t("Interception ~%d%% per missile") % percent,
		}
	if _suppressed_cover(state, striker, coord):
		return {"kind": ODDS_SUPPRESSED, "percent": 0, "text": _t("Air defence suppressed")}
	return {"kind": ODDS_NONE, "percent": 0, "text": _t("No air defence cover")}


## The odds line for a target id (installation or formation) of `striker`; {} when the target is
## unknown.
static func odds_for_target(
	state: OperationalState, striker: int, weapon_id: StringName, target_id: StringName
) -> Dictionary:
	var target := StrikeRules.find_target(state, striker, target_id)
	if target.is_empty():
		return {}
	return odds(state, striker, weapon_id, target["coord"])


## Hover-card lines of an installation: {is_air_defence, type_line, reach_line, suppressed,
## rounds, suppressed_line}. All texts are "" for a class other than air defence.
static func card_model(state: OperationalState, installation: Installation) -> Dictionary:
	var model := {
		"is_air_defence": false,
		"type_line": "",
		"reach_line": "",
		"suppressed": false,
		"rounds": 0,
		"suppressed_line": "",
	}
	if installation.class_id != &"air_defence":
		return model
	model["is_air_defence"] = true
	var type: AirDefenceDefinition = state.air_defence_types.get(installation.ad_type)
	if type != null:
		var line := _t(type.display_name)
		if type.examples != "":
			line += " – " + type.examples
		model["type_line"] = line
		model["reach_line"] = (
			_t("radius %d hexes (%d km)") % [type.radius_hexes, reach_km(type.radius_hexes)]
		)
	if installation.suppressed():
		model["suppressed"] = true
		model["rounds"] = installation.suppressed_rounds
		model["suppressed_line"] = suppressed_line(installation.suppressed_rounds)
	return model


## "▲ SUPPRESSED – 2 rounds left" (the hover card's amber row).
static func suppressed_line(rounds: int) -> String:
	return (
		"▲ %s – %s"
		% [_t("SUPPRESSED"), _t("%d rounds left") % rounds if rounds != 1 else _t("1 round left")]
	)


## "Suppressed for 2 rounds" (the report card).
static func report_line(rounds: int) -> String:
	return _t("Suppressed for %d rounds") % rounds if rounds != 1 else _t("Suppressed for 1 round")


static func reach_km(radius_hexes: int) -> int:
	return radius_hexes * StaffMapStrike.KM_PER_HEX


## Radius of a zone in hex units (centre-to-corner 1): the zone is a true circle on the ground.
static func radius_units(radius_hexes: int) -> float:
	return float(radius_hexes) * HEX_STEP


## `segments` points of the circle (centre, radius) in the ground plane, counter-clockwise.
static func ring(centre: Vector2, radius: float, segments := RING_SEGMENTS) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(segments)
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		points[i] = centre + Vector2(cos(angle), sin(angle)) * radius
	return points


## The closed polyline `points` cut into dashes `on` px long with `off` px gaps (a dash may span
## several segments); each dash is a polyline.
static func dashes(points: PackedVector2Array, on: float, off: float) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if points.size() < 2:
		return result
	var closed := points.duplicate()
	closed.append(points[0])
	var drawing := true
	var left := on
	var current := PackedVector2Array([closed[0]])
	for i in range(1, closed.size()):
		var from := closed[i - 1]
		var to := closed[i]
		var length := from.distance_to(to)
		var travelled := 0.0
		while length - travelled > left:
			travelled += left
			var at := from.lerp(to, travelled / length)
			if drawing:
				current.append(at)
				result.append(current)
				current = PackedVector2Array()
				left = off
			else:
				current = PackedVector2Array([at])
				left = on
			drawing = not drawing
		left -= length - travelled
		if drawing:
			current.append(to)
	if drawing and current.size() >= 2:
		result.append(current)
	return result


## 45 degree hatch lines `spacing` px apart (measured across the lines) clipped to the convex
## `polygon`: pairs of points for `draw_multiline`.
static func hatch(polygon: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var lines := PackedVector2Array()
	if polygon.size() < 3 or spacing <= 0.0:
		return lines
	# Lines x + y = k; consecutive k differ by spacing * sqrt(2).
	var low := INF
	var high := -INF
	for p in polygon:
		low = minf(low, p.x + p.y)
		high = maxf(high, p.x + p.y)
	var step := spacing * sqrt(2.0)
	var k := ceilf(low / step) * step
	while k < high:
		var hits: Array[Vector2] = []
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			var da := a.x + a.y - k
			var db := b.x + b.y - k
			if (da < 0.0) != (db < 0.0):
				hits.append(a.lerp(b, da / (da - db)))
		if hits.size() >= 2:
			lines.append(hits[0])
			lines.append(hits[1])
		k += step
	return lines


## True when an enemy (of `striker`) site that is suppressed covers `coord`.
static func _suppressed_cover(state: OperationalState, striker: int, coord: Vector2i) -> bool:
	for installation in state.installations:
		if (
			installation.owner == striker
			or installation.class_id != &"air_defence"
			or installation.destroyed()
			or not installation.suppressed()
		):
			continue
		var type: AirDefenceDefinition = state.air_defence_types.get(installation.ad_type)
		if type != null and Hex.distance(installation.coord, coord) <= type.radius_hexes:
			return true
	return false


static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))
