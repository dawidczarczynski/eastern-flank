class_name StaffMapRoute
extends RefCounted
## Route preview maths of the staff map (TASK-092c): the numbers behind the ribbon, stops and the
## cursor label (pure, tested) and the Chaikin smoothing of the line. Reads the OperationalState
## through OperationalRoutes / OperationalMovement; changes nothing.

## Unreachable reasons (translation keys; "" = reachable).
const REASON_WATER := "ROUTE_WATER"
const REASON_ENEMY := "ROUTE_ENEMY"
const REASON_OCCUPIED := "ROUTE_OCCUPIED"
const REASON_NO_ROUTE := "ROUTE_NO_ROUTE"
const REASON_CLOSED := "ROUTE_CLOSED"
const CHAIKIN_ITERATIONS := 3
## Opacity of an issued order (the planning preview is opaque).
const ISSUED_ALPHA := 0.82
## Dash and gap of a march line, in hex units.
const DASH_ON := 0.28
const DASH_OFF := 0.18


## Chaikin corner cutting: every pass replaces each segment by points at 1/4 and 3/4 of it and
## keeps the two end points, so the line still starts and ends on the first / last input point.
static func chaikin(
	points: PackedVector2Array, iterations := CHAIKIN_ITERATIONS
) -> PackedVector2Array:
	var line := points
	for _pass in iterations:
		if line.size() < 3:
			break
		var next := PackedVector2Array()
		next.append(line[0])
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			if i > 0:
				next.append(a.lerp(b, 0.25))
			if i < line.size() - 2:
				next.append(a.lerp(b, 0.75))
		next.append(line[line.size() - 1])
		line = next
	return line


## Why `destination` cannot be a route target for `formation`, as a translation key; "" when it
## can (a route may still not exist, see preview()). An enemy formation is a target only for a
## posture that does not avoid contact (attack order).
static func unreachable_reason(
	state: OperationalState, formation: Formation, destination: Vector2i, avoids_contact := true
) -> String:
	var grid := state.grid
	if destination == formation.coord or not grid.has_tile(destination):
		return REASON_NO_ROUTE
	if grid.get_terrain(destination) == Terrain.Type.WATER:
		return REASON_WATER
	if OperationalRoutes.destination_closed(state, formation, destination):
		return REASON_CLOSED  # checked before "occupied", as IssueOrderCommand does (TASK-116)
	var other := state.formation_at(destination)
	if other != null:
		if other.owner_id == formation.owner_id:
			return REASON_OCCUPIED
		return REASON_ENEMY if avoids_contact else ""
	return ""


## The preview of a route of `formation` to `destination` with `budget` move points per turn
## (OperationalPosture.budget) and `avoids_contact` (the posture's): {route, stops, cost, turns,
## stop, reason}. `route` = hexes entered (empty when unreachable, then `reason` is set), `stops`
## = where the formation stands after each of its turns (as OperationalRoutes.forecast), `cost` =
## summed step cost of the whole route, `turns` = stops.size(), `stop` = stop reason of the last
## walk (OperationalRoutes.STOP_*). Empty dictionary for the formation's own hex.
static func preview(
	state: OperationalState,
	formation: Formation,
	destination: Vector2i,
	avoids_contact: bool,
	budget: int,
	movement: OperationalMovement = null
) -> Dictionary:
	if destination == formation.coord:
		return {}
	if movement == null:
		movement = OperationalMovement.shipped()
	var reason := unreachable_reason(state, formation, destination, avoids_contact)
	var route: Array[Vector2i] = []
	if reason == "":
		route = OperationalRoutes.plan(state, formation, destination, avoids_contact, movement)
		if route.is_empty():
			reason = REASON_NO_ROUTE
	var result := {
		"route": route,
		"stops": [] as Array[Vector2i],
		"cost": 0,
		"turns": 0,
		"stop": &"",
		"reason": reason,
	}
	if route.is_empty():
		return result
	var cost := 0
	var previous := formation.coord
	for hex in route:
		cost += movement.step_cost(state.grid, previous, hex)
		previous = hex
	var stops: Array[Vector2i] = []
	var position := formation.coord
	var offset := 0
	var stop: StringName = OperationalRoutes.STOP_OUT_OF_POINTS
	for _turn in OperationalRoutes.MAX_FORECAST_TURNS:
		if offset >= route.size():
			break
		var rest: Array[Vector2i] = route.slice(offset)
		var walked := OperationalRoutes.walk(state, formation, position, rest, budget, movement)
		var steps: Array[Vector2i] = walked["steps"]
		if steps.is_empty():
			break
		position = walked["end"]
		offset += steps.size()
		stops.append(position)
		stop = walked["stop"]
		if stop != OperationalRoutes.STOP_OUT_OF_POINTS:
			break
	result["stops"] = stops
	result["cost"] = cost
	result["turns"] = stops.size()
	result["stop"] = stop
	return result


## The route as a smoothed polyline in map units (hex centres of the start and the route, then
## Chaikin): first point = the formation's hex centre, last = the destination centre.
static func smoothed_line(start: Vector2i, route: Array[Vector2i]) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.append(centre(start))
	for hex in route:
		points.append(centre(hex))
	return chaikin(points)


## Centre of hex `c` in map units (the xz plane of Hex.to_world at unit size).
static func centre(c: Vector2i) -> Vector2:
	var w := Hex.to_world(c, 1.0)
	return Vector2(w.x, w.z)


## The posture of key `number` (1-based: march, advance, defend); &"" when there is none.
static func posture_for_key(number: int) -> StringName:
	if number < 1 or number > OperationalPosture.NAMES.size():
		return &""
	return OperationalPosture.NAMES[number - 1]


## The preview of `formation`'s route to `destination` in its posture `posture_id` (the numbers
## come from the OperationalPosture resource: one source of truth); {} for an unknown posture.
static func preview_in_posture(
	state: OperationalState,
	formation: Formation,
	destination: Vector2i,
	posture_id: StringName,
	movement: OperationalMovement = null
) -> Dictionary:
	var posture := OperationalPosture.find(posture_id)
	if posture == null:
		return {}
	return preview(
		state,
		formation,
		destination,
		posture.avoids_contact,
		OperationalOrders.budget(formation, posture),
		movement
	)


## How a route is drawn. Posture = line style (march dashed, advance solid, defend ends in a
## defence arc); a planning preview is opaque with a dot on every hex and an amber target, an
## issued order is ISSUED_ALPHA without dots (docs/design/operational_map "Orders").
static func style(posture_id: StringName, issued: bool) -> Dictionary:
	return {
		"dashed": posture_id == &"march",
		"defend_arc": posture_id == &"defend",
		"alpha": ISSUED_ALPHA if issued else 1.0,
		"dots": not issued,
		"amber_target": not issued,
	}


## `points` cut into dashes: `on` units drawn, `off` units skipped, along the line (units of the
## points). A line shorter than one dash stays whole. Returns Array[PackedVector2Array].
static func dashes(points: PackedVector2Array, on: float, off: float) -> Array:
	var out: Array = []
	if points.size() < 2 or on <= 0.0:
		return [points]
	var current := PackedVector2Array([points[0]])
	var drawing := true
	var left := on
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		var done := 0.0
		while length - done > left:
			done += left
			var at := a.lerp(b, done / length)
			if drawing:
				current.append(at)
				out.append(current)
			else:
				current = PackedVector2Array([at])
			drawing = not drawing
			left = on if drawing else off
		left -= length - done
		if drawing:
			current.append(b)
	if drawing and current.size() > 1:
		out.append(current)
	return out
