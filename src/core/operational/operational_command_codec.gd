class_name OperationalCommandCodec
extends RefCounted
## Rebuilds operational commands from their `to_dict()` form (also after a JSON round trip).
## Same rules as the tactical codec: unknown "type", missing fields or non-numeric values give
## null; numbers may be ints or integral floats (JSON parses every number as a float), anything
## else (bools, strings, 1.5, INF, NAN, values beyond +-2^53) is rejected. Extra keys are ignored.

## Largest magnitude a double holds exactly as an integer.
const _MAX_EXACT_INT := 9007199254740992.0


static func from_dict(d: Dictionary) -> OperationalCommand:
	var type: Variant = d.get("type")
	if not (type is String or type is StringName):
		return null
	match String(type):
		EndOperationalTurnCommand.TYPE:
			return EndOperationalTurnCommand.new()
		_:
			return null


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
