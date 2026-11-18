class_name HexControl
extends RefCounted
## Hex control of the operational layer (TASK-107a, GDD "Sides" Victory): a hex is held by the last
## side with a formation on it. Start: the side of the hex's country, a hex with a start formation
## belongs to that formation's side. A formation takes every hex it walks through (the
## whole route of a move, end hex included; human decision 2026-11-14) and the hex of a battle it
## wins (the attacker takes the defender's hex). No zones of control. Holders live in
## OperationalState (`hex_initial` static, `hex_holders` the changes, saved). No randomness.


## Fills `state.hex_initial` from the countries' sides and the formations standing now.
static func setup(state: OperationalState) -> void:
	state.hex_initial.clear()
	state.hex_holders.clear()
	for hex: Vector2i in state.country_map:
		var country := state.get_country(state.country_map[hex])
		if country != null and country.stance != CountryState.NEUTRAL and country.side >= 0:
			state.hex_initial[hex] = country.side
	for formation in state.formations:
		state.hex_initial[formation.coord] = formation.owner_id


## The side (0 / 1) holding `hex`, -1 when nobody does.
static func holder(state: OperationalState, hex: Vector2i) -> int:
	return state.hex_holders.get(hex, state.hex_initial.get(hex, -1))


## Whether a holder change on `hex` may matter for victory: it carries a hex objective, or it is
## a land hex while the operation has a connection objective (NATO's link or Russia's corridor,
## TASK-177: any land hex can be on a route).
static func is_objective_hex(state: OperationalState, hex: Vector2i) -> bool:
	var def := state.definition
	if def == null:
		return false
	if OperationVictory.has_gap_link(def) or OperationVictory.has_corridor(def):
		var grid := state.grid
		if grid != null and grid.has_tile(hex) and grid.move_cost(hex) != Terrain.IMPASSABLE:
			return true
	for objective in state.definition.objectives:
		if objective.hex_in(state) == hex:
			return true
	return false


## `side` takes `hex`. One event `objective_changed` {kind `holder`, objective_id, old, new, round,
## hex, holder, previous} per objective on the hex when the holder changed (the connection
## objectives give none here: `OperationalSimulation.execute` reports their status flips);
## [] otherwise. `old` / `new` / `holder` / `previous` are sides (-1 = unheld).
static func take(state: OperationalState, hex: Vector2i, side: int) -> Array[Dictionary]:
	var previous := holder(state, hex)
	if previous == side:
		return []
	state.hex_holders[hex] = side
	var events: Array[Dictionary] = []
	if state.definition == null:
		return events
	for objective in state.definition.objectives:
		if objective.hex_in(state) == hex:
			(
				events
				. append(
					{
						"type": &"objective_changed",
						"kind": &"holder",
						"objective_id": objective.id,
						"old": previous,
						"new": side,
						"round": state.turn,
						"hex": hex,
						"holder": side,
						"previous": previous,
					}
				)
			)
	return events
