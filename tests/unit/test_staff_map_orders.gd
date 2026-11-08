extends TestCase
## Orders on the staff map (TASK-092d): route styles (preview vs issued), dashes, the posture
## picker, the controller (order / posture / cancel through commands, toast on rejection, arrows
## restored from the state alone, enemy orders hidden). One StaffMap is shared by the tests.

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


func after_all() -> void:
	_map.free()
	_map = null
	TranslationServer.set_locale(_previous_locale)


func after_each() -> void:
	_reset()


func _reset() -> void:
	for formation in _map.simulation().state.formations:
		formation.order = null
		formation.posture = &"defend"
	_map.select_formation(&"")
	_map.set_viewer(_map.simulation().state.current_player)


func _own() -> Formation:
	for formation in _map.simulation().state.formations:
		if formation.owner_id == _map.simulation().state.current_player:
			return formation
	return null


func _enemy() -> Formation:
	for formation in _map.simulation().state.formations:
		if formation.owner_id != _map.simulation().state.current_player:
			return formation
	return null


func _far_hex(formation: Formation, distance := 4) -> Vector2i:
	var state := _map.simulation().state
	for c: Vector2i in state.grid.coords():
		if Hex.distance(c, formation.coord) == distance and state.formation_at(c) == null:
			if not OperationalRoutes.plan(state, formation, c, false).is_empty():
				if not OperationalRoutes.plan(state, formation, c, true).is_empty():
					return c
	return StaffMapRoutePreview.OFF


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_map._unhandled_input(event)


# --- pure: style, dashes, keys ---


func test_style_preview_versus_issued() -> void:
	var preview := StaffMapRoute.style(&"advance", false)
	var issued := StaffMapRoute.style(&"advance", true)
	assert_eq(preview["alpha"], 1.0)
	assert_true(preview["dots"])
	assert_true(preview["amber_target"])
	assert_eq(issued["alpha"], 0.82)
	assert_false(issued["dots"])
	assert_false(issued["amber_target"])


func test_style_per_posture() -> void:
	assert_true(StaffMapRoute.style(&"march", false)["dashed"])
	assert_false(StaffMapRoute.style(&"advance", false)["dashed"])
	assert_false(StaffMapRoute.style(&"defend", false)["dashed"])
	assert_true(StaffMapRoute.style(&"defend", true)["defend_arc"])
	assert_false(StaffMapRoute.style(&"march", true)["defend_arc"])


func test_posture_for_key() -> void:
	assert_eq(StaffMapRoute.posture_for_key(1), &"march")
	assert_eq(StaffMapRoute.posture_for_key(2), &"advance")
	assert_eq(StaffMapRoute.posture_for_key(3), &"defend")
	assert_eq(StaffMapRoute.posture_for_key(4), &"")
	assert_eq(StaffMapRoute.posture_for_key(0), &"")


func test_dashes_cut_a_line() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	var dashes := StaffMapRoute.dashes(line, 2.0, 1.0)
	assert_eq(dashes.size(), 4, "0-2, 3-5, 6-8, 9-10")
	assert_eq((dashes[0] as PackedVector2Array)[1], Vector2(2, 0))
	assert_eq((dashes[1] as PackedVector2Array)[0], Vector2(3, 0))
	var last: PackedVector2Array = dashes[3]
	assert_eq(last[last.size() - 1], Vector2(10, 0), "ends on the last point")
	assert_eq(
		StaffMapRoute.dashes(PackedVector2Array([Vector2.ZERO, Vector2(1, 0)]), 2.0, 1.0).size(), 1
	)


func test_dashes_follow_a_corner() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(3, 0), Vector2(3, 3)])
	var dashes := StaffMapRoute.dashes(line, 4.0, 1.0)
	var corner := false
	for dash: PackedVector2Array in dashes:
		corner = corner or dash.has(Vector2(3, 0))
	assert_true(corner, "a dash bends round the corner")


func test_preview_in_posture_uses_the_posture_numbers() -> void:
	var state := _map.simulation().state
	var formation := _own()
	var target := _far_hex(formation, 6)
	assert_true(target != StaffMapRoutePreview.OFF)
	var march := StaffMapRoute.preview_in_posture(state, formation, target, &"march")
	var defend := StaffMapRoute.preview_in_posture(state, formation, target, &"defend")
	assert_true(march["turns"] <= defend["turns"], "defend is the slowest")
	var budget := OperationalPosture.find(&"defend").budget(formation.definition.move_points)
	assert_eq(defend["stops"], OperationalRoutes.forecast(state, formation, target, budget, true))
	assert_true(StaffMapRoute.preview_in_posture(state, formation, target, &"nope").is_empty())


# --- picker ---


func test_picker_captions_and_current_posture() -> void:
	var picker := StaffMapPosturePicker.new()
	picker.show_posture(&"advance")
	assert_eq(picker.captions(), PackedStringArray(["[1] MARCH", "[2] ATTACK", "[3] DEFEND"]))
	assert_eq(picker.pressed_posture(), &"advance")
	picker.show_posture(&"defend")
	assert_eq(picker.pressed_posture(), &"defend")
	picker.free()


func test_picker_button_emits_the_posture() -> void:
	var picker := StaffMapPosturePicker.new()
	var chosen: Array[StringName] = []
	picker.posture_chosen.connect(func(id: StringName) -> void: chosen.append(id))
	picker.button(&"march").pressed.emit()
	assert_eq(chosen, [&"march"] as Array[StringName])
	picker.free()


# --- controller ---


func test_selecting_an_own_formation_shows_the_picker_and_rows() -> void:
	var formation := _own()
	_map.select_formation(formation.id)
	assert_true(_map.posture_picker().visible)
	assert_eq(_map.posture_picker().pressed_posture(), &"defend")
	assert_true(_map.formation_panel().order_visible())
	assert_eq(_map.formation_panel().value_text("POSTURE"), "[3] DEFEND")
	assert_eq(_map.formation_panel().value_text("ORDER"), "NONE")
	_map.select_formation(_enemy().id)
	assert_false(_map.posture_picker().visible, "the enemy has no picker")
	assert_false(_map.formation_panel().order_visible())


func test_issue_order_creates_a_command_and_keeps_the_arrow_after_deselect() -> void:
	var formation := _own()
	var target := _far_hex(formation)
	_map.select_formation(formation.id)
	var history := _map.simulation().history.size()
	assert_true(_map.issue_order(target))
	assert_eq(_map.simulation().history.size(), history + 1)
	assert_eq(formation.order.destination, target)
	_map.select_formation(&"")
	assert_eq(_map.orders().shown_ids(), [formation.id] as Array[StringName])
	assert_true(_map.counters().counter(formation.id).has_order, "order mark on the counter")
	assert_eq(_map.turn_bar().end_button().detail.begins_with("ORDERS 1 / "), true)


func test_posture_keys_send_set_posture() -> void:
	var formation := _own()
	_map.select_formation(formation.id)
	_key(KEY_1)
	assert_eq(formation.posture, &"march")
	assert_eq(_map.posture_picker().pressed_posture(), &"march")
	_key(KEY_2)
	assert_eq(formation.posture, &"advance")
	assert_eq(_map.formation_panel().value_text("POSTURE"), "[2] ATTACK")
	var history := _map.simulation().history.size()
	_key(KEY_2)
	assert_eq(_map.simulation().history.size(), history, "same posture: no command")


func test_posture_change_keeps_the_order_and_restyles_the_arrow() -> void:
	var formation := _own()
	var target := _far_hex(formation)
	_map.select_formation(formation.id)
	_key(KEY_1)
	_map.issue_order(target)
	assert_true(_map.orders().style_of(formation.id)["dashed"])
	_key(KEY_3)
	assert_eq(formation.order.destination, target)
	assert_true(_map.orders().style_of(formation.id)["defend_arc"])
	assert_false(_map.orders().style_of(formation.id)["dashed"])


func test_cancel_keys_remove_the_order() -> void:
	var formation := _own()
	var target := _far_hex(formation)
	for key in [KEY_DELETE, KEY_BACKSPACE, KEY_X]:
		_map.select_formation(formation.id)
		_map.issue_order(target)
		assert_true(formation.order != null)
		_key(key)
		assert_true(formation.order == null)
		assert_eq(_map.orders().shown_ids().size(), 0)
		assert_false(_map.counters().counter(formation.id).has_order)


func test_rejection_shows_a_toast_and_changes_nothing() -> void:
	var formation := _own()
	_map.select_formation(formation.id)
	var before := _map.simulation().state.snapshot()
	assert_false(_map.issue_order(formation.coord))
	assert_true(_map.toast().visible)
	assert_eq(_map.simulation().state.snapshot(), before)
	_key(KEY_X)
	assert_eq(_map.simulation().state.snapshot(), before, "nothing to cancel")


func test_the_waiting_side_cannot_order() -> void:
	var state := _map.simulation().state
	var formation := _own()
	_map.select_formation(formation.id)
	var current := state.current_player
	state.current_player = 1 - current
	assert_false(_map.issue_order(_far_hex(formation)))
	state.current_player = current


func test_arrows_are_restored_from_the_state_alone() -> void:
	var formation := _own()
	var target := _far_hex(formation)
	formation.order = FormationOrder.new(target)  # no command: a state loaded mid-game
	formation.posture = &"march"
	_map.set_viewer(_own().owner_id)  # the view re-reads the state
	assert_eq(_map.orders().shown_ids(), [formation.id] as Array[StringName])
	assert_true(_map.counters().counter(formation.id).has_order)
	assert_true(_map.orders().style_of(formation.id)["dashed"])
	assert_false(_map.orders().style_of(formation.id)["dots"], "issued: no dots")


func test_enemy_orders_stay_hidden() -> void:
	var enemy := _enemy()
	var target := _far_hex(enemy)
	enemy.order = FormationOrder.new(target)
	_map.set_viewer(_own().owner_id)
	assert_eq(_map.orders().shown_ids().size(), 0)
	_map.select_formation(enemy.id)
	assert_false(
		_map.counters().counter(enemy.id).is_own(), "the mark is drawn for own counters only"
	)
	assert_false(_map.formation_panel().order_visible())
