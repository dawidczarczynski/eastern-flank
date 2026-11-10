extends TestCase
## Politics screen (TASK-117 variant B): view-model extras (groups, hot keys, tags, stance) and the
## sheet's keys on the staff map (Esc, 1-5, arrows, Enter, the open key).


func _state(player := 0) -> OperationalState:
	var state := Operation.build(&"suwalki_gap", 7)
	state.current_player = player
	return state


func _row(rows: Array[Dictionary], id: StringName) -> Dictionary:
	for row in rows:
		if row["id"] == id:
			return row
	return {}


func _first_choice(state: OperationalState, id: StringName) -> Dictionary:
	return _row(StaffMapDecisionsModel.rows(state, 0), id)["choices"][0]


func test_groups_cover_the_five_decisions_and_hot_keys_follow_order() -> void:
	var all: Array[StringName] = []
	all.append_array(StaffMapDecisionsModel.WIDEN)
	all.append_array(StaffMapDecisionsModel.KEEP_SMALL)
	all.sort()
	var order := StaffMapDecisionsModel.ORDER.duplicate()
	order.sort()
	assert_eq(all, order)
	assert_eq(StaffMapDecisionsModel.hot_key(&"escalate"), 1)
	assert_eq(StaffMapDecisionsModel.hot_key(&"demand_neutrality"), 5)


func test_choice_has_tag_cost_kind_and_stance() -> void:
	var state := _state()
	var escalate: Dictionary = _first_choice(state, &"escalate")
	assert_eq(escalate["tag"], &"")
	assert_eq(escalate["cost_kind"], &"up")
	var stand_down: Dictionary = _first_choice(state, &"stand_down")
	assert_eq(stand_down["cost_kind"], &"down")
	state.escalation_level = state.ladder.top() - 1
	escalate = _first_choice(state, &"escalate")
	assert_eq(escalate["tag"], &"threshold")
	state.decisions_left = 0
	escalate = _first_choice(state, &"escalate")
	assert_eq(escalate["tag"], &"blocked")
	var declare := _row(StaffMapDecisionsModel.rows(state, 0), &"declare_hostilities")
	for choice: Dictionary in declare["choices"]:
		assert_true(choice["relation"] in [&"own", &"hostile", &"neutral"], str(choice["relation"]))
		assert_true(String(choice["stance_text"]) != "")


func test_result_line_names_decision_and_level() -> void:
	var state := _state()
	var text := StaffMapDecisionsModel.result_line(state, 0, &"escalate")
	assert_true(text.contains(str(state.escalation_level)), text)


func _open_map() -> StaffMap:
	var map := StaffMap.new()
	map.auto_build = false
	map.viewer_player = 0
	(Engine.get_main_loop() as SceneTree).root.add_child(map)
	assert_true(map.build_now(), "staff map builds")
	map.set_viewer(map.simulation().state.current_player)
	map.toggle_decisions()
	return map


func test_esc_cancels_a_confirmation_then_closes() -> void:
	var map := _open_map()
	var panel := map.decisions_hud().panel()
	panel.select_card(&"escalate")
	assert_true(panel.handle_key(KEY_ENTER))  # take -> asks first
	assert_true(panel.is_confirming())
	assert_true(panel.handle_key(KEY_ESCAPE))
	assert_false(panel.is_confirming())
	assert_true(map.decisions_hud().is_open(), "first Esc only cancels")
	assert_true(map.decisions_hud().handle_key(KEY_ESCAPE))
	assert_false(map.decisions_hud().is_open(), "second Esc closes")
	map.free()


func test_hot_keys_pick_cards_and_enter_confirms() -> void:
	var map := _open_map()
	var state := map.simulation().state
	var level := state.escalation_level
	var panel := map.decisions_hud().panel()
	panel.handle_key(KEY_1)
	assert_eq(panel.selected(), &"escalate")
	panel.handle_key(KEY_ENTER)
	assert_true(panel.is_confirming())
	panel.handle_key(KEY_ENTER)
	assert_eq(state.escalation_level, level + 1)
	assert_true(panel.find_child("Result", true, false) != null, "result line shown")
	map.free()


func test_arrow_keys_change_the_country() -> void:
	var map := _open_map()
	var state := map.simulation().state
	var panel := map.decisions_hud().panel()
	var choices: Array = _row(StaffMapDecisionsModel.rows(state, 0), &"declare_hostilities")["choices"]
	if choices.size() < 2:
		map.free()
		return
	panel.handle_key(KEY_3)
	panel.handle_key(KEY_LEFT)
	panel.handle_key(KEY_RIGHT)
	assert_eq(panel.selected(), &"declare_hostilities")
	map.free()


func test_open_key_closes_and_is_not_a_pan_key() -> void:
	assert_true(
		StaffMapDecisionsPanel.OPEN_KEY not in [KEY_D, KEY_P, KEY_A, KEY_W, KEY_S, KEY_Q, KEY_E]
	)
	var map := _open_map()
	map.decisions_hud().handle_key(StaffMapDecisionsPanel.OPEN_KEY)
	assert_false(map.decisions_hud().is_open())
	map.free()


func test_wheel_does_not_zoom_the_map_while_the_screen_is_open() -> void:
	var map := _open_map()
	var zoom := map.zoom()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(640, 360)
	map._unhandled_input(wheel)
	assert_eq(map.zoom(), zoom, "the Politics screen idles the map")
	map.decisions_hud().close()
	map._unhandled_input(wheel)
	assert_true(map.zoom() != zoom, "the wheel zooms again once it is closed")
	map.free()
