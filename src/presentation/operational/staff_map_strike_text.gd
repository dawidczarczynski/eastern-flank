class_name StaffMapStrikeText
extends RefCounted
## Pure toast text of a deep strike on the staff map (TASK-097a): "NATO cruise x2 > Kaliningrad
## airfield: 1 hit, 1 intercepted (-35 %)". Reads the state for names only.


## The toast of a `strike_resolved` event.
static func resolved(state: OperationalState, event: Dictionary) -> String:
	var player: int = event["player"]
	var side := StaffMapTurnBar.side_name(state, player)
	var target_id: StringName = event["target"]
	var installation := state.get_installation(target_id)
	var target := String(target_id)
	if installation != null:
		target = TranslationServer.translate(installation.display_name)
	var parts: Array[String] = [_n(event["hits"], "hit"), "%d intercepted" % event["intercepted"]]
	if int(event["misses"]) > 0:
		parts.append(_n(event["misses"], "miss", "misses"))
	var text := (
		"%s %s x%d > %s: %s" % [side, event["means"], event["count"], target, ", ".join(parts)]
	)
	if int(event["damage_dealt"]) > 0:
		text += " (-%d)" % event["damage_dealt"]
	if event["target_destroyed"]:
		text += " DESTROYED"
	return text


static func _n(count: int, one: String, many := "") -> String:
	return "%d %s" % [count, one if count == 1 else (many if many != "" else one + "s")]
