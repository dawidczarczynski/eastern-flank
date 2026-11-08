class_name StaffMapTurnMarks
extends RefCounted
## View-model of what happened when a side ended its move (TASK-092e), built from the operational
## events alone: which formations "moved" (dimmed counter until the owner's next move starts),
## which are "in contact" (dashed ring on a formation that halted on contact and on the enemies
## next to it, until nobody is adjacent any more) and the turn report (one entry per ordered
## formation of the side that ended).
## Pure – no nodes; StaffMap feeds it every event and reads it back.

const ARRIVED := &"arrived"
const HALTED := &"halted"
const INTERRUPTED := &"interrupted"
const EN_ROUTE := &"en_route"

var _moved := {}  # formation id -> true
var _contact := {}  # formation id -> true
var _reports := {}  # owner -> Array[Dictionary] (see report_of)
var _unseen := {}  # owner -> true while the report was not shown yet
var _fresh := {}  # owner -> true when the next order event starts a new report


## Feeds one operational event; `state` is the state after the whole command (owners, coords).
func on_event(state: OperationalState, event: Dictionary) -> void:
	var id: StringName = event.get("formation_id", &"")
	match event.get("type"):
		&"formation_moved":
			_moved[id] = true
			_report(state, id, EN_ROUTE, event["to"], &"")
		&"formation_order_completed":
			_report(state, id, ARRIVED, event["destination"], &"")
		&"formation_halted":
			_contact[id] = true
			var at: Vector2i = event["at"]
			var owner := _owner(state, id)
			for c in Hex.neighbors(at):
				var other := state.formation_at(c)
				if other != null and other.owner_id != owner:
					_contact[other.id] = true
			_report(state, id, HALTED, at, event.get("reason", &"contact"))
		&"formation_order_interrupted":
			_report(state, id, INTERRUPTED, event["at"], event["reason"])
		&"operational_turn_started":
			_on_turn_started(state, event["player"])


func is_moved(formation_id: StringName) -> bool:
	return _moved.has(formation_id)


func in_contact(formation_id: StringName) -> bool:
	return _contact.has(formation_id)


## Report entries of `owner`'s last move: {id, kind, at (Vector2i), reason}.
func report_of(owner: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	entries.assign(_reports.get(owner, []))
	return entries


## True once for a report of `owner` that was not shown yet (the panel opens by itself).
func take_unseen(owner: int) -> bool:
	if not _unseen.has(owner) or report_of(owner).is_empty():
		return false
	_unseen.erase(owner)
	return true


func _on_turn_started(state: OperationalState, player: int) -> void:
	# The side to move now leaves its "moved" marks behind.
	for f in state.formations:
		if f.owner_id == player:
			_moved.erase(f.id)
	# A ring lasts as long as the contact: drop any that no longer touches an enemy.
	for id: StringName in _contact.keys():
		var f := state.get_formation(id)
		if f == null or not _touches_enemy(state, f):
			_contact.erase(id)
	for owner in _reports:
		_fresh[owner] = true


func _touches_enemy(state: OperationalState, f: Formation) -> bool:
	for c in Hex.neighbors(f.coord):
		var other := state.formation_at(c)
		if other != null and other.owner_id != f.owner_id:
			return true
	return false


func _report(
	state: OperationalState, id: StringName, kind: StringName, at: Vector2i, reason: StringName
) -> void:
	var owner := _owner(state, id)
	if owner < 0:
		return
	if not _reports.has(owner) or _fresh.get(owner, true):
		_reports[owner] = [] as Array[Dictionary]
		_fresh[owner] = false
		_unseen[owner] = true
	var entries: Array = _reports[owner]
	var entry := {"id": id, "kind": kind, "at": at, "reason": reason}
	for i in entries.size():
		if entries[i]["id"] == id:
			entries[i] = entry
			return
	entries.append(entry)


static func _owner(state: OperationalState, id: StringName) -> int:
	var f := state.get_formation(id)
	return f.owner_id if f != null else -1
