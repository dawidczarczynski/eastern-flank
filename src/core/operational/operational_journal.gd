class_name OperationalJournal
extends RefCounted
## Deterministic journal of the operation (TASK-148a): what each side did and what the enemy did
## to it, per turn. One history, a different view per side (`entries_for`). Political entries are
## bare effects, never who decided (as `PoliticalLog`). Filled by `OperationalSimulation.execute`
## through `on_event`; the view only reads. No RNG, no clock: the date comes from
## `OperationalClock` at display time.

const CATEGORIES: Array[StringName] = [&"strike", &"battle", &"move", &"politics"]
const KINDS: Array[StringName] = [
	&"formation_moved",
	&"formation_halted",
	&"order_completed",
	&"order_interrupted",
	&"order_issued",
	&"order_cancelled",
	&"posture_changed",
	&"contact_forbidden",
	&"formation_joined",
	&"battle_pending",
	&"battle_resolved",
	&"battle_consequences",
	&"formation_retreated",
	&"formation_destroyed",
	&"strike",
	&"stance_changed",
	&"level_changed",
	&"decision",
	&"sanctuary_breach",
	&"casus_belli",
	&"operation_ended",
]

var entries: Array[Entry] = []


class Entry:
	extends RefCounted
	## `state.turn` when appended.
	var turn: int = 0
	var category: StringName = &""
	var kind: StringName = &""
	## The side that acted; -1 for none / political.
	var actor: int = -1
	## The sides that see the entry; empty = both.
	var involved: Array[int] = []
	var coord: Vector2i = Vector2i.ZERO
	var has_coord: bool = false
	## Plain values only (ids as String, hexes as [q, r]).
	var args: Dictionary = {}

	func to_dict() -> Dictionary:
		return {
			"turn": turn,
			"category": String(category),
			"kind": String(kind),
			"actor": actor,
			"involved": involved.duplicate(),
			"coord": [coord.x, coord.y] if has_coord else [],
			"args": args.duplicate(true),
		}

	## null for a malformed dictionary (missing key, wrong type, unknown category / kind).
	static func from_dict(d: Variant) -> Entry:
		if not d is Dictionary:
			return null
		var dict: Dictionary = d
		for name in ["turn", "actor"]:
			if not _is_int(dict.get(name)):
				return null
		for name in ["category", "kind"]:
			if not dict.get(name) is String:
				return null
		if not dict.get("args") is Dictionary or not dict.get("involved") is Array:
			return null
		if not StringName(dict["category"]) in OperationalJournal.CATEGORIES:
			return null
		if not StringName(dict["kind"]) in OperationalJournal.KINDS:
			return null
		var e := Entry.new()
		for side in dict["involved"]:
			if not _is_int(side):
				return null
			e.involved.append(int(side))
		var c: Variant = dict.get("coord")
		if not c is Array or not (c.size() == 0 or c.size() == 2):
			return null
		if c.size() == 2:
			if not _is_int(c[0]) or not _is_int(c[1]):
				return null
			e.coord = Vector2i(int(c[0]), int(c[1]))
			e.has_coord = true
		e.turn = int(dict["turn"])
		e.category = StringName(dict["category"])
		e.kind = StringName(dict["kind"])
		e.actor = int(dict["actor"])
		e.args = _whole_numbers(dict["args"])
		return e

	## JSON parsing turns ints into floats; accept whole numbers of either type.
	static func _is_int(v: Variant) -> bool:
		return v is int or (v is float and is_equal_approx(v, roundf(v)))

	## A copy with every whole float turned back into an int.
	static func _whole_numbers(value: Variant) -> Variant:
		if value is float and is_equal_approx(value, roundf(value)):
			return int(value)
		if value is Array:
			var list: Array = []
			for item in value:
				list.append(_whole_numbers(item))
			return list
		if value is Dictionary:
			var out := {}
			for key in value:
				out[key] = _whole_numbers(value[key])
			return out
		return value


## Appends the entry `event` stands for (nothing for other event types). `state` is the state
## after the whole command: formations destroyed by it are gone, so sides come from the event.
func on_event(state: OperationalState, event: Dictionary) -> void:
	var e := Entry.new()
	e.turn = state.turn
	match event.get("type"):
		&"formation_moved":
			_move(e, &"formation_moved", _owner(state, event["formation_id"]))
			_at(e, event["to"])
			_args(e, event, ["formation_id", "from", "to", "cost"])
		&"formation_halted":
			var owner := _owner(state, event["formation_id"])
			_move(e, &"formation_halted", owner)
			if owner >= 0 and _touches_enemy(state, event["at"], owner):
				e.involved = [0, 1]
			_at(e, event["at"])
			_args(e, event, ["formation_id", "reason"])
		&"formation_order_completed":
			_move(e, &"order_completed", _owner(state, event["formation_id"]))
			_at(e, event["destination"])
			_args(e, event, ["formation_id", "destination"])
		&"formation_order_interrupted":
			_move(e, &"order_interrupted", _owner(state, event["formation_id"]))
			_at(e, event["at"])
			_args(e, event, ["formation_id", "reason"])
		&"formation_order_issued":
			_move(e, &"order_issued", _owner(state, event["formation_id"]))
			_at(e, event["destination"])
			_args(e, event, ["formation_id", "destination", "posture"])
		&"formation_order_cancelled":
			_move(e, &"order_cancelled", _owner(state, event["formation_id"]))
			_args(e, event, ["formation_id"])
		&"formation_posture_changed":
			_move(e, &"posture_changed", _owner(state, event["formation_id"]))
			_args(e, event, ["formation_id", "posture", "previous"])
		&"contact_forbidden":
			_move(e, &"contact_forbidden", _owner(state, event["attacker_id"]))
			_at(e, event["at"])
			_args(e, event, ["attacker_id", "defender_id", "country"])
		&"formation_joined":
			_move(e, &"formation_joined", int(event["player"]))
			_at(e, event["coord"])
			_args(e, event, ["formation_id", "country", "source"])
		&"battle_pending":
			_both(e, &"battle", &"battle_pending", _owner(state, event["attacker_id"]))
			_at(e, event["at"])
			_args(e, event, ["attacker_id", "defender_id", "index"])
		&"battle_resolved":
			_both(e, &"battle", &"battle_resolved", -1)
			_args(e, event, ["attacker_id", "defender_id", "winner", "reason"])
		&"battle_consequences":
			_both(e, &"battle", &"battle_consequences", -1)
			_args(
				e,
				event,
				[
					"attacker_id",
					"defender_id",
					"losses",
					"strength",
					"readiness",
					"field_holder",
					"retreat"
				]
			)
		&"formation_retreated":
			_both(e, &"battle", &"formation_retreated", -1)
			_at(e, event["to"])
			_args(e, event, ["formation_id", "from", "to", "blocked"])
		&"formation_destroyed":
			if event.get("cause") == &"strike":
				_fold(event, ["formation_id", "before", "after"], "target_destroyed", true)
				return
			_both(e, &"battle", &"formation_destroyed", -1)
			_at(e, event["at"])
			_args(e, event, ["formation_id", "player", "before", "after"])
		&"strike_launched":
			var player := int(event["player"])
			e.category = &"strike"
			e.kind = &"strike"
			e.actor = player
			e.involved = [mini(player, 1 - player), maxi(player, 1 - player)]
			_at(e, event["coord"])
			_args(e, event, ["means", "count", "target", "class_id"])
		&"strike_resolved":
			_fold(event, ["intercepted", "hits", "misses", "target_destroyed"], "", null)
			_fold(event, ["damage_dealt"], "damage", null)
			return
		&"installation_changed":
			if event.get("cause") == &"strike":
				_fold(event, ["before", "after", "destroyed"], "", null)
			return
		&"formation_damaged":
			if event.get("cause") == &"strike":
				_fold(event, ["before", "after"], "", null)
			return
		&"country_stance_changed":
			_politics(e, &"stance_changed")
			_args(e, event, ["country", "stance", "previous_stance", "side", "cause"])
		&"escalation_changed":
			_politics(e, &"level_changed")
			_args(e, event, ["level", "previous", "cause"])
		&"political_decision_taken":
			_politics(e, &"decision")
			_args(e, event, ["decision", "country"])
		&"sanctuary_breached":
			_politics(e, &"sanctuary_breach")
			_at(e, event.get("at"))
			_args(e, event, ["country"])
		&"casus_belli_gained":
			_politics(e, &"casus_belli")
			_at(e, event.get("at"))
			_args(e, event, ["country"])
		&"operation_ended":
			_politics(e, &"operation_ended")
			_args(e, event, ["winner", "reason"])
		_:
			return
	entries.append(e)


## The entries `player` sees, in order: those whose `involved` is empty or holds the player.
func entries_for(player: int) -> Array[Entry]:
	var out: Array[Entry] = []
	for e in entries:
		if e.involved.is_empty() or player in e.involved:
			out.append(e)
	return out


func size() -> int:
	return entries.size()


func to_dict() -> Dictionary:
	var list: Array = []
	for e in entries:
		list.append(e.to_dict())
	return {"entries": list}


## Strict: null when any entry is malformed. A missing / empty dict gives an empty journal.
static func from_dict(d: Variant) -> OperationalJournal:
	var journal := OperationalJournal.new()
	if d == null or (d is Dictionary and d.is_empty()):
		return journal
	if not d is Dictionary or not d.get("entries") is Array:
		return null
	for value in d["entries"]:
		var e := Entry.from_dict(value)
		if e == null:
			return null
		journal.entries.append(e)
	return journal


## Folds `keys` of a strike's effect event into the strike entry just written (the last entry).
## `flag` (when non-empty) is set to `flag_value` as well.
func _fold(event: Dictionary, keys: Array, flag: String, flag_value: Variant) -> void:
	if entries.is_empty() or entries[entries.size() - 1].kind != &"strike":
		return
	var e := entries[entries.size() - 1]
	for key: String in keys:
		if event.has(key):
			var name := key
			if key == "damage_dealt":
				name = "damage"
			if key == "destroyed":
				name = "target_destroyed"
			e.args[name] = _plain(event[key])
	if flag != "":
		e.args[flag] = flag_value


static func _owner(state: OperationalState, formation_id: StringName) -> int:
	var f := state.get_formation(formation_id)
	return f.owner_id if f != null else -1


## True when a formation of the other side stands next to `at`.
static func _touches_enemy(state: OperationalState, at: Vector2i, owner: int) -> bool:
	for neighbor in Hex.neighbors(at):
		var other := state.formation_at(neighbor)
		if other != null and other.owner_id != owner:
			return true
	return false


## A movement-family entry seen by its owner only (both when the owner is unknown).
static func _move(e: Entry, kind: StringName, owner: int) -> void:
	e.category = &"move"
	e.kind = kind
	e.actor = owner
	if owner >= 0:
		e.involved = [owner]


static func _both(e: Entry, category: StringName, kind: StringName, actor: int) -> void:
	e.category = category
	e.kind = kind
	e.actor = actor


static func _politics(e: Entry, kind: StringName) -> void:
	e.category = &"politics"
	e.kind = kind


static func _at(e: Entry, coord: Variant) -> void:
	if coord is Vector2i:
		e.coord = coord
		e.has_coord = true


static func _args(e: Entry, event: Dictionary, keys: Array) -> void:
	for key: String in keys:
		if event.has(key):
			e.args[key] = _plain(event[key])


## JSON-safe copy: ids become Strings, hexes [q, r] pairs.
static func _plain(value: Variant) -> Variant:
	if value is StringName:
		return String(value)
	if value is Vector2i:
		return [value.x, value.y]
	if value is Array:
		var list: Array = []
		for item in value:
			list.append(_plain(item))
		return list
	if value is Dictionary:
		var out := {}
		for key in value:
			out[String(key) if key is StringName else key] = _plain(value[key])
		return out
	return value
