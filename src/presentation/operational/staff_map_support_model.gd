class_name StaffMapSupportModel
extends RefCounted
## Pure view-model of outside support on the staff map (TASK-121, GDD "Outside support"): the
## Support tab of the Decisions panel (supporters with their packages, the other bloc's requests
## and the free responses they open), the ghost counters of arrivals on the way and the toast texts
## of the support events. A package is requested through the decision *Request support*; its
## button is disabled with the real rejection code of RequestSupportCommand (`validate`), so an
## invalid state never gets through. Reads only, never changes the state.

const DECISION := &"request_support"
## Package state -> chip text (translation keys, English).
const STATE_TEXTS := {
	&"open": "Available",
	&"on_way": "On its way",
	&"waiting": "Waiting",
	&"delivered": "Arrived",
	&"withdrawn": "Withdrawn",
}
const STATUS_TEXTS := {
	&"supporting": "Supporting",
	&"considering": "Considering",
	&"uninvolved": "Uninvolved",
}
## Rejection codes of the package itself (the others come from StaffMapDecisionsModel.REASONS).
const REASONS := {
	"unknown_package": "No such package",
	"not_your_package": "Not your package",
	"already_requested": "Already requested",
	"escalation_record": "You have escalated too much for this",
	"threshold": "Too close to the top of the ladder",
}


## Reason in words for a rejection `code` (package codes first, then the decisions' ones); `package`
## adds the level band to the level codes.
static func reason_text(code: String, package: SupportPackage = null) -> String:
	if package != null:
		if code == "level_too_low":
			return TranslationServer.translate("Needs level %d or higher") % package.min_level
		if code == "level_too_high":
			return TranslationServer.translate("Only up to level %d") % package.max_level
	if REASONS.has(code):
		return TranslationServer.translate(REASONS[code])
	return TranslationServer.translate(StaffMapDecisionsModel.REASONS.get(code, code))


## Supporters of `viewer`'s side, each {id, name, status, status_text, side, packages}. The
## packages are the ones not shown as an open response (see `responses`).
static func supporters(state: OperationalState, viewer: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var index := {}
	for support in state.support:
		var supporter := support.definition.supporter
		if supporter == null or support.definition.side != viewer:
			continue
		if not index.has(supporter.id):
			var status := SupportRules.status(state, supporter.id)
			index[supporter.id] = found.size()
			(
				found
				. append(
					{
						"id": supporter.id,
						"name": TranslationServer.translate(supporter.display_name),
						"status": status["status"],
						"status_text": TranslationServer.translate(STATUS_TEXTS[status["status"]]),
						"side": supporter.side,
						"packages": [] as Array[Dictionary],
					}
				)
			)
		if SupportRules.is_response(state, support.id) and not support.requested():
			continue
		var entry: Dictionary = found[index[supporter.id]]
		entry["packages"].append(package(state, viewer, support))
	return found


## The other bloc's requested packages {id, title, supporter, text, responses: [package]} - what
## the enemy asked for and the free answers it opens to `viewer`.
static func other_bloc(state: OperationalState, viewer: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for support in state.support:
		var definition := support.definition
		if definition.side == viewer or not support.requested() or support.withdrawn:
			continue
		var answers: Array[Dictionary] = []
		for id in SupportRules.open_responses(state, support.id):
			var answer := state.get_support(id)
			if answer != null and answer.definition.side == viewer:
				answers.append(package(state, viewer, answer))
		(
			found
			. append(
				{
					"id": support.id,
					"title": TranslationServer.translate(definition.display_name),
					"supporter": TranslationServer.translate(definition.supporter.display_name),
					"text":
					(
						TranslationServer.translate("%s requested %s")
						% [
							StaffMapTurnBar.side_name(state, definition.side),
							TranslationServer.translate(definition.display_name),
						]
					),
					"turns_text": _turns_text(state, support),
					"responses": answers,
				}
			)
		)
	return found


## One package as a choice of the decision card (same keys as StaffMapDecisionsModel.choice where
## they apply): {id (the decision), country (the package id), package, title, supporter, what,
## entry, delay, band, conditions, state, state_text, cost_text, cost_kind, response, enabled,
## code, reason, tag, danger, new_level, new_level_name, confirm}.
static func package(state: OperationalState, viewer: int, support: SupportState) -> Dictionary:
	var definition := support.definition
	var response := SupportRules.is_response(state, support.id)
	var code := _problem(state, viewer, support.id)
	var cost := 0 if response else definition.escalation_cost
	var previous := state.escalation_level
	var next := mini(previous + cost, state.ladder.cap()) if cost > 0 else previous
	var title := TranslationServer.translate(definition.display_name)
	var package_state := _state_of(state, support)
	var danger := cost > 0 and next >= state.ladder.cap() and previous < state.ladder.cap()
	var reason := ""
	if package_state == &"open" and code != "":
		reason = reason_text(code, definition)
	return {
		"id": DECISION,
		"country": support.id,
		"package": support.id,
		"title": title,
		"supporter": TranslationServer.translate(definition.supporter.display_name),
		"what": _what(definition),
		"entry": _entry_text(state, definition),
		"delay": _delay_text(definition),
		"band": _band_text(state, definition),
		"conditions": _conditions_text(state, definition),
		"state": package_state,
		"state_text": _state_text(state, support, package_state),
		"cost_text": _cost_text(cost, response),
		"cost_kind": &"up" if cost > 0 else &"free",
		"response": response,
		"enabled": code == "",
		"code": code,
		"reason": reason,
		"tag": &"blocked" if reason != "" else &"",
		"danger": danger,
		"new_level": next,
		"new_level_name": StaffMapEscalation.level_name(state, next),
		"confirm": _confirm(state, definition, title, previous, next, danger),
		"effect": _what(definition),
	}


## Ghost counters of the arrivals on the way for `viewer`: one per package and entry hex,
## {package, coord, count, turns (turns left, 0 = due), waiting (entry closed), country, text}.
static func ghosts(state: OperationalState, viewer: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for support in state.support:
		if support.definition.side != viewer or not support.on_its_way():
			continue
		var turns := _turns_left(state, support)
		var by_hex := {}
		for placement in support.waiting:
			by_hex[placement.coord] = int(by_hex.get(placement.coord, 0)) + 1
		for coord: Vector2i in by_hex:
			var waiting := turns <= 0
			var country := _country_name(state, coord)
			(
				found
				. append(
					{
						"package": support.id,
						"coord": coord,
						"count": by_hex[coord],
						"turns": turns,
						"waiting": waiting,
						"country": country,
						"text": ghost_text(turns, waiting, country),
					}
				)
			)
	return found


## "in 3 turns" / "next turn" / "waiting – Belarus closed".
static func ghost_text(turns: int, waiting: bool, country: String) -> String:
	if waiting:
		return TranslationServer.translate("waiting – %s closed") % country
	if turns == 1:
		return TranslationServer.translate("next turn")
	return TranslationServer.translate("in %d turns") % turns


## Toast text of a support event for `viewer`; "" for an event that is not for his side.
static func toast_text(state: OperationalState, viewer: int, event: Dictionary) -> String:
	var support := state.get_support(StringName(event.get("package", &"")))
	if support == null:
		return ""
	var definition := support.definition
	var title := TranslationServer.translate(definition.display_name)
	match event.get("type"):
		&"support_requested":
			if definition.side == viewer:
				return (
					TranslationServer.translate("%s requested – arrives in %d turns")
					% [title, definition.delay_turns]
				)
			var text := (
				TranslationServer.translate("%s requested %s")
				% [StaffMapTurnBar.side_name(state, definition.side), title]
			)
			if not event.get("responses", []).is_empty():
				text += " – " + TranslationServer.translate("a free response is open")
			return text
		&"support_delivered":
			if definition.side == viewer:
				return (
					TranslationServer.translate("%s has arrived (%d formations)")
					% [title, definition.formations.size()]
				)
		&"support_delayed":
			if definition.side == viewer:
				var country := ""
				if not support.waiting.is_empty():
					country = _country_name(state, support.waiting[0].coord)
				return TranslationServer.translate("%s is waiting – %s closed") % [title, country]
		&"support_withdrawn":
			if definition.side == viewer:
				return (
					TranslationServer.translate("%s withdrawn: %s")
					% [title, reason_text(String(event.get("reason", "")), definition)]
				)
	return ""


static func _problem(state: OperationalState, viewer: int, package_id: StringName) -> String:
	if not state.result.is_empty():
		return "operation_over"
	if viewer != state.current_player:
		return "not_your_turn"
	return RequestSupportCommand.new(package_id).validate(state)


static func _state_of(state: OperationalState, support: SupportState) -> StringName:
	if support.withdrawn:
		return &"withdrawn"
	if support.delivered:
		return &"delivered"
	if support.on_its_way():
		return &"waiting" if _turns_left(state, support) <= 0 else &"on_way"
	return &"open"


static func _turns_left(state: OperationalState, support: SupportState) -> int:
	return maxi(support.requested_turn + support.definition.delay_turns - state.turn, 0)


static func _turns_text(state: OperationalState, support: SupportState) -> String:
	if support.delivered:
		return TranslationServer.translate("arrived")
	var turns := _turns_left(state, support)
	return ghost_text(turns, turns <= 0, _entry_country(state, support.definition))


static func _state_text(state: OperationalState, support: SupportState, kind: StringName) -> String:
	match kind:
		&"on_way":
			return ghost_text(_turns_left(state, support), false, "")
		&"waiting":
			return ghost_text(0, true, _entry_country(state, support.definition))
		&"withdrawn":
			var why := SupportRules.conditions_problem(state, support.definition)
			var text := TranslationServer.translate(STATE_TEXTS[kind])
			if why == "":
				return text
			return "%s – %s" % [text, reason_text(why, support.definition)]
	return TranslationServer.translate(STATE_TEXTS[kind])


static func _what(definition: SupportPackage) -> String:
	var names: Array[String] = []
	for placement in definition.formations:
		names.append(TranslationServer.translate(placement.display_name))
	if names.is_empty():
		return ""
	return (
		TranslationServer.translate("%d formations: %s") % [names.size(), ", ".join(names)]
		if names.size() > 1
		else TranslationServer.translate("1 formation: %s") % names[0]
	)


static func _entry_text(state: OperationalState, definition: SupportPackage) -> String:
	return TranslationServer.translate("Enters at %s") % _entry_country(state, definition)


static func _entry_country(state: OperationalState, definition: SupportPackage) -> String:
	if definition.formations.is_empty():
		return ""
	return _country_name(state, definition.formations[0].coord)


static func _country_name(state: OperationalState, coord: Vector2i) -> String:
	var country := state.get_country(state.country_at(coord))
	if country == null:
		return TranslationServer.translate("the map edge")
	return TranslationServer.translate(country.definition.display_name)


static func _delay_text(definition: SupportPackage) -> String:
	if definition.delay_turns <= 0:
		return TranslationServer.translate("Arrives at once")
	return (
		TranslationServer.translate("Arrives %d turns after the request") % definition.delay_turns
	)


static func _band_text(state: OperationalState, definition: SupportPackage) -> String:
	return (
		TranslationServer.translate("Level %d – %d (%s – %s)")
		% [
			definition.min_level,
			definition.max_level,
			StaffMapEscalation.level_name(state, definition.min_level),
			StaffMapEscalation.level_name(state, definition.max_level),
		]
	)


static func _conditions_text(state: OperationalState, definition: SupportPackage) -> String:
	var parts: Array[String] = []
	if not definition.response_to.is_empty():
		parts.append(TranslationServer.translate("Free answer to the other bloc's request"))
	if definition.max_caused >= 0:
		parts.append(
			TranslationServer.translate("You caused at most %d levels") % definition.max_caused
		)
	if definition.entry_casus_belli:
		parts.append(
			(
				TranslationServer.translate("Entering %s gives the other side a casus belli")
				% _entry_country(state, definition)
			)
		)
	if definition.withdraw_if_unmet:
		parts.append(TranslationServer.translate("Withdrawn if the conditions lapse on the way"))
	return ". ".join(parts)


static func _cost_text(cost: int, response: bool) -> String:
	if cost > 0:
		return TranslationServer.translate("Level +%d") % cost
	if response:
		return TranslationServer.translate("Free answer")
	return TranslationServer.translate("Free")


static func _confirm(
	state: OperationalState,
	definition: SupportPackage,
	title: String,
	previous: int,
	next: int,
	danger: bool
) -> String:
	var arrives: String = (
		TranslationServer.translate("arrives in %d turns") % definition.delay_turns
		if definition.delay_turns > 0
		else TranslationServer.translate("arrives at once")
	)
	if next == previous:
		return TranslationServer.translate("Request %s? It %s.") % [title, arrives]
	var text := (
		TranslationServer.translate("Request %s? Level %d → %d (%s); it %s.")
		% [title, previous, next, StaffMapEscalation.level_name(state, next), arrives]
	)
	if danger:
		text += " " + TranslationServer.translate("– the highest level of escalation")
	return text
