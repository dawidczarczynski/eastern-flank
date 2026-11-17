class_name OperationalSimulation
extends RefCounted
## Operational logic facade (ADR 0015 §2): accepts operational commands, validates them, applies
## them and emits events. Campaign seed + command history reproduce the whole operation.

signal event_emitted(event: Dictionary)
signal command_rejected(command: OperationalCommand, reason: String)

var state: OperationalState
var history: Array[OperationalCommand] = []


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
	var gap_before := _gap(state)
	var events := command.apply(state)
	_report_gap(events, gap_before)
	for event in events:
		state.political_log.on_event(state, event)
		state.journal.on_event(state, event)
		event_emitted.emit(event)
	return true


## The Gap's status, `&""` without a chain.
func _gap(s: OperationalState) -> StringName:
	if s.definition == null or s.definition.gap_chain.is_empty():
		return &""
	return OperationVictory.gap_status(s, s.definition)


## Adds the `objective_changed` {kind gap} event when the command opened or closed the Gap; it
## goes before the end-of-round counter / ending events it led to.
func _report_gap(events: Array[Dictionary], before: StringName) -> void:
	var after := _gap(state)
	if before == after:
		return
	var at := events.size()
	for i in events.size():
		var kind: Variant = events[i].get("kind")
		if events[i]["type"] == &"operation_ended" or kind == &"gap_counter":
			at = i
			break
	events.insert(at, OperationVictory.gap_event(&"gap", before, after, state.turn))
