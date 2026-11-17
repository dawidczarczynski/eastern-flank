extends TestCase
## The objectives window of the staff map: rows for the viewer's side (points, current holder,
## Gap road link) and the round counter; the battle HUD's mission line asks for the briefing again.


func _state() -> OperationalState:
	return Operation.build(&"suwalki_gap", 7)


func test_rows_are_one_main_gap_then_the_side_objectives() -> void:
	var state := _state()
	var rows := StaffMapObjectivesModel.rows(state, 0)
	assert_eq(rows.size(), state.definition.objectives.size() + 1)
	assert_eq(rows[0]["tier"], StaffMapObjectivesModel.MAIN)
	assert_eq(rows[0]["chain"], state.definition.gap_chain)
	assert_eq(rows[0]["status"], StaffMapObjectivesModel.MINE, "the Gap starts open")
	var sides := 0
	for row in rows:
		assert_true(int(row["points"]) > 0)
		assert_true(String(row["label"]) != "")
		assert_true(row.has("hex") and row.has("selected"))
		sides += 1 if row["tier"] == StaffMapObjectivesModel.SIDE else 0
	assert_eq(sides, 4)


func test_selected_flag_follows_the_index() -> void:
	var rows := StaffMapObjectivesModel.rows(_state(), 0, 2)
	for i in rows.size():
		assert_eq(rows[i]["selected"], i == 2)


func test_gap_link_is_the_attackers_goal_when_closed() -> void:
	var state := _state()
	assert_eq(StaffMapObjectivesModel.rows(state, 1)[0]["status"], StaffMapObjectivesModel.THEIRS)


func test_holder_flips_status_for_the_viewer() -> void:
	var state := _state()
	var objective := state.definition.objectives[0]
	state.hex_holders[objective.hex_in(state)] = 0
	assert_eq(StaffMapObjectivesModel.rows(state, 0)[1]["status"], StaffMapObjectivesModel.MINE)
	assert_eq(StaffMapObjectivesModel.rows(state, 1)[1]["status"], StaffMapObjectivesModel.THEIRS)
	assert_eq(StaffMapObjectivesModel.rows(state, 0)[1]["chip"], "HELD BY US")
	assert_eq(StaffMapObjectivesModel.rows(state, 1)[1]["chip"], "HELD BY ENEMY")


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


# --- main card, side rows, selection (TASK-175a) ---


func test_main_card_texts_per_viewer() -> void:
	var state := _state()
	var def := state.definition
	var nato: Dictionary = StaffMapObjectivesModel.rows(state, 0)[0]
	var russia: Dictionary = StaffMapObjectivesModel.rows(state, 1)[0]
	assert_eq(nato["label"], "Keep the Gap road open")
	assert_eq(russia["label"], "Connect Kaliningrad with Belarus")
	var total := def.gap_chain.size()
	assert_eq(nato["chain_text"], "0 of %d held by Russia" % total)
	state.hex_holders[def.gap_chain[0]] = 1
	state.hex_holders[def.gap_chain[1]] = 1
	nato = StaffMapObjectivesModel.rows(state, 0)[0]
	assert_eq(nato["chain_text"], "2 of %d held by Russia" % total)
	assert_eq((nato["chain_held"] as Array).count(true), 2)
	state.gap_closed_rounds = 3
	nato = StaffMapObjectivesModel.rows(state, 0)[0]
	assert_eq(nato["progress"], "3 / %d" % def.closed_rounds_to_win)
	assert_true(String(nato["rule"]).contains("%d rounds in a row" % def.closed_rounds_to_win))
	assert_eq(def.closed_rounds_to_win, 5)


func test_section_headers() -> void:
	var state := _state()
	assert_eq(
		StaffMapObjectivesModel.side_header(state),
		"Side objectives - scored at the end, round %d" % state.definition.round_limit
	)


func test_scores_for_line_only_on_own_objectives() -> void:
	var state := _state()
	var def := state.definition
	for viewer in 2:
		var rows := StaffMapObjectivesModel.rows(state, viewer)
		for i in range(1, rows.size()):
			var objective := def.objectives[i - 1]
			var own := objective.holder_rule == OperationObjective.ANY or objective.side == viewer
			assert_eq(rows[i]["yours"], own)
			assert_eq(String(rows[i]["sub"]) != "", own, "%s for %d" % [rows[i]["label"], viewer])
	var nato_rows := StaffMapObjectivesModel.rows(state, 0)
	var own_rows := nato_rows.filter(
		func(r: Dictionary) -> bool: return r["tier"] == &"side" and r["yours"]
	)
	var own_row: Dictionary = own_rows[0]
	assert_true(String(own_row["sub"]).begins_with("Scores for"))


func test_window_selection_wraps_and_enter_centres() -> void:
	var state := _state()
	var window := StaffMapObjectivesWindow.new()
	window.show_objectives(state, 0)
	window.show()
	var centred: Array = []
	window.centre_requested.connect(func(h: Array[Vector2i]) -> void: centred.append(h))
	assert_eq(window.selected_row(), -1)
	assert_true(window.handle_key(KEY_DOWN))
	assert_eq(window.selected_row(), 0)
	assert_true(window.handle_key(KEY_UP))
	assert_eq(window.selected_row(), window.row_count() - 1, "wraps up")
	assert_true(window.handle_key(KEY_DOWN))
	assert_eq(window.selected_row(), 0, "wraps down")
	assert_true(window.handle_key(KEY_ENTER))
	assert_eq(centred.size(), 1)
	assert_eq(centred[0], state.definition.gap_chain, "the Gap row asks for the whole chain")
	window.select_row(1)
	window.activate_row(1)
	assert_eq(centred[1], [window.row_model(1)["hex"]])
	assert_false(window.handle_key(KEY_A))
	window.free()


func test_rows_are_tall_enough_for_their_content() -> void:
	var window := StaffMapObjectivesWindow.new()
	window.show_objectives(_state(), 0)
	assert_true(window.row_button(0).get_combined_minimum_size().y >= 100.0, "main card")
	for i in range(1, window.row_count()):
		assert_true(window.row_button(i).get_combined_minimum_size().y >= 46.0)
	window.free()


func test_closing_clears_the_selection() -> void:
	var window := StaffMapObjectivesWindow.new()
	window.show_objectives(_state(), 0)
	window.show()
	var changes: Array = []
	window.selection_changed.connect(func(h: Array[Vector2i]) -> void: changes.append(h))
	window.select_row(1)
	window.close()
	assert_eq(window.selected_row(), -1)
	assert_eq(changes.back(), [] as Array[Vector2i])
	window.free()


func test_click_on_a_row_button_centres_it() -> void:
	var window := StaffMapObjectivesWindow.new()
	window.show_objectives(_state(), 0)
	var got: Array = []
	window.centre_requested.connect(func(h: Array[Vector2i]) -> void: got.append(h))
	window.row_button(2).pressed.emit()
	assert_eq(window.selected_row(), 2)
	assert_eq(got.size(), 1)
	window.free()


func test_ring_keeps_an_outline_until_cleared() -> void:
	var ring := StaffMapJournalRing.new()
	var hexes: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1)]
	ring.show_selection(hexes, Vector2i(1, 1), Vector2.ZERO)
	var screen := func(c: Vector2i) -> Vector2: return Vector2(c) * 40.0
	ring.tick(StaffMapJournalRing.SECONDS + 0.5, screen)
	assert_true(ring.is_active(), "outline stays after the pulse")
	assert_eq(ring.outline_hexes(), hexes)
	ring.clear_outline()
	assert_false(ring.is_active())
	ring.free()


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
		"Gap closed - 1/%d rounds, hold it %d more rounds" % [need, need - 1]
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
