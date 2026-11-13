extends TestCase
## The operation menu of the staff map: the hamburger replaces Back, Save moved from the bottom
## bar into the menu, and Exit operation asks first (offering a save when unsaved).

const SAVE_DIR := "user://test_staff_map_menu"


func _build() -> StaffMap:
	var map := StaffMap.new()
	map.auto_build = false
	map.viewer_player = 0
	map.save_dir = SAVE_DIR
	(Engine.get_main_loop() as SceneTree).root.add_child(map)
	assert_true(map.build_now(), "staff map builds")
	return map


func _cleanup(map: StaffMap) -> void:
	map.free()
	DirAccess.remove_absolute(CampaignSaver.path_for("suwalki_gap", SAVE_DIR))


func test_save_left_the_bottom_bar_and_the_menu_has_it() -> void:
	var map := _build()
	assert_true(map.action_bar().button(&"save") == null, "no SAVE in the bottom bar")
	assert_true(map.menu_button() != null)
	assert_false(map.menu_window().is_open())
	_cleanup(map)


func test_hamburger_opens_and_closes_the_menu() -> void:
	var map := _build()
	map.toggle_menu()
	assert_true(map.menu_window().is_open())
	assert_true(map.menu_button().is_lit())
	map.toggle_menu()
	assert_false(map.menu_window().is_open())
	assert_false(map.menu_button().is_lit())
	_cleanup(map)


func test_the_centred_menu_does_not_move_the_camera() -> void:
	var map := _build()
	map.toggle_menu()
	map._sync_insets()
	var insets := map._insets
	assert_eq(insets.z, 0.0, "the centred menu is no left dock")
	assert_eq(insets.w, 0.0, "the centred menu is no right dock")
	_cleanup(map)


func test_opening_the_options_closes_the_menu() -> void:
	var map := _build()
	map.toggle_menu()
	map.toggle_options()
	assert_false(map.menu_window().is_open())
	assert_true(map.options_window().is_open())
	_cleanup(map)


func test_exit_asks_first_and_cancel_keeps_the_operation() -> void:
	var map := _build()
	map.toggle_menu()
	map.menu_window().exit_button().pressed.emit()
	assert_false(map.menu_window().is_open())
	var confirm := map.exit_confirm()
	assert_true(confirm.visible)
	assert_false(confirm.save_and_exit_button().visible, "nothing unsaved: no save offer")
	assert_true(map.cancel_exit())
	assert_false(confirm.visible)
	_cleanup(map)


func test_unsaved_progress_offers_a_save_and_saving_clears_it() -> void:
	var map := _build()
	assert_false(map.has_unsaved_changes(), "a fresh map is clean")
	assert_true(map.simulation().execute(EndOperationalTurnCommand.new()))
	assert_true(map.has_unsaved_changes())
	map.request_exit()
	assert_true(map.exit_confirm().save_and_exit_button().visible)
	map.cancel_exit()
	map.toggle_menu()
	map.menu_window().save_button().pressed.emit()
	assert_false(map.has_unsaved_changes())
	assert_false(map.menu_window().is_open(), "Save closes the menu")
	map.request_exit()
	assert_false(map.exit_confirm().save_and_exit_button().visible, "saved: nothing to offer")
	_cleanup(map)
