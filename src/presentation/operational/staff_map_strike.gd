class_name StaffMapStrike
extends RefCounted
## Pure view model of the strike mode on the staff map (TASK-097b, GDD "Deep strikes"): the means
## list, the salvo limit, per target whether it is legal and why not, the raise-and-strike option
## and the escalation lines of the confirm card. Reads the OperationalState only and builds
## nothing but dictionaries and texts; the commands are issued by StaffMapStrikeHud.

## Reason code -> English text (also the translation key). `{means}` is the means' name.
const REASON_TEXTS := {
	"own_soil": "Own territory",
	"out_of_range": "Out of range of {means}",
	"target_destroyed": "Already destroyed",
	"unknown_target": "Unknown target",
}
const CLOSED_TEXT := "Closed soil – opens at {level}"
const CLOSED_NEUTRAL_TEXT := "Closed soil"
const ROE_TEXT := "Not allowed at this level – needs {level}"
const CONDITIONAL_TEXT := "Needs {level} – raise the level first"
## Why the mode cannot be opened / a click does nothing, and the rejection codes a strike can get.
const PROBLEM_TEXTS := {
	"operation_over": "The operation is over",
	"battle_pending": "Resolve the pending battle first",
	"not_your_turn": "Not your turn",
	"no_strikes_left": "No strikes left this turn",
	"out_of_stock": "Out of stock",
	"bad_count": "Bad salvo size",
}
const THRESHOLD_TEXT := "Reaches the strategic threshold – you would lose the operation"


## "" when `viewer` may open the strike mode now, else operation_over / battle_pending /
## not_your_turn.
static func open_problem(state: OperationalState, viewer: int) -> String:
	if not state.result.is_empty():
		return "operation_over"
	if not state.pending_battles.is_empty():
		return "battle_pending"
	if state.current_player != viewer:
		return "not_your_turn"
	return ""


## Translated text of an open problem or a command rejection code (the code itself when unknown).
static func problem_text(code: String) -> String:
	return TranslationServer.translate(PROBLEM_TEXTS.get(code, code))


## Means of `player`'s side: [{id, name, stock, range_hexes, max_salvo}] in the state's order.
static func means_list(state: OperationalState, player: int) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for id: StringName in state.strike_means:
		var means: StrikeMeansDefinition = state.strike_means[id]
		(
			list
			. append(
				{
					"id": id,
					"name": TranslationServer.translate(means.display_name),
					"stock": StrikeRules.stock(state, player, id),
					"range_hexes": means.range_hexes,
					"max_salvo": means.max_salvo,
				}
			)
		)
	return list


## Largest salvo of the means: min(max_salvo, stock); 0 for an unknown means or no stock.
static func salvo_max(state: OperationalState, player: int, means_id: StringName) -> int:
	var means: StrikeMeansDefinition = state.strike_means.get(means_id)
	if means == null:
		return 0
	return mini(means.max_salvo, StrikeRules.stock(state, player, means_id))


## "Strikes: 2/2".
static func strikes_text(state: OperationalState) -> String:
	return (
		TranslationServer.translate("Strikes: %d/%d") % [state.strikes_left, state.strikes_per_turn]
	)


## Facts of one target for the means: {legal, conditional, reason_code, reason_text}. `legal`: the
## strike may be confirmed as it is (no reason); `conditional`: only the raise-and-strike option
## makes it legal (reason_code keeps the plain problem, reason_text says what to do).
static func target_view(
	state: OperationalState, player: int, target_id: StringName, means_id: StringName
) -> Dictionary:
	var code := StrikeRules.target_problem(state, player, target_id, means_id)
	var conditional := code != "" and raise_offered(state, player, target_id, means_id)
	var text := ""
	if conditional:
		text = _conditional_text(state)
	elif code != "":
		text = reason_text(state, player, target_id, means_id, code)
	return {
		"legal": code == "",
		"conditional": conditional,
		"reason_code": code,
		"reason_text": text,
	}


## The text of a problem code for this target and means.
static func reason_text(
	state: OperationalState, player: int, target_id: StringName, means_id: StringName, code: String
) -> String:
	match code:
		"closed_country":
			return _closed_text(state, player, target_id)
		"roe_class":
			var target := StrikeRules.find_target(state, player, target_id)
			var needed := _level_allowing(state, target.get("class_id", &""))
			return TranslationServer.translate(ROE_TEXT).replace(
				"{level}", StaffMapEscalation.level_name(state, needed)
			)
	var means: StrikeMeansDefinition = state.strike_means.get(means_id)
	var means_name: String = (
		TranslationServer.translate(means.display_name) if means != null else ""
	)
	return TranslationServer.translate(REASON_TEXTS.get(code, code)).replace("{means}", means_name)


## Whether the target is rejected only because the level is one short and the political decision
## Escalate (TASK-117) can fix it now: the problem is `roe_class`, or `closed_country` of an enemy
## sanctuary that the next level opens; the target is in range; `EscalateCommand` would be
## accepted; and the target class is allowed at the next level.
static func raise_offered(
	state: OperationalState, player: int, target_id: StringName, means_id: StringName
) -> bool:
	var target := StrikeRules.find_target(state, player, target_id)
	if target.is_empty():
		return false
	if target["kind"] == &"installation" and state.get_installation(target_id).destroyed():
		return false
	var coord: Vector2i = target["coord"]
	var reason := EscalationRules.strike_allowed(state, player, coord, target["class_id"])
	if reason != "roe_class" and reason != "closed_country":
		return false
	if means_id != &"" and not StrikeRules.in_range(state, player, means_id, coord):
		return false
	if EscalateCommand.new().validate(state) != "":
		return false
	var next := state.escalation_level + state.ladder.decision_escalation
	if not state.ladder.strike_classes_at(next).has(target["class_id"]):
		return false
	if reason == "closed_country":
		var country := state.get_country(state.country_at(coord))
		return (
			country != null
			and country.definition.sanctuary
			and CountryRules.relation(state, player, country.id) == &"enemy"
			and next >= state.ladder.sanctuary_open_level
		)
	return true


## The escalation lines of the confirm card: [{text, danger}]. `raised`: computed for the level
## after the Escalate decision. Nothing for a strike without escalation.
static func escalation_lines(
	state: OperationalState, player: int, target_id: StringName, raised := false
) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var preview := StrikeRules.escalation_preview(state, player, target_id)
	var base := state.escalation_level + (state.ladder.decision_escalation if raised else 0)
	var top := state.ladder.top()
	if preview >= 1:
		var target := StrikeRules.find_target(state, player, target_id)
		var coord: Vector2i = target["coord"]
		var breach := 0
		var country := state.get_country(state.country_at(coord))
		if (
			country != null
			and country.definition.sanctuary
			and CountryRules.relation(state, player, country.id) == &"enemy"
			and not country.breached_by[player]
		):
			breach = state.ladder.sanctuary_breach_escalation
			(
				lines
				. append(
					{
						"text":
						(
							TranslationServer.translate("Breaches %s sanctuary: +%d escalation")
							% [TranslationServer.translate(country.definition.display_name), breach]
						),
						"danger": false,
					}
				)
			)
		if preview > breach:
			(
				lines
				. append(
					{
						"text":
						(
							TranslationServer.translate("Urban hex: +%d escalation")
							% (preview - breach)
						),
						"danger": false,
					}
				)
			)
		(
			lines
			. append(
				{
					"text":
					(
						TranslationServer.translate("Escalation level: %s")
						% StaffMapEscalation.level_name(state, mini(base + preview, top))
					),
					"danger": false,
				}
			)
		)
	if base + preview >= top:
		lines.append({"text": String(TranslationServer.translate(THRESHOLD_TEXT)), "danger": true})
	return lines


## The confirm card: {title, means_line, raise_line, lines, danger}. `title` is the target's
## name; `raise_line` is "" unless `raised`; `danger` when a line is a danger line.
static func confirm_model(
	state: OperationalState,
	player: int,
	target_id: StringName,
	means_id: StringName,
	salvo: int,
	raised: bool
) -> Dictionary:
	var means: StrikeMeansDefinition = state.strike_means[means_id]
	var lines := escalation_lines(state, player, target_id, raised)
	var danger := false
	for line in lines:
		danger = danger or line["danger"]
	var raise_line := ""
	if raised:
		var next := state.escalation_level + state.ladder.decision_escalation
		raise_line = (
			TranslationServer.translate("Escalate to %s (uses this turn's decision)")
			% StaffMapEscalation.level_name(state, mini(next, state.ladder.top()))
		)
	return {
		"title": target_name(state, target_id),
		"means_line": "%s × %d" % [TranslationServer.translate(means.display_name), salvo],
		"raise_line": raise_line,
		"lines": lines,
		"danger": danger,
	}


## Translated name of a target (installation or formation); the id when unknown.
static func target_name(state: OperationalState, target_id: StringName) -> String:
	var installation := state.get_installation(target_id)
	if installation != null:
		return TranslationServer.translate(installation.display_name)
	var formation := state.get_formation(target_id)
	if formation != null:
		return TranslationServer.translate(formation.display_name)
	return String(target_id)


## The toast after the strike was rejected: the plain code, or, after a successful Escalate, that
## the level was raised but the strike failed.
static func failed_after_raise_text(code: String) -> String:
	return TranslationServer.translate("Level raised, but the strike failed: %s") % code


static func _conditional_text(state: OperationalState) -> String:
	var next := mini(state.escalation_level + state.ladder.decision_escalation, state.ladder.top())
	return TranslationServer.translate(CONDITIONAL_TEXT).replace(
		"{level}", StaffMapEscalation.level_name(state, next)
	)


## Lowest level that allows the class (the top when none does).
static func _level_allowing(state: OperationalState, class_id: StringName) -> int:
	for level in state.ladder.levels.size():
		if state.ladder.strike_classes_at(level).has(class_id):
			return level
	return state.ladder.top()


static func _closed_text(state: OperationalState, player: int, target_id: StringName) -> String:
	var target := StrikeRules.find_target(state, player, target_id)
	var country := state.get_country(state.country_at(target.get("coord", Vector2i.ZERO)))
	var level := -1
	if country != null:
		match CountryRules.relation(state, player, country.id):
			&"enemy":
				level = state.ladder.sanctuary_open_level
			&"hostile":
				level = state.ladder.allies_join_level
	if level < 0:
		return TranslationServer.translate(CLOSED_NEUTRAL_TEXT)
	return TranslationServer.translate(CLOSED_TEXT).replace(
		"{level}", StaffMapEscalation.level_name(state, level)
	)
