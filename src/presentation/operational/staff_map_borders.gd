class_name StaffMapBorders
extends RefCounted
## Pure texts and markers of the border rules on the staff map (TASK-116): why a hex is closed to
## a formation, the warnings of a route (EscalationRules.route_incidents) at the first hex of each
## incident, the toast of a gained casus belli and the report words. Reads the state only.

const REASON_CLOSED := "ROUTE_CLOSED"
## Marker kinds (drawn alike: an amber triangle; the label says what it is).
const BREACH := &"sanctuary_breach"
const CASUS_BELLI := &"casus_belli"


## Why a destination `formation` may not enter is closed: {title: "RUSSIA · CLOSED" (the country in
## caps + the closed word), name: "RUSSIA", reason: the sentence}; {} when it may enter.
static func closed_info(
	state: OperationalState, formation: Formation, destination: Vector2i
) -> Dictionary:
	if not OperationalRoutes.destination_closed(state, formation, destination):
		return {}
	var country := state.get_country(state.country_at(destination))
	if country == null:
		return {}
	var reason := "Neutral – closed until it joins"
	match CountryRules.relation(state, formation.owner_id, country.id):
		&"hostile":
			reason = "Hostile – closed to your side"
		&"enemy":
			reason = "Sanctuary – opens at escalation 2 (Open war)"
	var name := _country_name(country).to_upper()
	return {
		"name": name,
		"title": "%s · %s" % [name, TranslationServer.translate("CLOSED")],
		"reason": String(TranslationServer.translate(reason)),
	}


## One warning per incident of `route`: Array of {kind, at (the first hex of the incident), text,
## ends (true when it ends the operation)}.
static func warnings(
	state: OperationalState, formation: Formation, route: Array[Vector2i]
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for incident in EscalationRules.route_incidents(state, formation, route):
		(
			out
			. append(
				{
					"kind": incident["type"],
					"at": incident["at"],
					"text": incident_text(state, formation.owner_id, incident),
					"chip": chip_of(incident),
					"tag": tag_of(incident),
					"sentence": sentence_of(state, incident),
					"ends": incident.get("ends_operation", false),
				}
			)
		)
	return out


## The warnings of the route an `IssueOrderCommand` would take (planned as the preview does); []
## when the order has no route or no incident.
static func order_warnings(
	state: OperationalState, command: IssueOrderCommand
) -> Array[Dictionary]:
	var formation := state.get_formation(command.formation_id)
	if formation == null:
		return []
	var preview := StaffMapRoute.preview_in_posture(
		state, formation, command.destination, command.posture
	)
	if preview.is_empty() or preview["route"].is_empty():
		return []
	return warnings(state, formation, preview["route"])


## The chip of an incident: "+1", "CB", or "END" when it ends the operation.
static func chip_of(incident: Dictionary) -> String:
	if incident.get("ends_operation", false):
		return "END"
	if incident["type"] == BREACH:
		return "+%d" % incident["steps"]
	return "CB"


## The tag of a sanctuary breach on the route ("ESCALATION +1"); "" for a casus belli.
static func tag_of(incident: Dictionary) -> String:
	if incident["type"] != BREACH:
		return ""
	return TranslationServer.translate("ESCALATION +%d") % incident["steps"]


## The sentence under a breach tag ("Enters Russia", "... This ends the operation"); the full
## text for a casus belli.
static func sentence_of(state: OperationalState, incident: Dictionary) -> String:
	if incident["type"] != BREACH:
		return ""
	var country := state.get_country(incident["country"])
	var name := _country_name(country) if country != null else String(incident["country"])
	var text: String = TranslationServer.translate("Enters %s") % name
	if incident["ends_operation"]:
		text += ". " + TranslationServer.translate("This ends the operation")
	return text


## "Enters Russia: escalation +1", "... – this ends the operation", "NATO attacks out of
## Lithuania: casus belli for Russia".
static func incident_text(state: OperationalState, player: int, incident: Dictionary) -> String:
	var country := state.get_country(incident["country"])
	var name := _country_name(country) if country != null else String(incident["country"])
	if incident["type"] == BREACH:
		var text := (
			TranslationServer.translate("Enters %s: escalation +%d") % [name, incident["steps"]]
		)
		if incident["ends_operation"]:
			text += " – " + TranslationServer.translate("This ends the operation")
		return text
	return casus_belli_text(state, player, name, incident["for_player"])


## Words of a casus belli: `attacker` launches out of `country_name`, `for_player` gains the reason.
static func casus_belli_text(
	state: OperationalState, attacker: int, country_name: String, for_player: int
) -> String:
	return (
		TranslationServer.translate("%s attacks out of %s: casus belli for %s")
		% [
			StaffMapTurnBar.side_name(state, attacker),
			country_name,
			StaffMapTurnBar.side_name(state, for_player),
		]
	)


## The toast of a `casus_belli_gained` event.
static func casus_belli_event_text(state: OperationalState, event: Dictionary) -> String:
	var country := state.get_country(event["country"])
	var name := _country_name(country) if country != null else String(event["country"])
	var for_player: int = event["player"]
	return casus_belli_text(state, 1 - for_player, name, for_player)


## Turn report words of a contact the border rule forbids: "Halted – cannot attack into Russia".
static func forbidden_text(state: OperationalState, country_id: StringName) -> String:
	var country := state.get_country(country_id)
	var name := _country_name(country) if country != null else String(country_id)
	return TranslationServer.translate("Halted – cannot attack into %s") % name


static func _country_name(country: CountryState) -> String:
	return TranslationServer.translate(country.definition.display_name)
