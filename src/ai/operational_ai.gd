class_name OperationalAi
extends RefCounted
## The opponent's leader on the staff map (TASK-102a, GDD "Operational AI"): a pure, deterministic
## planner. `plan(state, player)` reads the whole OperationalState (full information) and returns
## the operational commands the player would give this turn: formation orders towards the goals
## (OperationDefinition.ai_goals) and up to `strikes_left` deep strikes. The caller executes them
## one by one through OperationalSimulation.execute(); the planner never changes `state`, never
## draws from `state.rng` and knows no side – both players run through the same code.

const NO_HEX := Vector2i.MAX


## The commands `player` gives this turn, in execution order (orders, then strikes); [] when
## `player` is not the current player or the operation is over. Bounded by `profile.max_commands`.
static func plan(
	state: OperationalState, player: int, profile: AiProfile = null
) -> Array[OperationalCommand]:
	var commands: Array[OperationalCommand] = []
	if profile == null:
		profile = AiProfile.shipped()
	if player != state.current_player or not state.result.is_empty():
		return commands
	if not state.pending_battles.is_empty() or profile.max_commands <= 0:
		return commands
	var strikes := _plan_strikes(state, player, profile)
	commands.append_array(
		_plan_orders(state, player, profile, profile.max_commands - strikes.size())
	)
	commands.append_array(strikes)
	return commands


# --- goals and orders ---


## The player's goals with a resolved hex: [{id, coord, weight, role}], in definition order.
static func _goals(state: OperationalState, player: int) -> Array[Dictionary]:
	var goals: Array[Dictionary] = []
	for goal in state.ai_goals:
		var coord := goal.hex_in(state)
		if goal.player == player and coord != NO_HEX and state.grid.has_tile(coord):
			goals.append({"id": goal.id, "coord": coord, "weight": goal.weight, "role": goal.role})
	return goals


static func _plan_orders(
	state: OperationalState, player: int, profile: AiProfile, limit: int
) -> Array[OperationalCommand]:
	var commands: Array[OperationalCommand] = []
	var goals := _goals(state, player)
	if goals.is_empty() or limit <= 0:
		return commands
	var own := _formations_of(state, player)
	var enemies: Array[Vector2i] = []
	for formation in state.formations:
		if formation.owner_id != player:
			enemies.append(formation.coord)
	var held := {}
	for formation in own:
		held[formation.coord] = true
	var picks: Array[Dictionary] = []
	for formation in own:
		var standing := _goal_at(goals, formation.coord)
		if not standing.is_empty():
			if standing["role"] == AiGoal.HOLD and formation.posture != &"defend":
				commands.append(SetPostureCommand.new(formation.id, &"defend"))
			continue
		var best := _best_goal(goals, formation, held, enemies, profile)
		if not best.is_empty():
			picks.append({"formation": formation, "goal": best["goal"], "score": best["score"]})
	picks.sort_custom(_better_pick)
	var used := {}
	var pending: Array[Dictionary] = []
	for pick in picks:
		var formation: Formation = pick["formation"]
		var goal: Dictionary = pick["goal"]
		if _keeps_order(state, formation, goal, profile, used):
			continue
		pending.append(pick)
	for pick in pending:
		if commands.size() >= limit:
			break
		var command := _order_for(state, pick["formation"], pick["goal"], enemies, profile, used)
		if command != null:
			commands.append(command)
	if commands.size() > limit:
		commands.resize(limit)
	return commands


static func _formations_of(state: OperationalState, player: int) -> Array[Formation]:
	var result: Array[Formation] = []
	for formation in state.formations:
		if formation.owner_id == player:
			result.append(formation)
	result.sort_custom(func(a: Formation, b: Formation) -> bool: return String(a.id) < String(b.id))
	return result


static func _goal_at(goals: Array[Dictionary], coord: Vector2i) -> Dictionary:
	var found := {}
	for goal in goals:
		if goal["coord"] == coord and (found.is_empty() or goal["role"] == AiGoal.HOLD):
			found = goal
	return found


## The goal with the highest score for the formation, ignoring goals an own formation stands on:
## {goal, score}; {} when there is none. Ties go to the earlier goal in definition order.
static func _best_goal(
	goals: Array[Dictionary],
	formation: Formation,
	held: Dictionary,
	enemies: Array[Vector2i],
	profile: AiProfile
) -> Dictionary:
	var best := {}
	for goal in goals:
		var coord: Vector2i = goal["coord"]
		if held.has(coord):
			continue
		var threat := 0
		for enemy in enemies:
			if Hex.distance(enemy, coord) <= profile.contact_range:
				threat += 1
		var score := (
			float(goal["weight"]) * profile.goal_weight
			- float(Hex.distance(formation.coord, coord)) * profile.distance_weight
			- float(threat) * profile.threat_weight * (1.0 - profile.aggression)
		)
		if best.is_empty() or score > float(best["score"]):
			best = {"goal": goal, "score": score}
	return best


static func _better_pick(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(a["score"], b["score"]):
		return a["score"] > b["score"]
	return String(a["formation"].id) < String(b["formation"].id)


## Whether the formation's standing order already leads towards the goal (its destination lies
## within the search radius of the goal hex) and is still valid; marks the destination as used.
static func _keeps_order(
	state: OperationalState,
	formation: Formation,
	goal: Dictionary,
	profile: AiProfile,
	used: Dictionary
) -> bool:
	if formation.order == null:
		return false
	var destination := formation.order.destination
	if used.has(destination):
		return false
	if Hex.distance(destination, goal["coord"]) > profile.destination_search_radius:
		return false
	var command := IssueOrderCommand.new(formation.id, destination, formation.posture)
	if command.validate(state) != "":
		return false
	used[destination] = true
	return true


## An order for the formation: the goal hex, or the nearest hex around it that the order
## accepts and no other plan order uses; null when there is none.
static func _order_for(
	state: OperationalState,
	formation: Formation,
	goal: Dictionary,
	enemies: Array[Vector2i],
	profile: AiProfile,
	used: Dictionary
) -> OperationalCommand:
	var goal_coord: Vector2i = goal["coord"]
	var posture := _posture_for(goal_coord, enemies, profile)
	for radius in profile.destination_search_radius + 1:
		for hex in _ring(goal_coord, radius, formation.coord):
			if used.has(hex):
				continue
			var command := IssueOrderCommand.new(formation.id, hex, posture)
			if command.validate(state) == "":
				used[hex] = true
				return command
	return null


## `advance` when an enemy formation is within ceil(1 / aggression) hexes of the goal, else
## `march`.
static func _posture_for(
	goal_coord: Vector2i, enemies: Array[Vector2i], profile: AiProfile
) -> StringName:
	var reach := int(ceil(1.0 / maxf(profile.aggression, 0.05)))
	for enemy in enemies:
		if Hex.distance(enemy, goal_coord) <= reach:
			return &"advance"
	return &"march"


## The hexes at exactly `radius` from `center` (the centre itself for 0), nearest to `origin`
## first, ties by (x, y).
static func _ring(center: Vector2i, radius: int, origin: Vector2i) -> Array[Vector2i]:
	var hexes: Array[Vector2i] = []
	if radius == 0:
		hexes.append(center)
		return hexes
	for dq in range(-radius, radius + 1):
		for dr in range(-radius, radius + 1):
			var hex := center + Vector2i(dq, dr)
			if Hex.distance(center, hex) == radius:
				hexes.append(hex)
	hexes.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var da := Hex.distance(origin, a)
			var db := Hex.distance(origin, b)
			if da != db:
				return da < db
			return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	return hexes


# --- strikes ---


## Up to `strikes_left` strikes (and at most `max_commands`): targets by tier (air defence, then
## airfield / C2, then formations about to make contact), each with the weapon of the best
## expected value, from stock above the reserve. A strike that raises the escalation level ends
## the strikes of the plan (the state it was planned against has changed).
static func _plan_strikes(
	state: OperationalState, player: int, profile: AiProfile
) -> Array[OperationalCommand]:
	var commands: Array[OperationalCommand] = []
	var left := mini(state.strikes_left, profile.max_commands)
	if left <= 0:
		return commands
	var remaining := {}
	for means_id: StringName in state.strike_means:
		remaining[means_id] = StrikeRules.stock(state, player, means_id)
	for target in _ranked_targets(state, player, profile):
		if commands.size() >= left:
			break
		var choice := _best_strike(state, player, profile, target, remaining)
		if choice.is_empty():
			continue
		commands.append(StrikeCommand.new(choice["means"], target["id"], choice["count"]))
		remaining[choice["means"]] = int(remaining[choice["means"]]) - int(choice["count"])
		if StrikeRules.escalation_preview(state, player, target["id"]) > 0:
			break
	return commands


## The enemy targets worth a look, best first: tier, then target weight (high first), then id.
static func _ranked_targets(
	state: OperationalState, player: int, profile: AiProfile
) -> Array[Dictionary]:
	var own_hexes: Array[Vector2i] = []
	for formation in state.formations:
		if formation.owner_id == player:
			own_hexes.append(formation.coord)
	var ranked: Array[Dictionary] = []
	for target in StrikeRules.targets(state, player):
		var class_id: StringName = target["class_id"]
		if not profile.target_weights.has(class_id) or not profile.target_tiers.has(class_id):
			continue
		if target["kind"] == &"installation":
			var installation := state.get_installation(target["id"])
			if installation.class_id == &"air_defence" and installation.suppressed():
				continue
		elif not _near_any(target["coord"], own_hexes, profile.contact_range):
			continue
		(
			ranked
			. append(
				{
					"id": target["id"],
					"tier": int(profile.target_tiers[class_id]),
					"weight": float(profile.target_weights[class_id]),
				}
			)
		)
	ranked.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["tier"] != b["tier"]:
				return a["tier"] < b["tier"]
			if not is_equal_approx(a["weight"], b["weight"]):
				return a["weight"] > b["weight"]
			return String(a["id"]) < String(b["id"])
	)
	return ranked


static func _near_any(coord: Vector2i, hexes: Array[Vector2i], within: int) -> bool:
	for hex in hexes:
		if Hex.distance(hex, coord) <= within:
			return true
	return false


## {means, count} of the weapon with the best expected value on the target (ties by id) that
## may fire, keeps the reserve, does not push the level to the cap and clears the minimum value;
## {} when none does.
static func _best_strike(
	state: OperationalState,
	player: int,
	profile: AiProfile,
	target: Dictionary,
	remaining: Dictionary
) -> Dictionary:
	var best := {}
	var best_value := 0.0
	var means_ids: Array = state.strike_means.keys()
	means_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var cap := state.ladder.cap()
	var preview := StrikeRules.escalation_preview(state, player, target["id"])
	if preview > 0 and state.escalation_level + preview >= cap:
		return best
	for means_id: StringName in means_ids:
		var means: StrikeMeansDefinition = state.strike_means[means_id]
		var spare := int(remaining.get(means_id, 0)) - profile.strike_reserve * means.max_salvo
		if spare < 1 or not means.usable_by(player):
			continue
		var count := mini(means.max_salvo, spare)
		var forecast := StrikeRules.forecast(state, player, means_id, count, target["id"])
		if forecast.is_empty():
			continue
		var damage := (
			means.damage if forecast["kind"] == &"installation" else means.formation_damage
		)
		var value := float(forecast["expected_hits"]) * float(damage) * float(target["weight"])
		if value >= profile.min_strike_value and value > best_value:
			best_value = value
			best = {"means": means_id, "count": count}
	return best
