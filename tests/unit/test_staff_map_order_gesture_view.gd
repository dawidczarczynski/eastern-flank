# gdlint: disable=max-public-methods
extends TestCase
## The order gesture wired into the staff map (TASK-153 stage 1): click-click ordering, the
## no-orders-left refusal, the cursor label, the attack look, the simulation left untouched.

const Fixtures := preload("res://tests/fixtures.gd")

static var _map: StaffMap
static var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_map = StaffMap.new()
	_map.auto_build = false
	(Engine.get_main_loop() as SceneTree).root.add_child(_map)
	assert_true(_map.build_now(), "staff map builds")


func after_all() -> void:
	_map.free()
	_map = null
	TranslationServer.set_locale(_previous_locale)


func after_each() -> void:
	for formation in _map.simulation().state.formations:
		formation.order = null
	_map.simulation().state.orders_issued = 0
	_map.simulation().state.ordered_this_turn.clear()
	_map.select_formation(&"")
	_map.set_viewer(_map.simulation().state.current_player)
	_map.order_gesture().tick(1.0)


func _own() -> Formation:
	for formation in _map.simulation().state.formations:
		if formation.owner_id == _map.simulation().state.current_player:
			return formation
	return null


func _far_hex(formation: Formation, distance := 3) -> Vector2i:
	var state := _map.simulation().state
	for c: Vector2i in state.grid.coords():
		if Hex.distance(c, formation.coord) == distance and state.formation_at(c) == null:
			if not OperationalRoutes.plan(state, formation, c, false).is_empty():
				return c
	return StaffMapRoutePreview.OFF


func _click_hex(c: Vector2i) -> void:
	_map.click_at(_map.hex_screen_position(c))


func test_selecting_an_own_formation_arms_the_gesture() -> void:
	var formation := _own()
	_map._sync_gesture()
	assert_eq(_map.order_gesture().state(), StaffMapOrderGesture.State.IDLE)
	_map.select_formation(formation.id)
	_map._sync_gesture()
	assert_eq(_map.order_gesture().state(), StaffMapOrderGesture.State.ARMED)
	assert_eq(_map.order_gesture().formation_id(), formation.id)


func test_a_second_click_on_the_armed_counter_disarms() -> void:
	var formation := _own()
	_map.select_formation(formation.id)
	_map.click_at(_map.counter_screen_position(formation.id))
	assert_eq(_map.selected_formation(), &"")
	assert_eq(_map.order_gesture().state(), StaffMapOrderGesture.State.IDLE)


func test_right_click_on_a_hex_opens_the_ring_without_disarming() -> void:
	var formation := _own()
	var target := _far_hex(formation)
	_map.select_formation(formation.id)
	assert_true(_map.right_click_at(_map.hex_screen_position(target)), "the ring opens")
	assert_true(_map.order_ring().is_open())
	assert_eq(_map.selected_formation(), formation.id, "the formation stays selected")
	_map.order_ring().close()


func test_click_click_issues_the_order_and_settles_back_to_idle() -> void:
	var formation := _own()
	var target := _far_hex(formation)
	_map.select_formation(formation.id)
	_click_hex(target)
	assert_eq(formation.order.destination, target)
	assert_eq(_map.order_gesture().state(), StaffMapOrderGesture.State.COMMITTED)
	assert_true(_map.orders().has_fresh(), "the new line settles from full opacity")
	_map.order_gesture().tick(StaffMapOrderGesture.SETTLE_SEC + 0.01)
	assert_eq(_map.order_gesture().state(), StaffMapOrderGesture.State.IDLE)


func test_aiming_and_arming_leave_the_simulation_untouched() -> void:
	var formation := _own()
	var before := _map.simulation().state.snapshot()
	var history := _map.simulation().history.size()
	_map.select_formation(formation.id)
	_map.order_gesture().hover(_far_hex(formation), {"valid": true}, 3)
	_map.order_gesture().cancel()
	assert_eq(_map.simulation().state.snapshot(), before)
	assert_eq(_map.simulation().history.size(), history)


func test_no_orders_left_refuses_the_click_without_a_command() -> void:
	var formation := _own()
	var state := _map.simulation().state
	state.orders_issued = state.orders_per_turn(formation.owner_id)
	assert_eq(state.orders_left(), 0)
	_map.select_formation(formation.id)
	var history := _map.simulation().history.size()
	_click_hex(_far_hex(formation))
	assert_eq(_map.simulation().history.size(), history, "no command was sent")
	assert_true(formation.order == null)
	assert_eq(_map.selected_formation(), formation.id, "still armed")


func test_cursor_label_shows_orders_left_and_then_the_reason() -> void:
	var formation := _own()
	var state := _map.simulation().state
	var target := _far_hex(formation)
	var preview := StaffMapRoute.preview_in_posture(state, formation, target, &"march")
	assert_true(
		StaffMapRoutePreview.cursor_label(state, formation, preview).contains("ORDERS LEFT")
	)
	state.orders_issued = state.orders_per_turn(formation.owner_id)
	assert_eq(
		StaffMapRoutePreview.cursor_label(state, formation, preview), "NO ORDERS LEFT THIS TURN."
	)


func test_verdicts_of_a_route() -> void:
	var formation := _own()
	var state := _map.simulation().state
	var target := _far_hex(formation)
	var good := StaffMapRoute.preview_in_posture(state, formation, target, &"march")
	assert_true(StaffMapRoutePreview.verdict_of(state, formation, good)["valid"])
	var own_hex := StaffMapRoute.preview_in_posture(state, formation, formation.coord, &"march")
	assert_false(StaffMapRoutePreview.verdict_of(state, formation, own_hex)["valid"])


func test_the_attack_style_has_a_rail_and_the_others_keep_their_looks() -> void:
	var attack := StaffMapRoute.style(&"advance", false, true)
	assert_true(attack["rail"])
	assert_eq(StaffMapRouteRibbon.kind_of(attack), StaffMapRouteRibbon.Kind.RAIL)
	assert_eq(
		StaffMapRouteRibbon.kind_of(StaffMapRoute.style(&"march", false)),
		StaffMapRouteRibbon.Kind.DASHED
	)
	assert_eq(
		StaffMapRouteRibbon.kind_of(StaffMapRoute.style(&"advance", false)),
		StaffMapRouteRibbon.Kind.SOLID
	)
	assert_eq(
		StaffMapRouteRibbon.kind_of(StaffMapRoute.style(&"defend", true)),
		StaffMapRouteRibbon.Kind.SOLID
	)


func test_ribbon_flows_only_when_asked_and_rail_is_hollow() -> void:
	var ribbon := StaffMapRouteRibbon.new()
	assert_false(ribbon.is_flowing())
	ribbon.set_flowing(true)
	assert_true(ribbon.is_flowing())
	ribbon.set_flowing(false)
	assert_false(ribbon.is_flowing())
	var kind := StaffMapRouteRibbon.Kind
	assert_true(ribbon.line_parameter(kind.RAIL, &"hollow_px") > 0.0)
	assert_eq(ribbon.line_parameter(kind.SOLID, &"hollow_px"), 0.0)
	assert_true(ribbon.line_parameter(kind.DASHED, &"dash_on_px") > 0.0)
	assert_eq(ribbon.line_parameter(kind.SOLID, &"dash_on_px"), 0.0)
	ribbon.free()


func test_line_mesh_carries_the_length_along_the_line_in_uv_y() -> void:
	var line := PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(2, 0, 3)])
	var mesh := StaffMapLines.polylines_mesh([line])
	var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var lengths := []
	for uv in uvs:
		if not lengths.has(uv.y):
			lengths.append(uv.y)
	lengths.sort()
	assert_eq(lengths, [0.0, 2.0, 5.0])


func test_simplify_drops_the_wobble_and_keeps_the_end_points() -> void:
	var points := PackedVector2Array(
		[Vector2(0, 0), Vector2(2, 0.2), Vector2(4, -0.2), Vector2(6, 0), Vector2(6, 4)]
	)
	var out := StaffMapRoute.simplify(points, StaffMapRoute.SIMPLIFY_TOLERANCE)
	assert_eq(out, PackedVector2Array([Vector2(0, 0), Vector2(6, 0), Vector2(6, 4)]))


# --- stage 2: ghost, alternative line, conflict mark, stub ---


func _aim(formation: Formation, hex: Vector2i) -> StaffMapRoutePreview:
	_map.select_formation(formation.id)
	var route := _map.route_preview()
	route.set_hex(hex)
	route.rebuild()
	return route


func test_aiming_shows_the_ghost_with_the_arrival_turn() -> void:
	var formation := _own()
	var route := _aim(formation, _far_hex(formation))
	var ghost: Dictionary = route.extras()["ghost"]
	assert_true(ghost["text"].begins_with("T+"))
	assert_eq(_map.route_marks().extras_of()["ghost"]["text"], ghost["text"])


func _mate(formation: Formation) -> Formation:
	for other in _map.simulation().state.formations:
		if other != formation and other.owner_id == formation.owner_id:
			return other
	return null


func test_an_invalid_target_shows_no_ghost() -> void:
	var formation := _own()
	var mate := _mate(formation)
	assert_true(mate != null)
	var route := _aim(formation, mate.coord)
	assert_false(route.extras().has("ghost"), "an occupied own hex is no target")


func test_the_conflict_mark_shows_when_another_own_order_ends_there() -> void:
	var formation := _own()
	var target := _far_hex(formation)
	var mate := _mate(formation)
	mate.order = FormationOrder.new(target)
	var route := _aim(formation, target)
	assert_eq(route.extras()["conflict"]["formation_id"], mate.id)
	assert_true(_map.route_marks().extras_of().has("conflict"))
	mate.order = null
	route = _aim(formation, target)
	assert_false(route.extras().has("conflict"), "no mark once the other order is gone")


func test_aiming_leaves_the_state_identical_with_all_extras() -> void:
	var formation := _own()
	var before := _map.simulation().state.snapshot()
	_aim(formation, _far_hex(formation))
	assert_eq(_map.simulation().state.snapshot(), before)


func test_the_alternative_plan_is_made_once_per_debounced_rebuild() -> void:
	var formation := _own()
	var route := _aim(formation, _far_hex(formation))
	var plans := route.alt_plans_made()
	for i in 5:
		route.set_hex(_far_hex(formation, 2 + i % 2))
	assert_eq(route.alt_plans_made(), plans, "hovering alone plans nothing")
	route.rebuild()
	assert_eq(route.alt_plans_made(), plans + 1)


func test_clicking_a_head_edits_the_order_for_free() -> void:
	var formation := _own()
	var first := _far_hex(formation)
	assert_true(first != StaffMapRoutePreview.OFF, "a reachable hex")
	_map.select_formation(formation.id)
	_click_hex(first)
	_map.order_gesture().tick(1.0)
	var state := _map.simulation().state
	var left := state.orders_left()
	var heads := _map.orders().heads_on_screen()
	assert_true(heads.has(formation.id), "the issued order has a head")
	_map.click_at(heads[formation.id])
	assert_eq(_map.order_gesture().state(), StaffMapOrderGesture.State.EDITING)
	assert_eq(_map.order_gesture().edited_from(), formation.id)
	assert_eq(formation.order.destination, first, "the old order stays until replaced")
	var second := _far_hex(formation, 2)
	if second != StaffMapRoutePreview.OFF and second != first:
		_click_hex(second)
		assert_eq(formation.order.destination, second)
		assert_eq(state.orders_left(), left, "re-aiming this turn's order is free")


func test_esc_while_editing_keeps_the_order() -> void:
	var formation := _own()
	var first := _far_hex(formation)
	_map.select_formation(formation.id)
	_click_hex(first)
	_map.order_gesture().tick(1.0)
	_map.click_at(_map.orders().heads_on_screen()[formation.id])
	assert_true(_map._cancel_gesture(), "no hex aimed: Esc ends the editing")
	assert_eq(_map.order_gesture().state(), StaffMapOrderGesture.State.IDLE)
	assert_eq(formation.order.destination, first)
