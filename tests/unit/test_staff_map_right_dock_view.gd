# gdlint: disable=max-public-methods
extends TestCase
## The right tabbed dock on the staff map (TASK-174a): S / J, tab switching, Esc / X, selection,
## the leave-strike-mode rule, the inset and the camera. Reads the shipped Suwalki operation.

const Fixtures := preload("res://tests/fixtures.gd")

static var _map: StaffMap
static var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_map = StaffMap.new()
	_map.auto_build = false
	_map.viewer_player = 0
	(Engine.get_main_loop() as SceneTree).root.add_child(_map)
	assert_true(_map.build_now(), "staff map builds")
	Fixtures.add_generic_strike_means(_map.simulation().state)


func after_all() -> void:
	_map.free()
	_map = null
	TranslationServer.set_locale(_previous_locale)


func before_each() -> void:
	var state := _map.simulation().state
	_map.viewer_player = 0
	state.current_player = 0
	state.escalation_level = 1
	state.strikes_left = 2
	state.stand_down_until = [-1, -1]
	state.pending_battles.clear()
	_map.close_dock()
	_map.close_info()
	_map.select_formation(&"")
	_map.strike_hud().close()


func _dock() -> StaffMapRightDock:
	return _map.right_dock()


func _viewport() -> Vector2:
	return _map.call("_viewport_size")


func _press(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_map._unhandled_input(event)


func test_s_opens_the_strike_tab_and_s_again_closes() -> void:
	_press(KEY_S)
	assert_true(_dock().is_tab_open(StaffMapRightDock.Tab.STRIKE))
	assert_true(_map.strike_hud().panel().visible)
	assert_eq(_map.dock_inset(), 420.0)
	_press(KEY_S)
	assert_false(_dock().is_open())
	assert_eq(_map.dock_inset(), 0.0, "closed: no right inset")


func test_j_switches_the_tab_and_leaves_strike_mode() -> void:
	_press(KEY_S)
	_press(KEY_J)
	assert_true(_dock().is_tab_open(StaffMapRightDock.Tab.JOURNAL))
	assert_false(_map.strike_hud().is_open(), "never two sections")
	assert_false(_map.strike_hud().panel().visible)
	assert_true(_map.journal_window().visible)
	assert_eq(_map.dock_inset(), 420.0, "the dock stays put")
	_press(KEY_S)
	assert_true(_dock().is_tab_open(StaffMapRightDock.Tab.STRIKE))
	assert_true(_map.strike_hud().is_open(), "the opposite switch re-enters strike mode")
	assert_false(_map.journal_window().visible)
	_press(KEY_S)
	assert_false(_dock().is_open())


func test_j_twice_closes_and_the_bar_lights_follow() -> void:
	var bar := _map.action_bar()
	_press(KEY_J)
	assert_true(bar.button(StaffMap.ACTION_JOURNAL).button_pressed)
	assert_false(bar.button(StaffMap.ACTION_STRIKE).button_pressed)
	_press(KEY_J)
	assert_false(_dock().is_open())
	assert_false(bar.button(StaffMap.ACTION_JOURNAL).button_pressed)


func test_esc_and_x_close_the_dock() -> void:
	_press(KEY_J)
	_press(KEY_ESCAPE)
	assert_false(_dock().is_open(), "Esc")
	_press(KEY_J)
	_map.journal_window().close_button().pressed.emit()
	assert_false(_dock().is_open(), "X on the journal")
	_press(KEY_S)
	_map.strike_hud().panel().close_button().pressed.emit()
	assert_false(_dock().is_open(), "X on the strike panel leaves the mode and the dock")
	assert_false(_map.strike_hud().is_open())


func test_a_click_on_the_bare_map_leaves_the_dock_open() -> void:
	_press(KEY_J)
	_map.close_docked_windows()
	assert_true(_dock().is_tab_open(StaffMapRightDock.Tab.JOURNAL))
	assert_true(_map.journal_window().visible)


func test_selecting_a_unit_closes_the_dock_and_it_stays_closed() -> void:
	_press(KEY_J)
	var own := _map.simulation().state.formations[0]
	_map.select_formation(own.id)
	assert_false(_dock().is_open())
	assert_false(_map.journal_window().visible)
	_map.select_formation(&"")
	assert_false(_dock().is_open(), "deselecting does not reopen")
	_press(KEY_J)
	assert_true(_dock().is_tab_open(StaffMapRightDock.Tab.JOURNAL), "J opens it again")


func test_info_closes_the_dock() -> void:
	_press(KEY_J)
	_map.open_info(_map.simulation().state.formations[0].id)
	assert_false(_dock().is_open())
	assert_true(_map.formation_panel().visible)


func test_a_selection_in_strike_mode_keeps_the_dock() -> void:
	_press(KEY_S)
	_map.select_formation(_map.simulation().state.formations[0].id)
	assert_true(_dock().is_tab_open(StaffMapRightDock.Tab.STRIKE))


func test_info_in_strike_mode_docks_the_formation_panel_on_the_left() -> void:
	_press(KEY_S)
	var id: StringName = _map.simulation().state.formations[0].id
	_map.open_info(id)
	assert_true(_dock().is_tab_open(StaffMapRightDock.Tab.STRIKE))
	assert_eq(_map.formation_panel().dock_side, StaffMapWindow.Dock.LEFT)


func test_last_tab_is_remembered_for_the_next_open() -> void:
	_press(KEY_J)
	_press(KEY_J)
	assert_eq(_dock().remembered_tab(), StaffMapRightDock.Tab.JOURNAL)
	_map.right_dock_view().tab_pressed.emit(_dock().remembered_tab())
	assert_true(_dock().is_tab_open(StaffMapRightDock.Tab.JOURNAL))


func test_tab_buttons_open_and_switch() -> void:
	_map.right_dock_view().tab_pressed.emit(StaffMapRightDock.Tab.STRIKE)
	assert_true(_dock().is_tab_open(StaffMapRightDock.Tab.STRIKE))
	_map.right_dock_view().tab_pressed.emit(StaffMapRightDock.Tab.JOURNAL)
	assert_true(_dock().is_tab_open(StaffMapRightDock.Tab.JOURNAL))


func test_the_journal_no_longer_takes_the_left_dock() -> void:
	_map.open_objectives()
	assert_true(_map.objectives_window().visible)
	_press(KEY_J)
	assert_true(_map.objectives_window().visible, "objectives stay on the left")
	assert_true(_map.journal_window().visible)
	_map.objectives_window().close()


func test_the_dock_sits_under_the_turn_bar_flush_right() -> void:
	_press(KEY_J)
	var rect := _map.journal_window().get_global_rect()
	assert_eq(rect.end.x, _viewport().x)
	assert_eq(rect.position.y, 92.0)
	assert_eq(rect.size.x, 420.0)


func test_opening_keeps_the_centre_of_the_visible_map() -> void:
	var width := _viewport().x
	_map.debug_focus(Vector2(60, 60), _map.zoom_limits().y * 0.5)
	var before := _map.ground_at_screen(Vector2(width * 0.5, 300))
	_press(KEY_J)
	var after := _map.ground_at_screen(Vector2((width - 420.0) * 0.5, 300))
	assert_true(before.distance_to(after) < 0.01, "same ground in the middle of the free area")
	_press(KEY_J)
	var back := _map.ground_at_screen(Vector2(width * 0.5, 300))
	assert_true(before.distance_to(back) < 0.01, "and again after closing")


# --- POLITICS tab (TASK-174b) ---


func test_h_opens_politics_and_h_again_closes() -> void:
	_press(KEY_H)
	assert_true(_dock().is_tab_open(StaffMapRightDock.Tab.POLITICS))
	assert_true(_map.decisions_hud().is_open())
	assert_eq(_map.dock_inset(), StaffMapRightDock.WIDTH)
	_press(KEY_H)
	assert_false(_dock().is_open())
	assert_false(_map.decisions_hud().is_open())


func test_s_and_j_switch_from_politics_and_p_does_not_open_the_dock() -> void:
	_press(KEY_H)
	_press(KEY_J)
	assert_true(_dock().is_tab_open(StaffMapRightDock.Tab.JOURNAL))
	assert_false(_map.decisions_hud().is_open())
	_press(KEY_H)
	_press(KEY_S)
	assert_true(_dock().is_tab_open(StaffMapRightDock.Tab.STRIKE))
	assert_false(_map.decisions_hud().is_open())
	_map.close_dock()
	var tint := _map.politics_hud().tint_enabled()
	_press(KEY_P)
	assert_false(_dock().is_open(), "P is only the tint toggle")
	assert_eq(_map.politics_hud().tint_enabled(), not tint)
	_press(KEY_P)


func test_politics_tab_fits_the_dock_and_has_three_sub_tabs() -> void:
	_press(KEY_H)
	var panel := _map.decisions_hud().panel()
	assert_true(StaffMapDecisionsPanel.COLUMN_WIDTH <= 388.0)
	assert_true(panel.size.x <= StaffMapRightDock.WIDTH)
	assert_eq(panel.tab(), StaffMapDecisionsPanel.TAB_DECISIONS, "DECISIONS first")
	var state := _map.simulation().state
	var wanted := 3 if state.support.is_empty() else 4
	assert_eq(panel.find_child("Tabs", true, false).get_child_count() - 1, wanted)
	panel.open_tab(StaffMapDecisionsPanel.TAB_OVERVIEW)
	assert_true(panel.find_child("Overview", true, false) != null)
	_map.close_dock()
	_press(KEY_H)
	assert_eq(panel.tab(), StaffMapDecisionsPanel.TAB_OVERVIEW, "the sub-tab is kept")
	panel.open_tab(StaffMapDecisionsPanel.TAB_DECISIONS)


func test_selecting_a_unit_closes_politics() -> void:
	_press(KEY_H)
	var own := _map.simulation().state.formations[0]
	_map.select_formation(own.id)
	assert_false(_dock().is_open())
	assert_false(_map.decisions_hud().is_open())
	_map.select_formation(&"")


func test_esc_closes_politics_and_the_tab_strip_has_three_tabs() -> void:
	_press(KEY_H)
	assert_true(_map.right_dock_view().tab_button(StaffMapRightDock.Tab.POLITICS) != null)
	_press(KEY_ESCAPE)
	assert_false(_dock().is_open())


func test_politics_tab_never_widens_over_the_tab_strip() -> void:
	_press(KEY_H)
	var panel := _map.decisions_hud().panel()
	panel.open_tab(StaffMapDecisionsPanel.TAB_LADDER)
	var overview := panel.find_child("Overview", true, false) as StaffMapOverviewColumn
	overview.ladder_expanded = true
	overview.ladder_toggled.emit()
	_map.right_dock_view().layout(_viewport())
	assert_eq(panel.size.x, StaffMapRightDock.WIDTH)
	var tab := _map.right_dock_view().tab_button(StaffMapRightDock.Tab.POLITICS)
	assert_true(tab.position.x + tab.size.x <= panel.position.x + 0.5, "the tabs stay beside it")
	panel.open_tab(StaffMapDecisionsPanel.TAB_DECISIONS)


func test_level_chip_opens_the_ladder_sub_tab_and_a_second_click_closes() -> void:
	_map.toggle_ladder()
	assert_true(_dock().is_tab_open(StaffMapRightDock.Tab.POLITICS))
	var panel := _map.decisions_hud().panel()
	assert_eq(panel.tab(), StaffMapDecisionsPanel.TAB_LADDER)
	assert_true(panel.find_child("Ladder", true, false) != null)
	assert_true(panel.find_child("Countries", true, false) == null, "countries are on OVERVIEW")
	_map.toggle_ladder()
	assert_false(_dock().is_open())
	panel.open_tab(StaffMapDecisionsPanel.TAB_DECISIONS)
