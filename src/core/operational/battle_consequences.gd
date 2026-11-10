class_name BattleConsequences
extends RefCounted
## What a finished contact battle does to the operation (TASK-095, GDD "Battle hand-off and
## auto-resolve"): company losses, destroyed formations, the loser's retreat, readiness. It reads
## only `field_holder` / `retreat` and the per-company strengths of the result – never the
## kind of result (played or auto) – so a played and an auto-resolved battle
## with equal fields give equal states.
## Draws nothing from `state.rng`.


## Applies `result` of the battle `setup` (already popped from the queue) to `state`. Events:
## `formation_destroyed` (cause `battle`), `formation_order_interrupted` (`retreated`),
## `formation_retreated`, then `battle_consequences`.
static func apply(
	state: OperationalState, setup: BattleSetup, result: BattleResult
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ids := ContactBattle.formation_ids(setup)
	var by_player: Array[Formation] = [null, null]
	for id in ids:
		var formation := state.get_formation(id)
		if formation != null:
			by_player[formation.owner_id] = formation
	var losses: Array[int] = [0, 0]
	var strengths: Array = [[0, 0], [0, 0]]
	var readiness: Array = [[0, 0], [0, 0]]
	for player in 2:
		var formation := by_player[player]
		if formation != null:
			strengths[player][0] = formation.strength()
			readiness[player][0] = formation.readiness
	for company in result.companies:
		losses[company.player] += company.losses()
		var formation := by_player[company.player]
		if formation == null:
			continue
		for own in formation.companies:
			if own.ref == company.ref:
				own.strength = clampi(company.strength_end, 0, own.max_strength)
	var settings := AftermathSettings.shipped()
	for player in 2:
		var formation := by_player[player]
		if formation == null:
			continue
		var loss := (
			settings.readiness_loss_attacker
			if player == setup.attacker
			else settings.readiness_loss_defender
		)
		formation.readiness = maxi(0, formation.readiness - loss)
		formation.fought = true
		formation.companies = formation.companies.filter(
			func(c: Formation.Company) -> bool: return c.strength > 0
		)
		strengths[player][1] = formation.strength()
		readiness[player][1] = formation.readiness
		if formation.companies.is_empty():
			readiness[player][1] = 0
			state.formations.erase(formation)
			(
				events
				. append(
					{
						"type": &"formation_destroyed",
						"formation_id": formation.id,
						"player": player,
						"at": formation.coord,
						"before": strengths[player][0],
						"after": 0,
						"cause": &"battle",
					}
				)
			)
	if result.retreat >= 0 and by_player[result.retreat] != null:
		var retreating := by_player[result.retreat]
		if state.get_formation(retreating.id) != null:
			events.append_array(_retreat(state, retreating, by_player[1 - result.retreat]))
	(
		events
		. append(
			{
				"type": &"battle_consequences",
				"attacker_id": ids[0],
				"defender_id": ids[1],
				"losses": losses,
				"strength": strengths,
				"readiness": readiness,
				"field_holder": result.field_holder,
				"retreat": result.retreat,
			}
		)
	)
	return events


## The hex `formation` falls back to: a passable, free neighbour, outside the enemies' zones of
## control when another exists, never into a country closed to its owner, farthest from `enemy`
## (ties: `Hex.DIRECTIONS` order). Null when there is none.
static func retreat_hex(state: OperationalState, formation: Formation, enemy: Formation) -> Variant:
	var movement := OperationalMovement.shipped()
	var zone := {}
	for other in state.formations:
		if other.owner_id != formation.owner_id:
			for n in Hex.neighbors(other.coord):
				zone[n] = true
	var best: Variant = null
	var best_free := false
	var best_distance := -1
	for hex in Hex.neighbors(formation.coord):
		if state.formation_at(hex) != null:
			continue
		if movement.step_cost(state.grid, formation.coord, hex) == Terrain.IMPASSABLE:
			continue
		if not CountryRules.may_enter(state, formation.owner_id, hex):
			continue  # never into a country closed to the retreating player (TASK-116)
		var free := not zone.has(hex)
		var distance := Hex.distance(hex, enemy.coord) if enemy != null else 0
		if (
			best == null
			or (free and not best_free)
			or (free == best_free and distance > best_distance)
		):
			best = hex
			best_free = free
			best_distance = distance
	return best


## At the start of the new current player's turn: a formation of that player that did not fight
## since its last turn began regains `readiness_recovery`; the `fought` marks are cleared.
## Event `formation_readiness_changed` for each formation whose readiness rose.
static func recover_readiness(state: OperationalState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var recovery := AftermathSettings.shipped().readiness_recovery
	for formation in state.formations:
		if formation.owner_id != state.current_player:
			continue
		if not formation.fought:
			var before := formation.readiness
			formation.readiness = mini(100, before + recovery)
			if formation.readiness != before:
				(
					events
					. append(
						{
							"type": &"formation_readiness_changed",
							"formation_id": formation.id,
							"before": before,
							"after": formation.readiness,
						}
					)
				)
		formation.fought = false
	return events


static func _retreat(
	state: OperationalState, formation: Formation, enemy: Formation
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var from := formation.coord
	var target: Variant = retreat_hex(state, formation, enemy)
	if formation.order != null:
		formation.order = null
		(
			events
			. append(
				{
					"type": &"formation_order_interrupted",
					"formation_id": formation.id,
					"reason": &"retreated",
					"at": from,
				}
			)
		)
	if target != null:
		formation.coord = target as Vector2i
	(
		events
		. append(
			{
				"type": &"formation_retreated",
				"formation_id": formation.id,
				"from": from,
				"to": formation.coord,
				"blocked": target == null,
			}
		)
	)
	return events
