class_name OperationalCommand
extends RefCounted
## Base command of the operational layer (ADR 0015 §2) – the only way to change
## OperationalState, whoever issues it (player, AI, replay). Mirrors the tactical command base
## but is a separate class so both stay statically typed.


## Returns an empty string when the command is allowed; otherwise a rejection reason code.
func validate(_state: OperationalState) -> String:
	return ""


## Executes the command (called only after successful validation).
## Returns events (Dictionary with a "type" key) for the presentation layer.
func apply(_state: OperationalState) -> Array[Dictionary]:
	return []


## JSON-compatible description of the command (see OperationalCommandCodec). The base command
## has no format and returns an empty Dictionary, which the codec rejects.
func to_dict() -> Dictionary:
	return {}
