# gdlint: disable=max-public-methods
extends TestCase
## The order gesture of the staff map (TASK-153, "Armed line"): the pure state machine
## IDLE -> ARMED -> AIMING (SNAPPED / INVALID) -> CONFIRM -> COMMITTED -> IDLE and the intents it
## returns. No nodes, no simulation.

const HEX := Vector2i(3, 2)
const OTHER := Vector2i(4, 2)
const OK := {"valid": true, "reason": "", "incident": false}
const BAD := {"valid": false, "reason": "ROUTE_WATER", "incident": false}
const BORDER := {"valid": true, "reason": "", "incident": true}


func _armed() -> StaffMapOrderGesture:
	var gesture := StaffMapOrderGesture.new()
	gesture.set_context(false, false, false, true)
	gesture.click_own_counter(&"a")
	return gesture


func _aiming(verdict := OK) -> StaffMapOrderGesture:
	var gesture := _armed()
	gesture.hover(HEX, verdict, 3)
	return gesture


# --- transitions ---


func test_click_on_an_own_counter_arms_and_a_second_click_disarms() -> void:
	var gesture := StaffMapOrderGesture.new()
	gesture.set_context(false, false, false, true)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.IDLE)
	var intent := gesture.click_own_counter(&"a")
	assert_eq(intent["type"], StaffMapOrderGesture.ARM)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.ARMED)
	assert_eq(gesture.formation_id(), &"a")
	intent = gesture.click_own_counter(&"a")
	assert_eq(intent["type"], StaffMapOrderGesture.DISARM)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.IDLE)


func test_clicking_another_own_counter_re_arms_on_it() -> void:
	var gesture := _aiming()
	var intent := gesture.click_own_counter(&"b")
	assert_eq(intent["type"], StaffMapOrderGesture.ARM)
	assert_eq(intent["id"], &"b")
	assert_eq(gesture.state(), StaffMapOrderGesture.State.ARMED)


func test_hovering_a_hex_aims_and_leaving_the_map_returns_to_armed() -> void:
	var gesture := _armed()
	gesture.hover(HEX, OK, 3)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.AIMING)
	assert_eq(gesture.aim(), StaffMapOrderGesture.Aim.SNAPPED)
	assert_eq(gesture.hex(), HEX)
	gesture.hover(StaffMapOrderGesture.NO_HEX, OK, 3)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.ARMED)


func test_an_invalid_hex_is_aiming_with_the_reason() -> void:
	var gesture := _aiming(BAD)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.AIMING)
	assert_eq(gesture.aim(), StaffMapOrderGesture.Aim.INVALID)
	assert_eq(gesture.reason(), "ROUTE_WATER")


func test_clicking_a_valid_hex_commits() -> void:
	var gesture := _aiming()
	var intent := gesture.click_hex(HEX, OK, 3)
	assert_eq(intent["type"], StaffMapOrderGesture.ISSUE)
	assert_eq(intent["hex"], HEX)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.COMMITTED)


func test_clicking_an_invalid_hex_stays_aiming_and_exposes_the_reason() -> void:
	var gesture := _aiming(BAD)
	var intent := gesture.click_hex(HEX, BAD, 3)
	assert_eq(intent["type"], StaffMapOrderGesture.REJECT)
	assert_eq(intent["reason"], "ROUTE_WATER")
	assert_eq(gesture.state(), StaffMapOrderGesture.State.AIMING)
	assert_eq(gesture.reason(), "ROUTE_WATER")


func test_a_click_without_a_hover_first_works_like_a_hover_then_click() -> void:
	var gesture := _armed()
	var intent := gesture.click_hex(HEX, OK, 3)
	assert_eq(intent["type"], StaffMapOrderGesture.ISSUE)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.COMMITTED)


func test_a_border_incident_asks_for_confirmation_first() -> void:
	var gesture := _aiming(BORDER)
	var intent := gesture.click_hex(HEX, BORDER, 3)
	assert_eq(intent["type"], StaffMapOrderGesture.CONFIRM_NEEDED)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.CONFIRM)
	assert_eq(gesture.confirm()["type"], StaffMapOrderGesture.NONE, "the view issues it itself")
	assert_eq(gesture.state(), StaffMapOrderGesture.State.COMMITTED)


func test_escape_in_confirm_goes_back_to_aiming() -> void:
	var gesture := _aiming(BORDER)
	gesture.click_hex(HEX, BORDER, 3)
	gesture.cancel()
	assert_eq(gesture.state(), StaffMapOrderGesture.State.AIMING)


func test_one_escape_leaves_the_order_mode_from_aiming() -> void:
	var gesture := _aiming()
	assert_eq(gesture.cancel()["type"], StaffMapOrderGesture.DISARM)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.IDLE)
	gesture.hover(OTHER, OK, 3)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.IDLE, "no aim line after Esc")


func test_committed_returns_to_idle_after_the_settle_time() -> void:
	var gesture := _aiming()
	gesture.click_hex(HEX, OK, 3)
	assert_eq(gesture.settle(), 0.0)
	gesture.tick(StaffMapOrderGesture.SETTLE_SEC * 0.5)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.COMMITTED)
	assert_true(is_equal_approx(gesture.settle(), 0.5))
	gesture.tick(StaffMapOrderGesture.SETTLE_SEC)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.IDLE)
	assert_eq(gesture.formation_id(), &"")


func test_deselecting_commits_stay_until_the_settle_ends() -> void:
	var gesture := _aiming()
	gesture.click_hex(HEX, OK, 3)
	gesture.select(&"")
	assert_eq(gesture.state(), StaffMapOrderGesture.State.COMMITTED)


# --- orders left ---


func test_no_orders_left_makes_the_aim_invalid_and_refuses_the_click() -> void:
	var gesture := _armed()
	gesture.hover(HEX, OK, 0)
	assert_eq(gesture.aim(), StaffMapOrderGesture.Aim.INVALID)
	assert_eq(gesture.reason(), "no_orders_left")
	var intent := gesture.click_hex(HEX, OK, 0)
	assert_eq(intent["type"], StaffMapOrderGesture.REJECT)
	assert_eq(intent["reason"], "no_orders_left")
	assert_eq(gesture.state(), StaffMapOrderGesture.State.AIMING)


# --- postures ---


func test_keys_change_the_posture_in_armed_and_aiming_and_the_same_key_drops_it() -> void:
	var gesture := _armed()
	var intent := gesture.pick_posture(&"advance")
	assert_eq(intent["type"], StaffMapOrderGesture.POSTURE)
	assert_eq(gesture.posture(), &"advance")
	gesture.hover(HEX, OK, 3)
	gesture.pick_posture(&"defend")
	assert_eq(gesture.posture(), &"defend")
	gesture.pick_posture(&"defend")
	assert_eq(gesture.posture(), &"")


func test_escape_with_a_picked_posture_leaves_the_order_mode() -> void:
	var gesture := _aiming()
	gesture.pick_posture(&"advance")
	assert_eq(gesture.cancel()["type"], StaffMapOrderGesture.DISARM)
	assert_eq(gesture.posture(), &"")
	assert_eq(gesture.state(), StaffMapOrderGesture.State.IDLE)


func test_a_posture_key_is_ignored_when_idle() -> void:
	var gesture := StaffMapOrderGesture.new()
	gesture.set_context(false, false, false, true)
	gesture.pick_posture(&"advance")
	assert_eq(gesture.posture(), &"")


func test_arming_another_formation_clears_the_posture() -> void:
	var gesture := _armed()
	gesture.pick_posture(&"advance")
	gesture.click_own_counter(&"b")
	assert_eq(gesture.posture(), &"")


# --- disabled ---


func _idle_when(strike: bool, modal: bool, sliding: bool, turn: bool) -> void:
	var gesture := StaffMapOrderGesture.new()
	gesture.set_context(strike, modal, sliding, turn)
	assert_true(gesture.is_blocked())
	var intent := gesture.click_own_counter(&"a")
	assert_eq(intent["type"], StaffMapOrderGesture.NONE)
	gesture.select(&"a")
	gesture.hover(HEX, OK, 3)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.IDLE)
	assert_eq(gesture.click_hex(HEX, OK, 3)["type"], StaffMapOrderGesture.NONE)


func test_disabled_in_strike_mode() -> void:
	_idle_when(true, false, false, true)


func test_disabled_under_a_modal() -> void:
	_idle_when(false, true, false, true)


func test_disabled_during_the_counter_slide() -> void:
	_idle_when(false, false, true, true)


func test_disabled_outside_the_viewers_turn() -> void:
	_idle_when(false, false, false, false)


func test_a_context_that_becomes_blocked_drops_an_armed_gesture() -> void:
	var gesture := _aiming()
	gesture.set_context(true, false, false, true)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.IDLE)


# --- EDITING (TASK-157) ---


func _editing() -> StaffMapOrderGesture:
	var gesture := StaffMapOrderGesture.new()
	gesture.set_context(false, false, false, true)
	gesture.click_head(&"a")
	return gesture


func test_click_head_enters_editing() -> void:
	var gesture := StaffMapOrderGesture.new()
	gesture.set_context(false, false, false, true)
	var intent := gesture.click_head(&"a")
	assert_eq(intent["type"], StaffMapOrderGesture.EDIT)
	assert_eq(intent["id"], &"a")
	assert_eq(gesture.state(), StaffMapOrderGesture.State.EDITING)
	assert_eq(gesture.formation_id(), &"a")
	assert_eq(gesture.edited_from(), &"a")
	assert_false(gesture.is_aiming())
	gesture.hover(HEX, OK, 3)
	assert_true(gesture.is_aiming())
	assert_eq(gesture.aim(), StaffMapOrderGesture.Aim.SNAPPED)


func test_editing_hover_invalid_reason_is_as_in_aiming() -> void:
	var gesture := _editing()
	gesture.hover(HEX, BAD, 3)
	assert_eq(gesture.aim(), StaffMapOrderGesture.Aim.INVALID)
	assert_eq(gesture.reason(), "ROUTE_WATER")


func test_editing_click_issues_and_settles_to_idle() -> void:
	var gesture := _editing()
	var intent := gesture.click_hex(HEX, OK, 3)
	assert_eq(intent["type"], StaffMapOrderGesture.ISSUE)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.COMMITTED)
	assert_eq(gesture.edited_from(), &"")
	gesture.tick(StaffMapOrderGesture.SETTLE_SEC)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.IDLE)


func test_editing_border_incident_confirms_and_esc_returns_to_editing() -> void:
	var gesture := _editing()
	assert_eq(gesture.click_hex(HEX, BORDER, 3)["type"], StaffMapOrderGesture.CONFIRM_NEEDED)
	gesture.cancel()
	assert_eq(gesture.state(), StaffMapOrderGesture.State.EDITING)


func test_editing_one_esc_disarms() -> void:
	var gesture := _editing()
	gesture.hover(HEX, OK, 3)
	assert_eq(gesture.cancel()["type"], StaffMapOrderGesture.DISARM)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.IDLE)
	assert_eq(gesture.edited_from(), &"")


func test_editing_fail_returns_to_editing() -> void:
	var gesture := _editing()
	gesture.hover(HEX, OK, 3)
	gesture.click_hex(HEX, OK, 3)
	gesture.fail()
	assert_eq(gesture.state(), StaffMapOrderGesture.State.EDITING)
	assert_eq(gesture.edited_from(), &"a")


func test_click_head_while_blocked_does_nothing() -> void:
	var gesture := StaffMapOrderGesture.new()
	gesture.set_context(true, false, false, true)
	assert_eq(gesture.click_head(&"a")["type"], StaffMapOrderGesture.NONE)
	assert_eq(gesture.state(), StaffMapOrderGesture.State.IDLE)


func test_click_head_switches_formation_and_clears_posture() -> void:
	var gesture := _armed()
	gesture.pick_posture(&"advance")
	gesture.click_head(&"b")
	assert_eq(gesture.formation_id(), &"b")
	assert_eq(gesture.posture(), &"")
	assert_eq(gesture.state(), StaffMapOrderGesture.State.EDITING)


func test_editing_posture_key_is_in_the_issue_details() -> void:
	var gesture := _editing()
	gesture.hover(HEX, OK, 3)
	gesture.pick_posture(&"advance")
	assert_eq(gesture.click_hex(HEX, OK, 3)["posture"], &"advance")


func test_editing_selection_sync_keeps_editing() -> void:
	var gesture := _editing()
	gesture.select(&"a")
	assert_eq(gesture.state(), StaffMapOrderGesture.State.EDITING)


func test_editing_no_orders_left_rejects() -> void:
	var gesture := _editing()
	gesture.hover(HEX, OK, 0)
	assert_eq(gesture.reason(), StaffMapOrderGesture.REASON_NO_ORDERS)
	assert_eq(gesture.click_hex(HEX, OK, 0)["type"], StaffMapOrderGesture.REJECT)


func test_edit_cost_label() -> void:
	assert_eq(StaffMapOrderGesture.edit_cost_label(true), "FREE")
	assert_eq(StaffMapOrderGesture.edit_cost_label(false), "COSTS 1 ORDER")
