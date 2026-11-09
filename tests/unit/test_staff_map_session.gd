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
	assert_true(Session.finish_battle(battle.state), "Report to staff")

	var back := _build()
	assert_true(back.simulation() == simulation, "the same simulation comes back")
	assert_eq(back.simulation().state.snapshot(), before, "state unchanged by the transition")
	assert_eq(back.view_settings(), settings, "camera, viewer, selection and toggles restored")
	assert_eq(back.selected_formation(), own.id)
	assert_false(back.contacts().notice.visible, "the battle is resolved")
	assert_eq(back.contacts().pending_count(), 0)
	var notice := back.result_notice()
	assert_true(notice.visible, "the short result notice shows")
	assert_eq(notice.row_count(), 2, "one row per formation")
	assert_true(notice.row_label(0).contains("→"), notice.row_label(0))
	notice.close()
	assert_false(notice.visible)
	assert_true(back.end_turn(), "End turn works")
	back.free()


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
	assert_eq(StaffMapBattleResult.row_text(rows[0]), "F1 · 10 → 4")
