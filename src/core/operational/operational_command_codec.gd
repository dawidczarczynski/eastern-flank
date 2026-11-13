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
		IssueOrderCommand.TYPE:
			return _issue_order(d)
		CancelOrderCommand.TYPE:
			var id: Variant = d.get("formation_id")
			if not id is String:
				return null
			return CancelOrderCommand.new(StringName(id as String))
		SetPostureCommand.TYPE:
			var id: Variant = d.get("formation_id")
			var posture: Variant = d.get("posture")
			if not (id is String and posture is String):
				return null
			return SetPostureCommand.new(StringName(id as String), StringName(posture as String))
		StrikeCommand.TYPE:
			var means: Variant = d.get("means")
			var target: Variant = d.get("target")
			var count: Variant = to_int_or_null(d.get("count"))
			if not (means is String and target is String) or count == null:
				return null
			return StrikeCommand.new(
				StringName(means as String), StringName(target as String), count as int
			)
		ResolveBattleCommand.TYPE:
			var result_value: Variant = d.get("result")
			if not result_value is Dictionary:
				return null
			var result := BattleResult.from_dict(result_value as Dictionary)
			if result == null:
				return null
			return ResolveBattleCommand.new(result)
		EscalateCommand.TYPE:
			return EscalateCommand.new()
		StandDownCommand.TYPE:
			return StandDownCommand.new()
		NuclearStrikeCommand.TYPE:
			return NuclearStrikeCommand.new()
		DeclareHostilitiesCommand.TYPE:
			var country: Variant = d.get("country")
			if not country is String:
				return null
			return DeclareHostilitiesCommand.new(StringName(country as String))
		InvokeAllianceCommand.TYPE:
			var country: Variant = d.get("country")
			if not country is String:
				return null
			return InvokeAllianceCommand.new(StringName(country as String))
		DemandNeutralityCommand.TYPE:
			var country: Variant = d.get("country")
			if not country is String:
				return null
			return DemandNeutralityCommand.new(StringName(country as String))
		RequestSupportCommand.TYPE:
			var package: Variant = d.get("package")
			if not package is String:
				return null
			return RequestSupportCommand.new(StringName(package as String))
		_:
			return null


static func _issue_order(d: Dictionary) -> OperationalCommand:
	var id: Variant = d.get("formation_id")
	var posture: Variant = d.get("posture")
	var dest: Variant = d.get("destination")
	if not (id is String and posture is String and dest is Array):
		return null
	var pair: Array = dest
	if pair.size() != 2:
		return null
	var q: Variant = to_int_or_null(pair[0])
	var r: Variant = to_int_or_null(pair[1])
	if q == null or r == null:
		return null
	return IssueOrderCommand.new(
		StringName(id as String), Vector2i(q as int, r as int), StringName(posture as String)
	)


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
