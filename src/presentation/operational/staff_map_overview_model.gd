class_name StaffMapOverviewModel
extends RefCounted
## Pure view-model of the read-only politics overview (TASK-119b, right column of the Politics
## screen): the ladder table, the countries list as seen by a viewer and the event log. Reads the
## OperationalState only, never changes it, holds no side-specific code.
##
## Deliberate asymmetry (GDD "Escalation ladder"): the ladder footer names what each side caused
## and de-escalated; the countries list and the event log show effects only – no row says who
## decided. Do not add a "by" to them.

const STANCE_WORDS := {
	&"own": "own",
	&"allied": "allied",
	&"neutral": "neutral",
	&"hostile": "hostile",
	&"enemy": "enemy",
}


## All blocks for `viewer`: {ladder, footer, countries, log}. A "support" block is added only
## when the operation has support packages (TASK-121); there is no such data yet, so it is absent.
static func build(state: OperationalState, viewer: int) -> Dictionary:
	return {
		"ladder": ladder_rows(state),
		"footer": footer(state),
		"countries": country_rows(state, viewer),
		"log": log_rows(state),
	}


## One row per level 0 .. top: {level, name, roe, event, current, nuclear}.
static func ladder_rows(state: OperationalState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var ladder := state.ladder
	for level in ladder.levels.size():
		(
			rows
			. append(
				{
					"level": level,
					"name": StaffMapEscalation.level_name(state, level),
					"roe": StaffMapEscalation.roe_text(state, level),
					"event": _entry_event(state, level),
					"current": level == state.escalation_level,
					"nuclear": level == ladder.top(),
				}
			)
		)
	return rows


## Per side {name, caused, deescalated, net} (net = caused - deescalated, at least 0).
static func footer(state: OperationalState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for side in state.player_sides.size():
		var caused: int = state.escalation_caused[side]
		var down: int = state.escalation_deescalated[side]
		(
			rows
			. append(
				{
					"name": StaffMapTurnBar.side_name(state, side),
					"caused": caused,
					"deescalated": down,
					"net": maxi(caused - down, 0),
				}
			)
		)
	return rows


## One row per country in setup order: {id, name, stance, stance_text, open, own, enemy, pending}.
## `stance` is own / allied / neutral / hostile / enemy as seen from `viewer`; `pending` is the
## number of formations that still come when the country joins (0 once contributed).
static func country_rows(state: OperationalState, viewer: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for country in state.countries:
		var stance := stance_for(state, viewer, country)
		var own := 0
		var enemy := 0
		for f in state.formations:
			if f.strength() <= 0 or state.country_at(f.coord) != country.id:
				continue
			if f.owner_id == viewer:
				own += 1
			else:
				enemy += 1
		(
			rows
			. append(
				{
					"id": country.id,
					"name": TranslationServer.translate(country.definition.display_name),
					"stance": stance,
					"stance_text": TranslationServer.translate(STANCE_WORDS[stance]),
					"open": CountryRules.may_enter_country(state, viewer, country.id),
					"own": own,
					"enemy": enemy,
					"pending": 0 if country.contributed else country.contribution.size(),
				}
			)
		)
	return rows


static func stance_for(state: OperationalState, viewer: int, country: CountryState) -> StringName:
	match CountryRules.relation(state, viewer, country.id):
		&"own":
			return &"own" if country.stance == CountryState.BELLIGERENT else &"allied"
		&"enemy":
			return &"enemy"
		&"hostile":
			return &"hostile"
	return &"neutral"


## The log, newest first: [{turn, text}]. Texts name effects only.
static func log_rows(state: OperationalState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var entries := state.political_log.entries
	for index in range(entries.size() - 1, -1, -1):
		rows.append({"turn": entries[index].turn, "text": entry_text(state, entries[index])})
	return rows


static func entry_text(state: OperationalState, e: PoliticalLog.Entry) -> String:
	var country := _country_name(state, e.country)
	match e.kind:
		&"stance_changed":
			var side := _side_name(state, e.side)
			if e.stance_after == CountryState.NEUTRAL or side == "":
				return TranslationServer.translate("%s -> neutral") % country
			return (
				TranslationServer.translate("%s -> %s (%s)")
				% [country, side, TranslationServer.translate(String(e.stance_after))]
			)
		&"level_changed":
			return (
				TranslationServer.translate("Level %d -> %d %s")
				% [
					e.level_before,
					e.level_after,
					StaffMapEscalation.level_name(state, e.level_after)
				]
			)
		&"decision":
			var title := TranslationServer.translate(
				StaffMapDecisionsModel.TITLES.get(e.cause, String(e.cause))
			)
			var text := TranslationServer.translate("Decision: %s") % title
			return text if country == "" else "%s - %s" % [text, country]
		&"sanctuary_breach":
			return TranslationServer.translate("Sanctuary entered - %s") % country
		&"contribution":
			return (
				TranslationServer.translate("%s sends reinforcements to %s")
				% [country, _side_name(state, e.side)]
			)
	return String(e.key)


static func _entry_event(state: OperationalState, level: int) -> String:
	var ladder := state.ladder
	if level == ladder.top():
		return TranslationServer.translate("ESC_MARK_END")
	if level == ladder.sanctuary_open_level:
		return TranslationServer.translate("ESC_MARK_SANCTUARY")
	if level == ladder.allies_join_level:
		return TranslationServer.translate("ESC_MARK_ALLIES")
	if level == ladder.cap():
		return TranslationServer.translate("ESC_MARK_CAP")
	return ""


static func _country_name(state: OperationalState, country_id: StringName) -> String:
	var country := state.get_country(country_id)
	if country == null:
		return ""
	return TranslationServer.translate(country.definition.display_name)


static func _side_name(state: OperationalState, side: int) -> String:
	if side < 0 or side >= state.player_sides.size():
		return ""
	return StaffMapTurnBar.side_name(state, side)
