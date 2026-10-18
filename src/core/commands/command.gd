class_name Command
extends RefCounted
## Base command. The only way to change GameState – regardless of whether it is issued by
## the player, the AI, the network or a replay.


## Returns an empty string when the command is allowed; otherwise a rejection reason code.
func validate(_state: GameState) -> String:
	return ""


## Executes the command (called only after successful validation).
## Returns events (Dictionary with a "type" key) for the presentation layer.
func apply(_state: GameState) -> Array[Dictionary]:
	return []


## JSON-compatible description of the command (see CommandCodec for the formats).
## Subclasses override it; the base command has no format and returns an empty Dictionary,
## which CommandCodec.from_dict rejects.
func to_dict() -> Dictionary:
	return {}
