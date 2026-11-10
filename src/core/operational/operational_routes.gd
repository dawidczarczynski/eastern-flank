class_name OperationalRoutes
extends RefCounted
## Routes of formations on the operational map (TASK-092c, GDD "Orders and postures"): the
## cheapest path by OperationalMovement.step_cost (`plan`), one turn's movement along it (`walk`)
## and where the formation stands after each turn (`forecast`). Pure functions, nothing changes
## state. Ties are broken deterministically: hexes are settled cheapest first, first discovered
## first (Hex.DIRECTIONS order), and a hex's parent is replaced only by a strictly cheaper way –
## the same rule as HexGrid.path_to.

const STOP_ARRIVED := &"arrived"
const STOP_CONTACT := &"contact"
const STOP_OUT_OF_POINTS := &"out_of_points"
const MAX_FORECAST_TURNS := 99


## The full route of `formation` to `destination` (excludes the start, ends with `destination`),
## without a move-point limit. Enemy hexes are impassable, other own formations can be passed.
## `avoid_contact`: hexes next to an enemy are impassable too, except the destination. Empty when
## the destination is the start, off the map, impassable, holds an own formation, holds an enemy
## while `avoid_contact` is set, or is unreachable. Without `avoid_contact` the destination may
## hold an enemy formation (attack order): the route ends on its hex, `walk` halts before it.
static func plan(
	state: OperationalState,
	formation: Formation,
	destination: Vector2i,
	avoid_contact: bool,
	movement: OperationalMovement = null
) -> Array[Vector2i]:
	var route: Array[Vector2i] = []
	var grid := state.grid
	var start := formation.coord
	if destination == start or not grid.has_tile(destination):
		return route
	var target := state.formation_at(destination)
	if target != null and (avoid_contact or target.owner_id == formation.owner_id):
		return route
	if movement == null:
		movement = OperationalMovement.shipped()
	var blocked := {}
	var enemy_hexes: Array[Vector2i] = []
	for other in state.formations:
		if other.owner_id != formation.owner_id:
			blocked[other.coord] = true
			enemy_hexes.append(other.coord)
	if avoid_contact:
		for hex in enemy_hexes:
			for n in Hex.neighbors(hex):
				if n != destination and n != start:
					blocked[n] = true
	blocked.erase(destination)  # an enemy destination (attack order) is the route's last hex
	# Hexes of countries closed to the player (TASK-116) are impassable, the destination too.
	var closed := closed_countries(state, formation.owner_id, start)
	if not closed.is_empty():
		for hex: Vector2i in state.country_map:
			if closed.has(state.country_map[hex]):
				blocked[hex] = true
	var parents := _search(grid, movement, start, destination, blocked)
	if not parents.has(destination):
		return route
	var current := destination
	while current != start:
		route.append(current)
		current = parents[current]
	route.reverse()
	return route


## The countries (id -> true) closed to `player` (`CountryRules.may_enter` is false), except the
## one the hex `standing_at` lies in: a formation is never trapped (TASK-116). Entry depends only
## on the country, so a hex is closed exactly when its country is in the set.
static func closed_countries(
	state: OperationalState, player: int, standing_at: Vector2i
) -> Dictionary:
	var closed := {}
	var home := state.country_at(standing_at)
	for country in state.countries:
		if country.id == home:
			continue
		if not CountryRules.may_enter_country(state, player, country.id):
			closed[country.id] = true
	return closed


## Whether `destination` lies in a country closed to the formation's owner (and not in the
## country it stands in).
static func destination_closed(
	state: OperationalState, formation: Formation, destination: Vector2i
) -> bool:
	if state.country_at(destination) == state.country_at(formation.coord):
		return false
	return not CountryRules.may_enter(state, formation.owner_id, destination)


## One turn's movement along `route` from `from` with `budget` points; changes nothing. Returns
## {steps: hexes entered (ends with end), end, cost, stop}. Steps are taken while their cost fits
## the points left; the first step is always taken. `stop`: &"arrived" when the last route hex is
## the end, &"contact" when the walk ends in a hex next to an enemy that is not the last route
## hex or halts before a route hex holding an enemy (attack order; also without moving), else
## &"out_of_points". It never ends on another formation: it is cut back to the last free hex.
static func walk(
	state: OperationalState,
	formation: Formation,
	from: Vector2i,
	route: Array[Vector2i],
	budget: int,
	movement: OperationalMovement = null
) -> Dictionary:
	if movement == null:
		movement = OperationalMovement.shipped()
	var zone := _zone_of_control(state, formation)
	var steps: Array[Vector2i] = []
	var costs: Array[int] = []
	var spent := 0
	var previous := from
	var contact_index := -2  # index of the step that ended in contact (-1: before the first)
	for i in route.size():
		var hex := route[i]
		var holder := state.formation_at(hex)
		if holder != null and holder.owner_id != formation.owner_id:
			contact_index = steps.size() - 1
			break
		var step := movement.step_cost(state.grid, previous, hex)
		if step == Terrain.IMPASSABLE:
			break
		if i > 0 and spent + step > budget:
			break
		spent += step
		steps.append(hex)
		costs.append(spent)
		previous = hex
		if i < route.size() - 1 and zone.has(hex):
			contact_index = i
			break
	# Cut back to the last hex that holds no other formation.
	while not steps.is_empty():
		var other := state.formation_at(steps[steps.size() - 1])
		if other == null or other == formation:
			break
		steps.pop_back()
		costs.pop_back()
	var end := from
	var cost := 0
	if not steps.is_empty():
		end = steps[steps.size() - 1]
		cost = costs[costs.size() - 1]
	var stop := STOP_OUT_OF_POINTS
	if not route.is_empty() and end == route[route.size() - 1] and not steps.is_empty():
		stop = STOP_ARRIVED
	elif contact_index >= -1 and steps.size() == contact_index + 1:
		stop = STOP_CONTACT
	return {"steps": steps, "end": end, "cost": cost, "stop": stop}


## The hex where `formation` stands after each of its turns on the way to `destination`, assuming
## nothing else moves. Plans once, then walks the rest of the route turn by turn; ends after the
## walk that arrives, after a contact walk, after a walk that does not move, or after
## MAX_FORECAST_TURNS walks. Empty when there is no route.
static func forecast(
	state: OperationalState,
	formation: Formation,
	destination: Vector2i,
	budget: int,
	avoid_contact: bool,
	movement: OperationalMovement = null
) -> Array[Vector2i]:
	var stops: Array[Vector2i] = []
	var route := plan(state, formation, destination, avoid_contact, movement)
	var position := formation.coord
	var offset := 0
	for _turn in MAX_FORECAST_TURNS:
		if offset >= route.size():
			break
		var rest: Array[Vector2i] = route.slice(offset)
		var result := walk(state, formation, position, rest, budget, movement)
		var steps: Array[Vector2i] = result["steps"]
		if steps.is_empty():
			break
		position = result["end"]
		offset += steps.size()
		stops.append(position)
		if result["stop"] != STOP_OUT_OF_POINTS:
			break
	return stops


## Hexes next to a formation of the other player(s), as a set.
static func _zone_of_control(state: OperationalState, formation: Formation) -> Dictionary:
	var zone := {}
	for other in state.formations:
		if other.owner_id != formation.owner_id:
			for n in Hex.neighbors(other.coord):
				zone[n] = true
	return zone


## Dijkstra with a bucket queue (step costs are small integers) on dense arrays over the grid's
## bounding box. Returns the parent of every settled hex; stops once `target` is settled. Within
## one cost the first discovered hex goes first, and a hex's parent changes only on a strictly
## lower cost. Step costs are those of
## OperationalMovement.step_cost, inlined for speed.
@warning_ignore("integer_division")
static func _search(
	grid: HexGrid,
	movement: OperationalMovement,
	start: Vector2i,
	target: Vector2i,
	blocked: Dictionary
) -> Dictionary:
	# Dense layers over the bounding box padded by one hex (the padding is impassable, so the
	# neighbour loop needs no bounds checks): entering cost (0 = impassable), road links, river flag.
	var all := grid.coords()
	var min_c := Vector2i(1 << 30, 1 << 30)
	var max_c := Vector2i(-(1 << 30), -(1 << 30))
	for c in all:
		min_c = Vector2i(mini(min_c.x, c.x), mini(min_c.y, c.y))
		max_c = Vector2i(maxi(max_c.x, c.x), maxi(max_c.y, c.y))
	min_c -= Vector2i.ONE
	var width := max_c.x - min_c.x + 2
	var size := width * (max_c.y - min_c.y + 2)
	var enter := PackedInt32Array()
	enter.resize(size)
	var roads := PackedInt32Array()
	var rivers := PackedByteArray()
	var has_links := grid.has_links()
	if has_links:
		roads.resize(size)
		rivers.resize(size)
	var terrain_costs := movement.move_costs
	for c in all:
		var i := (c.x - min_c.x) + (c.y - min_c.y) * width
		enter[i] = terrain_costs[grid.get_terrain(c)]
		if has_links:
			roads[i] = grid.road_links(c)
			rivers[i] = 1 if grid.river_links(c) != 0 else 0
	for c: Vector2i in blocked:
		var bi := (c.x - min_c.x) + (c.y - min_c.y) * width
		if bi >= 0 and bi < size and c.x >= min_c.x and c.x < min_c.x + width:
			enter[bi] = 0
	var road_cost := movement.road_cost
	var river_extra := movement.river_extra_cost
	var deltas: Array[int] = []
	for d in Hex.DIRECTIONS:
		deltas.append(d.x + d.y * width)
	var start_i := (start.x - min_c.x) + (start.y - min_c.y) * width
	var target_i := (target.x - min_c.x) + (target.y - min_c.y) * width
	var costs := PackedInt32Array()
	costs.resize(size)
	costs.fill(1 << 30)
	var parents := PackedInt32Array()
	parents.resize(size)
	parents.fill(-1)
	var done := PackedByteArray()
	done.resize(size)
	var buckets: Array = [[start_i]]
	var heads: Array[int] = [0]
	var cost_now := 0
	costs[start_i] = 0
	while cost_now < buckets.size():
		var bucket: Array = buckets[cost_now]
		var head := heads[cost_now]
		if head >= bucket.size():
			cost_now += 1
			continue
		heads[cost_now] = head + 1
		var ci: int = bucket[head]
		if done[ci] == 1 or costs[ci] != cost_now:
			continue
		done[ci] = 1
		if ci == target_i:
			break
		var link_mask := roads[ci] if has_links else 0
		for d in 6:
			var ni := ci + deltas[d]
			var step := enter[ni]
			if step <= 0 or done[ni] == 1:
				continue
			if has_links:
				if (link_mask & (1 << d)) != 0:
					step = road_cost
				elif rivers[ni] == 1:
					step += river_extra
			var new_cost := cost_now + step
			if new_cost < costs[ni]:
				costs[ni] = new_cost
				parents[ni] = ci
				while buckets.size() <= new_cost:
					buckets.append([])
					heads.append(0)
				buckets[new_cost].append(ni)
	# Back to coordinates: the parent of every settled hex.
	var result := {}
	if parents[target_i] < 0:
		return result
	var cur := target_i
	while cur != start_i:
		var par := parents[cur]
		result[Vector2i(cur % width + min_c.x, cur / width + min_c.y)] = Vector2i(
			par % width + min_c.x, par / width + min_c.y
		)
		cur = par
	return result
