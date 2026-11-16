extends TestCase
## The right-hand tabbed dock model (TASK-174a): open / switch / close, tab memory, selection
## rule, inset and minimum map width.


func test_open_shows_that_tab() -> void:
	var dock := StaffMapRightDock.new()
	assert_false(dock.is_open())
	dock.open(StaffMapRightDock.Tab.JOURNAL)
	assert_true(dock.is_open())
	assert_eq(dock.tab(), StaffMapRightDock.Tab.JOURNAL)


func test_open_another_tab_switches_never_two_sections() -> void:
	var dock := StaffMapRightDock.new()
	dock.open(StaffMapRightDock.Tab.STRIKE)
	dock.open(StaffMapRightDock.Tab.JOURNAL)
	assert_true(dock.is_open())
	assert_eq(dock.tab(), StaffMapRightDock.Tab.JOURNAL)
	assert_false(dock.is_tab_open(StaffMapRightDock.Tab.STRIKE))
	assert_true(dock.is_tab_open(StaffMapRightDock.Tab.JOURNAL))


func test_close_closes_and_reports_whether_it_was_open() -> void:
	var dock := StaffMapRightDock.new()
	assert_false(dock.close())
	dock.open(StaffMapRightDock.Tab.STRIKE)
	assert_true(dock.close())
	assert_false(dock.is_open())


func test_key_of_the_open_tab_closes_other_key_switches() -> void:
	var dock := StaffMapRightDock.new()
	assert_true(dock.toggle(StaffMapRightDock.Tab.STRIKE), "opens")
	assert_true(dock.toggle(StaffMapRightDock.Tab.JOURNAL), "switches, stays open")
	assert_eq(dock.tab(), StaffMapRightDock.Tab.JOURNAL)
	assert_false(dock.toggle(StaffMapRightDock.Tab.JOURNAL), "the key of the open tab closes")
	assert_false(dock.is_open())


func test_last_tab_is_remembered_default_strike() -> void:
	var dock := StaffMapRightDock.new()
	assert_eq(dock.remembered_tab(), StaffMapRightDock.Tab.STRIKE)
	dock.open(StaffMapRightDock.Tab.JOURNAL)
	dock.close()
	assert_eq(dock.remembered_tab(), StaffMapRightDock.Tab.JOURNAL)
	dock.open_remembered()
	assert_true(dock.is_tab_open(StaffMapRightDock.Tab.JOURNAL))


func test_selection_closes_unless_strike_mode() -> void:
	var dock := StaffMapRightDock.new()
	dock.open(StaffMapRightDock.Tab.JOURNAL)
	assert_true(dock.on_selection(false))
	assert_false(dock.is_open())
	dock.open(StaffMapRightDock.Tab.STRIKE)
	assert_false(dock.on_selection(true), "a strike-mode click never closes")
	assert_true(dock.is_open())


func test_stays_closed_after_a_selection_closed_it() -> void:
	var dock := StaffMapRightDock.new()
	dock.open(StaffMapRightDock.Tab.JOURNAL)
	dock.on_selection(false)
	assert_false(dock.on_selection(false), "nothing to close, nothing reopens")
	assert_false(dock.is_open())
	assert_eq(dock.remembered_tab(), StaffMapRightDock.Tab.JOURNAL)


func test_inset_is_420_open_and_0_closed() -> void:
	var dock := StaffMapRightDock.new()
	assert_eq(dock.inset(), 0.0)
	dock.open(StaffMapRightDock.Tab.STRIKE)
	assert_eq(dock.inset(), 420.0)
	assert_eq(1440.0 - dock.inset(), 1020.0)


func test_minimum_map_width_is_viewport_minus_the_dock() -> void:
	assert_eq(StaffMapRightDock.min_map_width(1440.0), 1020.0)
	assert_eq(StaffMapRightDock.min_map_width(1920.0), 1500.0)


func test_politics_tab_switches_with_the_others() -> void:
	var dock := StaffMapRightDock.new()
	dock.open(StaffMapRightDock.Tab.STRIKE)
	dock.open(StaffMapRightDock.Tab.POLITICS)
	assert_true(dock.is_tab_open(StaffMapRightDock.Tab.POLITICS))
	assert_false(dock.is_tab_open(StaffMapRightDock.Tab.STRIKE), "never two sections")
	dock.open(StaffMapRightDock.Tab.JOURNAL)
	assert_false(dock.is_tab_open(StaffMapRightDock.Tab.POLITICS))
	dock.open(StaffMapRightDock.Tab.POLITICS)
	assert_eq(dock.inset(), StaffMapRightDock.WIDTH)
	dock.close()
	assert_eq(dock.remembered_tab(), StaffMapRightDock.Tab.POLITICS, "POLITICS is remembered")
