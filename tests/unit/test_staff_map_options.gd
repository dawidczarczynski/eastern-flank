extends TestCase
## The bottom bar of the staff map: Strike has its own button and the map layer toggles sit
## behind one MAP OPTIONS button that opens a window.

static var _map: StaffMap


func before_all() -> void:
	_map = StaffMap.new()
	_map.auto_build = false
	_map.viewer_player = 0
	(Engine.get_main_loop() as SceneTree).root.add_child(_map)
	assert_true(_map.build_now(), "staff map builds")


func after_all() -> void:
	_map.free()
	_map = null


func test_map_toggles_live_in_the_options_window() -> void:
	var bar := _map.action_bar()
	assert_true(bar.button(StaffMap.ACTION_STRIKE) != null, "Strike is on the bottom bar")
	assert_true(bar.button(StaffMap.ACTION_MAP_OPTIONS) != null)
	assert_true(bar.button(StaffMap.ACTION_GRID) == null, "grid moved into the window")
	var window := _map.options_window()
	assert_false(window.visible)
	_map.toggle_options()
	assert_true(window.visible)
	assert_eq(window.ids().size(), 6, "grid, names, borders, politics, view, air defence cover")
	var before := _map.view().grid_visible()
	window.option(StaffMap.ACTION_GRID).pressed.emit()
	assert_eq(_map.view().grid_visible(), not before)
	window.option(StaffMap.ACTION_GRID).pressed.emit()
	assert_true(window.close())


func _press_on_map() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = Vector2(700, 500)
	_map.call(&"_on_mouse_button", event)


func test_options_window_has_the_hint_and_lights_the_bar_button() -> void:
	var window := _map.options_window()
	_map.toggle_options()
	assert_true(_map.action_bar().button(StaffMap.ACTION_MAP_OPTIONS).button_pressed, "button lit")
	assert_eq(window.position, Vector2(16, 110))
	assert_true(window.find_child("Hint", true, false) != null, "hint line")
	_map.toggle_options()
	assert_false(window.is_open())
	assert_false(_map.action_bar().button(StaffMap.ACTION_MAP_OPTIONS).button_pressed, "button dim")


func test_x_closes_the_options_window() -> void:
	_map.toggle_options()
	_map.options_window().close_button().pressed.emit()
	assert_false(_map.options_window().is_open())
	assert_false(_map.action_bar().button(StaffMap.ACTION_MAP_OPTIONS).button_pressed)


func test_click_on_the_map_closes_every_docked_window() -> void:
	_map.toggle_options()
	_press_on_map()
	assert_false(_map.options_window().is_open(), "options close on a map click")
	_map.open_country_card(_map.simulation().state.countries[0].id)
	assert_true(_map.country_card().visible)
	_press_on_map()
	assert_false(_map.country_card().visible, "the country card closes on a map click")


func test_one_docked_window_at_a_time_on_the_left() -> void:
	_map.open_country_card(_map.simulation().state.countries[0].id)
	_map.toggle_options()
	assert_true(_map.options_window().is_open())
	assert_false(_map.country_card().visible, "options take the card's place")
	_map.open_country_card(_map.simulation().state.countries[0].id)
	assert_false(_map.options_window().is_open(), "the card takes the options' place")
	assert_false(_map.action_bar().button(StaffMap.ACTION_MAP_OPTIONS).button_pressed)
	_map.country_card().hide()


func test_x_on_the_formation_panel_deselects() -> void:
	var own := _map.simulation().state.formations[0]
	_map.select_formation(own.id)
	var panel := _map.formation_panel()
	assert_true(panel.visible)
	assert_eq(panel.position.y, StaffMapWindow.TOP)
	panel.close_button().pressed.emit()
	assert_false(panel.visible)
	assert_eq(_map.selected_formation(), &"")
