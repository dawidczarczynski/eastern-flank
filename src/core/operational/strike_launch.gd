class_name StrikeLaunch
extends RefCounted
## Where a deep strike is launched from (TASK-147, GDD "Deep strikes"): the hex of the launcher or
## carrier shown on the staff map. Pure and deterministic, no `state.rng` draw, no state change:
## a presentation fact recorded in `strike_launched`, read by no rule. [ASSUMPTION] until the map
## has real launch sites. Moved from StaffMapStrikeTrail (TASK-097b / TASK-141b): `origin` and
## the standoff rule.

## The launch point of the standoff rule is searched at this share of the weapon's range.
const STANDOFF_SHARE := 0.9
## Launch sites per launcher kind (fighters and bombers both fly from airfields): own
## installations of `installations` (not destroyed) and own formations of `formations`
## (formation_class). Ships and submarines use the sea instead; a kind without sites always takes
## the standoff point.
const SITES := {
	&"fighter": {"installations": [&"airfield"], "formations": []},
	&"bomber": {"installations": [&"airfield"], "formations": []},
	&"launcher": {"installations": [], "formations": [&"artillery"]},
	&"drone_site": {"installations": [], "formations": []},
}
const SEA_KINDS: Array[StringName] = [&"ship", &"submarine"]


## The launch hex of `means_id` fired by `player` at `target`: the own site of the weapon's
## launcher kind (SITES) within the weapon's range that is nearest the target (ties: smaller x,
## then y); ships and submarines: a sea hex, `_sea_origin`. Else the standoff point
## `standoff_origin`. An unknown means gives the border hex `origin`.
static func launch_origin(
	state: OperationalState, player: int, means_id: StringName, target: Vector2i
) -> Vector2i:
	var means: StrikeMeansDefinition = state.strike_means.get(means_id)
	if means == null:
		return origin(state, player, target)
	if SEA_KINDS.has(means.launcher_kind):
		var sea := _sea_origin(state, player, target, means.range_hexes)
		if sea.size() == 1:
			return sea[0]
		return standoff_origin(state, player, target, means.range_hexes)
	var candidates := _sites(state, player, means.launcher_kind)
	var best := Vector2i.ZERO
	var best_distance := -1
	for hex in candidates:
		var distance := Hex.distance(hex, target)
		if distance > means.range_hexes:
			continue
		if (
			best_distance < 0
			or distance < best_distance
			or (distance == best_distance and _before(hex, best))
		):
			best = hex
			best_distance = distance
	if best_distance >= 0:
		return best
	return standoff_origin(state, player, target, means.range_hexes)


## The nearest hex (by hex distance) of a country that is own to `player`: the hex the range of a
## strike is measured from. Ties go to the smaller (x, y). `target` itself when there is none.
static func origin(state: OperationalState, player: int, target: Vector2i) -> Vector2i:
	var own := _own_countries(state, player)
	var best := target
	var best_distance := -1
	for hex: Vector2i in state.country_map:
		if not own.get(state.country_map[hex], false):
			continue
		var distance := Hex.distance(hex, target)
		if (
			best_distance < 0
			or distance < best_distance
			or (distance == best_distance and _before(hex, best))
		):
			best = hex
			best_distance = distance
	return best


## The standoff rule: of the own hexes within `range_hexes` of `target`, the one whose distance is
## closest to STANDOFF_SHARE of the range (so a long-range weapon, with no own hex that far, fires
## from the farthest own hex in range); ties go to the smaller x, then y. When no own hex is within
## range it is the nearest own (border) hex, `origin()`; `target` itself when nothing is own.
static func standoff_origin(
	state: OperationalState, player: int, target: Vector2i, range_hexes: int
) -> Vector2i:
	var border := origin(state, player, target)
	if not _is_own(state, player, border):
		return target
	var wanted := range_hexes * STANDOFF_SHARE
	var best := border
	var best_gap := INF
	for hex: Vector2i in state.country_map:
		if not _is_own(state, player, hex):
			continue
		var distance := Hex.distance(hex, target)
		if distance > range_hexes:
			continue
		var gap := absf(distance - wanted)
		if gap < best_gap or (gap == best_gap and _before(hex, best)):
			best = hex
			best_gap = gap
	return best


## Own installation and formation hexes of the launcher kind's sites, in setup order.
static func _sites(state: OperationalState, player: int, kind: StringName) -> Array[Vector2i]:
	var hexes: Array[Vector2i] = []
	var sites: Dictionary = SITES.get(kind, {})
	var classes: Array = sites.get("installations", [])
	var formation_classes: Array = sites.get("formations", [])
	for installation in state.installations:
		if (
			installation.owner == player
			and not installation.destroyed()
			and classes.has(installation.class_id)
		):
			hexes.append(installation.coord)
	for formation in state.formations:
		if (
			formation.owner_id == player
			and formation.definition != null
			and formation_classes.has(formation.definition.formation_class)
		):
			hexes.append(formation.coord)
	return hexes


## The launch hex of a ship: of the sea hexes (water of no country) within `range_hexes` of the
## target, the one nearest the own coast (steps over the map from an own land hex; 1 = next to
## it), then nearest the target, then smaller x, then y. [] when there is none (no sea in range
## or nothing own). One breadth-first search over the map, no rng.
static func _sea_origin(
	state: OperationalState, player: int, target: Vector2i, range_hexes: int
) -> Array[Vector2i]:
	var own := _own_countries(state, player)
	var steps := {}
	var frontier: Array[Vector2i] = []
	for hex: Vector2i in state.country_map:
		if own.get(state.country_map[hex], false) and not _is_water(state, hex):
			steps[hex] = 0
			frontier.append(hex)
	var best: Array[Vector2i] = []
	var best_distance := 0
	while not frontier.is_empty():
		var next_frontier: Array[Vector2i] = []
		for hex in frontier:
			for next in Hex.neighbors(hex):
				if steps.has(next) or not state.grid.has_tile(next):
					continue
				steps[next] = int(steps[hex]) + 1
				next_frontier.append(next)
				if state.country_map.has(next) or not _is_water(state, next):
					continue
				var distance := Hex.distance(next, target)
				if distance > range_hexes:
					continue
				if (
					best.is_empty()
					or distance < best_distance
					or (distance == best_distance and _before(next, best[0]))
				):
					best = [next]
					best_distance = distance
		if not best.is_empty():
			return best
		frontier = next_frontier
	return best


static func _is_water(state: OperationalState, hex: Vector2i) -> bool:
	return state.grid.has_tile(hex) and state.grid.get_terrain(hex) == Terrain.Type.WATER


static func _own_countries(state: OperationalState, player: int) -> Dictionary:
	var own := {}
	for country in state.countries:
		own[country.id] = CountryRules.relation(state, player, country.id) == &"own"
	return own


static func _is_own(state: OperationalState, player: int, hex: Vector2i) -> bool:
	return (
		state.country_map.has(hex)
		and CountryRules.relation(state, player, state.country_map[hex]) == &"own"
	)


static func _before(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)
