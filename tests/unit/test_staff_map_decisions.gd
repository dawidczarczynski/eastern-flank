extends TestCase
## Decisions panel view-model (TASK-117): names per side, disabled states with the reason, never
## letting an invalid state through, symmetric for both players; plus the panel on the staff map.


func _state(player := 0) -> OperationalState:
	var state := Operation.build(&"suwalki_gap", 7)
	state.current_player = player
	return state


func _row(rows: Array[Dictionary], id: StringName) -> Dictionary:
	for row in rows:
		if row["id"] == id:
			return row
	return {}


func test_five_rows_in_order() -> void:
	var rows := StaffMapDecisionsModel.rows(_state(), 0)
	var ids: Array[StringName] = []
	for row in rows:
		ids.append(row["id"])
	assert_eq(ids, StaffMapDecisionsModel.ORDER)


func test_escalate_shows_levels_and_is_enabled() -> void:
	var state := _state()
	var choice: Dictionary = _row(StaffMapDecisionsModel.rows(state, 0), &"escalate")["choices"][0]
	assert_true(choice["enabled"])
	assert_eq(choice["new_level"], state.escalation_level + 1)
	assert_true(String(choice["effect"]).contains("%d → %d" % [1, 2]), choice["effect"])


func test_stand_down_disabled_at_floor() -> void:
	var state := _state()
	state.escalation_level = 0
	var choice: Dictionary = _row(StaffMapDecisionsModel.rows(state, 0), &"stand_down")["choices"][0]
	assert_false(choice["enabled"])
	assert_eq(choice["code"], "at_floor")
	assert_true(String(choice["reason"]) != "")


func test_invoke_alliance_named_per_side_from_data() -> void:
	var state := _state()
	for player in 2:
		var side := SideDefinition.find(state.player_sides[player])
		var title := StaffMapDecisionsModel.title(state, player, &"invoke_alliance")
		assert_eq(title, String(TranslationServer.translate(side.alliance_decision_name)))
	assert_true(
		(
			StaffMapDecisionsModel.title(state, 0, &"invoke_alliance")
			!= StaffMapDecisionsModel.title(state, 1, &"invoke_alliance")
		)
	)


func test_budget_spent_disables_every_row() -> void:
	var state := _state()
	state.decisions_left = 0
	for row in StaffMapDecisionsModel.rows(state, 0):
		for choice: Dictionary in row["choices"]:
			assert_false(choice["enabled"], str(row["id"]))


func test_not_your_turn_disables_for_the_other_viewer() -> void:
	var state := _state(0)
	for row in StaffMapDecisionsModel.rows(state, 1):
		for choice: Dictionary in row["choices"]:
			assert_false(choice["enabled"])
			assert_eq(choice["code"], "not_your_turn")


func test_level_cap_is_disabled() -> void:
	var state := _state()
	state.escalation_level = state.ladder.cap()
	var choice: Dictionary = _row(StaffMapDecisionsModel.rows(state, 0), &"escalate")["choices"][0]
	assert_false(choice["enabled"])
	assert_eq(choice["code"], "level_cap")
	assert_eq(choice["tag"], &"blocked")
	state.escalation_level = state.ladder.cap() - 1
	choice = _row(StaffMapDecisionsModel.rows(state, 0), &"escalate")["choices"][0]
	assert_true(choice["enabled"])
	assert_true(choice["danger"], "the step to the cap is red")


func _collapse(state: OperationalState, player: int) -> void:
	state.fielded_strength[player] = CollapseRules.present_strength(state, player) * 2


func _ids(rows: Array[Dictionary]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for row in rows:
		ids.append(row["id"])
	return ids


func test_nuclear_card_only_for_the_nuclear_side() -> void:
	var state := _state(1)
	assert_false(_ids(StaffMapDecisionsModel.rows(state, 0)).has(&"nuclear_strike"), "not for NATO")
	assert_true(_ids(StaffMapDecisionsModel.rows(state, 1)).has(&"nuclear_strike"), "for Russia")
	assert_eq(StaffMapDecisionsModel.ids(state, 0), StaffMapDecisionsModel.ORDER)
	assert_eq(StaffMapDecisionsModel.hot_key(&"nuclear_strike"), 6)


func test_nuclear_card_reasons_per_state() -> void:
	var state := _state(1)
	state.escalation_level = state.ladder.cap() - 1
	_collapse(state, 1)
	var rows := StaffMapDecisionsModel.rows(state, 1)
	var choice: Dictionary = _row(rows, &"nuclear_strike")["choices"][0]
	assert_false(choice["enabled"])
	assert_eq(choice["code"], "level_too_low")
	assert_eq(String(choice["reason"]), "Only at the highest level of escalation")
	state = _state(1)
	state.escalation_level = state.ladder.cap()
	choice = _row(StaffMapDecisionsModel.rows(state, 1), &"nuclear_strike")["choices"][0]
	assert_eq(choice["code"], "no_collapse")
	assert_eq(String(choice["reason"]), "Only while the army is collapsing")
	_collapse(state, 1)
	choice = _row(StaffMapDecisionsModel.rows(state, 1), &"nuclear_strike")["choices"][0]
	assert_true(choice["enabled"], choice["reason"])
	assert_true(choice["danger"], "red")
	assert_eq(choice["new_level"], state.ladder.top())
	assert_eq(
		choice["confirm"],
		"Use a nuclear weapon? This ends the operation. Russia is judged to have crossed the line."
	)
	assert_eq(StaffMapDecisionsModel.command(&"nuclear_strike").validate(state), "")


func test_level_cap_blocks_escalate_for_both_sides_even_in_collapse() -> void:
	for player in 2:
		var state := _state(player)
		state.escalation_level = state.ladder.cap()
		_collapse(state, player)
		var rows := StaffMapDecisionsModel.rows(state, player)
		var choice: Dictionary = _row(rows, &"escalate")["choices"][0]
		assert_eq(choice["code"], "level_cap")
		assert_eq(String(choice["reason"]), "Already at the highest level")


func test_enabled_always_agrees_with_the_command() -> void:
	# An enabled button must be accepted, a disabled one rejected, for both players.
	for player in 2:
		var state := _state(player)
		for row in StaffMapDecisionsModel.rows(state, player):
			for choice: Dictionary in row["choices"]:
				var cmd := StaffMapDecisionsModel.command(row["id"], choice["country"])
				assert_eq(choice["enabled"], cmd.validate(state) == "", str(row["id"]))


func test_stand_down_cooldown_counter() -> void:
	var state := _state()
	assert_eq(StaffMapDecisionsModel.header(state, 0)["cooldown"], 0)
	state.stand_down_until[0] = state.turn + 1
	assert_eq(StaffMapDecisionsModel.header(state, 0)["cooldown"], 2)
	assert_eq(StaffMapDecisionsModel.header(state, 1)["cooldown"], 0)


func test_log_text_names_side_and_country() -> void:
	var state := _state()
	var text := StaffMapDecisionsModel.log_text(
		state, {"player": 0, "decision": &"escalate", "country": &""}
	)
	assert_true(text.contains(StaffMapTurnBar.side_name(state, 0)), text)


func test_panel_on_the_map_issues_the_command() -> void:
	var map := StaffMap.new()
	map.auto_build = false
	map.viewer_player = 0
	(Engine.get_main_loop() as SceneTree).root.add_child(map)
	assert_true(map.build_now(), "staff map builds")
	var state := map.simulation().state
	map.set_viewer(state.current_player)
	map.toggle_decisions()
	var panel := map.decisions_hud().panel()
	assert_true(panel.visible, "panel visible")
	assert_false(
		panel.button_of(&"escalate").disabled, "escalate enabled: " + panel.reason_of(&"escalate")
	)
	var level := state.escalation_level
	panel.button_of(&"escalate").pressed.emit()  # asks first (the level changes)
	assert_true(panel.is_confirming())
	assert_eq(state.escalation_level, level)
	panel.button_of(&"escalate").pressed.emit()  # Confirm
	assert_eq(state.escalation_level, level + 1)
	assert_eq(state.decisions_left, 0)
	assert_false(panel.button_of(&"escalate").disabled == false, "spent budget disables it")
	assert_true(panel.reason_of(&"escalate") != "")
	map.free()


func test_panel_closes_when_the_turn_ends() -> void:
	var map := StaffMap.new()
	map.auto_build = false
	map.viewer_player = 0
	(Engine.get_main_loop() as SceneTree).root.add_child(map)
	assert_true(map.build_now(), "staff map builds")
	map.set_viewer(map.simulation().state.current_player)
	map.toggle_decisions()
	assert_true(map.decisions_hud().is_open())
	assert_true(map.end_turn())
	assert_false(map.decisions_hud().is_open(), "closed by the turn end")
	map.free()


func test_close_button_closes_the_panel() -> void:
	var map := StaffMap.new()
	map.auto_build = false
	map.viewer_player = 0
	(Engine.get_main_loop() as SceneTree).root.add_child(map)
	assert_true(map.build_now(), "staff map builds")
	map.set_viewer(map.simulation().state.current_player)
	map.toggle_decisions()
	var close := map.decisions_hud().panel().find_child("Close", true, false) as Button
	assert_true(close != null, "close button exists")
	close.pressed.emit()
	assert_false(map.decisions_hud().is_open())
	map.free()


## Every text of the panel's model, the side / level / country names and the panel's own labels
## has a Polish entry in the CSV (the translation source).
func test_every_decision_text_has_a_polish_translation() -> void:
	var rows := {}
	var file := FileAccess.open("res://assets/i18n/strings.csv", FileAccess.READ)
	file.get_csv_line()
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() >= 3:
			rows[line[0]] = line[2]
	var keys: Array[String] = [
		"TIP_DECISIONS",
		"DECISIONS",
		"Decisions",
		"Decisions: %d of %d",
		"Level %s",
		"Take",
		"Confirm",
		"Cancel",
		"CLOSE",
		"Free",
		"Level +%d",
		"Level -1",
		"Standing down: %d turns without escalating",
		"Wider strikes: level %s",
		"De-escalate: level %s, no escalating for %d turns",
		"%s becomes hostile to the enemy, level %s",
		"%s becomes hostile to the enemy (casus belli, no level change)",
		"%s enters the war on your side, level %s",
		"%s is forced back to neutrality",
		"%s? Level %d → %d (%s)",
		"– the highest level of escalation",
		"Last resort",
		"Use a nuclear weapon? This ends the operation. %s is judged to have crossed the line.",
		"The operation ends: %s is judged the loser (level %s)",
		"Politics",
		"Widen the war",
		"Keep it small",
		"Decisions %d of %d",
		"Standing down · %d turns",
		"%s taken · level now %d · %s",
		"Confirm or cancel %s first",
		"Ally",
		"Hostile",
		"Neutral",
		"Target",
		"Blocked",
		"Threshold",
		"Overview · coming with the politics report",
		"Escalation ladder table",
		"Countries list",
		"Event log",
		StaffMapDecisionsPanel.RULES_TEXT,
		"1-5 pick a card · left / right country · Enter take, confirm · Esc cancel, close",
	]  # gdlint: disable=max-line-length
	keys.append_array(StaffMapDecisionsModel.TITLES.values())
	keys.append_array(StaffMapDecisionsModel.REASONS.values())
	for text: String in StaffMapDecisionsModel.NO_TARGET_EFFECTS.values():
		if text != "":
			keys.append(text)
	var state := _state()
	for side_id in state.player_sides:
		var side := SideDefinition.find(side_id)
		keys.append(side.display_name)
		if side.alliance_decision_name != "":
			keys.append(side.alliance_decision_name)
	for level in state.ladder.levels:
		keys.append(level.display_name)
	for country in state.countries:
		keys.append(country.definition.display_name)
	for key in keys:
		assert_true(rows.has(key) and String(rows[key]) != "", "no Polish text for: " + key)
