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
const CHAIKIN_ITERATIONS := 3


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
## can (a route may still not exist, see preview()).
static func unreachable_reason(
	state: OperationalState, formation: Formation, destination: Vector2i
) -> String:
	var grid := state.grid
	if destination == formation.coord or not grid.has_tile(destination):
		return REASON_NO_ROUTE
	if grid.get_terrain(destination) == Terrain.Type.WATER:
		return REASON_WATER
	var other := state.formation_at(destination)
	if other != null:
		return REASON_ENEMY if other.owner_id != formation.owner_id else REASON_OCCUPIED
	return ""


## The preview of a route of `formation` to `destination` at `pace`: {route, stops, cost, turns,
## stop, reason}. `route` = hexes entered (empty when unreachable, then `reason` is set), `stops`
## = where the formation stands after each of its turns (as OperationalRoutes.forecast), `cost` =
## summed step cost of the whole route, `turns` = stops.size(), `stop` = stop reason of the last
## walk (OperationalRoutes.STOP_*). Empty dictionary for the formation's own hex.
static func preview(
	state: OperationalState,
	formation: Formation,
	destination: Vector2i,
	pace: OperationalPace,
	movement: OperationalMovement = null
) -> Dictionary:
	if destination == formation.coord:
		return {}
	if movement == null:
		movement = OperationalMovement.shipped()
	var reason := unreachable_reason(state, formation, destination)
	var route: Array[Vector2i] = []
	if reason == "":
		route = OperationalRoutes.plan(state, formation, destination, pace.avoid_contact, movement)
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
		var walked := OperationalRoutes.walk(
			state, formation, position, rest, pace.budget, movement
		)
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


## The pace after pressing key `number` (1-based); `current` when there is no such pace.
static func pace_for_key(paces: Array[OperationalPace], number: int, current: int) -> int:
	return number - 1 if number >= 1 and number <= paces.size() else current
