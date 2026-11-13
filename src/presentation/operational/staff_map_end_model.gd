class_name StaffMapEndModel
extends RefCounted
## Texts of the end-of-operation notice (TASK-107b): headline for the viewer's side, the ending
## reason, the points table and the round count. Pure functions of the state and the
## `operation_ended` event (the `score` payload, recomputed from the state for a resumed record).

const HEADLINE_VICTORY := "Victory"
const HEADLINE_DEFEAT := "Defeat"
const HEADLINE_DRAW := "Draw"
const HEADLINE_NOBODY := "Nobody wins"
const REASONS := {
	&"gap_closed": "Russia held the Gap road link long enough. The operation ends.",
	&"round_limit": "The round limit was reached. The operation is scored.",
	&"nuclear_use": "%s used a nuclear weapon. The operation ends.",
}
const GENERIC_REASON := "The operation has ended."


## Victory / Defeat / Draw / Nobody wins for `viewer`. A -1 winner is a draw, except after
## `nuclear_use`, where it is a defeat for the side that used the weapon (the human playing it) and
## "Nobody wins" for the other one.
static func headline(_state: OperationalState, event: Dictionary, viewer: int) -> String:
	var winner: int = event.get("winner", -1)
	if winner >= 0:
		return _t(HEADLINE_VICTORY if winner == viewer else HEADLINE_DEFEAT)
	if event.get("reason") == &"nuclear_use":
		return _t(HEADLINE_DEFEAT if int(event.get("by", -1)) == viewer else HEADLINE_NOBODY)
	return _t(HEADLINE_DRAW)


static func reason_line(state: OperationalState, event: Dictionary) -> String:
	var reason: StringName = event.get("reason", &"")
	if not REASONS.has(reason):
		return _t(GENERIC_REASON)
	var text := _t(REASONS[reason])
	if reason == &"nuclear_use":
		return text % StaffMapTurnBar.side_name(state, int(event.get("by", 0)))
	return text


## The second line: "Nobody wins." after a nuclear attack, else the round count.
static func detail_line(state: OperationalState, event: Dictionary) -> String:
	if event.get("reason") == &"nuclear_use":
		return _t("Nobody wins.")
	return _t("Rounds played: %d") % rounds_played(state, event)


## The operation ends at a round boundary after `turn` was raised, except by a nuclear attack.
static func rounds_played(state: OperationalState, event: Dictionary) -> int:
	return state.turn if event.get("reason") == &"nuclear_use" else maxi(state.turn - 1, 0)


## The score payload of the event, or the score recomputed from the state (a resumed record).
static func scores(state: OperationalState, event: Dictionary) -> Dictionary:
	var payload: Dictionary = event.get("score", {})
	if not payload.is_empty() or state.definition == null:
		return payload
	return OperationVictory.score(state, state.definition)


## Table rows [label, side 0 points, side 1 points] (strings): one row per held objective, the
## escalation penalty and the total. Empty without a score.
static func table_rows(state: OperationalState, event: Dictionary) -> Array[PackedStringArray]:
	var payload := scores(state, event)
	var rows: Array[PackedStringArray] = []
	if payload.is_empty():
		return rows
	var ids: Array[StringName] = []
	for side in 2:
		for line in payload[side]["lines"]:
			if not ids.has(line["id"]):
				ids.append(line["id"])
	for id in ids:
		var row := PackedStringArray([_line_label(state, id)])
		for side in 2:
			var points := ""
			for line in payload[side]["lines"]:
				if line["id"] == id:
					points = "+%d" % int(line["points"])
			row.append(points if points != "" else "–")
		rows.append(row)
	(
		rows
		. append(
			PackedStringArray(
				[
					_t("Escalation"),
					_signed(payload[0]["escalation_penalty"]),
					_signed(payload[1]["escalation_penalty"]),
				]
			)
		)
	)
	rows.append(
		PackedStringArray([_t("Total"), str(payload[0]["total"]), str(payload[1]["total"])])
	)
	return rows


static func _line_label(state: OperationalState, id: StringName) -> String:
	if id == &"gap_open":
		return _t("Gap road link open")
	if id == &"gap_closed":
		return _t("Gap road link closed")
	if state.definition != null:
		for objective in state.definition.objectives:
			if objective.id == id:
				return _t(objective.display_name)
	return String(id)


static func _signed(value: int) -> String:
	return "%d" % value if value <= 0 else "+%d" % value


static func _t(key: String) -> String:
	return TranslationServer.translate(key)
