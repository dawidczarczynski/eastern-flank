class_name StaffMapObjectivesModel
extends RefCounted
## Texts of the objectives window of the staff map: what the viewer's side is scored on, who holds
## each objective now and the round counter. Pure functions of the state (OperationVictory is the
## one scoring rule); the words are translated here.

const MINE := &"mine"
const THEIRS := &"theirs"
const NONE := &"none"


## Rows {label, points, holder (translated), status (MINE / THEIRS / NONE), yours (bool)} for the
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
				}
			)
		)
	return result


## "ROUND 4 / 30".
static func round_line(state: OperationalState) -> String:
	var limit := 0 if state.definition == null else state.definition.round_limit
	return _t("ROUND %d / %d") % [maxi(state.turn, 1), limit]


static func _status(holder: int, viewer: int) -> StringName:
	if holder < 0:
		return NONE
	return MINE if holder == viewer else THEIRS


static func _holder_text(state: OperationalState, holder: int) -> String:
	return _t("NOBODY") if holder < 0 else StaffMapTurnBar.side_name(state, holder).to_upper()


static func _t(key: String) -> String:
	return TranslationServer.translate(key)
