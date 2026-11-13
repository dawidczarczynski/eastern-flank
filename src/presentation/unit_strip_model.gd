class_name UnitStripModel
extends RefCounted
## Pure model of the unit variant of the bottom-bar strip in the battle scene: the same widget
## as on the staff map (StaffMapUnitStrip), filled with a tactical unit – name, HEALTH (gauge and
## "7 / 10"), MOVES ("3 / 5") and STATUS (READY / DONE / HOSTILE). Reuses UnitPopupModel for the
## numbers, so the strip and the unit card never disagree. Texts are already translated.

const CAPTIONS: Array[String] = ["HEALTH", "MOVES", "STATUS"]
const KIND := "UNIT"


## Model for StaffMapUnitStrip.show_unit() of `unit` as `viewer_player` sees it.
static func build(state: GameState, unit: Unit, viewer_player: int) -> Dictionary:
	var popup := UnitPopupModel.build(state, unit, viewer_player)
	var own := unit.owner_id == viewer_player
	var hp: int = popup["hp"]
	var max_hp: int = popup["max_hp"]
	var side: Color = popup["color"]
	var moves := ""
	for stat: Dictionary in popup["stats"]:
		if stat["label"] == "Moves":
			moves = stat["value"]
	return {
		"id": StringName(str(unit.id)),
		"owner_id": unit.owner_id,
		"kind": KIND,
		"captions": CAPTIONS,
		"name":
		StaffMapUnitCardModel.abbreviate(
			StaffMapUnitCardModel.upper(_t(popup["name"])), StaffMapUnitCardModel.NAME_MAX_CHARS
		),
		"side_text": _t("OWN") if own else _t("HOSTILE"),
		"side_color": side,
		"known": true,
		"lit": StaffMapFormations.lit_segments(hp, max_hp),
		"gauge_color": UiPalette.hp_color(hp, max_hp),
		"unlit_color": UiPalette.HP_EMPTY,
		"strength_text": "%d / %d" % [hp, max_hp],
		"posture_text": moves.replace("/", " / "),
		"order_text": StaffMapUnitCardModel.upper(_t(_status_key(state, unit, viewer_player))),
	}


static func _status_key(state: GameState, unit: Unit, viewer_player: int) -> String:
	if unit.owner_id != viewer_player:
		return "HOSTILE"
	return "UNIT_STRIP_DONE" if UnitStatus.is_done(state, unit) else "UNIT_STRIP_READY"


static func _t(key: String) -> String:
	return TranslationServer.translate(key)
