class_name PoliticalLog
extends RefCounted
## Short deterministic history of political changes (TASK-119a): stance, level, decisions,
## sanctuary breaches and contributions arriving. Effects only – an entry never stores who
## decided it. Filled by `OperationalSimulation.execute` through `on_event`; the view only reads.

const CAP := 60
const KINDS: Array[StringName] = [
	&"stance_changed", &"level_changed", &"decision", &"sanctuary_breach", &"contribution"
]

var entries: Array[Entry] = []


class Entry:
	extends RefCounted
	var turn: int = 0
	var kind: StringName = &""
	var country: StringName = &""
	## Side of the effect (new stance side, formation owner); -1 for none.
	var side: int = -1
	var level_before: int = -1
	var level_after: int = -1
	var stance_before: StringName = &""
	var stance_after: StringName = &""
	var cause: StringName = &""
	## Text key for the view, e.g. `&"political_log.stance_changed"`.
	var key: StringName = &""
	var args: Dictionary = {}

	func to_dict() -> Dictionary:
		return {
			"turn": turn,
			"kind": String(kind),
			"country": String(country),
			"side": side,
			"level_before": level_before,
			"level_after": level_after,
			"stance_before": String(stance_before),
			"stance_after": String(stance_after),
			"cause": String(cause),
			"key": String(key),
			"args": args.duplicate(true),
		}

	## null for a malformed dictionary (missing key, wrong type, unknown kind).
	static func from_dict(d: Variant) -> Entry:
		if not d is Dictionary:
			return null
		var dict: Dictionary = d
		for name in ["turn", "side", "level_before", "level_after"]:
			if not _is_int(dict.get(name)):
				return null
		for name in ["kind", "country", "stance_before", "stance_after", "cause", "key"]:
			if not dict.get(name) is String:
				return null
		if not dict.get("args") is Dictionary:
			return null
		if not StringName(dict["kind"]) in PoliticalLog.KINDS:
			return null
		var e := Entry.new()
		e.turn = int(dict["turn"])
		e.kind = StringName(dict["kind"])
		e.country = StringName(dict["country"])
		e.side = int(dict["side"])
		e.level_before = int(dict["level_before"])
		e.level_after = int(dict["level_after"])
		e.stance_before = StringName(dict["stance_before"])
		e.stance_after = StringName(dict["stance_after"])
		e.cause = StringName(dict["cause"])
		e.key = StringName(dict["key"])
		e.args = (dict["args"] as Dictionary).duplicate(true)
		return e

	## JSON parsing turns ints into floats; accept whole numbers of either type.
	static func _is_int(v: Variant) -> bool:
		return v is int or (v is float and is_equal_approx(v, roundf(v)))


## Appends the entry `event` stands for (nothing for other event types).
func on_event(state: OperationalState, event: Dictionary) -> void:
	var e := Entry.new()
	e.turn = state.turn
	match event.get("type"):
		&"country_stance_changed":
			e.kind = &"stance_changed"
			e.country = event["country"]
			e.side = int(event["side"])
			e.stance_before = event["previous_stance"]
			e.stance_after = event["stance"]
			e.cause = event["cause"]
		&"escalation_changed":
			e.kind = &"level_changed"
			e.level_before = int(event["previous"])
			e.level_after = int(event["level"])
			e.cause = event["cause"]
		&"political_decision_taken":
			e.kind = &"decision"
			e.cause = StringName(event["decision"])
			e.country = StringName(event["country"])
		&"sanctuary_breached":
			e.kind = &"sanctuary_breach"
			e.country = event["country"]
		&"formation_joined":
			if event.get("source") != &"contribution":
				return
			e.kind = &"contribution"
			e.country = event["country"]
			e.side = int(event["player"])
			e.args = {"formation_id": String(event["formation_id"])}
		_:
			return
	e.key = StringName("political_log." + String(e.kind))
	entries.append(e)
	while entries.size() > CAP:
		entries.pop_front()


func size() -> int:
	return entries.size()


func to_dict() -> Dictionary:
	var list: Array = []
	for e in entries:
		list.append(e.to_dict())
	return {"entries": list}


## Strict: null when any entry is malformed. A missing / empty dict gives an empty log; more than
## CAP entries keep the last CAP.
static func from_dict(d: Variant) -> PoliticalLog:
	var log := PoliticalLog.new()
	if d == null or (d is Dictionary and d.is_empty()):
		return log
	if not d is Dictionary or not d.get("entries") is Array:
		return null
	for value in d["entries"]:
		var e := Entry.from_dict(value)
		if e == null:
			return null
		log.entries.append(e)
	while log.entries.size() > CAP:
		log.entries.pop_front()
	return log
