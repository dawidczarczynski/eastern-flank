extends TestCase


func _through_text(command: Command) -> Command:
	var parsed: Variant = JSON.parse_string(JSON.stringify(command.to_dict()))
	return CommandCodec.from_dict(parsed)


func test_move_to_dict_format() -> void:
	var d := MoveUnitCommand.new(3, Vector2i(4, -2)).to_dict()
	assert_eq(d, {"type": "move", "unit_id": 3, "target": [4, -2]})


func test_attack_to_dict_format() -> void:
	var d := AttackCommand.new(1, 5).to_dict()
	assert_eq(d, {"type": "attack", "attacker_id": 1, "target_id": 5})


func test_end_turn_to_dict_format() -> void:
	assert_eq(EndTurnCommand.new().to_dict(), {"type": "end_turn"})


func test_move_round_trip_through_text_keeps_types() -> void:
	var decoded := _through_text(MoveUnitCommand.new(3, Vector2i(4, -2)))
	assert_true(decoded is MoveUnitCommand)
	var move := decoded as MoveUnitCommand
	assert_eq(move.unit_id, 3)
	assert_eq(typeof(move.get("unit_id")), TYPE_INT)
	assert_eq(move.target, Vector2i(4, -2))
	assert_eq(typeof(move.get("target")), TYPE_VECTOR2I)


func test_attack_round_trip_through_text_keeps_types() -> void:
	var decoded := _through_text(AttackCommand.new(1, 5))
	assert_true(decoded is AttackCommand)
	var attack := decoded as AttackCommand
	assert_eq(attack.attacker_id, 1)
	assert_eq(attack.target_id, 5)
	assert_eq(typeof(attack.get("attacker_id")), TYPE_INT)
	assert_eq(typeof(attack.get("target_id")), TYPE_INT)


func test_end_turn_round_trip_through_text() -> void:
	assert_true(_through_text(EndTurnCommand.new()) is EndTurnCommand)


func test_unknown_type_is_null() -> void:
	assert_eq(CommandCodec.from_dict({"type": "teleport"}), null)


func test_missing_type_is_null() -> void:
	assert_eq(CommandCodec.from_dict({"attacker_id": 1, "target_id": 5}), null)


func test_non_string_type_is_null() -> void:
	assert_eq(CommandCodec.from_dict({"type": 7}), null)


func test_missing_fields_are_null() -> void:
	assert_eq(CommandCodec.from_dict({"type": "move", "unit_id": 3}), null)
	assert_eq(CommandCodec.from_dict({"type": "move", "target": [1, 2]}), null)
	assert_eq(CommandCodec.from_dict({"type": "attack", "attacker_id": 1}), null)
	assert_eq(CommandCodec.from_dict({"type": "attack", "target_id": 1}), null)


func test_non_numeric_values_are_null() -> void:
	assert_eq(CommandCodec.from_dict({"type": "attack", "attacker_id": "1", "target_id": 5}), null)
	assert_eq(CommandCodec.from_dict({"type": "attack", "attacker_id": true, "target_id": 5}), null)
	assert_eq(CommandCodec.from_dict({"type": "move", "unit_id": null, "target": [1, 2]}), null)
	assert_eq(CommandCodec.from_dict({"type": "move", "unit_id": 3, "target": ["1", 2]}), null)


func test_non_integral_floats_are_null() -> void:
	assert_eq(CommandCodec.from_dict({"type": "attack", "attacker_id": 1.5, "target_id": 5}), null)
	assert_eq(CommandCodec.from_dict({"type": "move", "unit_id": 3, "target": [1, 2.25]}), null)
	assert_eq(CommandCodec.from_dict({"type": "attack", "attacker_id": INF, "target_id": 5}), null)
	assert_eq(CommandCodec.from_dict({"type": "attack", "attacker_id": NAN, "target_id": 5}), null)


func test_integral_floats_become_ints() -> void:
	var decoded := CommandCodec.from_dict({"type": "attack", "attacker_id": 2.0, "target_id": 7.0})
	assert_true(decoded is AttackCommand)
	assert_eq(typeof((decoded as AttackCommand).get("attacker_id")), TYPE_INT)
	assert_eq((decoded as AttackCommand).target_id, 7)


func test_malformed_target_is_null() -> void:
	assert_eq(CommandCodec.from_dict({"type": "move", "unit_id": 3, "target": [1]}), null)
	assert_eq(CommandCodec.from_dict({"type": "move", "unit_id": 3, "target": [1, 2, 3]}), null)
	assert_eq(CommandCodec.from_dict({"type": "move", "unit_id": 3, "target": "1,2"}), null)
	assert_eq(CommandCodec.from_dict({"type": "move", "unit_id": 3, "target": {"q": 1}}), null)
