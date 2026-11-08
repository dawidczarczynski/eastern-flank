class_name StaffMapOrderRingModel
extends RefCounted
## Pure model of the order ring of the staff map: a right click on a hex with an own formation
## selected opens the HUD v3 radial ring (RadialRing, same component as the battle unit ring) on
## that hex with 1 MARCH, 2 ATTACK, 3 DEFEND and 4 CANCEL ORDER (only while the formation has an
## order); the other slots stay empty. Whether an order is possible and why not come from the
## validate() of IssueOrderCommand / CancelOrderCommand, the numbers on the card from
## StaffMapRoute.preview_in_posture – no rules here. Texts are translated here (presentation).
##
## build() returns {formation_id, hex, slots, details, summary}: `slots` in the RadialRing format
## (key, action, label, icon, enabled, empty, reason); `details[slot]` and `summary` are
## RingDetailCard dictionaries. The `action` of a slot is a posture id or &"cancel".

const SLOT_CANCEL := 3
const CANCEL := &"cancel"


## The ring on `hex` for `formation` in `state`.
static func build(state: OperationalState, formation: Formation, hex: Vector2i) -> Dictionary:
	var slots: Array[Dictionary] = []
	var details: Array[Dictionary] = []
	for i in OperationalPosture.NAMES.size():
		var posture := OperationalPosture.NAMES[i]
		var reason := reason_text(IssueOrderCommand.new(formation.id, hex, posture).validate(state))
		slots.append(_slot(i, posture, [_name_key(posture)], _icon(posture), reason))
		details.append(_posture_detail(state, formation, hex, posture, i, reason))
	if formation.order != null:
		var reason := reason_text(CancelOrderCommand.new(formation.id).validate(state))
		slots.append(
			_slot(SLOT_CANCEL, CANCEL, ["ORDER_RING_CANCEL", "ORDER_RING_ORDER"], CANCEL, reason)
		)
		details.append(_cancel_detail(reason))
	for i in range(slots.size(), RadialRingGeometry.SLOT_COUNT):
		slots.append(_empty_slot(i))
		details.append({})
	return {
		"formation_id": formation.id,
		"hex": hex,
		"slots": slots,
		"details": details,
		"summary": _summary(formation, hex),
	}


## "[2] ATTACK": the caption of posture `id` (translated), as the formation panel shows it.
static func caption(id: StringName) -> String:
	var number := OperationalPosture.NAMES.find(id) + 1
	return "[%d] %s" % [number, TranslationServer.translate(_name_key(id))]


## Player text of a command rejection reason ("" stays "").
static func reason_text(reason: String) -> String:
	if reason == "":
		return ""
	return TranslationServer.translate("ORDER_REJECTED_" + reason.to_upper())


## The posture of the default left click on `hex`: attack on an enemy-held hex, else march.
static func default_posture(
	state: OperationalState, formation: Formation, hex: Vector2i
) -> StringName:
	var holder := state.formation_at(hex)
	if holder != null and holder.owner_id != formation.owner_id:
		return &"advance"
	return &"march"


static func _t(key: String) -> String:
	return TranslationServer.translate(key)


static func _name_key(posture: StringName) -> String:
	return "POSTURE_" + String(posture).to_upper()


static func _icon(posture: StringName) -> StringName:
	return &"attack" if posture == &"advance" else posture


static func _slot(
	index: int, action: StringName, label: Array, icon: StringName, reason: String
) -> Dictionary:
	return {
		"key": index + 1,
		"action": action,
		"label": label,
		"icon": icon,
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


static func _posture_detail(
	state: OperationalState,
	formation: Formation,
	hex: Vector2i,
	posture: StringName,
	index: int,
	reason: String
) -> Dictionary:
	var data := OperationalPosture.find(posture)
	var budget := data.budget(formation.definition.move_points)
	var detail := _detail(
		index + 1, _t(_name_key(posture)), _t("POSTURE_HINT_" + String(posture).to_upper())
	)
	var effects: Array = [{"label": "PER TURN", "value": _t("%d PTS") % budget}]
	if reason != "":
		detail["disabled"] = true
		detail["footer_label"] = "UNAVAILABLE"
		detail["footer_value"] = reason
		detail["effects"] = effects
		return detail
	var preview := StaffMapRoute.preview_in_posture(state, formation, hex, posture)
	if not preview.is_empty() and not (preview["route"] as Array).is_empty():
		effects.push_front({"label": "ROUTE", "value": _t("%d PTS") % preview["cost"]})
		effects.append({"label": "TURNS", "value": str(preview["turns"])})
		detail["footer_label"] = "ENDS"
		detail["footer_value"] = _t(_stop_key(preview["stop"]))
	detail["effects"] = effects
	return detail


static func _stop_key(stop: StringName) -> String:
	if stop == OperationalRoutes.STOP_CONTACT:
		return "ROUTE_CONTACT"
	if stop == OperationalRoutes.STOP_OUT_OF_POINTS:
		return "ROUTE_STALLED"
	return "ROUTE_ARRIVED"


static func _cancel_detail(reason: String) -> Dictionary:
	var detail := _detail(
		SLOT_CANCEL + 1,
		TranslationServer.translate("ORDER_RING_CANCEL_TITLE"),
		TranslationServer.translate("ORDER_RING_CANCEL_HINT")
	)
	if reason != "":
		detail["disabled"] = true
		detail["footer_label"] = "UNAVAILABLE"
		detail["footer_value"] = reason
	return detail


## The card with nothing hovered: the formation's name and posture.
static func _summary(formation: Formation, hex: Vector2i) -> Dictionary:
	var detail := _detail(
		0, formation.definition.display_name, TranslationServer.translate("ORDER_RING_CHOOSE")
	)
	var offset := MapGenerator.axial_to_offset(hex)
	detail["effects"] = [
		{"label": "HEX", "value": "%02d·%02d" % [offset.x + 1, offset.y + 1]},
		{"label": "POSTURE", "value": caption(formation.posture).to_upper()},
	]
	return detail


static func _detail(key: int, title: String, description: String) -> Dictionary:
	return {
		"tab": "ORDER",
		"key": key,
		"title": title,
		"description": description,
		"forecast": {},
		"effects": [],
		"footer_label": "",
		"footer_value": "",
		"disabled": false,
	}
