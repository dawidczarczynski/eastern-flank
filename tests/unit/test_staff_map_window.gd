extends TestCase
## StaffMapWindow: the one frame of every docked window of the staff map (bottom_bar_windows.html,
## variant A) – fill, line, chamfers, X, width tier, dock positions and the shared rows.


func _windows() -> Array[StaffMapWindow]:
	var list: Array[StaffMapWindow] = [
		StaffMapOptionsWindow.new(),
		StaffMapCountryCard.new(),
		StaffMapFormationPanel.new(),
		StaffMapStrikePanel.new(),
		StaffMapStrikeConfirm.new(),
		StaffMapStrikeReport.new(),
	]
	return list


func test_every_window_shares_the_frame() -> void:
	for window in _windows():
		assert_eq(window.fill, UiPalette.PANEL_STRONG, "%s fill" % window.name)
		assert_eq(window.line_color, UiPalette.LINE, "%s line" % window.name)
		assert_eq(window.chamfers, StaffMapWindow.CHAMFERS, "%s chamfers" % window.name)
		assert_true(window.close_button() != null, "%s has an X" % window.name)
		assert_eq(window.close_button().size.x, StaffMapCloseButton.SIZE)
		assert_false(window.is_open(), "%s starts closed" % window.name)
		assert_eq(window.mouse_filter, Control.MOUSE_FILTER_STOP)
		window.free()


func test_width_tiers() -> void:
	assert_eq(StaffMapOptionsWindow.new().custom_minimum_size.x, StaffMapWindow.WIDTH_DEFAULT)
	assert_eq(StaffMapStrikePanel.new().custom_minimum_size.x, StaffMapWindow.WIDTH_DEFAULT)
	assert_eq(StaffMapCountryCard.new().custom_minimum_size.x, StaffMapWindow.WIDTH_DEFAULT)
	assert_eq(StaffMapStrikeReport.new().custom_minimum_size.x, StaffMapWindow.WIDTH_REPORT)


func test_dock_positions() -> void:
	assert_eq(
		StaffMapWindow.dock_position(StaffMapWindow.Dock.LEFT, 1600.0, 330.0), Vector2(16, 110)
	)
	assert_eq(
		StaffMapWindow.dock_position(StaffMapWindow.Dock.RIGHT, 1600.0, 300.0),
		Vector2(1600.0 - 16.0 - 300.0, 110)
	)
	var panel := StaffMapFormationPanel.new()
	assert_eq(panel.dock_side, StaffMapWindow.Dock.RIGHT, "the formation panel docks right")
	panel.dock(1920.0)
	assert_eq(panel.position, Vector2(1920.0 - 16.0 - StaffMapFormationPanel.WIDTH, 110))
	panel.free()
	var options := StaffMapOptionsWindow.new()
	options.open(1920.0)
	assert_eq(options.position, Vector2(16, 110), "options sit on the left dock")
	assert_true(options.is_open())
	assert_true(options.close())
	assert_false(options.close(), "closing a closed window reports false")
	options.free()


func test_x_emits_close_requested() -> void:
	var window := StaffMapOptionsWindow.new()
	var emitted := [false]
	window.close_requested.connect(func() -> void: emitted[0] = true)
	window.close_button().pressed.emit()
	assert_true(emitted[0])
	window.free()


func test_toggle_row_shows_state_and_key() -> void:
	var row := StaffMapWindow.toggle_row("GRID", "G")
	assert_eq(row.custom_minimum_size.y, 36.0)
	assert_eq(row.state_text(), "OFF")
	row.set_on(true)
	assert_eq(row.state_text(), "ON")
	assert_true(row.button_pressed)
	row.free()


func test_info_row_holds_label_and_value() -> void:
	var row := StaffMapWindow.info_row("Type")
	StaffMapWindow.row_value(row).text = "ARMOUR"
	assert_eq(StaffMapWindow.row_value(row).text, "ARMOUR")
	assert_eq(row.get_child_count(), 2)
	row.free()
