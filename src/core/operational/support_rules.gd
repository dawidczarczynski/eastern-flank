class_name SupportRules
extends RefCounted
## Pure rules of outside support (TASK-121, GDD "Outside support"): when a package can be
## requested, the status of a supporter, and the delivery at the start of the recipient's turn.
## Side-agnostic, no randomness.


## Whether some package listed in `response_to` of the package has been requested (and not
## withdrawn) - then the package is free and ignores its level / record conditions.
static func is_response(state: OperationalState, package_id: StringName) -> bool:
	var support := state.get_support(package_id)
	if support == null:
		return false
	for other_id in support.definition.response_to:
		var other := state.get_support(other_id)
		if other != null and other.requested() and not other.withdrawn:
			return true
	return false


## "" when `player` may request the package now, else why not (see the TASK-121 order of codes).
static func request_problem(state: OperationalState, player: int, package_id: StringName) -> String:
	var support := state.get_support(package_id)
	if support == null:
		return "unknown_package"
	var package := support.definition
	if package.side != player:
		return "not_your_package"
	if support.requested():
		return "already_requested"
	var response := is_response(state, package_id)
	if not response:
		var conditions := conditions_problem(state, package)
		if conditions != "":
			return conditions
	var cost := 0 if response else package.escalation_cost
	if cost > 0 and PoliticalDecisionCommand.is_standing_down(state, player):
		return "standing_down"
	if state.escalation_level + cost >= state.ladder.top():
		return "threshold"
	return ""


## The level and escalation-record conditions of a package: "" or `level_too_low`,
## `level_too_high`, `escalation_record`.
static func conditions_problem(state: OperationalState, package: SupportPackage) -> String:
	if state.escalation_level < package.min_level:
		return "level_too_low"
	if state.escalation_level > package.max_level:
		return "level_too_high"
	var side := package.side
	var net := state.escalation_caused[side] - state.escalation_deescalated[side]
	if package.max_caused >= 0 and net > package.max_caused:
		return "escalation_record"
	return ""


## {status, side} of a supporter: `&"supporting"` (some formation of a package joined),
## `&"considering"` (a package is on its way or could be requested, ignoring the escalation
## cost's `standing_down` / `threshold`), else `&"uninvolved"`. Withdrawn packages count as never
## requested. The side is the supporter's, -1 when no package names it.
static func status(state: OperationalState, supporter_id: StringName) -> Dictionary:
	var side := -1
	var result := &"uninvolved"
	for support in state.support:
		var supporter := support.definition.supporter
		if supporter == null or supporter.id != supporter_id:
			continue
		side = supporter.side
		if support.joined_any():
			result = &"supporting"
		elif result != &"supporting" and not support.withdrawn:
			if support.on_its_way():
				result = &"considering"
			elif (
				request_problem(state, support.definition.side, support.id)
				in ["", "standing_down", "threshold"]
			):
				result = &"considering"
	return {"status": result, "side": side}


## Ids of the other side's packages that list `package_id` in `response_to` and are not
## requested yet, in setup order.
static func open_responses(state: OperationalState, package_id: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	for support in state.support:
		if support.requested() or not support.definition.response_to.has(package_id):
			continue
		ids.append(support.id)
	return ids


## The delivery step, called right after `operational_turn_started` of the new current player:
## for each package of that player, in setup order, that is requested and due: withdraw it
## (`support_withdrawn`) or place the waiting formations (`formation_joined`, `casus_belli_gained`,
## `support_delivered` / `support_delayed`).
static func deliver(state: OperationalState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for support in state.support:
		var package := support.definition
		if package.side != state.current_player or not support.on_its_way():
			continue
		if state.turn < support.requested_turn + package.delay_turns:
			continue
		if package.withdraw_if_unmet and not support.joined_any():
			var reason := ""
			if not is_response(state, support.id):
				reason = conditions_problem(state, package)
			if reason != "":
				support.withdrawn = true
				support.waiting.clear()
				events.append(
					{
						"type": &"support_withdrawn",
						"package": support.id,
						"reason": StringName(reason)
					}
				)
				continue
		events.append_array(_place(state, support))
	return events


static func _place(state: OperationalState, support: SupportState) -> Array[Dictionary]:
	var package := support.definition
	var placed := Reinforcements.place(state, support.waiting, package.side, support.id, true)
	var events: Array[Dictionary] = placed["events"]
	support.waiting = placed["unplaced"]
	if package.entry_casus_belli:
		var joined := events.duplicate()
		for e in joined:
			events.append_array(_casus_belli(state, package.side, e))
	if support.waiting.is_empty():
		support.delivered = true
		var means := {}
		for grant in package.strike_means:
			events.append_array(
				StrikeRules.add_stock(state, package.side, grant.means, grant.count, support.id)
			)
			means[grant.means] = grant.count
		events.append(
			{
				"type": &"support_delivered",
				"package": support.id,
				"player": package.side,
				"formations":
				package.formations.map(func(p: FormationPlacement) -> StringName: return p.id),
				"means": means,
			}
		)
	else:
		events.append(
			{
				"type": &"support_delayed",
				"package": support.id,
				"reason": &"no_open_entry",
				"waiting":
				support.waiting.map(func(p: FormationPlacement) -> StringName: return p.id),
			}
		)
	return events


## `casus_belli_gained` for the country of a `formation_joined` event when it is aligned with
## `side` and the other side has no casus belli against it yet.
static func _casus_belli(
	state: OperationalState, side: int, joined: Dictionary
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var country := state.get_country(joined["country"])
	var other := 1 - side
	if (
		country != null
		and country.stance == CountryState.ALIGNED
		and country.side == side
		and not country.casus_belli[other]
	):
		country.casus_belli[other] = true
		(
			events
			. append(
				{
					"type": &"casus_belli_gained",
					"country": country.id,
					"player": other,
					"formation_id": joined["formation_id"],
					"at": joined["coord"],
				}
			)
		)
	return events
