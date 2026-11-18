class_name OperationalSimulation
extends RefCounted
## Operational logic facade (ADR 0015 §2): accepts operational commands, validates them, applies
## them and emits events. Campaign seed + command history reproduce the whole operation.

signal event_emitted(event: Dictionary)
signal command_rejected(command: OperationalCommand, reason: String)

var state: OperationalState
var history: Array[OperationalCommand] = []
## Last computed connection statuses and the holders they were computed for (see `_gap`).
var _gap_status: StringName = &""
var _gap_holders: Dictionary = {}
var _corridor_status: StringName = &""
var _corridor_holders: Dictionary = {}


func _init(p_state: OperationalState) -> void:
	state = p_state


func execute(command: OperationalCommand) -> bool:
	var reason := ""
	if not state.result.is_empty():
		reason = "operation_over"
	else:
		reason = command.validate(state)
	if reason != "":
		command_rejected.emit(command, reason)
		return false
	history.append(command)
	var holders_before := state.hex_holders.duplicate()
	var gap_before := _gap(state)
	var corridor_before := _corridor(state)
	var events := command.apply(state)
	if state.hex_holders != holders_before:
		_report_change(events, &"gap", gap_before, _gap(state))
		_report_change(events, &"corridor", corridor_before, _corridor(state))
	for event in events:
		state.political_log.on_event(state, event)
		state.journal.on_event(state, event)
		event_emitted.emit(event)
	return true


## NATO's link status, `&""` without the objective. Cached per holders: the route search runs
## only when a hex changed hands since the last check (TASK-177).
func _gap(s: OperationalState) -> StringName:
	if s.definition == null or not OperationVictory.has_gap_link(s.definition):
		return &""
	if _gap_holders != s.hex_holders or _gap_status == &"":
		_gap_status = OperationVictory.gap_status(s, s.definition)
		_gap_holders = s.hex_holders.duplicate()
	return _gap_status


## The corridor's status, `&""` without the objective; cached like `_gap`.
func _corridor(s: OperationalState) -> StringName:
	if s.definition == null or not OperationVictory.has_corridor(s.definition):
		return &""
	if _corridor_holders != s.hex_holders or _corridor_status == &"":
		_corridor_status = OperationVictory.corridor_status(s, s.definition)
		_corridor_holders = s.hex_holders.duplicate()
	return _corridor_status


## Adds the `objective_changed` {kind `gap` / `corridor`} event when the command flipped that
## objective; it goes before the end-of-round counter / ending events it led to.
func _report_change(
	events: Array[Dictionary], kind: StringName, before: StringName, after: StringName
) -> void:
	if before == after:
		return
	var at := events.size()
	for i in events.size():
		var event_kind: Variant = events[i].get("kind")
		if events[i]["type"] == &"operation_ended" or event_kind == &"corridor_counter":
			at = i
			break
	events.insert(at, OperationVictory.objective_event(kind, kind, before, after, state.turn))
