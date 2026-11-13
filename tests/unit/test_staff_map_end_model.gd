extends TestCase
## Texts of the end-of-operation notice (TASK-107b).

var _state: OperationalState


func before_each() -> void:
	_state = Operation.build(&"suwalki_gap", 7)
	_state.turn = 31


func _event(winner: int, reason: StringName, by := -1) -> Dictionary:
	return {"winner": winner, "reason": reason, "by": by}


func test_headline_per_viewer_and_reason() -> void:
	var limit := _event(0, &"round_limit")
	assert_eq(StaffMapEndModel.headline(_state, limit, 0), "Victory")
	assert_eq(StaffMapEndModel.headline(_state, limit, 1), "Defeat")
	assert_eq(StaffMapEndModel.headline(_state, _event(-1, &"round_limit"), 0), "Draw")
	assert_eq(StaffMapEndModel.headline(_state, _event(1, &"gap_closed", 1), 1), "Victory")
	var nuclear := _event(-1, &"nuclear_use", 1)
	assert_eq(StaffMapEndModel.headline(_state, nuclear, 1), "Defeat")
	assert_eq(StaffMapEndModel.headline(_state, nuclear, 0), "Nobody wins")


func test_reason_line_has_a_text_for_every_reason_and_a_generic_one() -> void:
	for reason in [&"gap_closed", &"round_limit", &"nuclear_use"]:
		var line := StaffMapEndModel.reason_line(_state, _event(-1, reason, 1))
		assert_false(line.is_empty())
		assert_false(line.contains("%"), line)
	assert_eq(
		StaffMapEndModel.reason_line(_state, _event(-1, &"something_new")),
		"The operation has ended."
	)


func test_table_rows_from_the_score_payload() -> void:
	var event := _event(0, &"round_limit")
	event["score"] = {
		0:
		{
			"lines": [{"id": &"chernyakhovsk", "points": 5}, {"id": &"gap_open", "points": 10}],
			"escalation_penalty": -3,
			"total": 12
		},
		1: {"lines": [{"id": &"vilnius", "points": 5}], "escalation_penalty": -6, "total": -1},
	}
	var rows := StaffMapEndModel.table_rows(_state, event)
	assert_eq(rows.size(), 5)
	assert_eq(rows[0], PackedStringArray(["Chernyakhovsk airfield", "+5", "–"]))
	assert_eq(rows[1], PackedStringArray(["Gap road link open", "+10", "–"]))
	assert_eq(rows[2], PackedStringArray(["Vilnius", "–", "+5"]))
	assert_eq(rows[3], PackedStringArray(["Escalation", "-3", "-6"]))
	assert_eq(rows[4], PackedStringArray(["Total", "12", "-1"]))


func test_rounds_played_and_resumed_score() -> void:
	assert_eq(StaffMapEndModel.rounds_played(_state, _event(-1, &"round_limit")), 30)
	assert_false(StaffMapEndModel.table_rows(_state, _event(-1, &"round_limit")).is_empty())
