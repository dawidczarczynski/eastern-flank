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
