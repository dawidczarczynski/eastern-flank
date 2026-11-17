extends TestCase
## The objectives window of the staff map: rows for the viewer's side (points, current holder,
## Gap road link) and the round counter; the battle HUD's mission line asks for the briefing again.


func _state() -> OperationalState:
	return Operation.build(&"suwalki_gap", 7)


func test_rows_list_every_objective_and_the_gap_link() -> void:
	var state := _state()
	var rows := StaffMapObjectivesModel.rows(state, 0)
	assert_eq(rows.size(), state.definition.objectives.size() + 1)
	assert_eq(rows[rows.size() - 1]["status"], StaffMapObjectivesModel.MINE, "the Gap starts open")
	for row in rows:
		assert_true(int(row["points"]) > 0)
		assert_true(String(row["label"]) != "")


func test_gap_link_is_the_attackers_goal_when_closed() -> void:
	var state := _state()
	var open_rows := StaffMapObjectivesModel.rows(state, 1)
	assert_eq(open_rows[open_rows.size() - 1]["status"], StaffMapObjectivesModel.THEIRS)


func test_holder_flips_status_for_the_viewer() -> void:
	var state := _state()
	var objective := state.definition.objectives[0]
	var hex := objective.hex_in(state)
	state.hex_holders[hex] = 0
	assert_eq(StaffMapObjectivesModel.rows(state, 0)[0]["status"], StaffMapObjectivesModel.MINE)
	assert_eq(StaffMapObjectivesModel.rows(state, 1)[0]["status"], StaffMapObjectivesModel.THEIRS)


func test_round_line_names_the_limit() -> void:
	var state := _state()
	assert_true(
		StaffMapObjectivesModel.round_line(state).contains(str(state.definition.round_limit))
	)


func test_window_builds_a_row_per_objective() -> void:
	var state := _state()
	var window := StaffMapObjectivesWindow.new()
	window.show_objectives(state, 0)
	assert_eq(window.row_count(), state.definition.objectives.size() + 1)
	window.free()


# --- rule lines, Gap progress and the objective toasts (TASK-165) ---


func test_every_row_has_a_rule_from_the_data() -> void:
	var state := _state()
	var rows := StaffMapObjectivesModel.rows(state, 0)
	for i in rows.size() - 1:
		assert_eq(rows[i]["rule"], "Scored at the end, round %d" % state.definition.round_limit)
	var gap: String = rows[rows.size() - 1]["rule"]
	assert_true(gap.contains(str(state.definition.closed_rounds_to_win)), gap)
	assert_true(gap.contains("otherwise scored at the end"), gap)
	assert_eq(StaffMapObjectivesModel.rows(state, 1)[rows.size() - 1]["rule"], gap, "same for both")


func test_gap_progress_reads_per_viewer() -> void:
	var state := _state()
	var need := state.definition.closed_rounds_to_win
	for viewer in 2:
		var row: Dictionary = StaffMapObjectivesModel.rows(state, viewer).back()
		assert_eq(row["progress"], "Closed 0/%d rounds" % need)
		assert_eq(row["hint"], "")
	state.gap_closed_rounds = 1
	var nato: Dictionary = StaffMapObjectivesModel.rows(state, 0).back()
	assert_eq(nato["progress"], "Russia: closed 1/%d rounds - break the chain" % need)
	assert_eq(nato["hint"], "Any chain hex lost resets it")
	var russia: Dictionary = StaffMapObjectivesModel.rows(state, 1).back()
	assert_eq(russia["progress"], "Closed 1/%d rounds - hold it one more round" % need)
	assert_eq(russia["hint"], "Any chain hex lost resets it")


func test_hex_rows_have_no_progress() -> void:
	var row: Dictionary = StaffMapObjectivesModel.rows(_state(), 0)[0]
	assert_eq(row["progress"], "")
	assert_eq(row["hint"], "")


func _event(kind: StringName, id: StringName, old: Variant, new: Variant) -> Dictionary:
	return {
		"type": &"objective_changed",
		"kind": kind,
		"objective_id": id,
		"old": old,
		"new": new,
		"round": 3,
	}


func test_toast_holder_change_per_viewer() -> void:
	var state := _state()
	var objective := state.definition.objectives[0]
	var event := _event(&"holder", objective.id, 0, 1)
	var name := TranslationServer.translate(objective.display_name)
	assert_eq(StaffMapObjectivesModel.event_text(state, 0, event), "%s taken by Russia" % name)
	assert_eq(StaffMapObjectivesModel.event_text(state, 1, event), "%s taken by you" % name)
	var back := _event(&"holder", objective.id, 1, 0)
	assert_eq(StaffMapObjectivesModel.event_text(state, 0, back), "%s taken by you" % name)
	assert_eq(StaffMapObjectivesModel.event_text(state, 1, back), "%s taken by NATO" % name)


func test_toast_gap_texts() -> void:
	var state := _state()
	var need := state.definition.closed_rounds_to_win
	var closed := _event(&"gap", &"gap", &"open", &"closed")
	var opened := _event(&"gap", &"gap", &"closed", &"open")
	for viewer in 2:
		assert_eq(StaffMapObjectivesModel.event_text(state, viewer, closed), "The Gap is closed")
		assert_eq(
			StaffMapObjectivesModel.event_text(state, viewer, opened), "The Gap is open again"
		)
		var reset := _event(&"gap_counter", &"gap", 1, 0)
		assert_eq(
			StaffMapObjectivesModel.event_text(state, viewer, reset),
			"Gap chain broken - counter reset"
		)
	var one := _event(&"gap_counter", &"gap", 0, 1)
	assert_eq(
		StaffMapObjectivesModel.event_text(state, 1, one),
		"Gap closed - 1/%d rounds, hold it one more round" % need
	)
	assert_eq(
		StaffMapObjectivesModel.event_text(state, 0, one),
		"Russia holds the Gap - 1/%d rounds, break the chain" % need
	)


func test_unknown_event_gives_no_text() -> void:
	var state := _state()
	assert_eq(StaffMapObjectivesModel.event_text(state, 0, {"type": &"x"}), "")
	assert_eq(StaffMapObjectivesModel.event_text(state, 0, _event(&"holder", &"nope", 0, 1)), "")


func test_toast_queues_messages_in_order() -> void:
	var toast := Toast.new()
	toast.enqueue("one")
	toast.enqueue("two")
	assert_eq(toast.message(), "one")
	toast.advance(Toast.SECONDS + 0.1)
	assert_eq(toast.message(), "two")
	toast.advance(Toast.SECONDS + 0.1)
	assert_false(toast.visible)
	toast.free()
