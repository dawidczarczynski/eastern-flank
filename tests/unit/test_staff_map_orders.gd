# gdlint: disable=max-public-methods
extends TestCase
## Orders on the staff map (TASK-092d): route styles (preview vs issued), dashes, the controller
## (left click = march / attack, the right-click order ring, cancel through commands, toast on
## rejection, arrows restored from the state alone, enemy orders hidden). One StaffMap is shared.

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


# --- controller ---


func _click_hex(c: Vector2i) -> void:
	_map.click_at(_map.hex_screen_position(c))


func _slot(index: int) -> Dictionary:
	return _map.order_ring().slots()[index]


func test_selecting_an_own_formation_shows_the_panel_rows_but_no_picker() -> void:
	var formation := _own()
	_map.select_formation(formation.id)
	assert_true(_map.formation_panel().order_visible())
	assert_eq(_map.formation_panel().value_text("POSTURE"), "[3] DEFEND")
	assert_eq(_map.formation_panel().value_text("ORDER"), "NONE")
	assert_false(_map.order_ring().is_open())
	_map.select_formation(_enemy().id)
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


func test_left_click_on_a_hex_marches_whatever_the_posture() -> void:
	var formation := _own()
	var target := _far_hex(formation)
	formation.posture = &"defend"
	_map.select_formation(formation.id)
	_click_hex(target)
	assert_eq(formation.order.destination, target)
	assert_eq(formation.posture, &"march")
	assert_eq(_map.selected_formation(), &"", "done with this one")
	assert_eq(_map.formation_panel().value_text("POSTURE"), "[1] MARCH")


func test_left_click_on_an_enemy_orders_an_attack() -> void:
	var formation := _own()
	var enemy := _enemy()
	formation.posture = &"march"
	_map.select_formation(formation.id)
	_map.click_at(_map.counter_screen_position(enemy.id))
	assert_true(formation.order != null, "order given")
	assert_eq(formation.order.destination, enemy.coord)
	assert_eq(formation.posture, &"advance")


func test_left_click_on_an_own_counter_selects_it() -> void:
	var formation := _own()
	var other := _enemy()
	_map.select_formation(other.id)
	_map.click_at(_map.counter_screen_position(formation.id))
	assert_eq(_map.selected_formation(), formation.id)


func test_right_click_opens_the_ring_on_the_hex() -> void:
	var formation := _own()
	var target := _far_hex(formation)
	_map.select_formation(formation.id)
	var history := _map.simulation().history.size()
	assert_true(_map.right_click_at(_map.hex_screen_position(target)))
	var ring := _map.order_ring()
	assert_true(ring.is_open())
	assert_eq(ring.hex(), target)
	assert_eq(_map.simulation().history.size(), history, "opening gives no command")
	for i in 3:
		assert_true(_slot(i)["enabled"], "free hex: march / attack / defend")
	assert_true(_slot(3)["empty"], "no order, no cancel segment")
	assert_true(_slot(5)["empty"])


func test_ring_slot_issues_that_posture() -> void:
	var formation := _own()
	var target := _far_hex(formation)
	for pair in [[0, &"march"], [1, &"advance"], [2, &"defend"]]:
		_map.select_formation(formation.id)
		_map.right_click_at(_map.hex_screen_position(target))
		_map.order_ring().activate(pair[0])
		assert_false(_map.order_ring().is_open())
		assert_eq(formation.posture, pair[1])
		assert_eq(formation.order.destination, target)
		assert_eq(_map.selected_formation(), &"", "deselected after the order")
		formation.order = null


func test_ring_keys_pick_a_segment_and_esc_closes() -> void:
	var formation := _own()
	var target := _far_hex(formation)
	_map.select_formation(formation.id)
	_map.right_click_at(_map.hex_screen_position(target))
	_key(KEY_ESCAPE)
	assert_false(_map.order_ring().is_open())
	assert_eq(_map.selected_formation(), formation.id, "Esc closed the ring only")
	_map.right_click_at(_map.hex_screen_position(target))
	_key(KEY_3)
	assert_eq(formation.posture, &"defend")
	assert_eq(formation.order.destination, target)


func test_left_click_elsewhere_closes_the_ring_without_ordering() -> void:
	var formation := _own()
	_map.select_formation(formation.id)
	_map.right_click_at(_map.hex_screen_position(_far_hex(formation)))
	_map.click_at(_map.hex_screen_position(_far_hex(formation, 3)))
	assert_false(_map.order_ring().is_open())
	assert_true(formation.order == null)
	assert_eq(_map.selected_formation(), formation.id)
	_map.right_click_at(_map.hex_screen_position(_far_hex(formation)))
	_map.right_click_at(Vector2(-5000, -5000))  # off the map: closes
	assert_false(_map.order_ring().is_open())


func test_ring_on_an_enemy_hex_enables_only_attack() -> void:
	var formation := _own()
	var enemy := _enemy()
	_map.select_formation(formation.id)
	_map.right_click_at(_map.hex_screen_position(enemy.coord))
	assert_true(_map.order_ring().is_open())
	assert_false(_slot(0)["enabled"])
	assert_eq(_slot(0)["reason"], "Only the Attack posture can target an enemy formation.")
	assert_true(_slot(1)["enabled"])
	assert_false(_slot(2)["enabled"])
	_map.order_ring().activate(0)
	assert_true(_map.order_ring().is_open(), "a disabled segment does nothing")
	assert_true(formation.order == null)
	_key(KEY_2)
	assert_eq(formation.order.destination, enemy.coord)
	assert_eq(formation.posture, &"advance")


func test_ring_on_an_own_hex_refuses_everything() -> void:
	var formation := _own()
	_map.select_formation(formation.id)
	_map.right_click_at(_map.hex_screen_position(formation.coord))
	for i in 3:
		assert_false(_slot(i)["enabled"])
		assert_true(_slot(i)["reason"] != "")


func test_ring_cancel_segment_only_with_an_order() -> void:
	var formation := _own()
	var target := _far_hex(formation)
	formation.order = FormationOrder.new(target)
	_map.select_formation(formation.id)
	_map.right_click_at(_map.hex_screen_position(_far_hex(formation, 3)))
	assert_false(_slot(3)["empty"])
	assert_true(_slot(3)["enabled"])
	assert_eq(_slot(3)["action"], &"cancel")
	_key(KEY_4)
	assert_true(formation.order == null)
	assert_eq(_map.selected_formation(), formation.id, "stays selected after cancelling")
	assert_false(_map.order_ring().is_open())


func test_ring_card_shows_the_route_numbers_of_the_hovered_segment() -> void:
	var formation := _own()
	var target := _far_hex(formation, 6)
	_map.select_formation(formation.id)
	_map.right_click_at(_map.hex_screen_position(target))
	var ring := _map.order_ring()
	ring.ring().hovered = 1
	ring.ring().slot_hovered.emit(1)
	assert_true(ring.card().visible)
	assert_eq(ring.hovered_posture(), &"advance")
	var model := StaffMapOrderRingModel.build(_map.simulation().state, formation, target)
	var state := _map.simulation().state
	var preview := StaffMapRoute.preview_in_posture(state, formation, target, &"advance")
	var turns: int = preview["turns"]
	assert_eq(model["details"][1]["effects"][2], {"label": "TURNS", "value": str(turns)})


func test_ring_closes_when_the_selection_changes_or_it_is_not_your_turn() -> void:
	var formation := _own()
	_map.select_formation(formation.id)
	_map.right_click_at(_map.hex_screen_position(_far_hex(formation)))
	_map.select_formation(&"")
	assert_false(_map.order_ring().is_open())
	var state := _map.simulation().state
	_map.select_formation(formation.id)
	var current := state.current_player
	state.current_player = 1 - current
	assert_false(_map.right_click_at(_map.hex_screen_position(_far_hex(formation))))
	state.current_player = current


func test_route_preview_follows_the_default_posture() -> void:
	var formation := _own()
	var enemy := _enemy()
	_map.select_formation(formation.id)
	_map.route_preview().set_hex(_far_hex(formation))
	_map.route_preview().rebuild()
	assert_eq(_map.route_preview().shown_posture(), &"march")
	_map.route_preview().set_hex(enemy.coord)
	_map.route_preview().rebuild()
	assert_eq(_map.route_preview().shown_posture(), &"advance")
	_map.route_preview().set_hex(StaffMapRoutePreview.OFF)
	_map.route_preview().rebuild()


func test_posture_change_keeps_the_order_and_restyles_the_arrow() -> void:
	var formation := _own()
	var target := _far_hex(formation)
	_map.select_formation(formation.id)
	_map.issue_order(target)
	assert_true(_map.orders().style_of(formation.id)["dashed"])
	_map.set_posture(&"defend")
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
