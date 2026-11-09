class_name ContactBattle
extends RefCounted
## Playing a pending contact battle (TASK-094c, GDD "Battle hand-off and auto-resolve"): the
## first pending BattleSetup on its real terrain (ContactMap.build on the two formations'
## operational hexes). The played battle comes back as `ResolveBattleCommand(BattleResult
## .from_battle(prepared setup, battle state))` (Session). Pure: nothing here changes the state or
## draws from an RNG; the battle's own seed is the setup's.


## Why the first pending battle cannot be played ("" = it can): `no_pending_battle`,
## `formation_missing` (a company ref names no formation) or `not_fieldable` (a company's unit is
## not in its player's battle faction).
static func problem(state: OperationalState) -> String:
	if state.pending_battles.is_empty():
		return "no_pending_battle"
	var setup := state.pending_battles[0]
	if hexes(state, setup).size() != 2:
		return "formation_missing"
	for company in setup.companies:
		var faction_id: StringName = (
			setup.factions[company.player] if company.player < setup.factions.size() else &""
		)
		var faction := FactionRegistry.get_faction(faction_id)
		if faction == null or faction.find_unit(company.unit_type) == null:
			return "not_fieldable"
	return ""


## The first pending battle ready to play: a copy with its map cut (ContactMap.build); the
## pending setup itself is not changed. Null when `problem` is not "" or the map cannot be cut
## (ContactMap reports why).
static func prepare(state: OperationalState) -> BattleSetup:
	if problem(state) != "":
		return null
	var setup := state.pending_battles[0]
	var at := hexes(state, setup)
	return ContactMap.build(setup, at[0], at[1])


## Formation ids [attacker, defender] of a contact battle, from its company refs
## "<formation id>/<n>"; an id is &"" when the side has no company.
static func formation_ids(setup: BattleSetup) -> Array[StringName]:
	var ids: Array[StringName] = [&"", &""]
	for company in setup.companies:
		ids[0 if company.player == setup.attacker else 1] = formation_of(company.ref)
	return ids


## Formation id of a company ref "<formation id>/<n>".
static func formation_of(ref: String) -> StringName:
	return StringName(ref.rsplit("/", true, 1)[0])


## Operational hexes [attacker, defender] of the battle's two formations; empty when one is
## missing from the state.
static func hexes(state: OperationalState, setup: BattleSetup) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for id in formation_ids(setup):
		var formation := state.get_formation(id)
		if formation == null:
			return []
		result.append(formation.coord)
	return result
