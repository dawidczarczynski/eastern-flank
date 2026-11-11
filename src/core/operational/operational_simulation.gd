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
	for event in command.apply(state):
		state.political_log.on_event(state, event)
		event_emitted.emit(event)
	return true
