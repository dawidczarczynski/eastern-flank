class_name GameSimulation
extends RefCounted
## Game logic facade: accepts commands, validates them, applies them and emits events.
## Command history + RNG seed are enough to reproduce a whole match (replay, saves, network).

signal event_emitted(event: Dictionary)
signal command_rejected(command: Command, reason: String)

var state: GameState
var history: Array[Command] = []


func _init(p_state: GameState) -> void:
	state = p_state


func execute(command: Command) -> bool:
	var reason := command.validate(state)
	if reason != "":
		command_rejected.emit(command, reason)
		return false
	history.append(command)
	for event in command.apply(state):
		event_emitted.emit(event)
	return true
