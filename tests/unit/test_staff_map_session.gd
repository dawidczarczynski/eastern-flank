extends TestCase
## Staff map <-> battle hand-off (TASK-094c, controller level): Play battle hands the simulation
## and the view to Session and opens the battle scene; the staff map built afterwards takes the
## same simulation back with the same state snapshot, camera, viewer, selection and toggles, the
## queue rebuilt from the state and the short result notice shown.

const Fixtures := preload("res://tests/fixtures.gd")

static var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	Session.abandon()


func after_all() -> void:
	Session.abandon()
	TranslationServer.set_locale(_previous_locale)


func _build() -> StaffMap:
	var map := StaffMap.new()
	map.auto_build = false
	map.viewer_player = 0
	(Engine.get_main_loop() as SceneTree).root.add_child(map)
	assert_true(map.build_now(), "staff map builds")
	return map


func test_play_battle_and_return_keeps_state_and_view() -> void:
	var map := _build()
	map.set_follow_side(false)
	var simulation := map.simulation()
	var state := simulation.state
	for event in Fixtures.theatre_contact(state):
		simulation.event_emitted.emit(event)
	assert_true(map.contacts().notice.visible)
	var own := state.formations[0]
	map.select_formation(own.id)
	map.debug_focus(Vector2(own.coord), map.zoom_limits().y * 0.5)
	map.view().set_grid_visible(not map.view().grid_visible())
	var opened: Array[String] = []
	map.open_scene = func(path: String) -> void: opened.append(path)
	var before := state.snapshot()
	var settings := map.view_settings()
	map.contacts().notice.press_play()
	assert_eq(opened, [Session.BATTLE_SCENE], "Play battle opens the battle scene")
	assert_true(Session.in_battle())
	map.free()

	var battle := GameSimulation.new(Scenario.from_setup(Session.battle))
	assert_true(MatchRunner.run(battle, 40))
	assert_true(Session.finish_battle(battle), "Report to staff")

	var back := _build()
	assert_true(back.simulation() == simulation, "the same simulation comes back")
	assert_eq(back.simulation().state.snapshot(), before, "state unchanged by the transition")
	assert_eq(back.view_settings(), settings, "camera, viewer, selection and toggles restored")
	assert_eq(back.selected_formation(), own.id)
	assert_false(back.contacts().notice.visible, "the battle is resolved")
	assert_eq(back.contacts().pending_count(), 0)
	var notice := back.result_notice()
	assert_true(notice.visible, "the short result notice shows")
	assert_eq(notice.row_count(), 2, "one tab per formation")
	assert_true(notice.summary_label().contains("Lost"), notice.summary_label())
	assert_false(notice.summary_label().contains("→"), "no bare arrows")
	notice.close()
	assert_false(notice.visible)
	assert_true(back.end_turn(), "End turn works")
	back.free()


## TASK-120: Auto-resolve closes the battle on the staff map (no scene change) and shows the short
## result notice with who holds the field; the record gets an auto entry.
func test_auto_resolve_stays_on_the_staff_map() -> void:
	var map := _build()
	var simulation := map.simulation()
	var state := simulation.state
	for event in Fixtures.theatre_contact(state):
		simulation.event_emitted.emit(event)
	assert_true(map.contacts().notice.auto_enabled())
	var opened: Array[String] = []
	map.open_scene = func(path: String) -> void: opened.append(path)
	map.contacts().notice.press_auto()
	assert_eq(opened, [], "no battle scene loads")
	assert_false(Session.in_battle())
	assert_eq(state.pending_battles.size(), 0)
	assert_false(map.contacts().notice.visible)
	var notice := map.result_notice()
	assert_true(notice.visible)
	assert_eq(notice.row_count(), 2)
	assert_true(notice.detail_count() >= 2, "company strengths per formation")
	assert_eq(Session.battles.size(), 1)
	assert_eq(Session.battles[0].resolution, &"auto")
	assert_eq(Session.battles[0].commands.size(), 0)
	map.free()


## TASK-094d: F5 saves with a pending battle ("Saved" toast); Continue builds the staff map
## around the replayed operation, viewed by the saved side, with the contact notice back.
func test_save_and_continue_restore_the_pending_battle() -> void:
	var dir := "user://test_staff_map_campaigns"
	var map := _build()
	map.save_dir = dir
	var simulation := map.simulation()
	assert_true(simulation.execute(IssueOrderCommand.new(&"ru_mr_4", Vector2i(16, 52), &"advance")))
	for i in 3:
		assert_true(simulation.execute(EndOperationalTurnCommand.new()))
	assert_eq(simulation.state.pending_battles.size(), 1, "a contact is pending")
	map.viewer_player = 1
	assert_true(map.save_campaign())
	assert_eq(map.toast().message(), "Saved")
	var snapshot := simulation.state.snapshot()
	var pending: Array = simulation.state.pending_battles.map(
		func(b: BattleSetup) -> Dictionary: return b.to_dict()
	)
	map.free()
	Session.abandon()

	var loaded := CampaignSaver.load_campaign(CampaignSaver.path_for("suwalki_gap", dir))
	assert_eq(loaded["error"], "")
	Session.resume(loaded["record"], loaded["simulation"])
	var back := StaffMap.new()
	back.auto_build = false
	(Engine.get_main_loop() as SceneTree).root.add_child(back)
	assert_true(back.build_now(), "staff map builds")
	assert_true(back.simulation() == loaded["simulation"], "Continue hands over the replay")
	assert_eq(back.viewer_player, 1, "the saved side views the map")
	assert_eq(back.simulation().state.snapshot(), snapshot)
	assert_eq(
		back.simulation().state.pending_battles.map(
			func(b: BattleSetup) -> Dictionary: return b.to_dict()
		),
		pending
	)
	assert_true(back.contacts().notice.visible, "the contact notice is back")
	back.free()
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(CampaignSaver.path_for("suwalki_gap", dir))
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func test_result_rows_sum_the_companies() -> void:
	var setup := BattleSetup.new()
	setup.attacker = 1
	for player in 2:
		var mission := BattleSetup.Mission.new()
		mission.formation_name = "F%d" % player
		setup.missions.append(mission)
	var result := BattleResult.new()
	for spec: Array in [[0, 5, 3], [1, 4, 4], [1, 6, 0]]:
		var company := BattleResult.Company.new()
		company.player = spec[0]
		company.strength_start = spec[1]
		company.strength_end = spec[2]
		result.companies.append(company)
	var rows := StaffMapBattleResult.sides(setup, result)
	assert_eq(rows[0], {"player": 1, "formation_name": "F1", "before": 10, "after": 4})
	assert_eq(rows[1], {"player": 0, "formation_name": "F0", "before": 5, "after": 3})
	assert_eq(
		StaffMapBattleResult.summary_text(rows[0]),
		"Strength at start 10 · Strength left 4 · Lost 6 (60%)"
	)
