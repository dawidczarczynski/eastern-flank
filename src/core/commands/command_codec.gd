class_name CommandCodec
extends RefCounted
## Rebuilds commands from their `to_dict()` form (also after a JSON round trip).
## Formats:
##   MoveUnitCommand → {"type": "move", "unit_id": 3, "target": [q, r]}
##   AttackCommand   → {"type": "attack", "attacker_id": 1, "target_id": 5}
##   EndTurnCommand  → {"type": "end_turn"}
## Validation is strict: unknown "type", missing fields or non-numeric values give null.
## Numbers may be ints or integral floats (JSON parses every number as a float); anything else
## (bools, strings, 1.5, INF, NAN, values beyond +-2^53) is rejected. Extra keys are ignored.

## Largest magnitude a double holds exactly as an integer.
const _MAX_EXACT_INT := 9007199254740992.0


static func from_dict(d: Dictionary) -> Command:
	var type: Variant = d.get("type")
	if not (type is String or type is StringName):
		return null
	match String(type):
		"move":
			return _move(d)
		"attack":
			return _attack(d)
		"end_turn":
			return EndTurnCommand.new()
	return null


static func _move(d: Dictionary) -> Command:
	var unit_id: Variant = to_int_or_null(d.get("unit_id"))
	var target: Variant = d.get("target")
	if unit_id == null or not target is Array or target.size() != 2:
		return null
	var q: Variant = to_int_or_null(target[0])
	var r: Variant = to_int_or_null(target[1])
	if q == null or r == null:
		return null
	return MoveUnitCommand.new(unit_id, Vector2i(q, r))


static func _attack(d: Dictionary) -> Command:
	var attacker_id: Variant = to_int_or_null(d.get("attacker_id"))
	var target_id: Variant = to_int_or_null(d.get("target_id"))
	if attacker_id == null or target_id == null:
		return null
	return AttackCommand.new(attacker_id, target_id)


## `value` as an int when it is an int or an integral, exactly representable float; else null.
static func to_int_or_null(value: Variant) -> Variant:
	if value is int:
		return value
	if not value is float:
		return null
	var f: float = value
	if is_nan(f) or is_inf(f) or f != floorf(f) or absf(f) > _MAX_EXACT_INT:
		return null
	return int(f)
