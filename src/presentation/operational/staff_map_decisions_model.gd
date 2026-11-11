class_name StaffMapDecisionsModel
extends RefCounted
## Pure view-model of the Decisions panel (TASK-117, docs/design/operational_map "Panels" – decision
## card): one row per political decision with its choices (a country for the targeted ones), each
## with the effect in one line, the escalation price, whether the button works and the reason when
## not. The reason is the rejection code of the real command (`validate`), so an invalid state can
## never get through; the only checks here are the viewer's (not his turn, operation over).
## Names per side come from SideDefinition (no side literal). Reads only, never changes the state.

const ESCALATE := &"escalate"
const STAND_DOWN := &"stand_down"
const DECLARE := &"declare_hostilities"
const INVOKE := &"invoke_alliance"
const DEMAND := &"demand_neutrality"
const NUCLEAR := &"nuclear_strike"
## The five standing decisions (hot keys 1-5). NUCLEAR (key 6) follows them only for a side whose
## data allows it (`may_use_nuclear`, TASK-140), see `ids`.
const ORDER: Array[StringName] = [ESCALATE, STAND_DOWN, DECLARE, INVOKE, DEMAND]
## The two groups of the Politics screen (left / right card column), each in card order.
const WIDEN: Array[StringName] = [ESCALATE, DECLARE, INVOKE]
const KEEP_SMALL: Array[StringName] = [STAND_DOWN, DEMAND]
## The last-resort group (its own caption under Keep it small), shown only when listed by `ids`.
const LAST_RESORT: Array[StringName] = [NUCLEAR]
## Stance word of a country chip, by its relation to the viewer (CountryRules.relation).
const STANCE_WORDS := {
	&"own": "Ally",
	&"enemy": "Hostile",
	&"hostile": "Hostile",
	&"neutral": "Neutral",
}

const TITLES := {
	ESCALATE: "Escalate",
	STAND_DOWN: "Stand down",
	DECLARE: "Declare hostilities",
	INVOKE: "Invoke alliance",
	DEMAND: "Demand neutrality",
	NUCLEAR: "Use nuclear weapon",
}
const NO_TARGET_EFFECTS := {
	ESCALATE: "",
	STAND_DOWN: "",
	DECLARE: "No neutral or hostile country to declare on",
	INVOKE: "No aligned ally to call",
	DEMAND: "No hostile country to give an ultimatum",
	NUCLEAR: "",
}

## Rejection codes that belong to one country (its chip is dashed); the others block the whole card.
const COUNTRY_CODES: Array[String] = [
	"occupying",
	"unknown_country",
	"own_country",
	"already_at_war",
	"not_your_ally",
	"not_hostile",
	"refuses_ultimatum",
	"troops_present",
]

## Rejection code -> reason in words (translation keys are the English texts).
const REASONS := {
	"not_your_turn": "Not your turn",
	"operation_over": "The operation is over",
	"battle_pending": "Resolve the pending battle first",
	"no_decisions_left": "One decision per turn: already taken",
	"standing_down": "Standing down: no escalating decisions yet",
	"level_cap": "Already at the highest level",
	"at_floor": "The level is already the lowest",
	"recent_escalation": "You escalated last turn",
	"occupying": "Your troops are on soil you took",
	"unknown_country": "No such country",
	"own_country": "Your own country",
	"already_at_war": "Already at war",
	"not_your_ally": "Not your ally",
	"not_hostile": "Not hostile to you",
	"refuses_ultimatum": "Refuses ultimatums",
	"level_too_high": "The level is too high for an ultimatum",
	"troops_present": "Enemy troops are on its soil",
	"no_target": "No country to choose",
	"not_nuclear_power": "Your side has no nuclear option",
	"level_too_low": "Only at the highest level of escalation",
	"no_collapse": "Only while the army is collapsing",
}
# gdlint: disable=max-line-length
const NUCLEAR_CONFIRM := "Use a nuclear weapon? This ends the operation. %s is judged to have crossed the line."
# gdlint: enable=max-line-length


## The decision's command for `country` (&"" for the untargeted ones); null for an unknown id.
static func command(id: StringName, country: StringName = &"") -> PoliticalDecisionCommand:
	match id:
		ESCALATE:
			return EscalateCommand.new()
		STAND_DOWN:
			return StandDownCommand.new()
		DECLARE:
			return DeclareHostilitiesCommand.new(country)
		INVOKE:
			return InvokeAllianceCommand.new(country)
		DEMAND:
			return DemandNeutralityCommand.new(country)
		NUCLEAR:
			return NuclearStrikeCommand.new()
	return null


## The decisions `viewer` sees, in card order: the five standing ones, plus NUCLEAR when the
## viewer's side may use it (SideDefinition.may_use_nuclear; never shown to the other side).
static func ids(state: OperationalState, viewer: int) -> Array[StringName]:
	var found := ORDER.duplicate()
	if viewer >= 0 and viewer < state.may_use_nuclear.size() and state.may_use_nuclear[viewer]:
		found.append(NUCLEAR)
	return found


## Header facts: decisions left / per turn, the stand-down cooldown (turns still barred, 0 = none)
## and the level text.
static func header(state: OperationalState, viewer: int) -> Dictionary:
	var barred := 0
	if viewer >= 0 and viewer < state.stand_down_until.size():
		barred = maxi(state.stand_down_until[viewer] - state.turn + 1, 0)
	return {
		"left": state.decisions_left if viewer == state.current_player else 0,
		"per_turn": state.ladder.decisions_per_turn,
		"cooldown": barred,
		"level": StaffMapEscalation.chip_text(state),
		"level_value": state.escalation_level,
		"level_name": StaffMapEscalation.level_name(state, state.escalation_level),
		"top": state.ladder.top(),
		"side": StaffMapTurnBar.side_name(state, viewer),
	}


## Whether a rejection `code` is about the chosen country alone.
static func is_country_block(code: String) -> bool:
	return COUNTRY_CODES.has(code)


## Hot key (1-6) of a decision: its position in ORDER, 6 for NUCLEAR.
static func hot_key(id: StringName) -> int:
	if id == NUCLEAR:
		return ORDER.size() + 1
	return ORDER.find(id) + 1


## Result line after the viewer took `id` ("Stand down taken · level now 0 · Contained clash").
static func result_line(state: OperationalState, viewer: int, id: StringName) -> String:
	return (
		TranslationServer.translate("%s taken · level now %d · %s")
		% [
			title(state, viewer, id),
			state.escalation_level,
			StaffMapEscalation.level_name(state, state.escalation_level),
		]
	)


## Title of a decision for the viewer's side (*Invoke alliance* is named by SideDefinition).
static func title(state: OperationalState, viewer: int, id: StringName) -> String:
	if id == INVOKE:
		var side := _side(state, viewer)
		if side != null and side.alliance_decision_name != "":
			return TranslationServer.translate(side.alliance_decision_name)
	return TranslationServer.translate(TITLES.get(id, String(id)))


## Rows for the panel: [{id, title, choices: [choice]}], in `ids` order. A choice: {country, name,
## effect, cost (escalation steps, 0 free), cost_text, cost_kind (&"up" / &"down" / &"free"),
## enabled,
## code, reason, tag ("" / &"blocked"), relation (&"own" / &"hostile" / &"neutral" /
## &"none"), stance_text, danger (the new level is the cap, or the nuclear attack: red), new_level,
## new_level_name, confirm}.
static func rows(state: OperationalState, viewer: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in ids(state, viewer):
		var choices: Array[Dictionary] = []
		for country in targets(state, viewer, id):
			choices.append(choice(state, viewer, id, country))
		if choices.is_empty():
			choices.append(_no_target(state, viewer, id))
		result.append({"id": id, "title": title(state, viewer, id), "choices": choices})
	return result


## Countries offered by a targeted decision, seen from `viewer` ([&""] for the untargeted ones).
static func targets(state: OperationalState, viewer: int, id: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	if id == ESCALATE or id == STAND_DOWN or id == NUCLEAR:
		found.append(&"")
		return found
	for country in state.countries:
		var relation := CountryRules.relation(state, viewer, country.id)
		var listed := false
		match id:
			DECLARE:
				listed = relation == &"neutral" or relation == &"hostile"
			INVOKE:
				listed = relation == &"own" and country.stance == CountryState.ALIGNED
			DEMAND:
				listed = relation == &"hostile"
		if listed:
			found.append(country.id)
	return found


## One choice of decision `id` on `country`.
static func choice(
	state: OperationalState, viewer: int, id: StringName, country: StringName
) -> Dictionary:
	var cmd := command(id, country)
	var code := _problem(state, viewer, cmd)
	var steps := _steps(state, viewer, id, country)
	var previous := state.escalation_level
	var next := previous - 1 if id == STAND_DOWN else previous + steps
	var cap := state.ladder.cap()
	if id == NUCLEAR:
		previous = cap
		next = state.ladder.top()
	elif previous <= cap:
		next = mini(next, cap)  # the ordinary decisions stop at the cap (`level_cap`)
	next = maxi(next, 0)
	var danger := id == NUCLEAR or (steps > 0 and next >= cap and previous < cap)
	var name_text := _country_name(state, country)
	var tag := &""
	if code != "":
		tag = &"blocked"
	var relation := CountryRules.relation(state, viewer, country)
	if relation == &"enemy":
		relation = &"hostile"
	return {
		"id": id,
		"country": country,
		"name": name_text,
		"effect": _effect(state, viewer, id, name_text, steps, previous, next),
		"cost": steps,
		"cost_text": _cost_text(id, steps),
		"cost_kind": _cost_kind(id, steps),
		"enabled": code == "",
		"code": code,
		"reason": "" if code == "" else TranslationServer.translate(REASONS.get(code, code)),
		"tag": tag,
		"relation": relation,
		"stance_text": TranslationServer.translate(STANCE_WORDS.get(relation, "")),
		"danger": danger,
		"new_level": next,
		"new_level_name": StaffMapEscalation.level_name(state, next),
		"confirm": _confirm(state, viewer, id, name_text, previous, next, danger),
	}


static func _no_target(state: OperationalState, viewer: int, id: StringName) -> Dictionary:
	var code := _problem(state, viewer, null)
	if code == "":
		code = "no_target"
	return {
		"id": id,
		"country": &"",
		"name": "",
		"effect": TranslationServer.translate(NO_TARGET_EFFECTS.get(id, "")),
		"cost": 0,
		"cost_text": _cost_text(id, 0),
		"cost_kind": _cost_kind(id, 0),
		"enabled": false,
		"code": code,
		"reason": TranslationServer.translate(REASONS.get(code, code)),
		"tag": &"blocked",
		"relation": &"none",
		"stance_text": "",
		"danger": false,
		"new_level": state.escalation_level,
		"new_level_name": StaffMapEscalation.level_name(state, state.escalation_level),
		"confirm": "",
	}


## "" when the viewer may issue `cmd`, else the code. The viewer is not the issuer (the current
## player) on someone else's turn.
static func _problem(state: OperationalState, viewer: int, cmd: PoliticalDecisionCommand) -> String:
	if not state.result.is_empty():
		return "operation_over"
	if viewer != state.current_player:
		return "not_your_turn"
	return "" if cmd == null else cmd.validate(state)


static func _steps(
	state: OperationalState, viewer: int, id: StringName, country: StringName
) -> int:
	match id:
		ESCALATE:
			return state.ladder.decision_escalation
		INVOKE:
			return state.ladder.alliance_escalation
		DECLARE:
			return DeclareHostilitiesCommand.cost(state, viewer, country)
		NUCLEAR:
			return state.ladder.top() - state.ladder.cap()
	return 0


static func _cost_kind(id: StringName, steps: int) -> StringName:
	if id == STAND_DOWN:
		return &"down"
	return &"up" if steps > 0 else &"free"


static func _cost_text(id: StringName, steps: int) -> String:
	if id == STAND_DOWN:
		return TranslationServer.translate("Level -1")
	if steps <= 0:
		return TranslationServer.translate("Free")
	return TranslationServer.translate("Level +%d") % steps


static func _effect(
	state: OperationalState,
	viewer: int,
	id: StringName,
	country_name: String,
	steps: int,
	previous: int,
	next: int
) -> String:
	var levels := "%d → %d" % [previous, next]
	match id:
		ESCALATE:
			return TranslationServer.translate("Wider strikes: level %s") % levels
		STAND_DOWN:
			return (
				TranslationServer.translate("De-escalate: level %s, no escalating for %d turns")
				% [levels, state.ladder.stand_down_cooldown_turns]
			)
		DECLARE:
			var key := "%s becomes hostile to the enemy, level %s"
			if steps == 0:
				key = "%s becomes hostile to the enemy (casus belli, no level change)"
				return TranslationServer.translate(key) % country_name
			return TranslationServer.translate(key) % [country_name, levels]
		INVOKE:
			return (
				TranslationServer.translate("%s enters the war on your side, level %s")
				% [country_name, levels]
			)
		DEMAND:
			return TranslationServer.translate("%s is forced back to neutrality") % country_name
		NUCLEAR:
			return (
				TranslationServer.translate("The operation ends: %s is judged the loser (level %s)")
				% [StaffMapTurnBar.side_name(state, viewer), levels]
			)
	return ""


static func _confirm(
	state: OperationalState,
	viewer: int,
	id: StringName,
	country_name: String,
	previous: int,
	next: int,
	danger: bool
) -> String:
	if id == NUCLEAR:
		return (
			TranslationServer.translate(NUCLEAR_CONFIRM) % StaffMapTurnBar.side_name(state, viewer)
		)
	var title_text := TranslationServer.translate(TITLES.get(id, String(id)))
	if country_name != "":
		title_text += " · " + country_name
	if next == previous:
		return title_text + "?"
	var text := (
		TranslationServer.translate("%s? Level %d → %d (%s)")
		% [title_text, previous, next, StaffMapEscalation.level_name(state, next)]
	)
	if danger and next > previous:
		text += " " + TranslationServer.translate("– the highest level of escalation")
	return text


static func _country_name(state: OperationalState, country_id: StringName) -> String:
	var country := state.get_country(country_id)
	if country == null:
		return ""
	return TranslationServer.translate(country.definition.display_name)


static func _side(state: OperationalState, player: int) -> SideDefinition:
	if player < 0 or player >= state.player_sides.size():
		return null
	return SideDefinition.find(state.player_sides[player])


## Log line of a `political_decision_taken` event for the turn report ("NATO: Escalate").
static func log_text(state: OperationalState, event: Dictionary) -> String:
	var player: int = event["player"]
	var id := StringName(event["decision"])
	var text := "%s: %s" % [StaffMapTurnBar.side_name(state, player), title(state, player, id)]
	var country := _country_name(state, StringName(event.get("country", &"")))
	return text if country == "" else "%s · %s" % [text, country]
