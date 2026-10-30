class_name TargetRingModel
extends RefCounted
## Pure model of the unit ring (TASK-089b): RMB on a unit opens the HUD v3 radial ring on it –
## on an enemy with 1 ATTACK and 2 INFO, on an own unit with 2 INFO only (its orders come with
## TASK-082); the other slots stay empty for later actions (e.g. fire support). INFO shows the
## unit's card only when triggered – the map has no hover card. Whether
## ATTACK is available and why not come from AttackCommand.validate(), the numbers from
## AttackCommand.forecast() – no rules here. Returns untranslated keys; the view translates them.
##
## build() returns {attacker_id, target_id, slots, attack, info, summary}:
## - slots: SLOT_COUNT entries {key (1-based), action (StringName, &"" when empty), label (Array of
##   label lines), icon (StringName), enabled, empty, reason (key, "" when enabled)} – the format
##   RadialRing draws, shared with the orders ring (TASK-082);
## - attack / info / summary: detail cards (RingDetailCard) {tab, key (0 = none), title,
##   description, forecast ({} or {expected, expected_text, low, high, range_text, max}), effects
##   (Array of {label, value}), footer_label, footer_value, disabled}; attack is {} for an own unit.

const SLOT_ATTACK := 0
const SLOT_INFO := 1
## AttackCommand.validate() reasons -> player text (translation key).
const REASON_TEXTS := {
	"game_over": "THE BATTLE IS OVER",
	"unit_not_found": "UNIT NOT FOUND",
	"not_your_unit": "NOT YOUR UNIT",
	"no_command_points": "NO COMMAND POINTS LEFT THIS TURN",
	"not_an_enemy": "NOT AN ENEMY",
	"already_attacked": "ALREADY ATTACKED THIS TURN",
	"out_of_range": "TARGET OUT OF RANGE",
}
const NO_SELECTION := "NO UNIT SELECTED"
const ATTACK_DESCRIPTION := (
	"Fire at the target. Every strength point rolls to hit, "
	+ "so the result varies around the average."
)
const INFO_DESCRIPTION := "Show the unit's card: strength, stats and status."


## The ring on `target_id` seen by `viewer_player` with `attacker_id` selected (-1 = none). A unit
## of the viewer gets no ATTACK slot.
static func build(
	state: GameState, viewer_player: int, attacker_id: int, target_id: int
) -> Dictionary:
	var target := state.get_unit(target_id)
	var own := target != null and target.owner_id == viewer_player
	var reason := attack_reason(state, attacker_id, target_id)
	var slots: Array[Dictionary] = []
	if own:
		slots.append(_empty_slot(SLOT_ATTACK))
	else:
		slots.append(_slot(SLOT_ATTACK, &"attack", ["ATTACK"], reason))
	slots.append(_slot(SLOT_INFO, &"info", ["INFO"], ""))
	for i in range(2, RadialRingGeometry.SLOT_COUNT):
		slots.append(_empty_slot(i))
	return {
		"attacker_id": attacker_id,
		"target_id": target_id,
		"slots": slots,
		"attack": {} if own else _attack_detail(state, attacker_id, target_id, reason),
		"info": _detail("ACTION", SLOT_INFO + 1, "INFO", INFO_DESCRIPTION),
		"summary": _summary(state, target_id, own),
	}


## "" when the attacker may attack the target now, else the player text of the reason.
static func attack_reason(state: GameState, attacker_id: int, target_id: int) -> String:
	if attacker_id == -1:
		return NO_SELECTION
	var reason := AttackCommand.new(attacker_id, target_id).validate(state)
	return "" if reason == "" else reason_text(reason)


## Player text (translation key) of a validate() reason; unknown reasons pass through.
static func reason_text(reason: String) -> String:
	return REASON_TEXTS.get(reason, reason)


static func _slot(index: int, action: StringName, label: Array, reason: String) -> Dictionary:
	return {
		"key": index + 1,
		"action": action,
		"label": label,
		"icon": action,
		"enabled": reason == "",
		"empty": false,
		"reason": reason,
	}


static func _empty_slot(index: int) -> Dictionary:
	return {
		"key": index + 1,
		"action": &"",
		"label": [],
		"icon": &"",
		"enabled": false,
		"empty": true,
		"reason": "",
	}


static func _attack_detail(
	state: GameState, attacker_id: int, target_id: int, reason: String
) -> Dictionary:
	var detail := _detail("ORDER", SLOT_ATTACK + 1, "ATTACK", ATTACK_DESCRIPTION)
	if reason != "":
		detail["disabled"] = true
		detail["footer_label"] = "UNAVAILABLE"
		detail["footer_value"] = reason
		return detail
	var target := state.get_unit(target_id)
	var f := AttackCommand.forecast(state, state.get_unit(attacker_id), target)
	detail["forecast"] = {
		"expected": f.expected_damage,
		"expected_text": "%.1f" % f.expected_damage,
		"low": f.damage_low,
		"high": f.damage_high,
		"range_text": "%d–%d" % [f.damage_low, f.damage_high],
		"max": target.hp,
	}
	# The DAMAGE line is the big number of the card; the others become its effect rows.
	var lines := HudModel.attack_forecast(state, attacker_id, target_id)
	detail["effects"] = lines.slice(1)
	detail["footer_label"] = "COST"
	detail["footer_value"] = "ENDS MOVEMENT"
	return detail


## The card with nothing hovered: the unit's name and strength.
static func _summary(state: GameState, target_id: int, own: bool) -> Dictionary:
	var detail := _detail("UNIT" if own else "TARGET", 0, "", "Choose an action…")
	var target := state.get_unit(target_id)
	if target != null:
		detail["title"] = target.definition.display_name
		detail["effects"] = [
			{"label": "STRENGTH", "value": "%d/%d" % [target.hp, target.definition.max_hp]}
		]
	return detail


static func _detail(tab: String, key: int, title: String, description: String) -> Dictionary:
	return {
		"tab": tab,
		"key": key,
		"title": title,
		"description": description,
		"forecast": {},
		"effects": [],
		"footer_label": "",
		"footer_value": "",
		"disabled": false,
	}
