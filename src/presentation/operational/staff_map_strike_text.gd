class_name StaffMapStrikeText
extends RefCounted
## Pure texts of a deep strike on the staff map (TASK-097a, TASK-097b): the one-line "Cruise
## missile ×2 on Chernyakhovsk airfield: 1 intercepted, 1 hit – integrity 100 → 65" and the data
## of the result report card (`report_model`, variant A of docs/design/operational_map/
## strike-result-report.html). Reads the state (after the strike) for names and the target's
## remaining integrity / strength only.


## The toast of a `strike_resolved` event.
static func resolved(state: OperationalState, event: Dictionary) -> String:
	var means: StrikeMeansDefinition = state.strike_means.get(event["means"])
	var means_name := String(event["means"])
	if means != null:
		means_name = TranslationServer.translate(means.display_name)
	var target_id: StringName = event["target"]
	var parts: Array[String] = []
	if int(event["intercepted"]) > 0:
		parts.append("%d intercepted" % event["intercepted"])
	parts.append(_n(event["hits"], "hit"))
	if int(event["misses"]) > 0:
		parts.append(_n(event["misses"], "miss", "misses"))
	var text := (
		"%s ×%d on %s: %s"
		% [
			means_name,
			event["count"],
			StaffMapStrike.target_name(state, target_id),
			", ".join(parts)
		]
	)
	var dealt: int = event["damage_dealt"]
	if event["target_destroyed"]:
		text += " – DESTROYED"
	elif dealt > 0:
		var installation := state.get_installation(target_id)
		if installation != null:
			text += (
				" – integrity %d → %d" % [installation.integrity + dealt, installation.integrity]
			)
		else:
			var formation := state.get_formation(target_id)
			if formation != null:
				text += " – strength %d → %d" % [formation.strength() + dealt, formation.strength()]
	return text


## The data of the report card of a `strike_resolved` event, read from the state after the strike.
## `event` may carry extras collected by StaffMapStrikeHud: "viewer" (the screen's side, default
## the striker), "coord", "target_name" / "target_max" (a destroyed formation is gone from the
## state), "stock_before" / "stock_after" and "escalation" (the events the same command caused).
## `trail.is_visible` decides which interceptor sites are listed. Texts are translated, not
## upper-cased.
static func report_model(
	state: OperationalState, event: Dictionary, trail: StaffMapStrikeTrail
) -> Dictionary:
	var striker: int = event["player"]
	var viewer: int = event.get("viewer", striker)
	var own := striker == viewer
	var means: StrikeMeansDefinition = state.strike_means.get(event["means"])
	var name := String(event["means"])
	var designation := ""
	if means != null:
		name = _t(means.display_name)
		var raw: Variant = means.get(&"designation")  # TASK-141a adds it
		if raw is String:
			designation = raw
	var target := _report_target(state, event)
	var escalation := _report_escalation(state, event)
	var count: int = event["count"]
	var side_text := _t("Your strike") if own else _t("Enemy strike")
	var threshold: bool = escalation["ends"]
	var model := {
		"own": own,
		"striker": striker,
		"side_text": side_text,
		"side_name": StaffMapTurnBar.side_name(state, striker),
		"tab": ("▲ %s · %s" % [_t("Threshold"), side_text]) if threshold else side_text,
		"right": "%s %d · %s" % [_t("TURN"), state.turn, StaffMapTurnBar.side_name(state, striker)],
		"threshold": threshold,
		"name": name,
		"designation": designation,
		"detail": "×%d" % count,
		"target_name": StaffMapStrike.target_name(state, event["target"]),
		"target_place": _report_place(state, event),
		"count": count,
		"hits": int(event["hits"]),
		"intercepted": int(event["intercepted"]),
		"misses": int(event["misses"]),
		"outcomes": _report_outcomes(event),
		"target": target,
		"interceptors": _report_sites(state, event, trail),
		"escalation": escalation,
		"stock": {"known": false},
		"strikes_left": state.strikes_left,
		"strikes_max": state.strikes_per_turn,
		"fallback": resolved(state, event),
	}
	if target["name"] != "":
		model["target_name"] = target["name"]
	if own:
		var after: int = event.get("stock_after", StrikeRules.stock(state, striker, event["means"]))
		model["stock"] = {
			"known": true, "before": event.get("stock_before", after + count), "after": after
		}
	var hit_text := (
		_n(int(event["hits"]), _t("hit"), _t("hits")) if int(event["hits"]) > 0 else _t("no hit")
	)
	var chip := "%s ×%d · %s" % [name, count, hit_text]
	if target["destroyed"]:
		chip += " · " + _t("destroyed")
	elif target["delta"] != 0:
		chip += " · −%d" % -int(target["delta"])
	model["chip"] = chip
	model["chip_name"] = "%s ×%d" % [name, count]
	var short := (
		"%d %s" % [int(event["hits"]), _t("hit")] if int(event["hits"]) > 0 else _t("no hit")
	)
	model["chip_result"] = _t("destroyed") if target["destroyed"] else short
	return model


## Hits first, then intercepted, then missed (the pictogram order).
static func _report_outcomes(event: Dictionary) -> Array[StringName]:
	var list: Array[StringName] = []
	for i in int(event["hits"]):
		list.append(StaffMapStrikeTrail.HIT)
	for i in int(event["intercepted"]):
		list.append(StaffMapStrikeTrail.INTERCEPTED)
	for i in int(event["misses"]):
		list.append(StaffMapStrikeTrail.MISSED)
	return list


static func _report_target(state: OperationalState, event: Dictionary) -> Dictionary:
	var dealt := int(event.get("damage_dealt", 0))
	var id: StringName = event["target"]
	var model := {
		"kind": &"integrity",
		"label": _t("Integrity"),
		"name": "",
		"before": 0,
		"after": 0,
		"delta": -dealt,
		"max": Installation.MAX_INTEGRITY,
		"destroyed": bool(event.get("target_destroyed", false)),
		"no_damage": dealt <= 0,
	}
	var installation := state.get_installation(id)
	if installation != null:
		model["after"] = installation.integrity
		model["before"] = installation.integrity + dealt
		return model
	var formation := state.get_formation(id)
	model["kind"] = &"strength"
	model["label"] = _t("STRENGTH").capitalize()
	model["name"] = str(event.get("target_name", ""))
	model["after"] = formation.strength() if formation != null else 0
	model["before"] = int(model["after"]) + dealt
	model["max"] = (
		formation.max_strength()
		if formation != null
		else int(event.get("target_max", maxi(dealt, 1)))
	)
	if formation != null:
		model["name"] = _t(formation.display_name)
	return model


## The country the target stands in ("Russia"), "" when unknown.
static func _report_place(state: OperationalState, event: Dictionary) -> String:
	var coord := _report_coord(state, event)
	var country := state.get_country(state.country_at(coord)) if coord.x > -9999 else null
	return _t(country.definition.display_name) if country != null else ""


static func _report_coord(state: OperationalState, event: Dictionary) -> Vector2i:
	if event.has("coord"):
		return event["coord"]
	var installation := state.get_installation(event["target"])
	if installation != null:
		return installation.coord
	var formation := state.get_formation(event["target"])
	return formation.coord if formation != null else Vector2i(-9999, -9999)


## The air-defence sites that contributed to the interception, each with the missiles it stopped
## (the same round-robin as the trail's marks); only the sites `trail.is_visible` lets through.
static func _report_sites(
	state: OperationalState, event: Dictionary, trail: StaffMapStrikeTrail
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var intercepted := int(event["intercepted"])
	var coord := _report_coord(state, event)
	if intercepted <= 0 or coord.x <= -9999:
		return result
	var sites := StaffMapStrikeTrail.interceptors_before(state, event, coord)
	for i in intercepted:
		if sites.is_empty():
			break
		var site: Dictionary = sites[i % sites.size()]
		site["count"] = int(site.get("count", 0)) + 1
	for site in sites:
		if int(site.get("count", 0)) > 0 and trail.is_visible.call(site["coord"], event["player"]):
			(
				result
				. append(
					{
						"name": StaffMapStrike.target_name(state, site["id"]),
						"count": site["count"],
						"coord": site["coord"],
					}
				)
			)
	return result


## The escalation the strike caused, from the events of its command.
static func _report_escalation(state: OperationalState, event: Dictionary) -> Dictionary:
	var top := state.ladder.top()
	var previous := -1
	var level := state.escalation_level
	var lines: Array[Dictionary] = []
	var ends := false
	for change: Dictionary in event.get("escalation", []):
		match change.get("type"):
			&"escalation_changed":
				if previous < 0:
					previous = int(change["previous"])
				level = int(change["level"])
				var steps := int(change["level"]) - int(change["previous"])
				match change.get("cause"):
					&"sanctuary_breach":
						lines.append({"text": _t("+%d sanctuary breach") % steps, "danger": false})
					&"urban_strike":
						lines.append({"text": _t("+%d urban hex") % steps, "danger": false})
			&"operation_ended":
				ends = true
	var changed := previous >= 0
	ends = ends or (changed and level >= top)
	if ends:
		lines.append(
			{"text": _t("Strategic threshold reached – the operation ends"), "danger": true}
		)
	return {
		"changed": changed,
		"previous": previous if changed else level,
		"level": level,
		"delta": level - previous if changed else 0,
		"top": top,
		"level_name": StaffMapEscalation.level_name(state, level),
		"lines": lines,
		"ends": ends,
	}


static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))


static func _n(count: int, one: String, many := "") -> String:
	return "%d %s" % [count, one if count == 1 else (many if many != "" else one + "s")]
