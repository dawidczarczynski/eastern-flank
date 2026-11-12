class_name OperationalPolitics
extends RefCounted
## The political half of the operational AI (TASK-102b, GDD "Operational AI" / "Political
## decisions"): picks at most one decision for a side by a few data-driven rules (thresholds in
## AiProfile). Pure and deterministic, side-agnostic, never changes the state: every returned
## command already passes `validate()` against it. Outside support (TASK-121 / 122) is not
## planned yet – there is no such command.
##
## Priority: Stand down, Demand neutrality, Invoke alliance, Declare hostilities, Escalate; Use
## nuclear weapon only when none of them applies.


## The decision `player` takes this turn, or null when there is none worth taking. `goals` are
## the player's goals as OperationalAi._goals gives them.
static func decide(
	state: OperationalState, player: int, profile: AiProfile, goals: Array[Dictionary]
) -> PoliticalDecisionCommand:
	var own := _own_coords(state, player)
	var untaken := _untaken_take_goals(goals, own)
	var choices: Array[PoliticalDecisionCommand] = [
		_stand_down(state, player, profile, own, untaken),
		_demand_neutrality(state, player, profile),
		_invoke_alliance(state, player, goals),
		_declare_hostilities(state, player, profile, untaken),
		_escalate(state, profile, untaken),
	]
	for choice in choices:
		if choice != null:
			return choice
	return _nuclear_strike(state)


static func _own_coords(state: OperationalState, player: int) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for formation in state.formations:
		if formation.owner_id == player:
			coords.append(formation.coord)
	return coords


## The `take` goals no own formation stands on.
static func _untaken_take_goals(
	goals: Array[Dictionary], own: Array[Vector2i]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for goal in goals:
		if goal["role"] == AiGoal.TAKE and not own.has(goal["coord"]):
			result.append(goal)
	return result


static func _valid(state: OperationalState, command: PoliticalDecisionCommand) -> bool:
	return command.validate(state) == ""


static func _stand_down(
	state: OperationalState,
	player: int,
	profile: AiProfile,
	own: Array[Vector2i],
	untaken: Array[Dictionary]
) -> PoliticalDecisionCommand:
	var weary := CollapseRules.in_collapse(state, player)
	if not weary:
		weary = state.escalation_level >= profile.stand_down_level and untaken.is_empty()
	if not weary:
		return null
	for goal in untaken:
		for coord in own:
			if Hex.distance(coord, goal["coord"]) <= profile.stand_down_goal_range:
				return null
	var command := StandDownCommand.new()
	return command if _valid(state, command) else null


static func _demand_neutrality(
	state: OperationalState, player: int, profile: AiProfile
) -> PoliticalDecisionCommand:
	if not profile.ultimatum_enabled:
		return null
	for country in _countries(state):
		if (
			CountryRules.relation(state, player, country.id) == &"hostile"
			and country.accepts_ultimatum
		):
			var command := DemandNeutralityCommand.new(country.id)
			if _valid(state, command):
				return command
	return null


static func _invoke_alliance(
	state: OperationalState, player: int, goals: Array[Dictionary]
) -> PoliticalDecisionCommand:
	for country in _countries(state):
		if (
			CountryRules.relation(state, player, country.id) == &"own"
			and country.stance == CountryState.ALIGNED
			and _holds_goal(state, country.id, goals)
		):
			var command := InvokeAllianceCommand.new(country.id)
			if _valid(state, command):
				return command
	return null


static func _declare_hostilities(
	state: OperationalState, player: int, profile: AiProfile, untaken: Array[Dictionary]
) -> PoliticalDecisionCommand:
	var own_strength := CollapseRules.present_strength(state, player)
	var enemy_strength := CollapseRules.present_strength(state, 1 - player)
	var strong := (
		own_strength > 0
		and float(own_strength) >= profile.declare_min_strength_ratio * float(enemy_strength)
	)
	for country in _countries(state):
		var relation := CountryRules.relation(state, player, country.id)
		if relation != &"neutral" and relation != &"hostile":
			continue
		if not _holds_goal(state, country.id, untaken):
			continue  # opening that soil gains nothing
		if not strong and not country.casus_belli[player]:
			continue
		var command := DeclareHostilitiesCommand.new(country.id)
		if _valid(state, command):
			return command
	return null


static func _escalate(
	state: OperationalState, profile: AiProfile, untaken: Array[Dictionary]
) -> PoliticalDecisionCommand:
	if untaken.size() < profile.escalate_min_goal_gap:
		return null
	var command := EscalateCommand.new()
	return command if _valid(state, command) else null


static func _nuclear_strike(state: OperationalState) -> PoliticalDecisionCommand:
	var command := NuclearStrikeCommand.new()
	return command if _valid(state, command) else null


static func _holds_goal(
	state: OperationalState, country_id: StringName, goals: Array[Dictionary]
) -> bool:
	for goal in goals:
		if state.country_at(goal["coord"]) == country_id:
			return true
	return false


## The countries in id order.
static func _countries(state: OperationalState) -> Array[CountryState]:
	var countries := state.countries.duplicate()
	countries.sort_custom(
		func(a: CountryState, b: CountryState) -> bool: return String(a.id) < String(b.id)
	)
	return countries
