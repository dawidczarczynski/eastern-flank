class_name StaffMapObjectivesModel
extends RefCounted
## Texts of the objectives window of the staff map: what the viewer's side is scored on, who holds
## each objective now and the round counter. Pure functions of the state (OperationVictory is the
## one scoring rule); the words are translated here.

const MINE := &"mine"
const THEIRS := &"theirs"
const NONE := &"none"


## Rows {label, points, holder (translated), status (MINE / THEIRS / NONE), yours (bool), rule
## (when it is scored), progress (the Gap's closed-round counter, "" for hexes), hint} for the
## objectives scoring for `viewer` (or for whoever holds them), then the Gap road link.
static func rows(state: OperationalState, viewer: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var def := state.definition
	if def == null:
		return result
	for objective in def.objectives:
		var holder := HexControl.holder(state, objective.hex_in(state))
		(
			result
			. append(
				{
					"label": _t(objective.display_name),
					"points": objective.points,
					"holder": _holder_text(state, holder),
					"status": _status(holder, viewer),
					"yours":
					objective.holder_rule == OperationObjective.ANY or objective.side == viewer,
					"rule": _t("Scored at the end, round %d") % def.round_limit,
					"progress": "",
					"hint": "",
				}
			)
		)
	if not def.gap_chain.is_empty():
		var closed := OperationVictory.gap_status(state, def) == OperationVictory.CLOSED
		var mine := (viewer == 1) == closed
		(
			result
			. append(
				{
					"label":
					_t("Gap road link closed") if viewer == 1 else _t("Gap road link open"),
					"points": def.gap_closed_points if viewer == 1 else def.gap_open_points,
					"holder": _t("CLOSED") if closed else _t("OPEN"),
					"status": MINE if mine else THEIRS,
					"yours": true,
					"rule":
					(
						_t(
							"%s wins after %d consecutive closed rounds; otherwise scored at the end"
						)
						% [StaffMapTurnBar.side_name(state, 1), def.closed_rounds_to_win]
					),
					"progress": _gap_progress(state, viewer),
					"hint":
					_t("Any chain hex lost resets it") if state.gap_closed_rounds > 0 else "",
				}
			)
		)
	return result


## "ROUND 4 / 30".
static func round_line(state: OperationalState) -> String:
	var limit := 0 if state.definition == null else state.definition.round_limit
	return _t("ROUND %d / %d") % [maxi(state.turn, 1), limit]


## Toast / journal text of an `objective_changed` event as `viewer` reads it; "" when the event is
## not understood.
static func event_text(state: OperationalState, viewer: int, event: Dictionary) -> String:
	var def := state.definition
	if def == null:
		return ""
	match event.get("kind"):
		&"holder":
			for objective in def.objectives:
				if objective.id == event.get("objective_id"):
					var taker := int(event.get("new", -1))
					var who := (
						_t("you") if taker == viewer else StaffMapTurnBar.side_name(state, taker)
					)
					return _t("%s taken by %s") % [_t(objective.display_name), who]
		&"gap":
			if event.get("new") == OperationVictory.CLOSED:
				return _t("The Gap is closed")
			return _t("The Gap is open again")
		&"gap_counter":
			var count := int(event.get("new", 0))
			if count == 0:
				return _t("Gap chain broken - counter reset")
			var need := def.closed_rounds_to_win
			if count >= need:
				return _t("The Gap was held %d/%d rounds") % [count, need]
			if viewer == 1:
				return _t("Gap closed - %d/%d rounds, %s") % [count, need, _hold_text(need - count)]
			return (
				_t("%s holds the Gap - %d/%d rounds, break the chain")
				% [StaffMapTurnBar.side_name(state, 1), count, need]
			)
	return ""


## Journal line of an `objective_changed` event as `viewer` reads it: like `event_text` but with no
## bloc named (the journal's rule), "us" / "the enemy" instead.
static func journal_text(state: OperationalState, viewer: int, event: Dictionary) -> String:
	var def := state.definition
	if def == null:
		return ""
	if event.get("kind") == &"holder":
		for objective in def.objectives:
			if objective.id == event.get("objective_id"):
				var taker := _t("us") if int(event.get("new", -1)) == viewer else _t("the enemy")
				return _t("%s taken by %s") % [_t(objective.display_name), taker]
		return ""
	if event.get("kind") == &"gap_counter" and int(event.get("new", 0)) > 0:
		return (
			_t("The Gap was held %d/%d rounds")
			% [int(event.get("new", 0)), def.closed_rounds_to_win]
		)
	return event_text(state, viewer, event)


static func _gap_progress(state: OperationalState, viewer: int) -> String:
	var count := state.gap_closed_rounds
	var need := state.definition.closed_rounds_to_win
	if count <= 0:
		return _t("Closed %d/%d rounds") % [0, need]
	if viewer == 1:
		return _t("Closed %d/%d rounds - %s") % [count, need, _hold_text(need - count)]
	return (
		_t("%s: closed %d/%d rounds - break the chain")
		% [StaffMapTurnBar.side_name(state, 1), count, need]
	)


## "hold it 1 more round" / "hold it 2 more rounds".
static func _hold_text(remaining: int) -> String:
	if remaining == 1:
		return _t("hold it one more round")
	return _t("hold it %d more rounds") % remaining


static func _status(holder: int, viewer: int) -> StringName:
	if holder < 0:
		return NONE
	return MINE if holder == viewer else THEIRS


static func _holder_text(state: OperationalState, holder: int) -> String:
	return _t("NOBODY") if holder < 0 else StaffMapTurnBar.side_name(state, holder).to_upper()


static func _t(key: String) -> String:
	return TranslationServer.translate(key)
