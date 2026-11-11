class_name Reinforcements
extends RefCounted
## Puts new formations on the staff map (TASK-118; TASK-121 reuses it for off-map support). Pure:
## appends to `state.formations`, no randomness.

## Farthest fallback hex from the wanted one, in hexes.
const FALLBACK_RANGE := 3


## Places `placements` for `player`. Each goes on its `coord` when that hex is free (no formation)
## and passable; otherwise on the nearest free passable hex of the same country within
## FALLBACK_RANGE (ring order from Hex.DIRECTIONS[0]). Wanted hexes of the whole batch are served
## first, so a fallback never takes a hex another placement asked for. With `require_open` hexes
## that are closed to `player` (CountryRules.may_enter) are skipped too. New formations are
## appended in placement order, with full strength, `state.initial_posture` and no order, owned by
## `player`; each adds its max_strength() to `state.fielded_strength[player]` (TASK-140). Returns
## {events, unplaced}: `formation_joined` per placed formation (`source` is
## copied) and, unless `require_open`, `formation_join_failed` per unplaced one, in placement
## order.
static func place(
	state: OperationalState,
	placements: Array[FormationPlacement],
	player: int,
	source: StringName,
	require_open := false
) -> Dictionary:
	var targets: Array = []
	var taken := {}
	for placement in placements:
		var coord := placement.coord
		var ok := _is_free(state, coord, player, require_open, taken)
		targets.append(coord if ok else null)
		if ok:
			taken[coord] = true
	for index in placements.size():
		if targets[index] == null:
			targets[index] = _fallback(state, placements[index].coord, player, require_open, taken)
			if targets[index] != null:
				taken[targets[index]] = true
	var events: Array[Dictionary] = []
	var unplaced: Array[FormationPlacement] = []
	for index in placements.size():
		var placement := placements[index]
		if targets[index] == null:
			unplaced.append(placement)
			if not require_open:
				(
					events
					. append(
						{
							"type": &"formation_join_failed",
							"formation_id": placement.id,
							"country": state.country_at(placement.coord),
							"reason": &"no_free_hex",
						}
					)
				)
			continue
		var coord: Vector2i = targets[index]
		var formation := Formation.from_placement(placement, state.initial_posture)
		formation.owner_id = player
		formation.coord = coord
		state.formations.append(formation)
		state.fielded_strength[player] += formation.max_strength()
		(
			events
			. append(
				{
					"type": &"formation_joined",
					"formation_id": placement.id,
					"player": player,
					"country": state.country_at(coord),
					"coord": coord,
					"source": source,
				}
			)
		)
	return {"events": events, "unplaced": unplaced}


static func _fallback(
	state: OperationalState, center: Vector2i, player: int, require_open: bool, taken: Dictionary
) -> Variant:
	var country := state.country_at(center)
	for radius in range(1, FALLBACK_RANGE + 1):
		var coord := center + Hex.DIRECTIONS[0] * radius
		for side in 6:
			var step := Hex.DIRECTIONS[(side + 2) % 6]
			for _i in radius:
				if (
					state.country_at(coord) == country
					and _is_free(state, coord, player, require_open, taken)
				):
					return coord
				coord += step
	return null


static func _is_free(
	state: OperationalState, coord: Vector2i, player: int, require_open: bool, taken: Dictionary
) -> bool:
	if taken.has(coord) or not state.grid.has_tile(coord):
		return false
	if state.grid.move_cost(coord) == Terrain.IMPASSABLE or state.formation_at(coord) != null:
		return false
	return not require_open or CountryRules.may_enter(state, player, coord)
