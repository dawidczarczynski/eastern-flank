class_name ContactRules
extends RefCounted
## When and how a contact starts a battle (TASK-094a, GDD "Battle hand-off and auto-resolve").
## `battle_allowed` is the one predicate every contact asks; TASK-116 (border rule) and TASK-100
## (fog) extend it.

const INTENT_MOVE := "MISSION_INTENT_MOVE"
const INTENT_HOLD := "MISSION_INTENT_HOLD"


## True when `attacker` may fight `defender`: the defender's hex must be open to the attacker
## (TASK-116 border rule – no battle against a formation in a country closed to the attacker).
static func battle_allowed(
	state: OperationalState, attacker: Formation, defender: Formation
) -> bool:
	return CountryRules.may_enter(state, attacker.owner_id, defender.coord)


## Starts the battles of this step's `formation_halted` (reason contact) events, in event order:
## the halted formation attacks the first adjacent enemy (Hex.DIRECTIONS order) that is allowed
## and not in a battle yet; a formation takes part in one pending battle per step. Appends to
## `state.pending_battles` (one `state.rng` draw each) and emits `battle_pending` into `events`.
static func start_battles(state: OperationalState, events: Array[Dictionary]) -> void:
	var halted: Array[Formation] = []
	for event in events:
		if event["type"] == &"formation_halted" and event["reason"] == &"contact":
			halted.append(state.get_formation(event["formation_id"] as StringName))
	var engaged := {}
	for attacker in halted:
		if attacker == null or engaged.has(attacker.id):
			continue
		var defender := _find_defender(state, attacker, engaged)
		if defender == null:
			var closed := _border_forbidden(state, attacker, engaged)
			if closed != null:
				(
					events
					. append(
						{
							"type": &"contact_forbidden",
							"attacker_id": attacker.id,
							"defender_id": closed.id,
							"at": closed.coord,
							"country": state.country_at(closed.coord),
						}
					)
				)
			continue
		engaged[attacker.id] = true
		engaged[defender.id] = true
		state.pending_battles.append(_build_setup(state, attacker, defender))
		var pending := {
			"type": &"battle_pending",
			"attacker_id": attacker.id,
			"defender_id": defender.id,
			"at": defender.coord,
			"index": state.pending_battles.size() - 1,
		}
		events.append(pending)


static func _find_defender(
	state: OperationalState, attacker: Formation, engaged: Dictionary
) -> Formation:
	for neighbor in Hex.neighbors(attacker.coord):
		var other := state.formation_at(neighbor)
		if other == null or other.owner_id == attacker.owner_id or engaged.has(other.id):
			continue
		if battle_allowed(state, attacker, other):
			return other
	return null


## The first adjacent enemy that only the border rule keeps `attacker` from fighting, else null.
static func _border_forbidden(
	state: OperationalState, attacker: Formation, engaged: Dictionary
) -> Formation:
	for neighbor in Hex.neighbors(attacker.coord):
		var other := state.formation_at(neighbor)
		if other == null or other.owner_id == attacker.owner_id or engaged.has(other.id):
			continue
		if not battle_allowed(state, attacker, other):
			return other
	return null


static func _build_setup(
	state: OperationalState, attacker: Formation, defender: Formation
) -> BattleSetup:
	var setup := BattleSetup.new()
	setup.seed = state.rng.randi()
	setup.map_id = state.map_id
	setup.operation_name = state.operation_name
	setup.factions = state.player_factions.duplicate()
	setup.attacker = attacker.owner_id
	setup.terrain = Terrain.definition(state.grid.get_terrain(defender.coord)).id
	setup.objectives = BattleObjectives.default_objectives()
	var sides: Array[Formation] = [null, null]
	sides[attacker.owner_id] = attacker
	sides[defender.owner_id] = defender
	setup.conditions.resize(2)
	setup.missions.resize(2)
	for player in 2:
		var formation := sides[player]
		var posture := OperationalPosture.find(formation.posture)
		var conditions := BattleConditionsRules.for_side(state.installations, player)
		conditions.posture = formation.posture
		conditions.position_bonus = 0 if posture == null else posture.position_bonus
		setup.conditions[player] = conditions
		setup.missions[player] = _mission(formation, formation == attacker)
	for formation in [attacker, defender]:
		for company: Formation.Company in formation.companies:
			if company.strength <= 0:
				continue  # a strike can leave a dead company in a surviving formation
			var planned := BattleSetup.Company.new()
			planned.player = formation.owner_id
			planned.unit_type = company.unit_type
			planned.coord = Vector2i.ZERO
			planned.strength = company.strength
			planned.ref = company.ref
			setup.companies.append(planned)
	return setup


static func _mission(formation: Formation, attacking: bool) -> BattleSetup.Mission:
	var mission := BattleSetup.Mission.new()
	if attacking:
		mission.task = &"attack"
	elif formation.posture == &"march":
		mission.task = &"hold_out"
	else:
		mission.task = &"defend"
	mission.formation_name = formation.display_name
	if formation.order != null:
		mission.intent_key = INTENT_MOVE
		mission.intent_args = [formation.order.destination.x, formation.order.destination.y]
	else:
		mission.intent_key = INTENT_HOLD
		mission.intent_args = [formation.coord.x, formation.coord.y]
	return mission
