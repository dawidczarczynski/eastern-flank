extends TestCase
## The battle's hamburger menu: opens and closes like the staff map's, the exit asks first and a
## confirmed exit emits `leave_confirmed`; a battle that cannot be saved has no SAVE row.


func _menu(campaign: bool, can_save := false) -> BattleMenu:
	var menu := BattleMenu.new(campaign, can_save)
	(Engine.get_main_loop() as SceneTree).root.add_child(menu)
	return menu


func test_hamburger_opens_and_closes_the_menu() -> void:
	var menu := _menu(true)
	menu.button().pressed.emit()
	assert_true(menu.window().is_open())
	assert_true(menu.button().is_lit())
	assert_true(menu.is_open())
	menu.button().pressed.emit()
	assert_false(menu.is_open())
	assert_false(menu.button().is_lit())
	menu.free()


func test_save_row_only_when_the_battle_can_be_saved() -> void:
	var plain := _menu(true, false)
	assert_false(plain.window().save_button().visible)
	var scenario := _menu(false, true)
	assert_true(scenario.window().save_button().visible)
	plain.free()
	scenario.free()


func test_exit_asks_first_and_cancel_stays() -> void:
	var menu := _menu(true)
	var left: Array[int] = [0]
	menu.leave_confirmed.connect(func() -> void: left[0] += 1)
	menu.toggle()
	menu.window().exit_button().pressed.emit()
	assert_false(menu.window().is_open())
	assert_true(menu.confirm().visible)
	assert_false(menu.confirm().save_and_exit_button().visible)
	assert_true(menu.close_topmost(), "Esc cancels the question")
	assert_false(menu.is_open())
	assert_eq(left[0], 0)
	menu.free()


func test_confirmed_exit_emits_leave() -> void:
	var menu := _menu(false)
	var left: Array[int] = [0]
	menu.leave_confirmed.connect(func() -> void: left[0] += 1)
	menu.request_exit()
	menu.confirm().exit_button().pressed.emit()
	assert_eq(left[0], 1)
	assert_false(menu.confirm().visible)
	menu.free()
