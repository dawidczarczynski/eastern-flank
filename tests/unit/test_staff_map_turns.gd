extends TestCase
## Turn bar, End turn, banner and viewer following on the staff map (TASK-093b).

static var _map: StaffMap
static var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_map = StaffMap.new()
	_map.auto_build = false
	_map.viewer_player = 1  # the human side moves first: Russia, as these tests were written
	(Engine.get_main_loop() as SceneTree).root.add_child(_map)
	assert_true(_map.build_now(), "staff map builds")
	_map.ai_side = -1  # these tests are about hot-seat; the AI side has its own test file


func after_all() -> void:
	_map.free()
	_map = null
	TranslationServer.set_locale(_previous_locale)


func test_end_turn_flow() -> void:
	_map.set_viewer(0)
	var state := _map.simulation().state
	var start_turn := state.turn
	var bar := _map.turn_bar()
	assert_eq(bar.date_text(), "14 JUN 2027 · 06:00–18:00")
	assert_true(bar.is_day_shown())
	assert_true(bar.mover_text().contains("RUSSIA"), bar.mover_text())
	assert_eq(bar.viewed_side_text(), "NATO")
	assert_eq(bar.side_meta_text(0), "WAITING · 8 FMN")
	assert_eq(bar.side_meta_text(1), "ENEMY MOVE · 10 FMN")
	assert_true(is_equal_approx(bar.side_alpha(0), StaffMapTurnBar.INACTIVE_ALPHA))
	assert_eq(bar.side_alpha(1), StaffMapTurnBar.ACTIVE_ALPHA)
	assert_true(_map.end_turn())
	assert_eq(state.current_player, 0)
	assert_eq(state.turn, start_turn)
	assert_eq(_map.viewer_player, 0, "NATO to move: view stays NATO")
	assert_true(_map.turn_banner().visible)
	assert_true(_map.turn_banner().title_text().contains("NATO"), _map.turn_banner().title_text())
	assert_true(_map.end_turn())
	assert_eq(state.turn, start_turn + 1)
	assert_eq(_map.viewer_player, 1, "Russia to move: the view follows the side to play")
	assert_false(bar.is_day_shown())
	assert_eq(bar.date_text(), "14 JUN 2027 · 18:00–06:00")
	assert_eq(bar.turn_text(), "02")
	_map.set_viewer(0)


func test_the_view_follows_the_side_to_play() -> void:
	_map.set_viewer(0)
	var state := _map.simulation().state
	for i in 4:
		_map.end_turn()
		assert_eq(_map.viewer_player, state.current_player, "hot-seat: orders for the mover")
	_map.set_viewer(0)


func test_button_disabled_while_battle_pending() -> void:
	var state := _map.simulation().state
	assert_false(_map.turn_bar().end_button().disabled)
	state.pending_battles.append(BattleSetup.new())
	_map.refresh_texts()
	assert_true(_map.turn_bar().end_button().disabled)
	assert_true(_map.turn_bar().end_button().tooltip_text != "")
	assert_false(_map.end_turn())
	state.pending_battles.clear()
	_map.refresh_texts()
	assert_false(_map.turn_bar().end_button().disabled)


func test_snapshot_does_not_depend_on_the_viewer() -> void:
	var state := _map.simulation().state
	_map.set_viewer(0)
	var a := JSON.stringify(state.snapshot())
	_map.set_viewer(1)
	var b := JSON.stringify(state.snapshot())
	_map.set_viewer(0)
	assert_eq(a, b)


func test_turn_bar_shows_side_flags() -> void:
	_map.set_viewer(0)
	var state := _map.simulation().state
	var bar := _map.turn_bar()
	for i in 2:
		var side := SideDefinition.find(state.player_sides[i])
		assert_true(bar.side_flag(i).visible)
		assert_true(bar.side_flag(i).texture == side.flag)
