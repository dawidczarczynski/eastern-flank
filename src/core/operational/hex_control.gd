class_name HexControl
extends RefCounted
## Hex control of the operational layer (TASK-107a, GDD "Sides" Victory): a hex is held by the last
## side with a formation on it. Start: the side of the hex's country, a hex with a start formation
## belongs to that formation's side. A formation takes a hex by ending its move there or by
## winning the battle there (the attacker takes the defender's hex); passing through changes
## nothing. No zones of control. Holders live in OperationalState (`hex_initial` static,
## `hex_holders` the changes, saved). No randomness.


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


## Whether `hex` carries a victory objective or belongs to the Gap chain.
static func is_objective_hex(state: OperationalState, hex: Vector2i) -> bool:
	if state.definition == null:
		return false
	if state.definition.gap_chain.has(hex):
		return true
	for objective in state.definition.objectives:
		if objective.hex_in(state) == hex:
			return true
	return false


## `side` takes `hex`. Event `objective_changed` {hex, holder, previous} when the holder changed
## and the hex carries an objective or is a chain hex; [] otherwise.
static func take(state: OperationalState, hex: Vector2i, side: int) -> Array[Dictionary]:
	var previous := holder(state, hex)
	if previous == side:
		return []
	state.hex_holders[hex] = side
	if not is_objective_hex(state, hex):
		return []
	return [{"type": &"objective_changed", "hex": hex, "holder": side, "previous": previous}]
