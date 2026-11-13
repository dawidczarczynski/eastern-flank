extends TestCase
## Outside support on the staff map (TASK-121 view): the Support tab model (supporters, package
## choices with the real rejection code, the other bloc's requests and free responses), the ghost
## counters of arrivals on the way and the toast texts; plus the panel's Support tab.


func _state(player := 0) -> OperationalState:
	var state := Operation.build(&"suwalki_gap", 7)
	state.current_player = player
	return state


func _take(state: OperationalState, command: OperationalCommand) -> Array[Dictionary]:
	var sim := OperationalSimulation.new(state)
	var events: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	assert_true(sim.execute(command), command.validate(state))
	return events


func _pack(state: OperationalState, viewer: int, id: StringName) -> Dictionary:
	return StaffMapSupportModel.package(state, viewer, state.get_support(id))


func test_supporters_of_the_viewer_side() -> void:
	var state := _state()
	var nato := StaffMapSupportModel.supporters(state, 0)
	assert_eq(nato.size(), 1)
	assert_eq(nato[0]["id"], &"nato_allies")
	assert_eq(nato[0]["packages"].size(), 1)
	var russia := StaffMapSupportModel.supporters(state, 1)
	assert_eq(russia[0]["id"], &"north_korea")


func test_package_blocked_below_its_level_with_reason() -> void:
	var state := _state(1)
	var pack := _pack(state, 1, &"nk_troops")  # needs level 2, the operation starts at 1
	assert_false(pack["enabled"])
	assert_eq(pack["code"], "level_too_low")
	assert_true(String(pack["reason"]).contains("2"), pack["reason"])
	assert_eq(pack["state"], &"open")


func test_package_enabled_with_cost_and_confirmation() -> void:
	var state := _state()
	var pack := _pack(state, 0, &"allied_reinforcements")
	assert_true(pack["enabled"], pack["code"])
	assert_eq(pack["new_level"], state.escalation_level + 1)
	assert_true(String(pack["confirm"]).contains("Allied reinforcements"), pack["confirm"])
	assert_eq(pack["id"], StaffMapSupportModel.DECISION)
	assert_eq(pack["country"], &"allied_reinforcements")
	assert_true(String(pack["band"]) != "" and String(pack["what"]) != "")


func test_not_your_turn_disables() -> void:
	var state := _state(1)
	assert_eq(_pack(state, 0, &"allied_reinforcements")["code"], "not_your_turn")


func test_requested_package_shows_ghost_and_state() -> void:
	var state := _state()
	_take(state, RequestSupportCommand.new(&"allied_reinforcements"))
	var pack := _pack(state, 0, &"allied_reinforcements")
	assert_eq(pack["state"], &"on_way")
	assert_true(String(pack["state_text"]).contains("4"), pack["state_text"])
	var ghosts := StaffMapSupportModel.ghosts(state, 0)
	assert_eq(ghosts.size(), 2)  # two entry hexes
	assert_false(ghosts[0]["waiting"])
	assert_eq(ghosts[0]["turns"], 4)
	assert_eq(StaffMapSupportModel.ghosts(state, 1).size(), 0)  # not visible to the other side


func test_other_bloc_lists_request_and_free_response() -> void:
	var state := _state()
	_take(state, RequestSupportCommand.new(&"allied_reinforcements"))
	state.current_player = 1
	var found := StaffMapSupportModel.other_bloc(state, 1)
	assert_eq(found.size(), 1)
	assert_eq(found[0]["id"], &"allied_reinforcements")
	var answers: Array = found[0]["responses"]
	assert_eq(answers.size(), 1)
	assert_true(answers[0]["response"])
	assert_eq(answers[0]["cost_kind"], &"free")
	assert_eq(answers[0]["new_level"], state.escalation_level)
	# The open response is not repeated under the supporter.
	assert_eq(StaffMapSupportModel.supporters(state, 1)[0]["packages"].size(), 0)


func test_ghost_text_waiting_and_turns() -> void:
	assert_eq(StaffMapSupportModel.ghost_text(3, false, "Belarus"), "in 3 turns")
	assert_eq(StaffMapSupportModel.ghost_text(1, false, "Belarus"), "next turn")
	assert_eq(StaffMapSupportModel.ghost_text(0, true, "Belarus"), "waiting – Belarus closed")


func _is_requested(e: Dictionary) -> bool:
	return e["type"] == &"support_requested"


func test_toasts_for_the_recipient_only() -> void:
	var state := _state()
	var events := _take(state, RequestSupportCommand.new(&"allied_reinforcements"))
	var requested: Dictionary = events.filter(_is_requested)[0]
	assert_true(StaffMapSupportModel.toast_text(state, 0, requested).contains("4"))
	assert_true(StaffMapSupportModel.toast_text(state, 1, requested).contains("free response"))
	var withdrawn := {
		"type": &"support_withdrawn",
		"package": &"allied_reinforcements",
		"reason": &"level_too_high"
	}
	assert_true(StaffMapSupportModel.toast_text(state, 0, withdrawn).contains("level 3"))
	assert_eq(StaffMapSupportModel.toast_text(state, 1, withdrawn), "")
	var delayed := {
		"type": &"support_delayed", "package": &"allied_reinforcements", "reason": &"no_open_entry"
	}
	assert_true(StaffMapSupportModel.toast_text(state, 0, delayed).contains("waiting"))


func test_decision_command_maps_to_request() -> void:
	var cmd := StaffMapDecisionsModel.command(StaffMapSupportModel.DECISION, &"nk_troops")
	assert_true(cmd is RequestSupportCommand)
	assert_eq(cmd.package_id, &"nk_troops")


func test_panel_support_tab_take_and_confirm() -> void:
	var state := _state()
	var panel := StaffMapDecisionsPanel.new()
	var palette := StaffMapPalette.new()
	var chosen: Array = []
	panel.decision_chosen.connect(
		func(id: StringName, c: StringName) -> void: chosen.append([id, c])
	)
	panel.show_state(state, palette, 0)
	panel.finish_fade()
	panel.open_tab(StaffMapDecisionsPanel.TAB_SUPPORT)
	assert_eq(panel.tab(), StaffMapDecisionsPanel.TAB_SUPPORT)
	var take := panel.button_of(&"allied_reinforcements")
	assert_true(take != null and not take.disabled)
	take.pressed.emit()  # costs a level: asks first
	assert_true(panel.is_confirming())
	assert_true(chosen.is_empty())
	panel.button_of(&"allied_reinforcements").pressed.emit()
	assert_eq(chosen, [[StaffMapSupportModel.DECISION, &"allied_reinforcements"]])
	panel.free()


func test_panel_blocked_package_shows_reason() -> void:
	var state := _state(1)
	var panel := StaffMapDecisionsPanel.new()
	panel.show_state(state, StaffMapPalette.new(), 1)
	panel.finish_fade()
	panel.open_tab(StaffMapDecisionsPanel.TAB_SUPPORT)
	assert_true(panel.button_of(&"nk_troops").disabled)
	assert_true(panel.reason_of(&"nk_troops") != "")
	panel.free()


func test_no_support_tab_without_packages() -> void:
	var state := Operation.build(&"suwalki_gap", 7)
	state.support.clear()
	var panel := StaffMapDecisionsPanel.new()
	panel.show_state(state, StaffMapPalette.new(), 0)
	panel.open_tab(StaffMapDecisionsPanel.TAB_SUPPORT)
	assert_eq(panel.tab(), StaffMapDecisionsPanel.TAB_DECISIONS)
	panel.free()
