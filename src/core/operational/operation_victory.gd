class_name OperationVictory
extends RefCounted
## Victory of an operation (TASK-107a, TASK-177, GDD "Sides" Victory): the state of NATO's link
## (Suwałki - Kaunas) and Russia's corridor (Kaliningrad - Belarus), both connectivity checks over
## land hexes, the score of both sides by one rule, and the endings checked at the end of a round
## (annihilation, `corridor_closed`, then `round_limit`). Pure; the data is an
## OperationDefinition. Draws nothing from `state.rng`.

const OPEN := &"open"
const CUT := &"cut"
const CLOSED := &"closed"
## Walkability rules of `_route`.
const ANY_LAND := 0
const SIDE_1 := 1
const NOT_SIDE_1 := 2


## NATO's link: `open` while a route of land hexes none of which side 1 holds joins
## `nato_link_from` with `nato_link_to` (neutral hexes allowed, no road needed), else `cut`. Without
## a link (the ends unset) or without a grid it is `open`.
static func gap_status(state: OperationalState, def: OperationDefinition) -> StringName:
	if not has_gap_link(def) or state.grid == null:
		return OPEN
	return OPEN if not gap_route(state, def).is_empty() else CUT


## Russia's corridor: `closed` while a route of land hexes all held by side 1 joins a hex of
## `corridor_from_country` with a hex of `corridor_to_country`, else `open` (also without a
## corridor or a grid).
static func corridor_status(state: OperationalState, def: OperationDefinition) -> StringName:
	if not has_corridor(def) or state.grid == null:
		return OPEN
	return CLOSED if not corridor_route(state, def).is_empty() else OPEN


## Whether the operation has NATO's link objective (both ends set).
static func has_gap_link(def: OperationDefinition) -> bool:
	return def.nato_link_from != Vector2i.MAX and def.nato_link_to != Vector2i.MAX


## Whether the operation has Russia's corridor objective (both countries set).
static func has_corridor(def: OperationDefinition) -> bool:
	return def.corridor_from_country != &"" and def.corridor_to_country != &""


## A shortest route (ends included) of land hexes not held by side 1 from `nato_link_from` to
## `nato_link_to`; [] when the link is cut or missing.
static func gap_route(state: OperationalState, def: OperationDefinition) -> Array[Vector2i]:
	if not has_gap_link(def) or state.grid == null:
		return []
	var starts: Array[Vector2i] = [def.nato_link_from]
	return _route(state, starts, def.nato_link_to, &"", &"", NOT_SIDE_1)


## A shortest route (ends included: a hex of each country) of land hexes all held by side 1
## between the corridor's two countries; [] when the corridor is open or missing.
static func corridor_route(state: OperationalState, def: OperationDefinition) -> Array[Vector2i]:
	if not has_corridor(def) or state.grid == null:
		return []
	var from := def.corridor_from_country
	return _route(
		state, border_hexes(state, from), Vector2i.MAX, def.corridor_to_country, from, SIDE_1
	)


## A shortest land route between the two ends of an objective whatever the holders: the NATO link
## (`gap` = true) or the corridor between its countries (ends included); [] when the objective is
## missing or the ends are not joined by land. For the view (framing, the ribbon).
static func land_route(
	state: OperationalState, def: OperationDefinition, gap: bool
) -> Array[Vector2i]:
	if state.grid == null:
		return []
	if gap:
		if not has_gap_link(def):
			return []
		var starts: Array[Vector2i] = [def.nato_link_from]
		return _route(state, starts, def.nato_link_to, &"", &"", ANY_LAND)
	if not has_corridor(def):
		return []
	var from := def.corridor_from_country
	return _route(
		state, border_hexes(state, from), Vector2i.MAX, def.corridor_to_country, from, ANY_LAND
	)


## Land hexes of the country `country_id` (state.country_map), sorted.
static func country_hexes(state: OperationalState, country_id: StringName) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for hex: Vector2i in state.country_map:
		if state.country_map[hex] == country_id and _is_land(state.grid, hex):
			result.append(hex)
	result.sort()
	return result


## Land hexes of `country_id` with a land neighbour outside it, sorted: every route that leaves the
## country leaves through one of them. Derived from the static map and cached in
## `state.border_cache`.
static func border_hexes(state: OperationalState, country_id: StringName) -> Array[Vector2i]:
	if state.border_cache.has(country_id):
		return state.border_cache[country_id]
	var result: Array[Vector2i] = []
	for hex in country_hexes(state, country_id):
		for direction in Hex.DIRECTIONS:
			var next: Vector2i = hex + direction
			if state.country_at(next) != country_id and _is_land(state.grid, next):
				result.append(hex)
				break
	state.border_cache[country_id] = result
	return result


static func _is_land(grid: HexGrid, hex: Vector2i) -> bool:
	return grid != null and grid.has_tile(hex) and grid.move_cost(hex) != Terrain.IMPASSABLE


static func _walkable(state: OperationalState, hex: Vector2i, rule: int) -> bool:
	if not _is_land(state.grid, hex):
		return false
	if rule == ANY_LAND:
		return true
	var holder: int = state.hex_holders.get(hex, state.hex_initial.get(hex, -1))
	return (holder == 1) == (rule == SIDE_1)


## A* over neighbouring land hexes walkable by `rule` (unit steps; heuristic: the hex distance to
## `goal_hex`, 0 when the goal is a country) from the walkable `starts` to `goal_hex` or the first
## hex of `goal_country`; hexes of `skip_country` are never entered (the starts are its border
## hexes). The route with both ends, [] when none. Deterministic: starts in order, neighbours in
## Hex.DIRECTIONS order, ties last-in first-out; no randomness.
static func _route(
	state: OperationalState,
	starts: Array[Vector2i],
	goal_hex: Vector2i,
	goal_country: StringName,
	skip_country: StringName,
	rule: int
) -> Array[Vector2i]:
	var by_hex := goal_hex != Vector2i.MAX
	var came_from := {}
	var cost := {}
	var buckets: Array[Array] = []
	for start in starts:
		if not cost.has(start) and _walkable(state, start, rule):
			came_from[start] = start
			cost[start] = 0
			_push(buckets, Hex.distance(start, goal_hex) if by_hex else 0, start)
	var f := 0
	while f < buckets.size():
		var bucket: Array = buckets[f]
		if bucket.is_empty():
			f += 1
			continue
		var hex: Vector2i = bucket.pop_back()
		var g: int = cost[hex]
		if g + (Hex.distance(hex, goal_hex) if by_hex else 0) != f:
			continue  # a stale entry: the hex was reached cheaper later
		if hex == goal_hex or (not by_hex and state.country_at(hex) == goal_country):
			return _walk_back(came_from, hex)
		for direction in Hex.DIRECTIONS:
			var next: Vector2i = hex + direction
			if cost.get(next, 1 << 30) <= g + 1:
				continue
			if skip_country != &"" and state.country_at(next) == skip_country:
				continue
			if not _walkable(state, next, rule):
				continue
			came_from[next] = hex
			cost[next] = g + 1
			var next_f := g + 1 + (Hex.distance(next, goal_hex) if by_hex else 0)
			_push(buckets, next_f, next)
			f = mini(f, next_f)
	return []


static func _push(buckets: Array[Array], f: int, hex: Vector2i) -> void:
	while buckets.size() <= f:
		buckets.append([])
	buckets[f].append(hex)


static func _walk_back(came_from: Dictionary, last: Vector2i) -> Array[Vector2i]:
	var route: Array[Vector2i] = [last]
	var hex := last
	while came_from[hex] != hex:
		hex = came_from[hex]
		route.append(hex)
	route.reverse()
	return route


## Points lost by `side` for its net escalation steps, as a number <= 0.
static func penalty(state: OperationalState, def: OperationDefinition, side: int) -> int:
	var net := maxi(0, state.escalation_caused[side] - state.escalation_deescalated[side])
	return -def.escalation_penalty * net


## Score of `side`: {lines: [{id, points}], escalation_penalty, total}. Objective lines carry the
## objective id; side 0 adds `gap_open` while NATO's link is open, side 1 `corridor` while the
## corridor is closed (each only when the operation has that objective).
static func side_score(state: OperationalState, def: OperationDefinition, side: int) -> Dictionary:
	var lines: Array[Dictionary] = []
	var total := 0
	for objective in def.objectives:
		if objective.scorer(HexControl.holder(state, objective.hex_in(state))) == side:
			lines.append({"id": objective.id, "points": objective.points})
			total += objective.points
	if side == 0 and has_gap_link(def) and gap_status(state, def) == OPEN:
		lines.append({"id": &"gap_open", "points": def.gap_open_points})
		total += def.gap_open_points
	if side == 1 and corridor_status(state, def) == CLOSED:
		lines.append({"id": &"corridor", "points": def.corridor_points})
		total += def.corridor_points
	var cost := penalty(state, def, side)
	return {"lines": lines, "escalation_penalty": cost, "total": total + cost}


## {0: breakdown, 1: breakdown} (see side_score).
static func score(state: OperationalState, def: OperationDefinition) -> Dictionary:
	return {0: side_score(state, def, 0), 1: side_score(state, def, 1)}


## The winner of the totals: the higher side, -1 when the difference is under `draw_margin`.
static func winner_of(scores: Dictionary, def: OperationDefinition) -> int:
	var diff: int = scores[0]["total"] - scores[1]["total"]
	if absi(diff) < def.draw_margin or diff == 0:
		return -1
	return 0 if diff > 0 else 1


## Annihilation (TASK-164): a side is wiped when it fielded something, has no formation on the map
## and no requested, not withdrawn support package with placements still waiting. The survivor
## wins whatever the score is; both wiped = draw (winner and by -1). Sets `state.result` and
## returns `operation_ended` when it fires; [] otherwise (also without a definition or when the
## operation is already over). Called after every command that can destroy a formation.
static func annihilation(state: OperationalState) -> Array[Dictionary]:
	if state.definition == null or not state.result.is_empty():
		return []
	var wiped_0 := wiped(state, 0)
	var wiped_1 := wiped(state, 1)
	if not wiped_0 and not wiped_1:
		return []
	var survivor := -1 if wiped_0 == wiped_1 else (1 if wiped_0 else 0)
	return end(state, survivor, &"annihilation", survivor)


## True when `side` has lost everything: see `annihilation`.
static func wiped(state: OperationalState, side: int) -> bool:
	if state.definition == null or state.fielded_strength[side] <= 0:
		return false
	for formation in state.formations:
		if formation.owner_id == side:
			return false
	for pending in state.support:
		if (
			pending.definition.side == side
			and pending.requested()
			and not pending.withdrawn
			and not pending.waiting.is_empty()
		):
			return false
	return true


## Checks at the end of the finished round `round_number` (callers: EndOperationalTurnCommand
## when play returns to the first player): `annihilation` first (a support package withdrawn at
## the boundary), then the corridor counter, `corridor_closed`, then `round_limit`. Sets
## `state.result` and returns `operation_ended` when one fires; [] otherwise (also without a
## definition or when the operation is already over).
static func end_round(state: OperationalState, round_number: int) -> Array[Dictionary]:
	var def := state.definition
	if def == null or not state.result.is_empty():
		return []
	var wiped_out := annihilation(state)
	if not wiped_out.is_empty():
		return wiped_out
	var previous := state.corridor_closed_rounds
	if corridor_status(state, def) == CLOSED:
		state.corridor_closed_rounds += 1
	else:
		state.corridor_closed_rounds = 0
	var events: Array[Dictionary] = []
	if state.corridor_closed_rounds != previous:
		events.append(
			objective_event(
				&"corridor_counter",
				&"corridor",
				previous,
				state.corridor_closed_rounds,
				round_number
			)
		)
	if state.corridor_closed_rounds >= def.closed_rounds_to_win:
		events.append_array(end(state, 1, &"corridor_closed", 1))
	elif round_number >= def.round_limit:
		events.append_array(end(state, winner_of(score(state, def), def), &"round_limit", -1))
	return events


## Event `objective_changed` for a connection objective: kind `gap` (objective_id `gap`, old /
## new = OPEN / CUT), `corridor` (objective_id `corridor`, OPEN / CLOSED) or `corridor_counter`
## (objective_id `corridor`, old / new = closed rounds in a row). Carries no side wording.
static func objective_event(
	kind: StringName, objective_id: StringName, old: Variant, new: Variant, round_number: int
) -> Dictionary:
	return {
		"type": &"objective_changed",
		"kind": kind,
		"objective_id": objective_id,
		"old": old,
		"new": new,
		"round": round_number,
	}


## Ends the operation: sets `state.result` {winner, reason, by} and returns the `operation_ended`
## event with the `score` payload {0: breakdown, 1: breakdown} (an empty one without a definition).
static func end(
	state: OperationalState, winner: int, reason: StringName, by: int
) -> Array[Dictionary]:
	state.result = {"winner": winner, "reason": reason, "by": by}
	state.pending_battles.clear()
	var scores := {} if state.definition == null else score(state, state.definition)
	return [
		{"type": &"operation_ended", "winner": winner, "reason": reason, "by": by, "score": scores}
	]
