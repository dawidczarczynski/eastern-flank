extends TestCase
## The objectives window of the staff map: rows for the viewer's side only (points, current holder,
## the viewer's main link objective) and the round counter; toasts per viewer.


func _state() -> OperationalState:
	return Operation.build(&"suwalki_gap", 7)


## Side objectives `viewer` plays for: its own and the neutral ones (holder rule `any`).
static func _own_sides(state: OperationalState, viewer: int) -> Array[OperationObjective]:
	var own: Array[OperationObjective] = []
	for objective in state.definition.objectives:
		if objective.holder_rule == OperationObjective.ANY or objective.side == viewer:
			own.append(objective)
	return own


func test_rows_are_the_own_main_then_own_and_neutral_side_objectives() -> void:
	var state := _state()
	for viewer in 2:
		var rows := StaffMapObjectivesModel.rows(state, viewer)
		var own := _own_sides(state, viewer)
		assert_eq(rows.size(), own.size() + 1, "no enemy objective for %d" % viewer)
		assert_eq(rows[0]["tier"], StaffMapObjectivesModel.MAIN)
		for i in own.size():
			assert_eq(rows[i + 1]["tier"], StaffMapObjectivesModel.SIDE)
			assert_eq(
				rows[i + 1]["label"], String(TranslationServer.translate(own[i].display_name))
			)
			assert_true(rows[i + 1]["yours"])
		for row in rows:
			assert_true(int(row["points"]) > 0)
			assert_false(row.has("chain"), "no route is prescribed")
	assert_eq(_own_sides(state, 0).size(), 2, "Chernyakhovsk + Grodno")
	assert_eq(_own_sides(state, 1).size(), 3, "Bialystok, Vilnius + Grodno")
	var nato := StaffMapObjectivesModel.rows(state, 0)
	var russia := StaffMapObjectivesModel.rows(state, 1)
	assert_eq(nato[0]["kind"], StaffMapObjectivesModel.GAP)
	assert_eq(russia[0]["kind"], StaffMapObjectivesModel.CORRIDOR)


func test_main_rows_frame_the_two_ends_of_the_link() -> void:
	var state := _state()
	var def := state.definition
	var nato: Dictionary = StaffMapObjectivesModel.rows(state, 0)[0]
	assert_eq(nato["hexes"], [def.nato_link_from, def.nato_link_to] as Array[Vector2i])
	var russia: Dictionary = StaffMapObjectivesModel.rows(state, 1)[0]
	var ends: Array[Vector2i] = russia["hexes"]
	assert_eq(ends.size(), 2)
	assert_eq(state.country_at(ends[0]), def.corridor_from_country, "an end in Kaliningrad")
	assert_eq(state.country_at(ends[1]), def.corridor_to_country, "an end in Belarus")
	var map := ImportedMap.find(state.map_id)
	var names: Array[String] = []
	for hex in ends:
		names.append(String(BattleName.place(map, hex)["name"]))
	assert_eq(names, ["Калининград", "Гродна"] as Array[String], "the biggest places")


func test_selected_flag_follows_the_index() -> void:
	var rows := StaffMapObjectivesModel.rows(_state(), 0, 2)
	for i in rows.size():
		assert_eq(rows[i]["selected"], i == 2)


func test_main_chips_follow_the_link_status() -> void:
	var state := _state()
	var def := state.definition
	var nato: Dictionary = StaffMapObjectivesModel.rows(state, 0)[0]
	assert_eq(nato["chip"], "CONNECTED")
	assert_eq(nato["status"], StaffMapObjectivesModel.MINE)
	assert_false(nato["alert"])
	var russia: Dictionary = StaffMapObjectivesModel.rows(state, 1)[0]
	assert_eq(russia["chip"], "NOT CONNECTED")
	assert_eq(russia["status"], StaffMapObjectivesModel.NONE)
	assert_false(russia["alert"])
	state.hex_holders[def.nato_link_to] = 1
	nato = StaffMapObjectivesModel.rows(state, 0)[0]
	assert_eq(nato["chip"], "CUT")
	assert_eq(nato["status"], StaffMapObjectivesModel.THEIRS, "a cut link is bad for NATO")
	assert_true(nato["alert"])
	assert_eq(nato["tag"], "SUWAŁKI ↔ KAUNAS ▪ CUT +%d" % def.gap_open_points)
	for hex in OperationVictory.land_route(state, def, false):
		state.hex_holders[hex] = 1
	state.corridor_closed_rounds = 2
	russia = StaffMapObjectivesModel.rows(state, 1)[0]
	assert_eq(russia["chip"], "CONNECTED")
	assert_eq(russia["status"], StaffMapObjectivesModel.MINE)
	assert_true(russia["alert"])
	assert_eq(russia["tag"], "KALININGRAD ↔ BELARUS ▪ 2/%d" % def.closed_rounds_to_win)


func test_holder_flips_status_for_the_viewer() -> void:
	var state := _state()
	var grodno := state.definition.objectives[3]
	assert_eq(grodno.holder_rule, OperationObjective.ANY)
	state.hex_holders[grodno.hex_in(state)] = 0
	var nato := StaffMapObjectivesModel.rows(state, 0)
	var russia := StaffMapObjectivesModel.rows(state, 1)
	assert_eq(nato[nato.size() - 1]["status"], StaffMapObjectivesModel.MINE)
	assert_eq(russia[russia.size() - 1]["status"], StaffMapObjectivesModel.THEIRS)
	assert_eq(nato[nato.size() - 1]["chip"], "HELD BY US")
	assert_eq(russia[russia.size() - 1]["chip"], "HELD BY ENEMY")


func test_round_line_names_the_limit() -> void:
	var state := _state()
	assert_true(
		StaffMapObjectivesModel.round_line(state).contains(str(state.definition.round_limit))
	)


func test_window_builds_a_row_per_objective() -> void:
	var state := _state()
	var window := StaffMapObjectivesWindow.new()
	window.show_objectives(state, 0)
	assert_eq(window.row_count(), _own_sides(state, 0).size() + 1)
	window.free()


# --- main card, side rows, selection (TASK-175a) ---


func test_main_card_texts_per_viewer() -> void:
	var state := _state()
	var def := state.definition
	var need := def.closed_rounds_to_win
	assert_eq(need, 5)
	state.corridor_closed_rounds = 3
	var nato: Dictionary = StaffMapObjectivesModel.rows(state, 0)[0]
	var russia: Dictionary = StaffMapObjectivesModel.rows(state, 1)[0]
	assert_eq(nato["label"], "Keep Suwałki connected with Kaunas")
	assert_eq(nato["ends_text"], "SUWAŁKI ↔ KAUNAS")
	assert_eq(nato["points"], def.gap_open_points)
	assert_eq(nato["need"], 0, "no counter for NATO")
	assert_eq(nato["progress"], "")
	assert_eq(
		nato["rule"],
		(
			"Any land route without enemy hexes counts. +%d at the end while connected."
			% def.gap_open_points
		)
	)
	assert_eq(nato["tag"], "SUWAŁKI ↔ KAUNAS ▪ CONNECTED +%d" % def.gap_open_points)
	assert_eq(russia["label"], "Connect Kaliningrad with Belarus")
	assert_eq(russia["ends_text"], "KALININGRAD ↔ BELARUS")
	assert_eq(russia["points"], def.corridor_points)
	assert_eq(russia["need"], need)
	assert_eq(russia["closed_rounds"], 3)
	assert_eq(russia["progress"], "3 / %d" % need)
	assert_eq(
		russia["rule"],
		(
			(
				"Any route of land held by us counts. Connected %d rounds in a row: "
				+ "we win at once; otherwise +%d at the end while connected."
			)
			% [need, def.corridor_points]
		)
	)
	assert_eq(russia["tag"], "KALININGRAD ↔ BELARUS ▪ 3/%d" % need)


func test_section_headers() -> void:
	var state := _state()
	assert_eq(StaffMapObjectivesModel.main_header(), "Main objective")
	assert_eq(
		StaffMapObjectivesModel.side_header(state),
		"Side objectives - scored at the end, round %d" % state.definition.round_limit
	)


func test_every_side_row_says_who_it_scores_for() -> void:
	var state := _state()
	for viewer in 2:
		var rows := StaffMapObjectivesModel.rows(state, viewer)
		for i in range(1, rows.size()):
			assert_true(String(rows[i]["sub"]).begins_with("Scores for"), rows[i]["label"])


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
	var def := state.definition
	assert_eq(
		centred[0],
		[def.nato_link_from, def.nato_link_to] as Array[Vector2i],
		"the main row asks for both ends of the link"
	)
	window.activate_row(1)
	assert_eq(centred[1], [window.row_model(1)["hex"]])
	assert_false(window.handle_key(KEY_A))
	window.free()


func test_rows_are_tall_enough_for_their_content() -> void:
	var window := StaffMapObjectivesWindow.new()
	window.show_objectives(_state(), 0)
	assert_true(
		window.row_button(0).get_combined_minimum_size().y >= 70.0, "main card: title + rule"
	)
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
	window.row_button(1).pressed.emit()
	assert_eq(window.selected_row(), 1)
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
	var grodno := state.definition.objectives[3]  # neutral: both sides follow it
	var event := _event(&"holder", grodno.id, 0, 1)
	var name := TranslationServer.translate(grodno.display_name)
	assert_eq(StaffMapObjectivesModel.event_text(state, 0, event), "%s taken by Russia" % name)
	assert_eq(StaffMapObjectivesModel.event_text(state, 1, event), "%s taken by you" % name)
	var back := _event(&"holder", grodno.id, 1, 0)
	assert_eq(StaffMapObjectivesModel.event_text(state, 0, back), "%s taken by you" % name)
	assert_eq(StaffMapObjectivesModel.event_text(state, 1, back), "%s taken by NATO" % name)


func test_no_toast_for_the_other_sides_side_objective() -> void:
	var state := _state()
	var chernyakhovsk := state.definition.objectives[0]  # NATO's
	var event := _event(&"holder", chernyakhovsk.id, 1, 0)
	assert_true(StaffMapObjectivesModel.event_text(state, 0, event) != "")
	assert_eq(StaffMapObjectivesModel.event_text(state, 1, event), "")
	assert_eq(StaffMapObjectivesModel.journal_text(state, 1, event), "")


func test_toasts_of_the_links_only_for_their_own_side() -> void:
	var state := _state()
	var need := state.definition.closed_rounds_to_win
	var cut := _event(&"gap", &"gap", &"open", &"cut")
	var restored := _event(&"gap", &"gap", &"cut", &"open")
	var established := _event(&"corridor", &"corridor", &"open", &"closed")
	var broken := _event(&"corridor", &"corridor", &"closed", &"open")
	var two := _event(&"corridor_counter", &"corridor", 1, 2)
	var reset := _event(&"corridor_counter", &"corridor", 1, 0)
	var text := func(viewer: int, e: Dictionary) -> String:
		return StaffMapObjectivesModel.event_text(state, viewer, e)
	assert_eq(text.call(0, cut), "The Suwałki–Kaunas link is cut")
	assert_eq(text.call(0, restored), "The Suwałki–Kaunas link is restored")
	assert_eq(text.call(1, established), "The Kaliningrad–Belarus link is established")
	assert_eq(text.call(1, broken), "The Kaliningrad–Belarus link is broken")
	assert_eq(text.call(1, two), "Kaliningrad–Belarus link held 2/%d rounds" % need)
	assert_eq(text.call(1, reset), "Kaliningrad–Belarus link broken - counter reset")
	assert_eq(StaffMapObjectivesModel.journal_text(state, 0, cut), "The Suwałki–Kaunas link is cut")
	for e in [cut, restored]:
		assert_eq(text.call(1, e), "", "Russia never reads NATO's link")
		assert_eq(StaffMapObjectivesModel.journal_text(state, 1, e), "")
	for e in [established, broken, two, reset]:
		assert_eq(text.call(0, e), "", "NATO never reads Russia's link or counter")
		assert_eq(StaffMapObjectivesModel.journal_text(state, 0, e), "")


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
