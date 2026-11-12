extends TestCase
## Politics overview (TASK-119b): the pure model (ladder table, footer, countries as seen by a
## viewer, event log without attribution) and the column on the Politics screen.

const Decisions := preload("res://tests/unit/test_political_decisions.gd")


func _state() -> OperationalState:
	return Decisions._setup()


func _country(rows: Array[Dictionary], id: StringName) -> Dictionary:
	for row in rows:
		if row["id"] == id:
			return row
	return {}


func test_ladder_has_one_row_per_level_and_one_current() -> void:
	var state := _state()
	var rows := StaffMapOverviewModel.ladder_rows(state)
	assert_eq(rows.size(), state.ladder.levels.size())
	var current := rows.filter(func(r: Dictionary) -> bool: return r["current"])
	assert_eq(current.size(), 1)
	assert_eq(current[0]["level"], state.escalation_level)
	assert_eq(
		String(rows[rows.size() - 1]["roe"]), String(TranslationServer.translate("ESC_ROE_NONE"))
	)
	assert_true(rows[rows.size() - 1]["nuclear"])
	assert_eq(rows[state.ladder.sanctuary_open_level]["event"], tr("ESC_MARK_SANCTUARY"))
	assert_eq(rows[state.ladder.allies_join_level]["event"], tr("ESC_MARK_ALLIES"))


func test_footer_counts_per_side_with_net_floor() -> void:
	var state := _state()
	state.escalation_caused = [3, 0]
	state.escalation_deescalated = [1, 2]
	var rows := StaffMapOverviewModel.footer(state)
	assert_eq(rows[0]["net"], 2)
	assert_eq(rows[1]["net"], 0)
	assert_eq(rows[0]["caused"], 3)


func test_countries_seen_from_both_sides() -> void:
	var state := _state()
	CountryRules.set_stance(state, &"lithuania", CountryState.ALIGNED, 0, &"debug", -1)
	var nato := _country(StaffMapOverviewModel.country_rows(state, 0), &"lithuania")
	var russia := _country(StaffMapOverviewModel.country_rows(state, 1), &"lithuania")
	assert_eq(nato["stance"], &"allied")
	assert_true(nato["open"])
	assert_eq(russia["stance"], &"hostile")
	assert_false(russia["open"])
	assert_eq(StaffMapOverviewModel.country_rows(state, 0).size(), state.countries.size())


func test_belligerent_is_own_or_enemy() -> void:
	var state := _state()
	CountryRules.set_stance(state, &"lithuania", CountryState.BELLIGERENT, 0, &"debug", -1)
	assert_eq(
		_country(StaffMapOverviewModel.country_rows(state, 0), &"lithuania")["stance"], &"own"
	)
	var seen := _country(StaffMapOverviewModel.country_rows(state, 1), &"lithuania")
	assert_eq(seen["stance"], &"enemy")


func test_log_newest_first_and_empty_state() -> void:
	var state := _state()
	assert_true(StaffMapOverviewModel.log_rows(state).is_empty())
	var sim := OperationalSimulation.new(state)
	assert_true(sim.execute(EscalateCommand.new()))
	var rows := StaffMapOverviewModel.log_rows(state)
	assert_true(rows.size() >= 2)
	assert_true(String(rows[0]["text"]).begins_with("Level"), rows[0]["text"])
	assert_true(String(rows[rows.size() - 1]["text"]).begins_with("Decision"))


func test_log_text_does_not_depend_on_who_decided() -> void:
	var texts: Array = []
	for first in 2:
		var state := _state()
		state.current_player = first
		OperationalSimulation.new(state).execute(EscalateCommand.new())
		texts.append(
			StaffMapOverviewModel.log_rows(state).map(
				func(r: Dictionary) -> Variant: return r["text"]
			)
		)
	assert_eq(texts[0], texts[1])


func test_building_the_model_does_not_change_the_state() -> void:
	var state := _state()
	OperationalSimulation.new(state).execute(EscalateCommand.new())
	var before := state.snapshot()
	StaffMapOverviewModel.build(state, 0)
	StaffMapOverviewModel.build(state, 1)
	assert_eq(state.snapshot(), before)


func test_level_six_and_zero_build() -> void:
	var state := _state()
	for level in [0, state.ladder.top()]:
		state.escalation_level = level
		var rows := StaffMapOverviewModel.ladder_rows(state)
		assert_true(rows[level]["current"])


func test_no_support_block_without_support_data() -> void:
	assert_false(StaffMapOverviewModel.build(_state(), 0).has("support"))


func test_column_builds_blocks() -> void:
	var state := _state()
	var palette := StaffMapPalette.new()
	var column := StaffMapOverviewColumn.new()
	column.show_state(state, palette, 0)
	assert_true(column.find_child("Ladder", true, false) != null)
	assert_true(column.find_child("Countries", true, false) != null)
	assert_true(column.find_child("Log", true, false) != null)
	column.free()


func test_ladder_is_collapsed_to_the_current_level_until_toggled() -> void:
	var state := _state()
	var column := StaffMapOverviewColumn.new()
	column.show_state(state, StaffMapPalette.new(), 0)
	var ladder := column.find_child("Ladder", true, false)
	assert_eq(ladder.get_child_count(), 1)
	column.ladder_expanded = true
	column.show_state(state, StaffMapPalette.new(), 0)
	assert_eq(
		column.find_child("Ladder", true, false).get_child_count(), state.ladder.levels.size()
	)
	assert_true(column.find_child("CollapseStrip", true, false) != null)
	column.free()
