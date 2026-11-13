class_name OperationVictory
extends RefCounted
## Victory of an operation (TASK-107a, GDD "Sides" Victory): the state of the Gap road link, the
## score of both sides by one rule, and the endings checked at the end of a round (`gap_closed`,
## then `round_limit`). Pure; the data is an OperationDefinition. Draws nothing from `state.rng`.

const OPEN := &"open"
const CLOSED := &"closed"


## `closed` when side 1 holds every hex of the chain, else `open` (an empty chain is `open`).
static func gap_status(state: OperationalState, def: OperationDefinition) -> StringName:
	if def.gap_chain.is_empty():
		return OPEN
	for hex in def.gap_chain:
		if HexControl.holder(state, hex) != 1:
			return OPEN
	return CLOSED


## Points lost by `side` for its net escalation steps, as a number <= 0.
static func penalty(state: OperationalState, def: OperationDefinition, side: int) -> int:
	var net := maxi(0, state.escalation_caused[side] - state.escalation_deescalated[side])
	return -def.escalation_penalty * net


## Score of `side`: {lines: [{id, points}], escalation_penalty, total}. Objective lines carry the
## objective id; the Gap adds `gap_open` (side 0) or `gap_closed` (side 1) when the chain exists.
static func side_score(state: OperationalState, def: OperationDefinition, side: int) -> Dictionary:
	var lines: Array[Dictionary] = []
	var total := 0
	for objective in def.objectives:
		if objective.scorer(HexControl.holder(state, objective.hex_in(state))) == side:
			lines.append({"id": objective.id, "points": objective.points})
			total += objective.points
	if not def.gap_chain.is_empty():
		var status := gap_status(state, def)
		if side == 0 and status == OPEN:
			lines.append({"id": &"gap_open", "points": def.gap_open_points})
			total += def.gap_open_points
		elif side == 1 and status == CLOSED:
			lines.append({"id": &"gap_closed", "points": def.gap_closed_points})
			total += def.gap_closed_points
	var cost := penalty(state, def, side)
	return {"lines": lines, "escalation_penalty": cost, "total": total + cost}


## {0: breakdown, 1: breakdown} (see side_score).
static func score(state: OperationalState, def: OperationDefinition) -> Dictionary:
	return {0: side_score(state, def, 0), 1: side_score(state, def, 1)}


## The winner of the totals: the higher side, -1 when the difference is under `draw_margin`.
static func winner_of(scores: Dictionary, def: OperationDefinition) -> int:
	var diff: int = scores[0]["total"] - scores[1]["total"]
	if absi(diff) < def.draw_margin or diff == 0:
		return -1
	return 0 if diff > 0 else 1


## Checks at the end of the finished round `round_number` (callers: EndOperationalTurnCommand
## when play returns to the first player): the chain counter, then `gap_closed`, then
## `round_limit`. Sets `state.result` and returns `operation_ended` when one fires; [] otherwise
## (also without a definition or when the operation is already over).
static func end_round(state: OperationalState, round_number: int) -> Array[Dictionary]:
	var def := state.definition
	if def == null or not state.result.is_empty():
		return []
	if gap_status(state, def) == CLOSED and not def.gap_chain.is_empty():
		state.gap_closed_rounds += 1
	else:
		state.gap_closed_rounds = 0
	if state.gap_closed_rounds >= def.closed_rounds_to_win:
		return end(state, 1, &"gap_closed", 1)
	if round_number >= def.round_limit:
		return end(state, winner_of(score(state, def), def), &"round_limit", -1)
	return []


## Ends the operation: sets `state.result` {winner, reason, by} and returns the `operation_ended`
## event with the `score` payload {0: breakdown, 1: breakdown} (an empty one without a definition).
static func end(
	state: OperationalState, winner: int, reason: StringName, by: int
) -> Array[Dictionary]:
	state.result = {"winner": winner, "reason": reason, "by": by}
	state.pending_battles.clear()
	var scores := {} if state.definition == null else score(state, state.definition)
	return [
		{"type": &"operation_ended", "winner": winner, "reason": reason, "by": by, "score": scores}
	]
