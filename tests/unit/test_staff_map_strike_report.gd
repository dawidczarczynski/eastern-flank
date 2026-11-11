# gdlint: disable=max-public-methods
extends TestCase
## The strike result report (TASK-097b, variant A): the pure model `StaffMapStrikeText.report_model`
## and the queue / timing / keys of `StaffMapStrikeReports`, on TASK-115's strip grid.

const Strikes := preload("res://tests/unit/test_strikes.gd")
const Model := preload("res://tests/unit/test_staff_map_strike_model.gd")
const A1 := &"a1"  # Russian airfield (6, 0)
const AD := &"ru_ad"  # Russian air defence (7, 0)
const POLISH_AIRFIELD := &"pl_air"  # (0, 1)

static var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_all() -> void:
	TranslationServer.set_locale(_previous_locale)


static func _event(
	target: StringName, player: int, intercepted: int, hits: int, misses: int, extra := {}
) -> Dictionary:
	var event := {
		"type": &"strike_resolved",
		"player": player,
		"means": &"sure",
		"target": target,
		"count": intercepted + hits + misses,
		"intercepted": intercepted,
		"hits": hits,
		"misses": misses,
		"damage_dealt": 0,
		"target_destroyed": false,
		"interceptor_ids": [&"ru_ad"],
	}
	event.merge(extra, true)
	return event


static func _model(
	state: OperationalState, event: Dictionary, trail := StaffMapStrikeTrail.new()
) -> Dictionary:
	return StaffMapStrikeText.report_model(state, event, trail)


# --- the model ---


func test_own_strike_on_an_installation() -> void:
	var state := Model._state(2)
	state.get_installation(A1).integrity = 65
	state.strikes_left = 1
	var event := _event(A1, 0, 1, 1, 1, {"damage_dealt": 35, "stock_before": 6, "stock_after": 3})
	var model := _model(state, event)
	assert_true(model["own"])
	assert_eq(model["side_text"], "Your strike")
	assert_eq(model["name"], "sure")
	assert_eq(model["target_name"], "a1")
	assert_eq(model["count"], 3)
	assert_eq(model["outcomes"], [&"hit", &"intercepted", &"missed"], "hits, intercepted, missed")
	assert_eq([model["hits"], model["intercepted"], model["misses"]], [1, 1, 1])
	var target: Dictionary = model["target"]
	assert_eq(target["kind"], &"integrity")
	assert_eq([target["before"], target["after"], target["delta"]], [100, 65, -35])
	assert_false(target["destroyed"])
	assert_false(target["no_damage"])
	assert_eq(model["stock"], {"known": true, "before": 6, "after": 3})
	assert_eq([model["strikes_left"], model["strikes_max"]], [1, state.strikes_per_turn])
	assert_false(model["threshold"])
	assert_true(model["chip"].contains("1 hit"), model["chip"])
	assert_true(model["chip"].contains("−35"), model["chip"])
	assert_eq(model["fallback"], StaffMapStrikeText.resolved(state, event), "one-line fallback")


func test_interceptor_sites_with_counts() -> void:
	var state := Model._state(2)
	var model := _model(state, _event(A1, 0, 2, 0, 0))
	var sites: Array = model["interceptors"]
	assert_eq(sites.size(), 1)
	assert_eq(sites[0]["name"], "ru_ad")
	assert_eq(sites[0]["count"], 2)
	assert_eq(sites[0]["coord"], Vector2i(7, 0))
	assert_eq(_model(state, _event(A1, 0, 0, 2, 0))["interceptors"], [], "none intercepted: none")


func test_sites_the_viewer_cannot_see_are_left_out() -> void:
	var state := Model._state(2)
	var trail := StaffMapStrikeTrail.new()
	trail.is_visible = func(_coord: Vector2i, _player: int) -> bool: return false
	assert_eq(_model(state, _event(A1, 0, 1, 1, 0), trail)["interceptors"], [])


func test_destroyed_installation() -> void:
	var state := Model._state(2)
	state.get_installation(A1).integrity = 0
	var model := _model(
		state, _event(A1, 0, 0, 3, 0, {"damage_dealt": 35, "target_destroyed": true})
	)
	var target: Dictionary = model["target"]
	assert_true(target["destroyed"])
	assert_eq([target["before"], target["after"]], [35, 0])
	assert_true(model["chip"].contains("destroyed"), model["chip"])


func test_all_intercepted_and_all_missed_do_no_damage() -> void:
	var state := Model._state(2)
	var intercepted := _model(state, _event(A1, 0, 2, 0, 0))
	assert_true(intercepted["target"]["no_damage"])
	assert_eq(intercepted["outcomes"], [&"intercepted", &"intercepted"])
	assert_eq(intercepted["target"]["delta"], 0)
	var missed := _model(state, _event(A1, 0, 0, 0, 2))
	assert_true(missed["target"]["no_damage"])
	assert_eq(missed["outcomes"], [&"missed", &"missed"])
	assert_eq(missed["interceptors"], [], "no interception section when nothing was intercepted")


func test_formation_target_shows_strength() -> void:
	var state := Model._state(2)
	var formation := state.get_formation(&"r")
	var after := formation.strength()
	var model := _model(state, _event(&"r", 0, 0, 2, 1, {"damage_dealt": 4}))
	var target: Dictionary = model["target"]
	assert_eq(target["kind"], &"strength")
	assert_eq([target["before"], target["after"], target["delta"]], [after + 4, after, -4])
	assert_eq(target["max"], formation.max_strength())
	assert_eq(target["name"], String(TranslationServer.translate(formation.display_name)))


func test_destroyed_formation_uses_the_snapshot_of_the_event() -> void:
	var state := Model._state(2)
	var event := _event(
		&"gone",
		0,
		0,
		2,
		0,
		{
			"damage_dealt": 10,
			"target_destroyed": true,
			"target_name": "2nd Tank Bn",
			"target_max": 20
		}
	)
	var target: Dictionary = _model(state, event)["target"]
	assert_eq(target["kind"], &"strength")
	assert_eq([target["before"], target["after"], target["max"]], [10, 0, 20])
	assert_eq(target["name"], "2nd Tank Bn")
	assert_true(target["destroyed"])


func test_enemy_strike_has_no_stock_and_names_the_viewers_sites() -> void:
	var state := Model._state(2)
	state.get_installation(POLISH_AIRFIELD).integrity = 30
	var event := _event(POLISH_AIRFIELD, 1, 0, 2, 0, {"damage_dealt": 70, "viewer": 0})
	var model := _model(state, event)
	assert_false(model["own"])
	assert_eq(model["side_text"], "Enemy strike")
	assert_false(model["stock"]["known"], "enemy stock is unknown")
	assert_eq([model["target"]["before"], model["target"]["after"]], [100, 30])


func test_escalation_lines_and_level() -> void:
	var state := Model._state(2)
	state.escalation_level = 3
	var event := _event(
		A1,
		0,
		0,
		1,
		0,
		{
			"escalation":
			[
				{"type": &"sanctuary_breached", "country": &"russia", "player": 0},
				{
					"type": &"escalation_changed",
					"level": 2,
					"previous": 1,
					"by": 0,
					"cause": &"sanctuary_breach"
				},
				{
					"type": &"escalation_changed",
					"level": 3,
					"previous": 2,
					"by": 0,
					"cause": &"urban_strike"
				},
			]
		}
	)
	var model := _model(state, event)
	var escalation: Dictionary = model["escalation"]
	assert_true(escalation["changed"])
	assert_eq([escalation["previous"], escalation["level"], escalation["delta"]], [1, 3, 2])
	assert_eq(escalation["level_name"], "Regional war")
	assert_eq(escalation["lines"].size(), 2)
	assert_eq(escalation["lines"][0]["text"], "+1 sanctuary breach")
	assert_eq(escalation["lines"][1]["text"], "+1 urban hex")
	assert_false(model["threshold"])
	var calm: Dictionary = _model(state, _event(A1, 0, 0, 1, 0))["escalation"]
	assert_false(calm["changed"])
	assert_eq(calm["level"], state.escalation_level)
	assert_eq(calm["lines"], [])


func test_threshold_marks_the_report() -> void:
	var state := Model._state(3)
	state.escalation_level = state.ladder.top()
	var event := _event(
		A1,
		0,
		0,
		1,
		0,
		{
			"escalation":
			[
				{
					"type": &"escalation_changed",
					"level": 4,
					"previous": 3,
					"by": 0,
					"cause": &"urban_strike"
				},
				{"type": &"operation_ended", "by": 0, "winner": 1},
			]
		}
	)
	var model := _model(state, event)
	assert_true(model["threshold"])
	var lines: Array = model["escalation"]["lines"]
	assert_true(lines[lines.size() - 1]["danger"], "the red threshold line closes the list")
	assert_true(model["tab"].contains("Threshold"), model["tab"])


# --- the queue ---


class Harness:
	extends RefCounted
	var reports: StaffMapStrikeReports

	func _init() -> void:
		reports = StaffMapStrikeReports.new(StaffMapPalette.new())

	func release() -> void:
		reports.free_nodes()


static func _entry(own: bool, threshold := false) -> Dictionary:
	return {
		"own": own,
		"striker": 0 if own else 1,
		"side_name": "NATO" if own else "Russia",
		"threshold": threshold,
		"tab": "Your strike" if own else "Enemy strike",
		"right": "TURN 7",
		"name": "Cruise",
		"designation": "",
		"detail": "×2",
		"target_name": "Airfield",
		"target_place": "Russia",
		"hits": 1,
		"intercepted": 1,
		"misses": 0,
		"count": 2,
		"outcomes": [&"hit", &"intercepted"],
		"target":
		{
			"kind": &"integrity",
			"label": "Integrity",
			"name": "",
			"before": 100,
			"after": 65,
			"delta": -35,
			"max": 100,
			"destroyed": false,
			"no_damage": false,
		},
		"interceptors": [],
		"escalation":
		{
			"changed": false,
			"previous": 1,
			"level": 1,
			"delta": 0,
			"level_name": "Limited war",
			"top": 4,
			"lines": [],
			"ends": false,
		},
		"stock": {"known": own, "before": 6, "after": 3},
		"strikes_left": 1,
		"strikes_max": 2,
		"chip": "Cruise ×2 · 1 hit · −35",
		"fallback": "",
	}


func test_own_card_appears_after_the_burst_and_collapses_after_nine_seconds() -> void:
	var h := Harness.new()
	var reports := h.reports
	reports.add(_entry(true))
	assert_false(reports.card_visible(), "the map burst plays first")
	reports.tick(0.5)
	assert_true(reports.card_visible())
	reports.tick(8.5)
	assert_true(reports.card_visible(), "still there before 9 s")
	reports.tick(1.0)
	assert_false(reports.card_visible())
	assert_true(reports.chip_visible(), "collapsed to the chip")
	h.release()


func test_hover_pauses_the_timer() -> void:
	var h := Harness.new()
	var reports := h.reports
	reports.add(_entry(true))
	reports.tick(0.5)
	reports.card().mouse_entered.emit()
	reports.tick(30.0)
	assert_true(reports.card_visible(), "hovered card stays")
	reports.card().mouse_exited.emit()
	reports.tick(9.5)
	assert_true(reports.chip_visible())
	h.release()


func test_enemy_reports_are_queued_three_and_a_half_seconds_each() -> void:
	var h := Harness.new()
	var reports := h.reports
	for i in 3:
		reports.add(_entry(false))
	reports.tick(0.5)
	assert_eq(reports.index(), 0)
	assert_eq(reports.count(), 3)
	reports.tick(3.6)
	assert_eq(reports.index(), 1)
	assert_true(reports.card_visible())
	reports.tick(3.6)
	assert_eq(reports.index(), 2)
	reports.tick(3.6)
	assert_false(reports.card_visible())
	assert_true(reports.chip_visible(), "the last one stays as a chip")
	assert_true(reports.chip().text_of().contains("3/3"), reports.chip().text_of())
	h.release()


func test_threshold_never_auto_collapses() -> void:
	var h := Harness.new()
	var reports := h.reports
	reports.add(_entry(true, true))
	reports.tick(0.5)
	reports.tick(120.0)
	assert_true(reports.card_visible())
	h.release()


func test_keys_j_enter_escape_and_arrows() -> void:
	var h := Harness.new()
	var reports := h.reports
	assert_false(reports.handle_key(KEY_J), "nothing to toggle")
	assert_false(reports.handle_key(KEY_ENTER), "Enter falls through to End turn")
	reports.add(_entry(true))
	reports.tick(0.5)
	assert_true(reports.handle_key(KEY_J))
	assert_true(reports.chip_visible(), "J collapses")
	assert_true(reports.handle_key(KEY_J))
	assert_true(reports.card_visible(), "J expands")
	reports.tick(60.0)
	assert_true(reports.card_visible(), "a card the player opened stays")
	assert_true(reports.handle_key(KEY_ENTER))
	assert_true(reports.chip_visible(), "Enter collapses")
	assert_false(reports.handle_key(KEY_ENTER), "...and the next Enter is End turn")
	reports.handle_key(KEY_J)
	assert_true(reports.handle_key(KEY_ESCAPE))
	assert_true(reports.chip_visible(), "Esc collapses")
	assert_false(reports.handle_key(KEY_ESCAPE), "Esc on the chip is not taken")
	reports.clear()
	for i in 3:
		reports.add(_entry(false))
	reports.tick(0.5)
	assert_true(reports.handle_key(KEY_RIGHT))
	assert_eq(reports.index(), 1)
	assert_true(reports.handle_key(KEY_LEFT))
	assert_eq(reports.index(), 0)
	assert_true(reports.handle_key(KEY_ENTER), "Enter shows the next of a queue")
	assert_eq(reports.index(), 1)
	assert_true(reports.card_visible())
	h.release()


func test_x_dismisses_card_and_chip() -> void:
	var h := Harness.new()
	var reports := h.reports
	reports.add(_entry(true))
	reports.tick(0.5)
	reports.card().close_button().pressed.emit()
	assert_false(reports.card_visible())
	assert_false(reports.chip_visible(), "X dismisses, nothing collapses")
	assert_eq(reports.count(), 0)
	reports.add(_entry(true))
	reports.tick(0.5)
	reports.handle_key(KEY_J)
	assert_true(reports.chip_visible())
	reports.chip().close_button().pressed.emit()
	assert_false(reports.chip_visible())
	assert_eq(reports.count(), 0)
	h.release()


func test_clear_removes_everything() -> void:
	var h := Harness.new()
	var reports := h.reports
	reports.add(_entry(false))
	reports.tick(0.5)
	reports.clear()
	assert_false(reports.card_visible())
	assert_false(reports.chip_visible())
	assert_eq(reports.count(), 0)
	reports.tick(10.0)
	assert_false(reports.card_visible(), "a pending card is gone too")
	h.release()


# --- suppression line (TASK-098b) ---


func _suppression(after: int) -> Dictionary:
	return {
		"type": &"installation_suppressed",
		"id": AD,
		"before": 0,
		"after": after,
		"cause": &"strike",
	}


func test_report_line_for_a_suppressing_hit() -> void:
	var state := Model._state(2)
	var event := _event(AD, 0, 0, 1, 0, {"damage_dealt": 35, "suppression": _suppression(2)})
	var model := _model(state, event)
	assert_eq(model["suppressed_rounds"], 2)
	assert_eq(model["suppressed_line"], "Suppressed for 2 rounds")


func test_no_report_line_without_a_hit_or_when_destroyed() -> void:
	var state := Model._state(2)
	var miss := _event(AD, 0, 0, 0, 1, {"suppression": _suppression(2)})
	assert_eq(_model(state, miss)["suppressed_line"], "", "no hit, no line")
	var destroyed := _event(
		AD,
		0,
		0,
		1,
		0,
		{"damage_dealt": 100, "target_destroyed": true, "suppression": _suppression(0)}
	)
	assert_eq(_model(state, destroyed)["suppressed_line"], "", "destroyed")
	var other := _event(A1, 0, 0, 1, 0, {"damage_dealt": 35})
	assert_eq(_model(state, other)["suppressed_line"], "", "not an air-defence site")


func test_report_card_shows_the_line() -> void:
	var state := Model._state(2)
	var card := StaffMapStrikeReport.new(StaffMapPalette.new())
	var event := _event(AD, 0, 0, 1, 0, {"damage_dealt": 35, "suppression": _suppression(2)})
	card.present(_model(state, event))
	assert_true(
		card.texts().any(func(t: String) -> bool: return t.contains("Suppressed for 2 rounds"))
	)
	card.free()
