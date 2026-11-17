class_name StaffMapObjectivesModel
extends RefCounted
## Texts of the objectives window of the staff map: what the viewer's side is scored on, who holds
## each objective now and the round counter. Pure functions of the state (OperationVictory is the
## one scoring rule); the words are translated here.

const MINE := &"mine"
const THEIRS := &"theirs"
const NONE := &"none"

const RULE_KEY := (
	"%s wins at once if it holds the whole road for %d rounds in a row. "
	+ "Break the chain to reset the count."
)
const MAIN := &"main"
const SIDE := &"side"


## Rows for `viewer`: the Gap road first (tier `main`), then the hex objectives (tier `side`). Each
## is {label, tier, hex (the Gap: its middle hex), chain (the Gap's ordered hexes, [] for others),
## selected (row index == `selected`), status (MINE / THEIRS / NONE), holder (translated), chip
## (HELD BY US / ...), points, yours (bool), sub (the "scores for" line, "" on enemy rows)}; the
## Gap row adds {chain_held (bool per hex, held by side 1), held, total, chain_text, closed_rounds,
## need, progress, rule, attacker_status (how `viewer` sees side 1)}.
static func rows(state: OperationalState, viewer: int, selected := -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var def := state.definition
	if def == null:
		return result
	if not def.gap_chain.is_empty():
		result.append(_gap_row(state, viewer))
	for objective in def.objectives:
		var hex := objective.hex_in(state)
		var holder := HexControl.holder(state, hex)
		var any := objective.holder_rule == OperationObjective.ANY
		var yours := any or objective.side == viewer
		var sub := ""
		if yours:
			sub = (
				_t("Scores for whoever holds it")
				if any
				else _t("Scores for %s") % StaffMapTurnBar.side_name(state, viewer)
			)
		(
			result
			. append(
				{
					"label": _t(objective.display_name),
					"tier": SIDE,
					"hex": hex,
					"chain": [] as Array[Vector2i],
					"status": _status(holder, viewer),
					"holder": _holder_text(state, holder),
					"chip": _chip_text(holder, viewer),
					"points": objective.points,
					"yours": yours,
					"sub": sub,
				}
			)
		)
	for i in result.size():
		result[i]["selected"] = i == selected
	return result


## Header of the main section.
static func main_header() -> String:
	return _t("Main objective - decides the operation at once")


## "Side objectives - scored at the end, round 30".
static func side_header(state: OperationalState) -> String:
	var limit := 0 if state.definition == null else state.definition.round_limit
	return _t("Side objectives - scored at the end, round %d") % limit


static func _gap_row(state: OperationalState, viewer: int) -> Dictionary:
	var def := state.definition
	var closed := OperationVictory.gap_status(state, def) == OperationVictory.CLOSED
	var held: Array[bool] = []
	var count := 0
	for hex in def.gap_chain:
		var russian := HexControl.holder(state, hex) == 1
		held.append(russian)
		count += 1 if russian else 0
	var need := def.closed_rounds_to_win
	return {
		"label":
		_t("Keep the Gap road open") if viewer != 1 else _t("Connect Kaliningrad with Belarus"),
		"tier": MAIN,
		"hex": def.gap_chain[def.gap_chain.size() / 2],
		"chain": def.gap_chain.duplicate(),
		"status": MINE if (viewer == 1) == closed else THEIRS,
		"holder": _t("CLOSED") if closed else _t("OPEN"),
		"chip": _t("CLOSED") if closed else _t("OPEN"),
		"points": def.gap_closed_points if viewer == 1 else def.gap_open_points,
		"yours": true,
		"sub": "",
		"chain_held": held,
		"held": count,
		"total": def.gap_chain.size(),
		"chain_text":
		(
			_t("%d of %d held by %s")
			% [count, def.gap_chain.size(), StaffMapTurnBar.side_name(state, 1)]
		),
		"closed_rounds": state.gap_closed_rounds,
		"need": need,
		"progress": "%d / %d" % [state.gap_closed_rounds, need],
		"rule": _t(RULE_KEY) % [StaffMapTurnBar.side_name(state, 1), need],
		"attacker_status": MINE if viewer == 1 else THEIRS,
	}


static func _chip_text(holder: int, viewer: int) -> String:
	if holder < 0:
		return _t("NOBODY")
	return _t("HELD BY US") if holder == viewer else _t("HELD BY ENEMY")


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
